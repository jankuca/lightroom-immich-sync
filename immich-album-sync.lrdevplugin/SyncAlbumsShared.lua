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
            -- console:debugf("Similarity between '%s' and '%s': %.2f", albumName, candidateName, similarity)
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

-- Function to find a collection set by name
local function findCollectionSetByName(name, parentSet)
    local catalog = LrApplication.activeCatalog()
    local sets

    if parentSet then
        sets = parentSet:getChildCollectionSets()
    else
        sets = catalog:getChildCollectionSets()
    end

    for _, set in ipairs(sets) do
        if set:getName() == name then
            return set
        end
    end

    return nil
end

-- Function to create a collection set
local function createCollectionSet(name, parentSet, options)
    local isDryRun = options and options.isDryRun or false
    local catalog = LrApplication.activeCatalog()
    local newSet

    console:infof("%sCreating collection set: %s", getDryRunPrefix(isDryRun), name)

    if not isDryRun then
        catalog:withWriteAccessDo("Create Collection Set", function(context)
            newSet = catalog:createCollectionSet(name, parentSet, true)
        end)
    end

    return newSet
end

-- Function to find or create a collection set
local function findOrCreateCollectionSet(name, parentSet, options)
    local isDryRun = options and options.isDryRun or false
    local set = findCollectionSetByName(name, parentSet)

    if not set then
        set = createCollectionSet(name, parentSet, {
            isDryRun = isDryRun
        })
    end

    return set
end

-- Function to find or create a year-based collection set
local function findOrCreateYearCollectionSet(year, rootSet, options)
    local isDryRun = options and options.isDryRun or false
    return findOrCreateCollectionSet(tostring(year), rootSet, {
        isDryRun = isDryRun
    })
end

-- Function to get the root collection set based on user preferences
local function getRootCollectionSet()
    if prefs.rootCollectionSet and prefs.rootCollectionSet ~= "" then
        return findCollectionSetByName(prefs.rootCollectionSet)
    end

    return nil
end

local function getLightroomAlbums()
    local catalog = LrApplication.activeCatalog()
    local collections = {}
    local rootSet = getRootCollectionSet()

    if rootSet then
        local rootCollections = rootSet:getChildCollections()
        for _, collection in ipairs(rootCollections) do
            table.insert(collections, collection)
        end

        -- If organizing by year, also check in year subfolders
        if prefs.organizeByYear then
            local yearSets = rootSet:getChildCollectionSets()
            for _, yearSet in ipairs(yearSets) do
                local yearCollections = yearSet:getChildCollections()
                for _, collection in ipairs(yearCollections) do
                    table.insert(collections, collection)
                end
            end
        end
    else
        collections = catalog:getChildCollections()
    end

    local albums = {}
    for _, collection in ipairs(collections) do
        albums[collection:getName()] = collection
    end
    return albums
end

-- Helper function to get the dry run prefix for log messages
local function getDryRunPrefix(isDryRun)
    return isDryRun and "[DRY RUN] " or ""
end

-- Helper function to check if an album is selected for syncing
local function isAlbumSelected(albumName, selectedAlbums)
    -- If not in specific album mode, all albums are selected
    if not prefs.syncSpecificAlbums then
        return true
    end

    -- Check for exact match first
    if selectedAlbums[albumName] then
        -- console:debugf("Album '%s' matched exactly", albumName)
        return true
    end

    -- Check for substring match
    for selectedAlbumName, _ in pairs(selectedAlbums) do
        if string.find(albumName, selectedAlbumName, 1, true) then
            -- console:debugf("Album '%s' matched by substring '%s'", albumName, selectedAlbumName)
            return true
        end
    end

    return false
end

-- Helper function to show a confirmation dialog for album renaming
local function confirmAlbumRename(source, oldName, newName)
    -- If confirmation is disabled, always return true
    if not prefs.confirmAlbumRenames then
        return true
    end

    local message = string.format("Do you want to rename the %s album?\n\nFrom: %s\nTo: %s", source, oldName, newName)
    local result = LrDialogs.confirm("Confirm Album Rename", message, "Rename")
    return result == "ok"
end

local function createLightroomAlbum(albumName, options)
    local isDryRun = options and options.isDryRun or false
    local startDate = options and options.startDate or nil
    console:infof("%sCreating album in Lightroom: %s", getDryRunPrefix(isDryRun), albumName)

    local newAlbum = nil

    if not isDryRun then
        local catalog = LrApplication.activeCatalog()
        local rootSet = getRootCollectionSet()
        local parentSet = rootSet

        -- If organizing by year and we have a start date, create/find year collection set
        if prefs.organizeByYear and startDate and rootSet then
            local year
            if type(startDate) == "string" then
                -- Extract year from ISO date string (YYYY-MM-DD)
                year = startDate:match("^(%d%d%d%d)")
            end

            if year then
                parentSet = findOrCreateYearCollectionSet(year, rootSet, {
                    isDryRun = isDryRun
                })
                console:infof("%sPlacing album in year collection set: %s", getDryRunPrefix(isDryRun), year)
            end
        end

        if not isDryRun then
            catalog:withWriteAccessDo("Create Album", function(context)
                newAlbum = catalog:createCollection(albumName, parentSet, true)
            end)
        end
    end

    return newAlbum
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
                        console:infof(getDryRunPrefix(isDryRun) ..
                                          "Found similar album names - Lightroom: '%s', Immich: '%s', Similarity: %.2f",
                            lrAlbumName, similarImmichName, similarity)

                        -- Determine which name is better (longer)
                        local betterName = getBetterAlbumName(lrAlbumName, similarImmichName)
                        console:infof(getDryRunPrefix(isDryRun) .. "Using better name: '%s'", betterName)

                        -- Update names in both systems if needed
                        if betterName ~= lrAlbumName then
                            local shouldRename = confirmAlbumRename("Lightroom", lrAlbumName, betterName)

                            if shouldRename then
                                renameLightroomAlbum(lrCollection, betterName, {
                                    isDryRun = isDryRun
                                })
                                if not isDryRun then
                                    -- Update our local copy of the album list
                                    lightroomAlbums[betterName] = lrCollection
                                    lightroomAlbums[lrAlbumName] = nil
                                end
                            else
                                console:infof("User declined to rename Lightroom album from '%s' to '%s'", lrAlbumName,
                                    betterName)
                            end
                        end

                        if betterName ~= similarImmichName then
                            local immichAlbumData = immichAlbumsCopy[similarImmichName]
                            console:infof(getDryRunPrefix(isDryRun) .. "Updating Immich album name from '%s' to '%s'",
                                similarImmichName, betterName)

                            local shouldRename = confirmAlbumRename("Immich", similarImmichName, betterName)

                            if shouldRename then
                                if not isDryRun then
                                    ImmichAPI.updateImmichAlbumName(immichAlbumData.id, betterName)
                                    -- Update our local copy of the album list
                                    immichAlbums[betterName] = immichAlbumData
                                    immichAlbums[similarImmichName] = nil
                                end
                            else
                                console:infof("User declined to rename Immich album from '%s' to '%s'",
                                    similarImmichName, betterName)
                            end
                        end

                        -- Mark the original albums as processed to avoid processing them again
                        processedAlbums[lrAlbumName] = true
                        processedAlbums[similarImmichName] = true

                        -- If either album was renamed, mark the new name as processed too
                        if betterName ~= lrAlbumName or betterName ~= similarImmichName then
                            processedAlbums[betterName] = true
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
        for albumName, albumData in pairs(immichAlbums) do
            -- console:debugf(getDryRunPrefix(isDryRun) .. "Checking album: %s", albumName)
            if isAlbumSelected(albumName, selectedAlbums) and not lightroomAlbums[albumName] then
                local newAlbum = createLightroomAlbum(albumName, {
                    isDryRun = isDryRun,
                    startDate = albumData.startDate
                })
                if not isDryRun then
                    -- Add the newly created album to our list so it will be included in photo syncing
                    if newAlbum then
                        lightroomAlbums[albumName] = newAlbum
                        console:infof("Added newly created album '%s' to the list for photo syncing", albumName)
                    end
                    console:infof("Created album in Lightroom: %s", albumName)
                end
            end
        end
    end

    -- Create missing albums in Immich
    if prefs.createAlbumsInImmich then
        console:info(getDryRunPrefix(isDryRun) .. "Creating missing albums in Immich...")
        for albumName, _ in pairs(lightroomAlbums) do
            -- console:debugf((isDryRun and "[DRY RUN] " or "") .. "Checking album: %s", albumName)
            if isAlbumSelected(albumName, selectedAlbums) and not immichAlbums[albumName] then
                console:infof((isDryRun and "[DRY RUN] " or "") .. "Creating album in Immich: %s", albumName)
                if not isDryRun then
                    -- Create album and get the album data back
                    local albumData = ImmichAPI.createImmichAlbum(albumName)
                    -- Add the newly created album to our list
                    immichAlbums[albumName] = albumData
                    console:infof("Created album in Immich: %s", albumName)
                end
            end
        end
    end

    -- Sync photo lists between Lightroom and Immich
    console:info(getDryRunPrefix(isDryRun) .. "Syncing photo lists between Lightroom and Immich...")

    for albumName, albumData in pairs(immichAlbums) do
        local lightroomAlbum = lightroomAlbums[albumName]

        if isAlbumSelected(albumName, selectedAlbums) and lightroomAlbum then
            console:infof((isDryRun and "[DRY RUN] " or "") .. "Syncing photos for album: %s", albumName)

            -- Get photos in Immich album
            local immichPhotos = ImmichAPI.getPhotosInImmichAlbum(albumData.id)
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
                        -- Extract the full date (YYYY-MM-DD) from the path
                        local dateDirname = lrPath:match(".*(%d%d%d%d%-%d%d%-%d%d)/")

                        -- Choose function based on user preference
                        if prefs.ignoreFileExtensions then
                            -- Use the function that ignores file extensions
                            ImmichAPI.addAssetToAlbumByOriginalPathWithoutExtension(albumData.id,
                                dateDirname .. " - " .. filename)
                        else
                            -- Use the original function that requires exact match
                            ImmichAPI.addAssetToAlbumByOriginalPath(albumData.id, dateDirname .. " - " .. filename)
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
