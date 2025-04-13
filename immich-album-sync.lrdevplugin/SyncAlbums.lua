-- SyncAlbums.lua - Main Sync Logic
local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local ImmichAPI = require "ImmichAPI"
local LrLogger = import "LrLogger"
local LrPrefs = import "LrPrefs"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file
console:infof('Logger started')

local prefs = LrPrefs.prefsForPlugin()

local function getLightroomAlbums()
    local catalog = LrApplication.activeCatalog()
    local collections = catalog:getChildCollections()

    local albums = {}
    for _, collection in ipairs(collections) do
        albums[collection:getName()] = collection
    end
    return albums
end

local function createLightroomAlbum(albumName)
    console:infof("Creating album in Lightroom: %s", albumName)
    local catalog = LrApplication.activeCatalog()
    catalog:withWriteAccessDo("Create Album", function(context)
        catalog:createCollection(albumName, nil, true)
    end)
end

local function syncAlbums()
    local lightroomAlbums = getLightroomAlbums()
    local immichAlbums = ImmichAPI.getImmichAlbums()

    -- Create missing albums in Lightroom
    if prefs.createAlbumsInLightroom then
        console:info("Creating missing albums in Lightroom...")
        for albumName, _ in pairs(immichAlbums) do
            if not lightroomAlbums[albumName] then
            console:debugf("Checking album: %s", albumName)
                createLightroomAlbum(albumName)
                LrDialogs.message("Created album in Lightroom: " .. albumName)
            end
        end
    end

    -- Create missing albums in Immich
    if prefs.createAlbumsInImmich then
        console:info("Creating missing albums in Immich...")
        for albumName, _ in pairs(lightroomAlbums) do
            if not immichAlbums[albumName] then
            console:debugf("Checking album: %s", albumName)
                ImmichAPI.createImmichAlbum(albumName)
                LrDialogs.message("Created album in Immich: " .. albumName)
            end
        end
    end

    LrDialogs.message("Album Sync Complete")
end

LrTasks.startAsyncTask(function()
    syncAlbums()
end)
