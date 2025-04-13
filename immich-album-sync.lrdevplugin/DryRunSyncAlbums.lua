-- DryRunSyncAlbums.lua - Dry Run Sync Logic
local LrTasks = import "LrTasks"
local SyncAlbumsShared = require "SyncAlbumsShared"
local LrLogger = import "LrLogger"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file
console:infof('Logger started - Dry Run Mode')

LrTasks.startAsyncTask(function()
    SyncAlbumsShared.syncAlbums({
        isDryRun = true
    }) -- Simulate sync without making changes
end)
