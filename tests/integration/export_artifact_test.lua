-- SDK and binary reads are controlled doubles; no mutations reach real input files.
local handle = assert(io.open('fixtures/metadata/phase2-sample.jpg', 'rb'))
local jpeg = handle:read('*a'); assert(handle:close())
local fixture = assert(loadfile('tests/support/jumbf_fixture.lua'))()
local integrity = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/JpegIntegrity.lua'))()
local count = 0
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function harness()
    local h = { data = { ['/source.jpg'] = jpeg, ['/source.RAF'] = 'RAW fixture',
        ['/source.xmp'] = 'XMP fixture', ['/render.jpg'] = fixture.add(jpeg) }, aliases = {}, sizes = {}, deleted = {} }
    h.original = '/source.jpg'
    local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/infrastructure/ExportArtifact.lua'))
    -- Reads are bounded in the production module. Test data stays entirely in this table.
    local environment = setmetatable({ io = { open = function(path, mode)
        equal(mode, 'rb')
        if h.unreadable == path then return nil, 'Permission denied' end
        local data = h.data[path]
        if not data then return nil, 'Missing file' end
        return { read = function(_, bytes) return data:sub(1, bytes) end, close = function() return true end }
    end } }, { __index = _G })
    setfenv(chunk, environment)
    h.store = chunk { integrity = integrity, fileUtils = {
        resolveAllAliases = function(path) return h.aliases[path] or path end,
        exists = function(path) return h.data[path] and 'file' or false end,
        fileAttributes = function(path) return { fileSize = h.sizes[path] or #h.data[path] } end,
        delete = function(path)
            h.deleted[#h.deleted + 1] = path
            if h.deleteFailure then return false, 'Permission denied' end
            h.data[path] = nil; return true
        end,
    }, pathUtils = {
        standardizePath = function(path) return path end,
        child = function(path, name) return path .. '/' .. name end,
        extension = function(path) return path:match('%.([^.]+)$') or '' end,
    } }
    h.rendition = { destinationPath = '/render.jpg', type = function() return 'LrExportRendition' end,
        photo = { getRawMetadata = function(_, key) equal(key, 'path'); return h.original end } }
    h.capture = function()
        return h.store.capture(h.rendition, '/render.jpg', '/source.jpg',
            { jpeg = '/source.jpg', raw = '/source.RAF', xmp = '/source.xmp' })
    end
    h.stage = function()
        local cap = assert(h.capture())
        local path = assert(h.store.bindWork(cap, '/work')); h.data[path] = jpeg
        return cap, path
    end
    return h
end
local function rejected(result, err, code)
    equal(result, nil); equal(err.code, code or 'ArtifactRejected')
end
test('only a verified owned render can be committed and source files stay unchanged', function()
    local h = harness(); local cap, path = h.stage()
    equal(assert(h.store.source(cap)), '/render.jpg')
    equal(assert(h.store.verify(cap)), path); equal(assert(h.store.commitPath(cap)), path)
    equal(#h.deleted, 1); equal(h.deleted[1], '/render.jpg'); equal(h.data['/render.jpg'], nil)
    equal(h.data['/source.jpg'], jpeg); equal(h.data['/source.RAF'], 'RAW fixture'); equal(h.data['/source.xmp'], 'XMP fixture')
    equal(h.store.canClean(cap, path), true); equal(h.store.canClean(cap, '/source.jpg'), false)
end)
test('rejects a fabricated or forgotten capability', function()
    local h = harness(); rejected(h.store.source({}))
    local cap = assert(h.capture()); h.store.forget(cap); rejected(h.store.bindWork(cap, '/work'))
    equal(h.store.canClean(cap, '/work/cleaned.jpg'), false); equal(#h.deleted, 0)
end)
for _, change in ipairs {
    function(h) h.rendition.type = function() return 'LrPhoto' end end,
    function(h) h.rendition.destinationPath = '/other.jpg' end,
    function(h) h.original = '/other.jpg' end,
    function(h) h.rendition.destinationPath = nil end,
} do
    test('rejects inconsistent SDK rendering identity', function()
        local h = harness(); change(h); rejected(h.capture()); equal(#h.deleted, 0)
    end)
end
for _, source in ipairs { '/source.jpg', '/source.RAF', '/source.xmp' } do
    test('rejects a render alias to protected input ' .. source, function()
        local h = harness(); h.aliases['/render.jpg'] = source
        rejected(h.capture()); equal(#h.deleted, 0)
    end)
end
for _, case in ipairs { { 'missing' }, { 'oversized' }, { 'unreadable' }, { 'malformed' } } do
    test('rejects ' .. case[1] .. ' render before deletion', function()
        local h = harness()
        if case[1] == 'missing' then h.data['/render.jpg'] = nil
        elseif case[1] == 'oversized' then h.sizes['/render.jpg'] = 64 * 1024 * 1024 + 1
        elseif case[1] == 'unreadable' then h.unreadable = '/render.jpg'
        else h.data['/render.jpg'] = 'broken' end
        local result, err = h.capture(); rejected(result, err, case[1] == 'malformed' and 'InvalidJpeg' or 'ArtifactRejected')
        equal(#h.deleted, 0)
    end)
end
test('rejects an existing work file and ambiguous percent output path', function()
    local h = harness(); local cap = assert(h.capture()); h.data['/work/cleaned.jpg'] = 'existing'
    rejected(h.store.bindWork(cap, '/work')); rejected(h.store.bindWork(cap, '/work%name'))
    equal(h.data['/work/cleaned.jpg'], 'existing'); equal(#h.deleted, 0)
end)
for _, change in ipairs {
    function(h) h.data['/render.jpg'] = jpeg end,
    function(h) h.aliases['/render.jpg'] = '/new-render.jpg' end,
    function(h) h.original = '/render.jpg' end,
    function(h) h.aliases['/source.xmp'] = '/render.jpg' end,
    function(h) h.original = '/work/cleaned.jpg' end,
} do
    test('rechecks render and input references before committing', function()
        local h = harness(); local cap = h.stage(); assert(h.store.verify(cap)); change(h)
        rejected(h.store.commitPath(cap)); equal(#h.deleted, 0)
    end)
end
for _, source in ipairs { '/source.jpg', '/source.RAF', '/source.xmp', '/unowned.jpg' } do
    test('refuses to verify or clean a stage alias to ' .. source, function()
        local h = harness(); local cap, path = h.stage(); h.aliases[path] = source
        rejected(h.store.verify(cap)); equal(h.store.canClean(cap, path), false); equal(#h.deleted, 0)
    end)
end
test('refuses cleanup if the catalog begins referring to the work copy', function()
    local h = harness(); local cap, path = h.stage(); h.original = path
    equal(h.store.canClean(cap, path), false)
end)
test('refuses cleanup when a protected sidecar resolves to the work copy', function()
    local h = harness(); local cap, path = h.stage(); h.aliases['/source.xmp'] = path
    equal(h.store.canClean(cap, path), false); rejected(h.store.verify(cap)); equal(#h.deleted, 0)
end)
test('rejects retained JUMBF and changes to non-JUMBF data', function()
    local h = harness(); local cap, path = h.stage(); h.data[path] = fixture.add(jpeg)
    local result, err = h.store.verify(cap); rejected(result, err, 'JumbfRemaining')
    h.data[path] = jpeg .. 'changed trailing bytes'
    result, err = h.store.verify(cap); rejected(result, err, 'JpegChanged'); equal(#h.deleted, 0)
end)
test('rejects an unverified artifact and propagates deletion failure', function()
    local h = harness(); local cap = h.stage(); rejected(h.store.commitPath(cap))
    assert(h.store.verify(cap)); h.deleteFailure = true; rejected(h.store.commitPath(cap))
    assert(h.data['/render.jpg']); equal(#h.deleted, 1)
end)
test('revalidates processed output after successful verification', function()
    local h = harness(); local cap, path = h.stage(); assert(h.store.verify(cap))
    h.data[path] = fixture.add(jpeg)
    local result, err = h.store.commitPath(cap); rejected(result, err, 'JumbfRemaining'); equal(#h.deleted, 0)
end)
print(string.format('%d export-artifact boundary tests passed.', count))
