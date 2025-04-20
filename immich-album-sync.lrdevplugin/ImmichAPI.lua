-- ImmichAPI.lua - Handle API Calls to Immich
local LrHttp = import "LrHttp"
local LrLogger = import "LrLogger"
local LrPrefs = import "LrPrefs"
local LrPathUtils = import 'LrPathUtils'

local dkjsonPath = LrPathUtils.child(_PLUGIN.path, "DkJson.lua")
local json = dofile(dkjsonPath)

local console = LrLogger("ImmichAlbumSync")

local prefs = LrPrefs.prefsForPlugin()

local LrTasks = import "LrTasks"

-- Utility function to retry an API call with exponential backoff
-- Parameters:
--   apiCallFn: Function that performs the API call and returns the result
--   validateFn: Function that validates the result and returns true if valid, false otherwise
--   maxRetries: Maximum number of retry attempts (default: 2)
--   retryDelay: Initial delay in seconds between retries (default: 1)
--   logPrefix: Prefix for log messages (default: "API call")
local function retryApiCall(params)
    local apiCallFn = params.apiCallFn
    local validateFn = params.validateFn
    local maxRetries = params.maxRetries or 2
    local retryDelay = params.retryDelay or 1
    local logPrefix = params.logPrefix or "API call"

    local attempt = 0
    local result

    while attempt <= maxRetries do
        attempt = attempt + 1

        -- Perform the API call
        result = apiCallFn()

        -- Validate the result
        if validateFn(result) then
            return result
        end

        -- Log the retry attempt
        if attempt <= maxRetries then
            console:infof("Retry %d/%d: %s failed, retrying in %d second(s)", attempt, maxRetries, logPrefix, retryDelay)
            LrTasks.sleep(retryDelay)
        end
    end

    console:warnf("All retries failed for %s", logPrefix)
    return result
end

local function getImmichAlbums()
    local response = LrHttp.get(prefs.immichURL .. "/api/albums", {{
        field = "x-api-key",
        value = prefs.apiKey
    }})

    console:debugf("API: Immich Albums: %s", response)

    local albums = {}
    if response then
        local data = json.decode(response)
        for _, album in ipairs(data) do
            -- Store the full album object with metadata
            albums[album.albumName] = {
                id = album.id,
                startDate = album.startDate,
                endDate = album.endDate,
                albumName = album.albumName,
                assetCount = album.assetCount,
                albumInfo = album
            }
        end
    end

    return albums
end

local function createImmichAlbum(albumName)
    console:infof("Creating album in Immich: %s", albumName)

    local payload = json.encode({
        albumName = albumName
    })
    local response = LrHttp.post(prefs.immichURL .. "/api/albums", payload, {{
        field = "x-api-key",
        value = prefs.apiKey
    }, {
        field = "Content-Type",
        value = "application/json"
    }})

    console:debugf("API: Create Immich Albums: %s", response)

    local data = json.decode(response)
    if data then
        return {
            id = data.id,
            startDate = data.startDate,
            endDate = data.endDate,
            albumName = data.albumName,
            albumInfo = data
        }
    end

    return nil
end

local function getPhotosInImmichAlbum(albumId)
    local response = LrHttp.get(prefs.immichURL .. "/api/albums/" .. albumId, {{
        field = "x-api-key",
        value = prefs.apiKey
    }})

    console:debugf("API: Photos in Immich Album: %s", response)
    local data = json.decode(response)

    local photos = {}
    local albumData = {}

    if response and data then
        -- Extract album metadata
        albumData = {
            id = data.id,
            startDate = data.startDate,
            endDate = data.endDate,
            albumName = data.albumName,
            albumInfo = data
        }

        -- Extract photos
        for _, photo in ipairs(data.assets) do
            local immichPath = photo.originalPath
            photos[immichPath] = photo.id
        end
    end

    return photos, albumData
end

-- Helper function to search for assets by path with retries
local function searchAssetsByPath(searchPath, logMessage)
    local searchPayload = json.encode({
        originalPath = searchPath
    })

    local result = retryApiCall({
        apiCallFn = function()
            local searchResponse = LrHttp.post(prefs.immichURL .. "/api/search/metadata", searchPayload, {{
                field = "x-api-key",
                value = prefs.apiKey
            }, {
                field = "Content-Type",
                value = "application/json"
            }})

            local data = searchResponse and json.decode(searchResponse)
            return {
                response = searchResponse,
                data = data
            }
        end,
        validateFn = function(result)
            return result.data and result.data.assets and result.data.assets.items
        end,
        maxRetries = 2,
        retryDelay = 1,
        logPrefix = "Search asset by path: " .. searchPath
    })

    console:debugf(logMessage, searchPath, result.response)

    -- If we still don't have valid data after all retries, return an empty structure
    if not result.data or not result.data.assets or not result.data.assets.items then
        return {
            assets = {
                items = {}
            }
        }
    end

    return result.data
end

-- Helper function to add assets to an album
local function addAssetsToAlbum(albumId, assetIdList)
    if #assetIdList > 0 then
        local insertPayload = json.encode({
            ids = assetIdList
        })
        local insertResponse = LrHttp.post(prefs.immichURL .. "/api/albums/" .. albumId .. "/assets", insertPayload, {{
            field = "x-api-key",
            value = prefs.apiKey
        }, {
            field = "Content-Type",
            value = "application/json"
        }}, 'PUT')

        console:debugf("API: Add Asset to Album: %s -> %s", insertPayload, insertResponse)
        return true
    else
        return false
    end
end

-- Function to add asset to album by exact original path
local function addAssetToAlbumByOriginalPath(albumId, assetOriginalPath)
    console:infof("Adding asset to album: %s -> %s", assetOriginalPath, albumId)

    -- Search for assets with exact path
    local data = searchAssetsByPath(assetOriginalPath, "API: Search Asset by Original Path: %s -> %s")

    -- Collect asset IDs
    local assetIdList = {}
    for _, asset in ipairs(data.assets.items) do
        console:debugf("Found matching asset: %s", asset.originalPath)
        table.insert(assetIdList, asset.id)
    end

    -- Add assets to album
    if not addAssetsToAlbum(albumId, assetIdList) then
        console:infof("No matching assets found for: %s", assetOriginalPath)
    end
end

-- Function to add asset to album by original path without considering file extension
local function addAssetToAlbumByOriginalPathWithoutExtension(albumId, assetOriginalPath)
    console:infof("Adding asset to album (ignoring extension): %s -> %s", assetOriginalPath, albumId)

    -- Extract the filename and remove the extension
    local filename = LrPathUtils.leafName(assetOriginalPath)
    local filenameWithoutExtension = filename:gsub("%.%w+$", "")

    -- Get the path without the filename
    local pathWithoutFilename = string.sub(assetOriginalPath, 1, #assetOriginalPath - #filename)
    local searchPath = pathWithoutFilename .. filenameWithoutExtension

    -- Search for the file using a partial path (without extension)
    local data = searchAssetsByPath(searchPath, "API: Search Asset by Original Path (without extension): %s -> %s")

    -- Collect asset IDs with filename matching (ignoring extension)
    local assetIdList = {}
    for _, asset in ipairs(data.assets.items) do
        -- Extract the filename from the asset's original path
        local assetFilename = LrPathUtils.leafName(asset.originalPath)
        local assetFilenameWithoutExt = assetFilename:gsub("%.%w+$", "")

        -- Check if the base filenames match (ignoring extension)
        if assetFilenameWithoutExt == filenameWithoutExtension then
            console:debugf("Found matching asset (ignoring extension): %s", asset.originalPath)
            table.insert(assetIdList, asset.id)
        end
    end

    -- Add assets to album
    if not addAssetsToAlbum(albumId, assetIdList) then
        console:infof("No matching assets found for: %s", assetOriginalPath)
    end
end

-- Function to update an album name in Immich
local function updateImmichAlbumName(albumId, newName)
    console:infof("Updating album name in Immich: %s -> %s", albumId, newName)

    local payload = json.encode({
        albumName = newName
    })
    local response = LrHttp.post(prefs.immichURL .. "/api/albums/" .. albumId, payload, {{
        field = "x-api-key",
        value = prefs.apiKey
    }, {
        field = "Content-Type",
        value = "application/json"
    }}, 'PATCH')

    console:debugf("API: Update Immich Album Name: %s -> %s", payload, response)

    return response
end

return {
    -- Core API functions
    getImmichAlbums = getImmichAlbums,
    createImmichAlbum = createImmichAlbum,
    getPhotosInImmichAlbum = getPhotosInImmichAlbum,
    addAssetToAlbumByOriginalPath = addAssetToAlbumByOriginalPath,
    addAssetToAlbumByOriginalPathWithoutExtension = addAssetToAlbumByOriginalPathWithoutExtension,
    updateImmichAlbumName = updateImmichAlbumName,

    -- Utility functions
    retryApiCall = retryApiCall
}
