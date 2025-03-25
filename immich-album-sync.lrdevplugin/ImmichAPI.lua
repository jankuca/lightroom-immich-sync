-- ImmichAPI.lua - Handle API Calls to Immich
local LrHttp = import "LrHttp"
local json = require("json")
local LrPrefs = import "LrPrefs"

local prefs = LrPrefs.prefsForPlugin()

local function getImmichAlbums()
    local response = LrHttp.get(prefs.immichURL .. "/api/albums", {{
        field = "Authorization",
        value = "Bearer " .. prefs.apiKey
    }})

    local albums = {}
    if response then
        local data = json.decode(response)
        for _, album in ipairs(data) do
            albums[album.name] = album.id
        end
    end
    return albums
end

local function createImmichAlbum(albumName)
    local payload = json.encode({
        name = albumName
    })
    local response = LrHttp.post(prefs.immichURL .. "/api/albums", payload, {{
        field = "Authorization",
        value = "Bearer " .. prefs.apiKey
    }, {
        field = "Content-Type",
        value = "application/json"
    }})
    return response
end

local function getPhotosInImmichAlbum(albumId)
    local response = LrHttp.get(prefs.immichURL .. "/api/albums/" .. albumId, {{
        field = "Authorization",
        value = "Bearer " .. prefs.apiKey
    }})

    local photos = {}
    if response then
        local data = json.decode(response)
        for _, photo in ipairs(data.photos) do
            local immichPath = photo.originalPath
            photos[immichPath] = true
        end
    end
    return photos
end

return {
    getImmichAlbums = getImmichAlbums,
    createImmichAlbum = createImmichAlbum,
    getPhotosInImmichAlbum = getPhotosInImmichAlbum
}
