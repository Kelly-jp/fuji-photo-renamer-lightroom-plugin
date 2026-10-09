local context = assert(..., 'MetadataReader requires infrastructure and core dependencies')
local scanner, reader, resolver = assert(context.scanner), assert(context.reader), assert(context.resolver)
local Reader = {}
function Reader.read(originalPath, mode, executablePath, isCanceled)
    local paths, scanError = scanner.resolve(originalPath, mode)
    if not paths then return nil, scanError end
    local sources, warnings = {}, {}
    for _, kind in ipairs { 'xmp', 'raw', 'jpeg' } do
        if isCanceled and isCanceled() then return nil, { code = 'Canceled', message = 'キャンセルされました。' } end
        if paths[kind] then
            local result, readError = reader.readMetadata(paths[kind], { executablePath = executablePath })
            if not result then return nil, readError end
            sources[kind] = { metadata = result.metadata, fieldSources = result.fieldSources }
            for _, warning in ipairs(result.warnings or {}) do warnings[#warnings + 1] = kind .. '：' .. warning end
        end
    end
    local result, mergeError = resolver.resolve(sources)
    if not result then return nil, mergeError end
    result.paths, result.warnings = paths, warnings
    return result
end
return Reader
