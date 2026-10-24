local count = 0
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function harness()
    local h = { existing = { ['/Applications/Editor.app'] = 'directory', ['C:/Editor.exe'] = 'file',
        ['/out/a.jpg'] = 'file', ['/out/b.jpg'] = 'file', ['/other/c.jpg'] = 'file' }, revealed = {} }
    h.processing = assert(loadfile('src/FujiPhotoRenamer.lrplugin/infrastructure/ExportPostProcessing.lua')) {
        fileUtils = { exists = function(path) return h.existing[path] end },
        pathUtils = { isAbsolute = function(path) return path:sub(1, 1) == '/' or path:match('^%a:/') end,
            extension = function(path) return path:match('%.([^.]*)$') or '' end, parent = function(path) return path:match('^(.*)/[^/]+$') end },
        shell = { revealInShell = function(path) h.revealed[#h.revealed + 1] = path end,
            openFilesInApp = function(paths, application) h.opened, h.application = paths, application; if h.fail then error('Cannot open app') end end },
    }
    return h
end
test('none and empty results do not open anything', function()
    local h = harness(); h.processing.run('none', '', { '/out/a.jpg' }); h.processing.run('reveal', '', {})
    assert(not h.opened and #h.revealed == 0)
end)
test('reveals the first saved file once per folder', function()
    local h = harness(); h.processing.run('reveal', '', { '/out/a.jpg', '/out/b.jpg', '/other/c.jpg' })
    assert(#h.revealed == 2 and h.revealed[1] == '/out/a.jpg' and h.revealed[2] == '/other/c.jpg')
end)
for _, application in ipairs { '/Applications/Editor.app', 'C:/Editor.exe' } do
    test('opens unique saved paths with the chosen application: ' .. application, function()
        local h = harness(); h.processing.run('open_application', application, { '/out/a.jpg', '/out/a.jpg', '/out/b.jpg' })
        assert(h.application == application and #h.opened == 2 and h.opened[2] == '/out/b.jpg')
    end)
end
for _, application in ipairs { '', 'relative.exe', '/missing.app', '/folder', '/Applications/Bad\n.app' } do
    test('rejects an invalid application', function()
        local h = harness(); assert(not h.processing.validate('open_application', application)); assert(not h.opened)
    end)
end
test('rejects unknown actions', function() assert(not harness().processing.validate('unknown', '')) end)
test('rejects disappeared outputs before opening an application', function()
    local h = harness(); assert(not pcall(h.processing.run, 'open_application', '/Applications/Editor.app', { '/out/a.jpg', '/missing.jpg' }))
    assert(not h.opened)
end)
test('surfaces shell errors rather than reporting success', function()
    local h = harness(); h.fail = true
    assert(not pcall(h.processing.run, 'open_application', '/Applications/Editor.app', { '/out/a.jpg' }))
end)
print(string.format('%d export-post-processing boundary tests passed.', count))
