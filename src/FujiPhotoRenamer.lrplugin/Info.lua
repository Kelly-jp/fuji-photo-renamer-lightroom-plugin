local diagnosticMenuItems = {
    {
        title = 'メタデータ取得 / 入力ファイル探索を検証…',
        file = 'Phase2Diagnostic.lua',
    },
}

return {
    LrSdkVersion = 11.0,
    LrSdkMinimumVersion = 11.0,
    LrToolkitIdentifier = 'jp.kelly.fuji-photo-renamer',
    LrPluginName = 'Fuji Photo Renamer — 開発検証版',
    LrExportServiceProvider = {
        title = 'Fuji Photo Renamer — 開発検証版',
        file = 'ExportServiceProvider.lua',
    },
    LrExportMenuItems = diagnosticMenuItems,
    LrLibraryMenuItems = diagnosticMenuItems,
    VERSION = { major = 0, minor = 7, revision = 2, build = 16 },
}
