local mod = dmhub.GetModLoading()

--The Hero sheet's own windows: sheet windows opened from the Character tab,
--built on HeroSheetWindow.ShowDialog. Here: Skills (Manage by the Skills
--heading) and Languages (+ Add by Languages). Both host the Builder's Skills
--& Languages component on a draft, so nothing changes until Save, which
--writes it all as one undo step.

HeroSheetWindows = rawget(_G, "HeroSheetWindows") or {}

--A large window (1320 x 820): the body is what is left under the header
--(54 and its rule) and above the footer (60 and its rule).
local SKILLS_WIDTH = 1320
local SKILLS_BODY_HEIGHT = 704

--- Open the Skills or Languages window for the open Hero.
--- @param kind string "skill" or "language"
local function Open(kind)
    local token = HeroSheet.Token()
    if token == nil or token.properties == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local hero = token.properties --[[@as character]]
    local charid = token.charid
    local draft = HeroSkillsLanguages.Read(hero, kind)
    local panel, control = HeroSkillsLanguages.Panel{
        draft = draft,
        width = HeroSheetWindow.DialogWidth(SKILLS_WIDTH),
        height = SKILLS_BODY_HEIGHT,
    }
    local isSkill = kind == "skill"
    HeroSheetWindow.ShowDialog{
        title = cond(isSkill, "Skills", "Languages"),
        subtitle = token.name,
        body = panel,
        width = SKILLS_WIDTH,
        bodyHeight = SKILLS_BODY_HEIGHT,
        flush = true,
        --Esc first clears a selected row, then closes as Cancel.
        onEscape = function()
            return control.ClearSelection()
        end,
        onSave = function()
            --the sheet may have switched Hero under the window (opened from
            --the map): the draft belongs to the Hero it was read from.
            local now = HeroSheet.Token()
            if now == nil or now.charid ~= charid then
                HeroSheetWindow.Toast("The sheet switched Hero, so these changes were not saved.")
                return
            end
            if HeroSkillsLanguages.Changed(draft) then
                HeroSheetWrite.Save{
                    description = cond(isSkill, "Change skills", "Change languages"),
                    execute = function(props)
                        HeroSkillsLanguages.Apply(props --[[@as character]], draft)
                    end,
                }
                --the change is in the live Hero already: redraw the band now
                --rather than waiting for the server's echo.
                HeroSheet.Saved()
            end
            if isSkill then
                HeroSheetWindow.Toast("Skills saved.")
            end
        end,
    }
end

--- The Skills window: grant rows, skills added by hand, and every skill.
function HeroSheetWindows.OpenSkills()
    Open("skill")
end

--- The Languages window: grant rows, languages added by hand, and every
--- language with its speakers.
function HeroSheetWindows.OpenLanguages()
    Open("language")
end
