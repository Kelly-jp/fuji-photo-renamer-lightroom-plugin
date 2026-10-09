local diagnosticMenuItems = {
    {
        title = 'Phase 2：ExifTool のメタデータ取得を検証…',
        file = 'Phase2Diagnostic.lua',
    },
}

return {
    LrSdkVersion = 11.0,
    LrSdkMinimumVersion = 11.0,
    LrToolkitIdentifier = 'jp.kelly.fuji-photo-renamer',
    LrPluginName = 'Fuji Photo Renamer — 開発検証版',
    LrExportServiceProvider = {
        title = 'Fuji Photo Renamer — Phase 1',
        file = 'ExportServiceProvider.lua',
    },
    LrExportMenuItems = diagnosticMenuItems,
    LrLibraryMenuItems = diagnosticMenuItems,
    VERSION = { major = 0, minor = 1, revision = 5, build = 6 },
}
