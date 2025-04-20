-- QuickDryRunSyncAlbums.lua - Quick Mode Dry Run Sync Logic
local LrTasks = import "LrTasks"
local SyncAlbumsShared = require "SyncAlbumsShared"
local LrLogger = import "LrLogger"
local LrFunctionContext = import "LrFunctionContext"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file
console:infof('Logger started - Quick Mode Dry Run')

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("quickDryRunSyncAlbums", function(context)
        SyncAlbumsShared.syncAlbums({
            isDryRun = true,
            isQuickMode = true,
            functionContext = context
        }) -- Simulate quick sync without making changes
    end)
end)
