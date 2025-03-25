-- Info.lua - Plugin Metadata
return {
    LrSdkVersion = 10.0,
    LrToolkitIdentifier = "com.yourname.lightroom.immichsync",
    LrPluginName = "Immich Album Sync",

    LrExportMenuItems = {{
        title = "Sync Albums with Immich",
        file = "SyncAlbums.lua"
    }, {
        title = "Immich Sync Settings",
        file = "ConfigDialog.lua"
    }}
}
