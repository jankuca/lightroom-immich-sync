-- QuickSyncAlbums.lua - Quick Mode Sync Logic
local LrTasks = import "LrTasks"
local SyncAlbumsShared = require "SyncAlbumsShared"
local LrLogger = import "LrLogger"
local LrFunctionContext = import "LrFunctionContext"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file
console:infof('Logger started - Quick Mode')

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("quickSyncAlbums", function(context)
        SyncAlbumsShared.syncAlbums({
            isDryRun = false,
            isQuickMode = true,
            functionContext = context
        }) -- Perform quick sync
    end)
end)
