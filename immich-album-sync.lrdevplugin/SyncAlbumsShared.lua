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

-- Levenshtein distance function to calculate string similarity
local function levenshteinDistance(str1, str2)
    local len1, len2 = #str1, #str2
    local matrix = {}

    -- Initialize the matrix
    for i = 0, len1 do
        matrix[i] = {
            [0] = i
        }
    end
    for j = 0, len2 do
        matrix[0][j] = j
    end

    -- Fill the matrix
    for i = 1, len1 do
        for j = 1, len2 do
            local cost = (str1:sub(i, i) == str2:sub(j, j)) and 0 or 1
            matrix[i][j] = math.min(matrix[i - 1][j] + 1, -- deletion
            matrix[i][j - 1] + 1, -- insertion
            matrix[i - 1][j - 1] + cost -- substitution
            )
        end
    end

    return matrix[len1][len2]
end

-- Function to normalize album names for comparison
local function normalizeAlbumName(name)
    -- Convert to lowercase
    local normalized = string.lower(name)
    -- Remove common separators (spaces, dashes, underscores)
    normalized = normalized:gsub("[%s%-_]", "")
    return normalized
end

-- Function to calculate similarity between two album names
local function calculateSimilarity(name1, name2)
    local normalized1 = normalizeAlbumName(name1)
    local normalized2 = normalizeAlbumName(name2)

    -- Calculate Levenshtein distance
    local distance = levenshteinDistance(normalized1, normalized2)

    -- Calculate similarity score (0 to 1, where 1 is identical)
    local maxLength = math.max(#normalized1, #normalized2)
    if maxLength == 0 then
        return 1
    end -- Both strings are empty

    return 1 - (distance / maxLength)
end

-- Function to find similar album names
local function findSimilarAlbumName(albumName, albumList, similarityThreshold)
    local threshold = similarityThreshold or 0.7 -- Default threshold
    local bestMatch = nil
    local bestSimilarity = 0

    for candidateName, _ in pairs(albumList) do
        if candidateName ~= albumName then -- Skip exact matches
            local similarity = calculateSimilarity(albumName, candidateName)
            console:debugf("Similarity between '%s' and '%s': %.2f", albumName, candidateName, similarity)
            if similarity > threshold and similarity > bestSimilarity then
                bestMatch = candidateName
                bestSimilarity = similarity
            end
        end
    end

    return bestMatch, bestSimilarity
end

-- Function to determine which album name is better (prefer longer name)
local function getBetterAlbumName(name1, name2)
    if #name1 >= #name2 then
        return name1
    else
        return name2
    end
end

-- Function to rename a Lightroom album
local function renameLightroomAlbum(collection, newName, options)
    local isDryRun = options and options.isDryRun or false
    console:infof("%sRenaming Lightroom album from '%s' to '%s'", isDryRun and "[DRY RUN] " or "", collection:getName(),
        newName)

    if not isDryRun then
        local catalog = LrApplication.activeCatalog()
        catalog:withWriteAccessDo("Rename Album", function(context)
            collection:setName(newName)
        end)
    end
end

local function getLightroomAlbums()
    local catalog = LrApplication.activeCatalog()
    local collections = catalog:getChildCollections()

    local albums = {}
    for _, collection in ipairs(collections) do
        albums[collection:getName()] = collection
    end
    return albums
end

-- Helper function to check if an album is selected for syncing
local function isAlbumSelected(albumName, selectedAlbums)
    return not prefs.syncSpecificAlbums or selectedAlbums[albumName]
end

-- Helper function to get the dry run prefix for log messages
local function getDryRunPrefix(isDryRun)
    return isDryRun and "[DRY RUN] " or ""
end

local function createLightroomAlbum(albumName, options)
    local isDryRun = options and options.isDryRun or false
    console:infof("%sCreating album in Lightroom: %s", getDryRunPrefix(isDryRun), albumName)

    if not isDryRun then
        local catalog = LrApplication.activeCatalog()
        catalog:withWriteAccessDo("Create Album", function(context)
            catalog:createCollection(albumName, nil, true)
        end)
    end
end

local function syncAlbums(options)
    local isDryRun = options and options.isDryRun or false
    console:infof('%sStarting album sync%s', getDryRunPrefix(isDryRun), isDryRun and " (no changes will be made)" or "")

    local lightroomAlbums = getLightroomAlbums()
    local immichAlbums = ImmichAPI.getImmichAlbums()

    local selectedAlbums = {}
    if prefs.syncSpecificAlbums and prefs.selectedAlbums then
        console:info(getDryRunPrefix(isDryRun) .. "Running in \"specific album only\" mode...")
        console:debugf(getDryRunPrefix(isDryRun) .. "Selected Albums: %s", prefs.selectedAlbums)
        for album in string.gmatch(prefs.selectedAlbums, "[^;]+") do
            local albumName = album:match("^%s*(.-)%s*$")
            console:infof(getDryRunPrefix(isDryRun) .. "Selected Album: %s", albumName)
            selectedAlbums[albumName] = true
        end
    end

    -- Sync album names between Lightroom and Immich if enabled
    if prefs.syncAlbumNames then
        console:info(getDryRunPrefix(isDryRun) .. "Syncing album names between Lightroom and Immich...")

        -- First, create a copy of the album lists to track changes
        local lightroomAlbumsCopy = {}
        for name, collection in pairs(lightroomAlbums) do
            lightroomAlbumsCopy[name] = collection
        end

        local immichAlbumsCopy = {}
        for name, id in pairs(immichAlbums) do
            immichAlbumsCopy[name] = id
        end

        -- Track albums that have been processed to avoid duplicate operations
        local processedAlbums = {}

        -- For each Lightroom album, find similar albums in Immich
        for lrAlbumName, lrCollection in pairs(lightroomAlbumsCopy) do
            if not processedAlbums[lrAlbumName] and isAlbumSelected(lrAlbumName, selectedAlbums) then
                -- Skip if exact match exists (will be handled by regular sync)
                if not immichAlbums[lrAlbumName] then
                    -- Use user-defined threshold or default to 0.7
                    local threshold = tonumber(prefs.albumSimilarityThreshold) or 0.7
                    local similarImmichName, similarity = findSimilarAlbumName(lrAlbumName, immichAlbumsCopy, threshold)

                    if similarImmichName then
                        -- Check if the Immich album is in the selected albums list when specific albums are enabled
                        local immichAlbumSelected = isAlbumSelected(similarImmichName, selectedAlbums)

                        console:infof(getDryRunPrefix(isDryRun) ..
                                          "Found similar album names - Lightroom: '%s', Immich: '%s', Similarity: %.2f",
                            lrAlbumName, similarImmichName, similarity)

                        -- Only proceed if both albums are selected or specific album sync is disabled
                        if immichAlbumSelected then
                            console:debugf(getDryRunPrefix(isDryRun) .. "Both albums are selected for syncing.")

                            -- Determine which name is better (longer)
                            local betterName = getBetterAlbumName(lrAlbumName, similarImmichName)
                            console:infof(getDryRunPrefix(isDryRun) .. "Using better name: '%s'", betterName)

                            -- Update names in both systems if needed
                            if betterName ~= lrAlbumName then
                                renameLightroomAlbum(lrCollection, betterName, {
                                    isDryRun = isDryRun
                                })
                                if not isDryRun then
                                    -- Update our local copy of the album list
                                    lightroomAlbums[betterName] = lrCollection
                                    lightroomAlbums[lrAlbumName] = nil
                                end
                            end

                            if betterName ~= similarImmichName then
                                local immichAlbumId = immichAlbumsCopy[similarImmichName]
                                console:infof(getDryRunPrefix(isDryRun) ..
                                                  "Updating Immich album name from '%s' to '%s'", similarImmichName,
                                    betterName)

                                if not isDryRun then
                                    ImmichAPI.updateImmichAlbumName(immichAlbumId, betterName)
                                    -- Update our local copy of the album list
                                    immichAlbums[betterName] = immichAlbumId
                                    immichAlbums[similarImmichName] = nil
                                end
                            end

                            -- Mark both albums as processed
                            processedAlbums[lrAlbumName] = true
                            processedAlbums[similarImmichName] = true
                            processedAlbums[betterName] = true
                        else
                            console:infof(getDryRunPrefix(isDryRun) ..
                                              "Skipping album name sync for '%s' and '%s' because one or both are not in the selected albums list.",
                                lrAlbumName, similarImmichName)
                        end
                    end
                end
            end
        end
    else
        console:info(getDryRunPrefix(isDryRun) .. "Album name syncing is disabled. Skipping...")
    end

    -- Create missing albums in Lightroom
    if prefs.createAlbumsInLightroom then
        console:info(getDryRunPrefix(isDryRun) .. "Creating missing albums in Lightroom...")
        for albumName, _ in pairs(immichAlbums) do
            console:debugf(getDryRunPrefix(isDryRun) .. "Checking album: %s", albumName)
            if isAlbumSelected(albumName, selectedAlbums) and not lightroomAlbums[albumName] then
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
        console:info(getDryRunPrefix(isDryRun) .. "Creating missing albums in Immich...")
        for albumName, _ in pairs(lightroomAlbums) do
            console:debugf((isDryRun and "[DRY RUN] " or "") .. "Checking album: %s", albumName)
            if isAlbumSelected(albumName, selectedAlbums) and not immichAlbums[albumName] then
                console:infof((isDryRun and "[DRY RUN] " or "") .. "Creating album in Immich: %s", albumName)
                if not isDryRun then
                    ImmichAPI.createImmichAlbum(albumName)
                    LrDialogs.message("Created album in Immich: " .. albumName)
                end
            end
        end
    end

    -- Sync photo lists between Lightroom and Immich
    console:info(getDryRunPrefix(isDryRun) .. "Syncing photo lists between Lightroom and Immich...")

    for albumName, immichAlbumId in pairs(immichAlbums) do
        local lightroomAlbum = lightroomAlbums[albumName]

        if isAlbumSelected(albumName, selectedAlbums) and lightroomAlbum then
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
                    immichPhotoDatedItems[filename] = {
                        immichPhotoPath = immichPhotoPath,
                        dateDirname = dateDirname,
                        filename = filename,
                        basename = basename
                    }
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

                        -- Choose function based on user preference
                        if prefs.ignoreFileExtensions then
                            -- Use the function that ignores file extensions
                            ImmichAPI.addAssetToAlbumByOriginalPathWithoutExtension(immichAlbumId,
                                dateDirname .. " - " .. filename)
                        else
                            -- Use the original function that requires exact match
                            ImmichAPI.addAssetToAlbumByOriginalPath(immichAlbumId, dateDirname .. " - " .. filename)
                        end
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
