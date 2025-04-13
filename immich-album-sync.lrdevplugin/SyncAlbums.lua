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

    -- Sync photo lists between Lightroom and Immich
    console:info("Syncing photo lists between Lightroom and Immich...")

    for albumName, immichAlbumId in pairs(immichAlbums) do
        local lightroomAlbum = lightroomAlbums[albumName]

        if (not prefs.syncSpecificAlbums or selectedAlbums[albumName]) and lightroomAlbum then
            console:infof("Syncing photos for album: %s", albumName)

            -- Get photos in Immich album
            local immichPhotos = ImmichAPI.getPhotosInImmichAlbum(immichAlbumId)
            local immichPhotoDatedItems = {}
            for immichPhotoPath, photoId in pairs(immichPhotos) do
                local datedPath = immichPhotoPath:match(
                    "(%d%d%d%d/%d%d%d%d%-%d%d/%d%d%d%d%-%d%d%-%d%d/%d%d%d%d%-%d%d%-%d%d %- .+)$")
                if datedPath then
                    local basename = LrPathUtils.leafName(datedPath)
                    local dateDirname, filename = basename:match("^(.-) %- (.+)$")
                    immichPhotoDatedItems[filename] = {immichPhotoPath, dateDirname, filename, basename}
                end
            end

            -- Get photos in Lightroom album
            local lightroomPhotoDatedItems = {}
            local lightroomPhotos = lightroomAlbum:getPhotos()
            for _, photo in ipairs(lightroomPhotos) do
                local photoPath = photo:getRawMetadata("path")
                local datedPath = photoPath:match("(%d%d%d%d/(%d%d%d%d%-%d%d)?/%d%d%d%d%-%d%d%-%d%d/.+)$")
                lightroomPhotoDatedItems[datedPath] = photoPath
            end

            -- Add photos from Lightroom to Immich album:
            for datedLrPath, lrPath in pairs(lightroomPhotoDatedItems) do
                if not immichPhotoDatedItems[datedLrPath] then
                    console:infof("Adding photo to Immich: %s", lrPath)

                    -- get leaf and the most nested folder name
                    local filename = LrPathUtils.leafName(lrPath)
                    local dateDirname = LrPathUtils.leafName(LrPathUtils.parent(
                        LrPathUtils.parent(LrPathUtils.parent(lrPath))))

                    ImmichAPI.addAssetToAlbumByOriginalPath(immichAlbumId, dateDirname .. " - " .. filename)
                end
            end

            -- Add photos from Immich to Lightroom album:
            for datedImmichPath, immichPath in pairs(immichPhotoDatedItems) do
                if not lightroomPhotoDatedItems[datedImmichPath] then
                    console:infof("Adding photo to Lightroom: %s", immichPath)

                    local basename = LrPathUtils.leafName(immichPath)
                    local dateDirname, filename = basename:match("^(.-) %- (.+)$")

                    if dateDirname and filename then
                        local filenameWithoutExtension = filename:gsub("%.%w+$", "")

                        local catalog = LrApplication.activeCatalog()
                        local photos = catalog:findPhotos({
                            searchDesc = {
                                {
                                    criteria = "filename",
                                    operation = "any",
                                    value = filenameWithoutExtension
                                },
                                {
                                    criteria = "folder",
                                    operation = "==",
                                    value = dateDirname
                                },
                                combine = "intersect"
                            }
                        })

                        -- keep only photos that match as "filename.(any extension)":
                        local filteredPhotos = {}
                        for _, photo in ipairs(photos) do
                            local photoPath = photo:getRawMetadata("path")
                            local photoFilename = LrPathUtils.leafName(photoPath)
                            local photoBasenameWithoutExtension = photoFilename:gsub("%.%w+$", "")

                            if photoBasenameWithoutExtension == filenameWithoutExtension then
                                table.insert(filteredPhotos, photo)
                            end
                        end

                        if #filteredPhotos == 0 then
                            console:infof(
                                "Photo not found in Lightroom: immich path = %s, dateDirname = %s, filename = %s",
                                immichPath, dateDirname, filename)
                        else
                            for _, photo in ipairs(filteredPhotos) do
                                local photoPath = photo:getRawMetadata("path")
                                console:infof("Adding photo found in Lightroom to the album: %s", photoPath)
                            end

                            catalog:withWriteAccessDo("Add Photos to Album", function(context)
                                lightroomAlbum:addPhotos(filteredPhotos)
                            end)
                        end
                    else
                        console:infof("Invalid Immich path: %s -> dirname = %s, filename = %s", immichPath, dateDirname,
                            filename)
                    end

                    -- local catalog = LrApplication.activeCatalog()
                    -- catalog:withWriteAccessDo("Add Photo", function(context)
                    --     catalog:addPhotoByPath(immichPath)
                    -- end)
                end
            end
        end
    end

    LrDialogs.message("Album Sync Complete")
end

LrTasks.startAsyncTask(function()
    syncAlbums()
end)
