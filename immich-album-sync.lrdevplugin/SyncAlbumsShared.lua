-- SyncAlbumsShared.lua - Shared Sync Logic for both actual sync and dry run
local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local ImmichAPI = require "ImmichAPI"
local LrLogger = import "LrLogger"
local LrPrefs = import "LrPrefs"
local LrPathUtils = import "LrPathUtils"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file

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

local function createLightroomAlbum(albumName, options)
    local isDryRun = options and options.isDryRun or false
    console:infof("%sCreating album in Lightroom: %s", isDryRun and "[DRY RUN] " or "", albumName)

    if not isDryRun then
        local catalog = LrApplication.activeCatalog()
        catalog:withWriteAccessDo("Create Album", function(context)
            catalog:createCollection(albumName, nil, true)
        end)
    end
end

local function syncAlbums(options)
    local isDryRun = options and options.isDryRun or false
    console:infof('%sStarting album sync%s', isDryRun and "[DRY RUN] " or "",
        isDryRun and " (no changes will be made)" or "")

    local lightroomAlbums = getLightroomAlbums()
    local immichAlbums = ImmichAPI.getImmichAlbums()

    local selectedAlbums = {}
    if prefs.syncSpecificAlbums and prefs.selectedAlbums then
        console:info((isDryRun and "[DRY RUN] " or "") .. "Running in \"specific album only\" mode...")
        console:debugf((isDryRun and "[DRY RUN] " or "") .. "Selected Albums: %s", prefs.selectedAlbums)
        for album in string.gmatch(prefs.selectedAlbums, "[^;]+") do
            local albumName = album:match("^%s*(.-)%s*$")
            console:infof((isDryRun and "[DRY RUN] " or "") .. "Selected Album: %s", albumName)
            selectedAlbums[albumName] = true
        end
    end

    -- Create missing albums in Lightroom
    if prefs.createAlbumsInLightroom then
        console:info((isDryRun and "[DRY RUN] " or "") .. "Creating missing albums in Lightroom...")
        for albumName, _ in pairs(immichAlbums) do
            console:debugf((isDryRun and "[DRY RUN] " or "") .. "Checking album: %s", albumName)
            if (not prefs.syncSpecificAlbums or selectedAlbums[albumName]) and not lightroomAlbums[albumName] then
                createLightroomAlbum(albumName, {
                    isDryRun = isDryRun
                })
                if not isDryRun then
                    LrDialogs.message("Created album in Lightroom: " .. albumName)
                end
            end
        end
    end

    -- Create missing albums in Immich
    if prefs.createAlbumsInImmich then
        console:info((isDryRun and "[DRY RUN] " or "") .. "Creating missing albums in Immich...")
        for albumName, _ in pairs(lightroomAlbums) do
            console:debugf((isDryRun and "[DRY RUN] " or "") .. "Checking album: %s", albumName)
            if (not prefs.syncSpecificAlbums or selectedAlbums[albumName]) and not immichAlbums[albumName] then
                console:infof((isDryRun and "[DRY RUN] " or "") .. "Creating album in Immich: %s", albumName)
                if not isDryRun then
                    ImmichAPI.createImmichAlbum(albumName)
                    LrDialogs.message("Created album in Immich: " .. albumName)
                end
            end
        end
    end

    -- Sync photo lists between Lightroom and Immich
    console:info((isDryRun and "[DRY RUN] " or "") .. "Syncing photo lists between Lightroom and Immich...")

    for albumName, immichAlbumId in pairs(immichAlbums) do
        local lightroomAlbum = lightroomAlbums[albumName]

        if (not prefs.syncSpecificAlbums or selectedAlbums[albumName]) and lightroomAlbum then
            console:infof((isDryRun and "[DRY RUN] " or "") .. "Syncing photos for album: %s", albumName)

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
                local datedPath = photoPath:match(".*(%d%d%d%d%/%d%d%d%d%-%d%d%/%d%d%d%d%-%d%d%-%d%d%/.+)$")
                if datedPath then
                    lightroomPhotoDatedItems[datedPath] = photoPath
                else
                    console:infof((isDryRun and "[DRY RUN] " or "") ..
                                      "Warning: Photo path does not match expected format: %s", photoPath)
                end
            end

            -- Add photos from Lightroom to Immich album:
            for datedLrPath, lrPath in pairs(lightroomPhotoDatedItems) do
                if not immichPhotoDatedItems[datedLrPath] then
                    console:infof((isDryRun and "[DRY RUN] " or "") .. "Adding photo to Immich: %s", lrPath)

                    if not isDryRun then
                        -- get leaf and the most nested folder name
                        local filename = LrPathUtils.leafName(lrPath)
                        local dateDirname = LrPathUtils.leafName(
                            LrPathUtils.parent(LrPathUtils.parent(LrPathUtils.parent(lrPath))))

                        ImmichAPI.addAssetToAlbumByOriginalPath(immichAlbumId, dateDirname .. " - " .. filename)
                    end
                end
            end

            -- Add photos from Immich to Lightroom album:
            for datedImmichPath, immichItem in pairs(immichPhotoDatedItems) do
                if not lightroomPhotoDatedItems[datedImmichPath] then
                    console:infof((isDryRun and "[DRY RUN] " or "") .. "Adding photo to Lightroom: %s",
                        immichItem.immichPhotoPath)

                    if not isDryRun then
                        local basename = LrPathUtils.leafName(immichItem.immichPhotoPath)

                        if immichItem.dateDirname and immichItem.filename then
                            local filenameWithoutExtension = immichItem.filename:gsub("%.%w+$", "")

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
                                        value = immichItem.dateDirname
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
                                console:infof((isDryRun and "[DRY RUN] " or "") ..
                                                  "Photo not found in Lightroom: immich path = %s, dateDirname = %s, filename = %s",
                                    immichItem.immichPhotoPath, immichItem.dateDirname, immichItem.filename)
                            else
                                for _, photo in ipairs(filteredPhotos) do
                                    local photoPath = photo:getRawMetadata("path")
                                    console:infof((isDryRun and "[DRY RUN] " or "") ..
                                                      "Adding photo found in Lightroom to the album: %s", photoPath)
                                end

                                catalog:withWriteAccessDo("Add Photos to Album", function(context)
                                    lightroomAlbum:addPhotos(filteredPhotos)
                                end)
                            end
                        else
                            console:infof((isDryRun and "[DRY RUN] " or "") ..
                                              "Invalid Immich path: %s -> dirname = %s, filename = %s",
                                immichItem.immichPhotoPath, immichItem.dateDirname, immichItem.filename)
                        end
                    end
                end
            end
        end
    end

    if isDryRun then
        LrDialogs.message("Dry Run Complete",
            "Dry run completed. Check the log for details on what would happen during a real sync.", "info")
    else
        LrDialogs.message("Album Sync Complete")
    end
end

return {
    syncAlbums = syncAlbums
}
