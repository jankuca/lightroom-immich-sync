-- ConfigDialog.lua - Configuration UI
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrPrefs = import "LrPrefs"
local LrApplication = import "LrApplication"

local prefs = LrPrefs.prefsForPlugin()

local function getLightroomAlbums()
    local catalog = LrApplication.activeCatalog()
    local collections = catalog:getChildCollections()

    local albumNames = {}
    for _, collection in ipairs(collections) do
        table.insert(albumNames, collection:getName())
    end
    return albumNames
end

local function showConfigDialog()
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
            title = "Albums to Sync (semicolon separated):",
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
            title = "Ignore file extensions when matching photos",
            value = LrView.bind("ignoreFileExtensions")
        }},

        f:row{f:push_button{
            title = "Save Settings",
            action = function()
                LrDialogs.message("Settings saved.")
            end
        }}
    }

    LrDialogs.presentModalDialog {
        title = "Immich Album Sync Settings",
        contents = c
    }
end

showConfigDialog()
