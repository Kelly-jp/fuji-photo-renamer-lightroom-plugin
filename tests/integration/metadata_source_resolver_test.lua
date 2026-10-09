-- SDK boundary doubles: no ExifTool, subprocesses, or real photo data.
local modulePath = 'src/FujiPhotoRenamer.lrplugin/infrastructure/MetadataSourceResolver.lua'
local testCount = 0
local function equal(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
local function test(name, callback)
    callback(); testCount = testCount + 1; print('PASS ' .. name)
end

local function harness(files, options)
    options = options or {}
    local state = { scans = {}, exhausted = {} }
    local pathUtils = {
        isAbsolute = function(path) return path:sub(1, 1) == '/' or path:match('^%a:[/\\]') ~= nil end,
        leafName = function(path) return path:match('[^/\\]+$') end,
        removeExtension = function(path) return (path:gsub('%.[^.]*$', '')) end,
        extension = function(path) return path:match('%.([^./\\]+)$') or '' end,
        parent = function(path)
            if path == '/' or path:match('^%a:[/\\]$') then return nil end
            local parent = path:match('^(.*)[/\\][^/\\]+$')
            if parent and parent:match('^%a:$') then return parent .. '\\' end
            return parent == '' and '/' or parent
        end,
        standardizePath = function(path) return path end,
    }
    local fileUtils = {
        exists = function(path) return files[path] or false end,
        isReadable = function(path) return not (options.unreadable or {})[path] end,
        resolveAllAliases = function(path) return (options.aliases or {})[path] or path end,
        directoryEntries = function(directory)
            state.scans[directory] = (state.scans[directory] or 0) + 1
            if (options.failedDirectories or {})[directory] then error('Directory access failed') end
            local entries = {}
            for path in pairs(files) do if pathUtils.parent(path) == directory then entries[#entries + 1] = path end end
            table.sort(entries)
            local i = 0
            return function()
                i = i + 1
                if options.iteratorFailure and i == 2 then error('Iterator failed') end
                if entries[i] then return entries[i] end
                state.exhausted[directory] = true
            end
        end,
    }
    local resolver = assert(loadfile(modulePath)) { fileUtils = fileUtils, pathUtils = pathUtils, tasks = { pcall = pcall } }
    state.resolve = function(path, mode) return resolver.resolve(path or '/photos/DSCF1234.JPG', mode) end
    return state
end

local function baseFiles(extra)
    local files = { ['/'] = 'directory', ['/photos'] = 'directory', ['/photos/DSCF1234.JPG'] = 'file' }
    for path, kind in pairs(extra or {}) do files[path] = kind end
    return files
end

for _, extension in ipairs { 'RAF', 'raf', 'RaF', 'DNG', 'dng', 'dNg' } do
    test('finds a same-directory RAW with extension ' .. extension, function()
        local path = '/photos/DSCF1234.' .. extension
        local h = harness(baseFiles { [path] = 'file' })
        local result = assert(h.resolve(nil, 'same_directory'))
        equal(result.raw, path); equal(result.jpeg, '/photos/DSCF1234.JPG'); equal(result.xmp, nil)
        equal(h.scans['/photos'], 1); assert(h.exhausted['/photos'])
    end)
end

test('returns nil for missing related sources', function()
    local result = assert(harness(baseFiles()).resolve(nil, 'same_directory'))
    equal(result.raw, nil); equal(result.xmp, nil); equal(result.jpeg, '/photos/DSCF1234.JPG')
end)
test('finds XMP with no related RAW', function()
    local result = assert(harness(baseFiles { ['/photos/DSCF1234.XmP'] = 'file' }).resolve(nil, 'same_directory'))
    equal(result.xmp, '/photos/DSCF1234.XmP'); equal(result.raw, nil)
end)
test('parent-only mode ignores a RAW in the same directory', function()
    local h = harness(baseFiles { ['/photos/DSCF1234.RAF'] = 'file', ['/DSCF1234.DNG'] = 'file' })
    equal(assert(h.resolve(nil, 'parent_directory')).raw, '/DSCF1234.DNG')
end)
test('same-directory mode does not use a parent RAW', function()
    local h = harness(baseFiles { ['/DSCF1234.RAF'] = 'file' })
    equal(assert(h.resolve(nil, 'same_directory')).raw, nil)
    equal(h.scans['/'], nil)
end)
test('default mode prefers the same directory over the parent', function()
    local h = harness(baseFiles { ['/photos/DSCF1234.RAF'] = 'file', ['/DSCF1234.DNG'] = 'file' })
    equal(assert(h.resolve()).raw, '/photos/DSCF1234.RAF'); equal(h.scans['/'], nil)
end)
test('same_then_parent falls back when the same directory has no RAW', function()
    local h = harness(baseFiles { ['/DSCF1234.RAF'] = 'file', ['/DSCF1234.xmp'] = 'file' })
    local result = assert(h.resolve(nil, 'same_then_parent'))
    equal(result.raw, '/DSCF1234.RAF'); equal(result.xmp, '/DSCF1234.xmp')
    equal(h.scans['/photos'], 1); equal(h.scans['/'], 1)
end)
test('collects XMP adjacent to the original if none is adjacent to RAW', function()
    local h = harness(baseFiles { ['/DSCF1234.RAF'] = 'file', ['/photos/DSCF1234.xmp'] = 'file' })
    equal(assert(h.resolve()).xmp, '/photos/DSCF1234.xmp')
end)

for _, case in ipairs {
    { 'RAF and DNG in the same level', { ['/photos/DSCF1234.RAF'] = 'file', ['/photos/DSCF1234.DNG'] = 'file', ['/DSCF1234.RAF'] = 'file' } },
    { 'two case variants of a RAW extension', { ['/photos/DSCF1234.RAF'] = 'file', ['/photos/DSCF1234.raf'] = 'file' } },
    { 'two XMPs in different levels', { ['/DSCF1234.RAF'] = 'file', ['/DSCF1234.xmp'] = 'file', ['/photos/DSCF1234.xmp'] = 'file' } },
} do
    test('rejects ambiguity: ' .. case[1], function()
        local h = harness(baseFiles(case[2])); local result, err = h.resolve()
        equal(result, nil); equal(err.code, 'AmbiguousSource'); equal(#err.candidates, 2)
        assert(h.exhausted['/photos'])
    end)
end

test('deduplicates XMP aliases resolving to the same canonical path', function()
    local files = baseFiles { ['/DSCF1234.RAF'] = 'file', ['/DSCF1234.xmp'] = 'file', ['/photos/DSCF1234.xmp'] = 'file' }
    local h = harness(files, { aliases = { ['/photos/DSCF1234.xmp'] = '/DSCF1234.xmp' } })
    equal(assert(h.resolve()).xmp, '/DSCF1234.xmp')
end)
test('does not fall back to the parent after a stem case conflict', function()
    local h = harness(baseFiles { ['/photos/dscf1234.RAF'] = 'file', ['/DSCF1234.RAF'] = 'file' })
    local result, err = h.resolve()
    equal(result, nil); equal(err.code, 'AmbiguousStem'); equal(h.scans['/'], nil)
end)
test('ignores a directory named like a RAW and an unrelated stem', function()
    local h = harness(baseFiles { ['/photos/DSCF1234.RAF'] = 'directory', ['/photos/DSCF9999.RAF'] = 'file' })
    equal(assert(h.resolve(nil, 'same_directory')).raw, nil)
end)
test('does not recurse into child directories', function()
    local h = harness(baseFiles { ['/photos/sub'] = 'directory', ['/photos/sub/DSCF1234.RAF'] = 'file' })
    equal(assert(h.resolve(nil, 'same_directory')).raw, nil)
    equal(h.scans['/photos/sub'], nil)
end)
test('preserves a Japanese stem containing dots', function()
    local files = { ['/photos'] = 'directory', ['/photos/写真.v2.jpeg'] = 'file', ['/photos/写真.v2.raf'] = 'file' }
    equal(assert(harness(files).resolve('/photos/写真.v2.jpeg', 'same_directory')).raw, '/photos/写真.v2.raf')
end)
test('treats wildcard-like stem characters literally', function()
    local files = { ['/photos'] = 'directory', ['/photos/a[1].JPG'] = 'file', ['/photos/a[1].RAF'] = 'file', ['/photos/a1.RAF'] = 'file' }
    equal(assert(harness(files).resolve('/photos/a[1].JPG', 'same_directory')).raw, '/photos/a[1].RAF')
end)

for _, extension in ipairs { 'RAF', 'DNG' } do
    test('uses original ' .. extension .. ' directly and finds its JPEG', function()
        local raw = '/photos/DSCF1234.' .. extension
        local h = harness(baseFiles { [raw] = 'file', ['/photos/DSCF1234.xmp'] = 'file' })
        local result = assert(h.resolve(raw, 'parent_directory'))
        equal(result.raw, raw); equal(result.jpeg, '/photos/DSCF1234.JPG'); equal(result.xmp, '/photos/DSCF1234.xmp')
        equal(h.scans['/'], nil)
    end)
end
test('supports a RAW with no associated JPEG', function()
    local files = { ['/photos'] = 'directory', ['/photos/DSCF1234.RAF'] = 'file' }
    local result = assert(harness(files).resolve('/photos/DSCF1234.RAF'))
    equal(result.jpeg, nil); equal(result.raw, '/photos/DSCF1234.RAF')
end)
test('rejects several associated JPEGs', function()
    local h = harness(baseFiles { ['/photos/DSCF1234.RAF'] = 'file', ['/photos/DSCF1234.jpeg'] = 'file' })
    local result, err = h.resolve('/photos/DSCF1234.RAF')
    equal(result, nil); equal(err.code, 'AmbiguousSource')
end)
test('stops parent search at the filesystem root', function()
    local files = { ['/'] = 'directory', ['/DSCF1234.JPG'] = 'file' }
    local h = harness(files); equal(assert(h.resolve('/DSCF1234.JPG', 'parent_directory')).raw, nil)
    equal(h.scans['/'], 1)
end)
test('uses SDK Windows paths and case-insensitive extensions', function()
    local files = { ['C:\\photos'] = 'directory', ['C:\\photos\\DSCF1234.JPG'] = 'file', ['C:\\photos\\DSCF1234.raf'] = 'file' }
    equal(assert(harness(files).resolve('C:\\photos\\DSCF1234.JPG', 'same_directory')).raw, 'C:\\photos\\DSCF1234.raf')
end)
test('searches a Windows drive root as the parent and then stops', function()
    local files = { ['C:\\'] = 'directory', ['C:\\photos'] = 'directory',
        ['C:\\photos\\DSCF1234.JPG'] = 'file', ['C:\\DSCF1234.DNG'] = 'file' }
    equal(assert(harness(files).resolve('C:\\photos\\DSCF1234.JPG', 'parent_directory')).raw, 'C:\\DSCF1234.DNG')
end)
test('does not equate Unicode-normalization variants of the stem', function()
    local files = { ['/photos'] = 'directory', ['/photos/café.JPG'] = 'file', ['/photos/café.RAF'] = 'file' }
    equal(assert(harness(files).resolve('/photos/café.JPG', 'same_directory')).raw, nil)
end)
test('reports an unreadable XMP instead of returning a partial success', function()
    local files = baseFiles { ['/photos/DSCF1234.xmp'] = 'file' }
    local h = harness(files, { unreadable = { ['/photos/DSCF1234.xmp'] = true } })
    local result, err = h.resolve(nil, 'same_directory')
    equal(result, nil); equal(err.code, 'SourceReadError')
end)
test('ignores an unsupported RAW extension', function()
    local h = harness(baseFiles { ['/photos/DSCF1234.CR3'] = 'file' })
    equal(assert(h.resolve(nil, 'same_directory')).raw, nil)
end)

for _, mode in ipairs { false, 'unknown', 1 } do
    test('rejects an invalid mode before scanning', function()
        local h = harness(baseFiles()); local result, err = h.resolve(nil, mode)
        equal(result, nil); equal(err.code, 'InvalidMode'); equal(next(h.scans), nil)
    end)
end
for _, path in ipairs { 'relative.JPG', '/photos/a\n.JPG', '/photos/a\0.JPG', '/photos/source.xmp' } do
    test('rejects invalid or unsupported input', function()
        local result, err = harness(baseFiles()).resolve(path)
        equal(result, nil); assert(err.code == 'InvalidInputPath' or err.code == 'UnsupportedInput')
    end)
end
test('reports a missing original as an error rather than an empty result', function()
    local result, err = harness({}).resolve()
    equal(result, nil); equal(err.code, 'SourceReadError')
end)
test('reports an unreadable RAW rather than falling back to parent', function()
    local files = baseFiles { ['/photos/DSCF1234.RAF'] = 'file', ['/DSCF1234.RAF'] = 'file' }
    local h = harness(files, { unreadable = { ['/photos/DSCF1234.RAF'] = true } })
    local result, err = h.resolve(); equal(result, nil); equal(err.code, 'SourceReadError'); equal(h.scans['/'], nil)
end)
test('reports directory access failure', function()
    local h = harness(baseFiles(), { failedDirectories = { ['/photos'] = true } })
    local result, err = h.resolve(); equal(result, nil); equal(err.code, 'SourceReadError')
end)
test('reports iterator failure without pretending the source is missing', function()
    local h = harness(baseFiles { ['/photos/DSCF1234.RAF'] = 'file' }, { iteratorFailure = true })
    local result, err = h.resolve(); equal(result, nil); equal(err.code, 'SourceReadError')
end)

print(string.format('%d Phase 3 boundary tests passed; Lightroom and native filesystem checks remain separate.', testCount))
