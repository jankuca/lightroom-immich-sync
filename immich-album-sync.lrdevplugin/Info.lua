-- Info.lua - Plugin Metadata
return {
    LrSdkVersion = 10.0,
    LrToolkitIdentifier = "com.yourname.lightroom.immichsync",
    LrPluginName = "Immich Album Sync",

    LrExportMenuItems = {{
        title = "Sync Albums with Immich",
        file = "SyncAlbums.lua"
    }, {
        title = "Quick Sync Albums with Immich",
        file = "QuickSyncAlbums.lua"
    }, {
        title = "Dry Run - Sync Albums with Immich",
        file = "DryRunSyncAlbums.lua"
    }, {
        title = "Dry Run - Quick Sync Albums with Immich",
        file = "QuickDryRunSyncAlbums.lua"
    }, {
        title = "Immich Sync Settings",
        file = "ConfigDialog.lua"
    }}
}
