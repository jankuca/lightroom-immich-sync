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

    local selectedAlbums = {}
    if prefs.syncSpecificAlbums and prefs.selectedAlbums then
        console:info("Running in \"specific album only\" mode...")
        console:debugf("Selected Albums: %s", prefs.selectedAlbums)
        for album in string.gmatch(prefs.selectedAlbums, "[^;]+") do
            local albumName = album:match("^%s*(.-)%s*$")
            console:infof("Selected Album: %s", albumName)
            selectedAlbums[albumName] = true
        end
    end

    -- Create missing albums in Lightroom
    if prefs.createAlbumsInLightroom then
        console:info("Creating missing albums in Lightroom...")
        for albumName, _ in pairs(immichAlbums) do
            console:debugf("Checking album: %s", albumName)
            if (not prefs.syncSpecificAlbums or selectedAlbums[albumName]) and not lightroomAlbums[albumName] then
                createLightroomAlbum(albumName)
                LrDialogs.message("Created album in Lightroom: " .. albumName)
            end
        end
    end

    -- Create missing albums in Immich
    if prefs.createAlbumsInImmich then
        console:info("Creating missing albums in Immich...")
        for albumName, _ in pairs(lightroomAlbums) do
            console:debugf("Checking album: %s", albumName)
            if (not prefs.syncSpecificAlbums or selectedAlbums[albumName]) and not immichAlbums[albumName] then
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
