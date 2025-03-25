-- SyncAlbums.lua - Main Sync Logic
local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local ImmichAPI = require "ImmichAPI"
local LrPrefs = import "LrPrefs"

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
    local catalog = LrApplication.activeCatalog()
    catalog:createCollection(albumName, nil, true)
end

local function syncAlbums()
    local lightroomAlbums = getLightroomAlbums()
    local immichAlbums = ImmichAPI.getImmichAlbums()

    if prefs.createAlbumsInLightroom then
        for albumName, _ in pairs(immichAlbums) do
            if not lightroomAlbums[albumName] then
                createLightroomAlbum(albumName)
                LrDialogs.message("Created album in Lightroom: " .. albumName)
            end
        end
    end

    if prefs.createAlbumsInImmich then
        for albumName, _ in pairs(lightroomAlbums) do
            if not immichAlbums[albumName] then
                ImmichAPI.createImmichAlbum(albumName)
                LrDialogs.message("Created album in Immich: " .. albumName)
            end
        end
    end

    LrDialogs.message("Album Sync Complete")
end

syncAlbums()
