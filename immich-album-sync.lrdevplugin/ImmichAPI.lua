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

local function addAssetToAlbumByOriginalPath(albumId, assetOriginalPath)
    console:infof("Adding asset to album: %s -> %s", assetOriginalPath, albumId)

    local searchPayload = json.encode({
        originalPath = assetOriginalPath
    })
    local searchResponse = LrHttp.post(prefs.immichURL .. "/api/search/metadata", searchPayload, {{
        field = "x-api-key",
        value = prefs.apiKey
    }, {
        field = "Content-Type",
        value = "application/json"
    }})

    console:debugf("API: Search Asset by Original Path: %s -> %s", assetOriginalPath, searchResponse)

    local data = json.decode(searchResponse)
    local assetIds = {}
    for _, asset in ipairs(data.assets.items) do
        assetIds[asset.id] = asset.originalPath
    end

    local assetIdList = {}
    for assetId, _ in pairs(assetIds) do
        console:debugf("Adding asset to album: %s -> %s", assetId, albumId)
        table.insert(assetIdList, assetId)
    end

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
end

return {
    getImmichAlbums = getImmichAlbums,
    createImmichAlbum = createImmichAlbum,
    getPhotosInImmichAlbum = getPhotosInImmichAlbum,
    addAssetToAlbumByOriginalPath = addAssetToAlbumByOriginalPath
}
