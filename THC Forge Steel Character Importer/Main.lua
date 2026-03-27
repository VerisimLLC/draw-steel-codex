--[[ 
Module: Forge Steel Character Importer
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Imports characters from Forge Steel into Codex.

Usage:
  In Codex, Tools -> Import Assets -> Forge Steel Character
  
Dependencies:
  Basic Chat Message module
--]]

Commands.RegisterMacro{
    name = "fsci",
    summary = "FSCI debug toggle",
    doc = "Usage: /fsci [d] [v]\nToggles Forge Steel Character Importer debug (d) and verbose (v) modes.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        return {{text = "d", summary = "debug mode"}, {text = "v", summary = "verbose mode"}, {text = "dv", summary = "debug + verbose"}}
    end,
    command = function(args)
        if args and #args then
            if string.find(args:lower(), "d") then FSCIUtils.ToggleDebugMode() end
            if string.find(args:lower(), "v") then FSCIUtils.ToggleVerboseMode() end
        end
        SendTitledChatMessage(string.format("<color=#00cccc>[d]ebug:</color> %s <color=#00cccc>[v]erbose:</color> %s", FSCIUtils.inDebugMode(), FSCIUtils.inVerboseMode()), "fsci", "#e09c9c")
    end,
}

local function debugWriteToFile(dto)
    if FSCIUtils.inDebugMode() then
        local jsonString = dto:ToJSON()
        local writePath = "characters/" .. dmhub.gameid
        local exportFilename = string.format("%s.json", dto:GetCharacterName())
        dmhub.WriteTextFile(writePath, exportFilename, jsonString)
    end
end

import.Register {
    id = "thcfscijson",
    description = "Forge Steel Character (JSON)",
    input = "plaintext",
    priority = 200,

    text = function(importer, text)
        local importer = FSCIImporter:new(text)
        if importer then
            importer:Import()
        else
            FSCIUtils.writeLog("!!!! Could not create Forge Steel importer!", FSCIUtils.STATUS.ERROR)
        end
    end
}