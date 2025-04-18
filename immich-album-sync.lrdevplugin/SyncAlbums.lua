-- SyncAlbums.lua - Main Sync Logic
local LrTasks = import "LrTasks"
local SyncAlbumsShared = require "SyncAlbumsShared"
local LrLogger = import "LrLogger"
local LrFunctionContext = import "LrFunctionContext"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file
console:infof('Logger started')

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("syncAlbums", function(context)
        SyncAlbumsShared.syncAlbums({
            isDryRun = false,
            functionContext = context
        }) -- Perform actual sync
    end)
end)
