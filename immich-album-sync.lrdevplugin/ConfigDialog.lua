-- ConfigDialog.lua - Configuration UI
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrPrefs = import "LrPrefs"

local prefs = LrPrefs.prefsForPlugin()

local function showConfigDialog()
    local f = LrView.osFactory()

    local c = f:column{
        bind_to_object = prefs,

        f:static_text{
            title = "Immich Sync Configuration",
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
            title = "Create missing albums in Lightroom",
            value = LrView.bind("createAlbumsInLightroom")
        }},

        f:row{f:checkbox{
            title = "Create missing albums in Immich",
            value = LrView.bind("createAlbumsInImmich")
        }},

        f:row{f:checkbox{
            title = "Check for missing photos in Lightroom",
            value = LrView.bind("checkMissingInLightroom")
        }},

        f:row{f:checkbox{
            title = "Check for missing photos in Immich",
            value = LrView.bind("checkMissingInImmich")
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
