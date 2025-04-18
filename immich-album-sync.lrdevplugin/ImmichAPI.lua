-- ImmichAPI.lua - Handle API Calls to Immich
local LrHttp = import "LrHttp"
local LrLogger = import "LrLogger"
local LrPrefs = import "LrPrefs"
local LrPathUtils = import 'LrPathUtils'

local dkjsonPath = LrPathUtils.child(_PLUGIN.path, "DkJson.lua")
local json = dofile(dkjsonPath)

local console = LrLogger("ImmichAlbumSync")

local prefs = LrPrefs.prefsForPlugin()

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
            albums[album.albumName] = album.id
        end
    end

    return albums
end

local function createImmichAlbum(albumName)
    console:infof("Creating album in Immich: %s", albumName)

    local payload = json.encode({
        name = albumName
    })
    local response = LrHttp.post(prefs.immichURL .. "/api/albums", payload, {{
        field = "x-api-key",
        value = prefs.apiKey
    }, {
        field = "Content-Type",
        value = "application/json"
    }})

    console:debugf("API: Create Immich Albums: %s", response)

    return response
end

local function getPhotosInImmichAlbum(albumId)
    local response = LrHttp.get(prefs.immichURL .. "/api/albums/" .. albumId, {{
        field = "x-api-key",
        value = prefs.apiKey
    }})

    console:debugf("API: Photos in Immich Album: %s", response)
    local data = json.decode(response)

    local photos = {}
    if response then
        for _, photo in ipairs(data.assets) do
            local immichPath = photo.originalPath
            photos[immichPath] = photo.id
        end
    end

    return photos
end

-- Helper function to search for assets by path
local function searchAssetsByPath(searchPath, logMessage)
    local searchPayload = json.encode({
        originalPath = searchPath
    })
    local searchResponse = LrHttp.post(prefs.immichURL .. "/api/search/metadata", searchPayload, {{
        field = "x-api-key",
        value = prefs.apiKey
    }, {
        field = "Content-Type",
        value = "application/json"
    }})

    console:debugf(logMessage, searchPath, searchResponse)

    return json.decode(searchResponse)
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

return {
    getImmichAlbums = getImmichAlbums,
    createImmichAlbum = createImmichAlbum,
    getPhotosInImmichAlbum = getPhotosInImmichAlbum,
    addAssetToAlbumByOriginalPath = addAssetToAlbumByOriginalPath,
    addAssetToAlbumByOriginalPathWithoutExtension = addAssetToAlbumByOriginalPathWithoutExtension
}
