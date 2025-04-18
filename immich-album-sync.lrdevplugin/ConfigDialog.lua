-- ConfigDialog.lua - Configuration UI
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrPrefs = import "LrPrefs"
local LrApplication = import "LrApplication"
local LrTasks = import "LrTasks"

local prefs = LrPrefs.prefsForPlugin()

-- Set default values if not already set
if not prefs.albumSimilarityThreshold then
    prefs.albumSimilarityThreshold = "0.7"
end

if prefs.syncAlbumNames == nil then
    prefs.syncAlbumNames = true
end

if prefs.confirmAlbumRenames == nil then
    prefs.confirmAlbumRenames = true
end

if prefs.rootCollectionSet == nil then
    prefs.rootCollectionSet = ""
end

if prefs.organizeByYear == nil then
    prefs.organizeByYear = false
end

local function getLightroomAlbums()
    local catalog = LrApplication.activeCatalog()
    local collections = catalog:getChildCollections()

    local albumNames = {}
    for _, collection in ipairs(collections) do
        table.insert(albumNames, collection:getName())
    end
    return albumNames
end

-- Start the main task to show the config dialog
LrTasks.startAsyncTask(function()

    local f = LrView.osFactory()

    local c = f:column{
        bind_to_object = prefs,

        f:static_text{
            title = "Immich Album Sync Configuration",
            font = "<system/bold>"
        },

        f:row{f:static_text{
            title = "Immich Server URL:"
        }, f:edit_field{
            value = LrView.bind("immichURL"),
            width_in_chars = 30
        }},

        f:row{f:static_text{
            title = "API Key:"
        }, f:edit_field{
            value = LrView.bind("apiKey"),
            width_in_chars = 30,
            password = true
        }},

        f:row{f:checkbox{
            title = "Sync only selected albums",
            value = LrView.bind("syncSpecificAlbums")
        }},

        f:row{f:edit_field{
            title = "Albums to Sync (semicolon separated, supports substring matching):",
            value = LrView.bind("selectedAlbums"),
            width_in_chars = 40
        }},

        f:row{f:checkbox{
            title = "Create missing albums in Lightroom",
            value = LrView.bind("createAlbumsInLightroom")
        }},

        f:row{f:checkbox{
            title = "Create missing albums in Immich",
            value = LrView.bind("createAlbumsInImmich")
        }},

        f:row{f:checkbox{
            title = "Sync album names (match similar names)",
            value = LrView.bind("syncAlbumNames")
        }},

        f:row{f:checkbox{
            title = "Confirm album renames",
            value = LrView.bind("confirmAlbumRenames")
        }},

        f:row{f:checkbox{
            title = "Ignore file extensions when matching photos",
            value = LrView.bind("ignoreFileExtensions")
        }},

        f:row{f:static_text{
            title = "Album name similarity threshold (0.0-1.0):"
        }, f:edit_field{
            value = LrView.bind("albumSimilarityThreshold"),
            width_in_chars = 5,
            validate = function(view, value)
                local num = tonumber(value)
                if not num or num < 0 or num > 1 then
                    return false, "Please enter a number between 0.0 and 1.0"
                end
                return true
            end,
            immediate = true
        }},

        f:separator{
            fill_horizontal = 1
        },

        f:static_text{
            title = "Lightroom Collection Organization",
            font = "<system/bold>"
        },

        f:row{f:static_text{
            title = "Root Collection Set Name:"
        }, f:edit_field{
            value = LrView.bind("rootCollectionSet"),
            width_in_chars = 30,
            immediate = true
        }},

        f:row{f:checkbox{
            title = "Organize albums by year",
            value = LrView.bind("organizeByYear")
        }},

        f:row{f:push_button{
            title = "Save Settings",
            action = function()
                LrDialogs.message("Settings saved.")
            end
        }}
    }

    -- Show the dialog
    LrDialogs.presentModalDialog {
        title = "Immich Album Sync Settings",
        contents = c
    }

end)
