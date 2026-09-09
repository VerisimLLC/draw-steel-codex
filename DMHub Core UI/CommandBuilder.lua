local mod = dmhub.GetModLoading()

--CommandBuilder: the "no code" macro builder ("command creation mode").
--
--A journal command button starts a recording session (CommandBuilder.Begin,
--called from the rich-tag info popup in MarkdownDocument.lua). While the
--session is active, opt-in UI across the app shows a lightning affordance
--(CommandBuilder.LightningIcon) whose click menu records steps, and a
--floating, moveable, resizable dialog (CreateDialog, auto-opened by the
--CreateDialogHost mount point CodexTitleBar.lua embeds) shows the recorded
--steps vertically with Cancel/Done.
--
--Completing the session joins the steps with "; " -- the engine's
--CommandController already splits a command line on ';' and runs the parts in
--order -- and hands the single command string back to whoever began the
--session, which writes it into the [[/command|label]] journal macro.
--
--The mode flag is a transient setting: flipping it fires "monitor" events on
--every live panel that declares multimonitor = {"commandcreationmode"} (the
--same mechanism settings checkboxes use), and panels being created just call
--CommandBuilder.IsActive().

CommandBuilder = {}

local g_modeSetting = setting{
    id = "commandcreationmode",
    description = "Command Creation Mode",
    storage = "transient",
    default = false,
}

--{ steps = { {command = string, text = string}, ... },
--  complete = function(commandString), cancel = function|nil }
local g_session = nil

--The recorder dialog (see CreateDialog), when open. It closes itself when
--the session ends and is opened by Begin / the CreateDialogHost mount point
--via EnsureDialogOpen (forward-declared; defined after CreateDialog).
local g_dialog = nil
local EnsureDialogOpen

--A Lua reload tears down the session table but the transient setting
--survives; reset it so lingering lightning icons do not show for a session
--that no longer exists.
if g_modeSetting:Get() then
    g_modeSetting:Set(false)
end

--Step annotation format: a step inside a stored command pipe may carry a
--descriptive name in braces after the command, e.g.
--    roll 1d6 {Roll 1d6}; toggle showgrid {Toggle Show Grid}
--The name is builder metadata only: it is stripped before execution (see
--CommandBuilder.StripAnnotations, used by RichMacro when a journal button is
--pressed) and is used to label the step chips when a command is loaded back
--into the builder. Names must not contain ';', '{' or '}' -- the lightning
--menus only produce plain text, so this is not enforced per character.

--Encode one step for storage. The annotation is only added when the text is
--a real descriptive name rather than the "/command" default.
function CommandBuilder.EncodeStep(command, text)
    if text ~= nil and text ~= "" and text ~= "/" .. command then
        return string.format("%s {%s}", command, text)
    end
    return command
end

--Decode one stored step: returns command, name (name is nil when the step
--has no annotation).
function CommandBuilder.ParseStep(stepString)
    local command, name = stepString:match("^(.-)%s*{(.-)}%s*$")
    if command ~= nil then
        command = command:match("^%s*(.-)%s*$")
        if name ~= "" then
            return command, name
        end
        return command, nil
    end
    return stepString:match("^%s*(.-)%s*$"), nil
end

--Strip {name} annotations from a full command pipe, producing the string
--that should actually be executed.
function CommandBuilder.StripAnnotations(commandString)
    if commandString == nil or string.find(commandString, "{", 1, true) == nil then
        return commandString
    end
    local parts = {}
    for part in string.gmatch(commandString, "[^;]+") do
        local command = CommandBuilder.ParseStep(part)
        if command ~= "" then
            parts[#parts+1] = command
        end
    end
    return table.concat(parts, "; ")
end

--PERF instrumentation: cumulative construction cost of lightning affordances
--since load, in CPU seconds (os.clock). Hosts that build many icons snapshot
--this before/after to attribute their own build time -- the settings dialog
--prints the delta on every open (SETTINGSPERF:: in the log).
CommandBuilder.profile = {
    count = 0,
    seconds = 0,
}

function CommandBuilder.IsActive()
    return g_session ~= nil
end

function CommandBuilder.GetSteps()
    if g_session == nil then
        return {}
    end
    return g_session.steps
end

local function RefreshDialog()
    if g_dialog ~= nil and g_dialog.valid then
        g_dialog:FireEventTree("refreshCommandBuilder")
    end
end

--Begin a command creation session.
--options.seedCommand: the button's existing command (without the leading /);
--  it is split on ';' and preloaded as already-recorded steps so the user
--  extends the button rather than losing what it did.
--options.complete: function(commandString) called when the user hits Done.
--options.cancel: optional function() called when the user cancels.
function CommandBuilder.Begin(options)
    if g_session ~= nil then
        CommandBuilder.Cancel()
    end

    local steps = {}
    local seed = options.seedCommand
    if seed ~= nil and seed ~= "" then
        for part in string.gmatch(seed, "[^;]+") do
            local command, name = CommandBuilder.ParseStep(part)
            if command ~= "" then
                steps[#steps+1] = { command = command, text = name or ("/" .. command) }
            end
        end
    end

    --assign the session before flipping the setting so monitor handlers that
    --read CommandBuilder.IsActive() see the mode as active.
    g_session = {
        steps = steps,
        complete = options.complete,
        cancel = options.cancel,
    }
    g_modeSetting:Set(true)
    --open the recorder dialog directly rather than waiting on the setting
    --monitor -- the dialog host's monitor also opens it, but this way the
    --dialog appears even if a monitor firing is missed or coalesced.
    EnsureDialogOpen(nil)
    RefreshDialog()
end

function CommandBuilder.Cancel()
    local session = g_session
    if session == nil then
        return
    end
    g_session = nil
    g_modeSetting:Set(false)
    if session.cancel ~= nil then
        session.cancel()
    end
    RefreshDialog()
end

function CommandBuilder.Complete()
    local session = g_session
    if session == nil or #session.steps == 0 then
        return
    end
    g_session = nil
    g_modeSetting:Set(false)

    local commands = {}
    for _,step in ipairs(session.steps) do
        commands[#commands+1] = CommandBuilder.EncodeStep(step.command, step.text)
    end
    session.complete(table.concat(commands, "; "))
    RefreshDialog()
end

--Append one step to the recording.
--options.command: the slash command to run (without the leading /).
--options.text: short human label shown in the recorder chip.
function CommandBuilder.RecordStep(options)
    if g_session == nil then
        return
    end
    g_session.steps[#g_session.steps+1] = {
        command = options.command,
        text = options.text or ("/" .. options.command),
    }
    RefreshDialog()
end

function CommandBuilder.RemoveStep(index)
    if g_session == nil then
        return
    end
    table.remove(g_session.steps, index)
    RefreshDialog()
end

--Move a step so it sits at the given insertion position (1..#steps+1,
--interpreted against the list BEFORE the step is removed -- i.e. "insert
--before the step currently at insertBefore").
function CommandBuilder.MoveStep(fromIndex, insertBefore)
    if g_session == nil then
        return
    end
    local steps = g_session.steps
    local step = steps[fromIndex]
    if step == nil then
        return
    end
    table.remove(steps, fromIndex)
    if insertBefore > fromIndex then
        insertBefore = insertBefore - 1
    end
    insertBefore = clamp(insertBefore, 1, #steps + 1)
    table.insert(steps, insertBefore, step)
    RefreshDialog()
end

--Replace a recorded step's command (and optionally its label) in place.
function CommandBuilder.UpdateStep(index, options)
    if g_session == nil then
        return
    end
    local step = g_session.steps[index]
    if step == nil then
        return
    end
    if options.command ~= nil then
        step.command = options.command
    end
    if options.text ~= nil then
        step.text = options.text
    end
    RefreshDialog()
end

--Shared styles for every lightning icon. MergeTokens, NOT MergeStyles: the
--icons sit downstream of hosts that already own the full theme cascade
--(settings dialog, title bar), and MergeStyles would bundle the entire base
--theme into every icon -- measured at ~95ms per icon, 2.7s of a settings
--open. Cached because the rules are identical for every icon; invalidated on
--theme/scheme change so newly built icons pick up fresh colors (live icons
--recolor when their host rebuilds, which theme changes already trigger).
--
--EnsureThemeSubscription is forward-declared here and assigned below, after
--all three caches exist so the handler can close over them. See its
--definition for why the subscription is lazy rather than at file scope.
local EnsureThemeSubscription

local g_lightningStyles = nil

local function LightningStyles()
    if g_lightningStyles == nil then
        EnsureThemeSubscription()
        g_lightningStyles = ThemeEngine.MergeTokens{
            {
                selectors = {"commandBuilderLightning"},
                bgimage = "phosphor/lightning-duotone.png",
                bgcolor = "@accent",
            },
            {
                selectors = {"commandBuilderLightning", "hover"},
                bgimage = "phosphor/lightning-fill.png",
                bgcolor = "@accentHover",
            },
        }
    end
    return g_lightningStyles
end

--Styles for the command browser popup (see CreateCommandBrowserPopup). Same
--MergeTokens-not-MergeStyles + cache treatment as the lightning styles.
local g_browserStyles = nil

local function BrowserStyles()
    if g_browserStyles == nil then
        EnsureThemeSubscription()
        g_browserStyles = ThemeEngine.MergeTokens{
            {
                selectors = {"commandBrowserRow"},
                bgimage = true,
                bgcolor = "clear",
            },
            {
                selectors = {"commandBrowserRow", "hover"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"commandBrowserRow", "selected"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"commandBrowserName"},
                color = "@fg",
            },
            {
                selectors = {"commandBrowserName", "parent:selected"},
                color = "@accent",
            },
            {
                selectors = {"commandBrowserDescription"},
                color = "@fgMuted",
            },
            {
                selectors = {"commandBrowserParamLabel"},
                color = "@fg",
            },
        }
    end
    return g_browserStyles
end

--Styles for the recorder dialog (see CreateDialog). Unlike the lightning
--icons, the dialog is a standalone floating window mounted at the top level
--rather than downstream of an existing theme cascade, so it is a cascade
--ROOT: MergeStyles (base theme + these rules) is the correct call here.
--Cached because sessions reopen the dialog; invalidated on theme change so
--the next open picks up fresh colors.
local g_dialogStyles = nil

local function DialogStyles()
    if g_dialogStyles == nil then
        EnsureThemeSubscription()
        g_dialogStyles = ThemeEngine.MergeStyles{
            {
                selectors = {"commandBuilderTitle"},
                color = "@accent",
            },
            {
                selectors = {"commandBuilderIcon"},
                bgcolor = "@fg",
            },
            {
                selectors = {"commandBuilderIcon", "hover"},
                bgcolor = "@fgStrong",
            },
            {
                selectors = {"commandBuilderDialogRow"},
                bgimage = true,
                bgcolor = "clear",
            },
            {
                selectors = {"commandBuilderDialogRow", "hover"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"commandBuilderDialogIndex"},
                color = "@fgMuted",
            },
            {
                selectors = {"commandBuilderDialogLabel"},
                color = "@fg",
            },
            {
                selectors = {"commandBuilderDialogCommand"},
                color = "@fgMuted",
            },
            --reorder drop zones between rows: invisible at rest, an accent
            --bar while a row drag hovers the gap. Deliberately no
            --"drag-target" rule -- a global rule paints that class always.
            --Zero height would reclaim the 4px but a zero-area panel cannot
            --be hovered, which would kill reordering entirely.
            {
                selectors = {"commandBuilderDialogDropTarget"},
                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = 4,
            },
            {
                selectors = {"commandBuilderDialogDropTarget", "drag-target-hover"},
                bgcolor = "@accent",
                height = 6,
            },
        }
    end
    return g_dialogStyles
end

--Invalidate the caches above whenever the theme or color scheme changes.
--
--Subscribed on first use rather than at file scope, and NOT because it is
--cheaper: ThemeEngine.OnThemeChanged goes through EventUtils, which is
--defined by Utils.lua in this same mod. File load order comes from the
--module's cloud configuration, so this file can (and currently does) load
--before Utils -- a file-scope call raises "Attempt to read uninitialized
--variable EventUtils" and aborts the rest of this file at startup. Every
--caller of the three getters runs at panel-build time, long after every
--file has loaded, so the first style build is always a safe place to
--subscribe. Keep any future OnThemeChanged call in this file behind the
--same latch.
--
--g_themeSub is deliberately not cleared by the handler -- it latches the
--subscription for the life of the mod (EventUtils drops the handler on mod
--unload, and a reload re-runs this file with the latch back to nil).
local g_themeSub = nil

EnsureThemeSubscription = function()
    if g_themeSub ~= nil then
        return
    end
    g_themeSub = ThemeEngine.OnThemeChanged(mod, function()
        g_lightningStyles = nil
        g_browserStyles = nil
        g_dialogStyles = nil
    end)
end

--The macros that opted into being surfaced as user-facing commands by
--passing commandInfo to Commands.RegisterMacro (see Utils.lua for the
--shape). Returns { { macro = registered name, info = commandInfo }, ... }
--sorted by display name. Read fresh each time the browser opens so late
--registrations show up -- and so the dmonly filter below reflects the
--current user rather than whoever was logged in when the file loaded.
--
--commandInfo.dmonly marks a macro whose body returns early on
--`not dmhub.isDM`. Recording one as a player produces a button that silently
--does nothing, so those rows are omitted entirely rather than shown and
--disabled.
function CommandBuilder.GetSurfacedCommands()
    local result = {}
    local isDM = dmhub.isDM
    for macroName,macroInfo in pairs(Commands.GetAllMacros()) do
        local info = macroInfo.commandInfo
        if info ~= nil and (isDM or not info.dmonly) then
            result[#result+1] = {
                macro = macroName,
                info = info,
            }
        end
    end
    table.sort(result, function(a, b)
        return (a.info.name or a.macro) < (b.info.name or b.macro)
    end)
    return result
end

--How the "Send to all players" option applies to a surfaced command (see the
--commandInfo contract in Utils.lua). Returns optional (whether the user gets
--a check to toggle it) and defaultOn (its initial state).
local function BroadcastOption(info)
    local mode = info ~= nil and info.broadcast or nil
    if mode == "always" then
        return false, true
    elseif mode == "on" or mode == true then
        return true, true
    elseif mode == "off" then
        return true, false
    end
    return false, false
end

--Param kinds. A param with no type is a number on a slider (the original and
--still the common case). "choices" is a dropdown, "audio" the sound picker
--widget, "text" a free-text input. See the commandInfo contract in Utils.lua
--for the full field list.
local function ParamIsText(param)
    return param.type == "text"
end

--Params whose baked argument is a single opaque token (an id) rather than a
--number: they bake and unbake verbatim.
local function ParamIsString(param)
    return param.type == "choices" or param.type == "audio"
end

--Free text has to survive two layers that carve up a command string: the
--engine splits a command line on ';' (CommandController.ExecuteCommandPipe),
--and a recorded step may carry a "{Name}" annotation. A title containing any
--of those three characters would silently split the step or eat the
--annotation, so they are dropped rather than escaped -- there is nothing a
--banner title needs them for.
local function SanitizeText(text)
    return (string.gsub(text, "[;{}]", ""))
end

--Index of the first text param, or nil. Text params are the tail of the
--argument string -- everything before them is one whitespace token each --
--so this is the boundary between the two baking/parsing regimes.
local function FirstTextParam(params)
    for i,param in ipairs(params or {}) do
        if ParamIsText(param) then
            return i
        end
    end
    return nil
end

--Options for a "choices" param, as {{id=, text=}, ...}. An explicit
--param.options wins; otherwise the macro's own chat-completion function is
--reused. Every command that wants a dropdown already ships one for the chat
--input, and reusing it means the browser and the typed command always offer
--the same list. Completion entries are {text = value, summary = label} or
--bare strings.
local function ResolveChoices(macroName, param, index)
    if param.options ~= nil then
        return param.options
    end
    local macroInfo = Commands.GetMacroInfo(macroName) or Commands.GetMacroInfo(string.lower(macroName))
    local completions = macroInfo ~= nil and macroInfo.completions or nil
    if completions == nil then
        return {}
    end
    --completions is authored for the chat input and can touch tables that do
    --not exist yet (no map loaded, asset table still downloading); a throw
    --here would take the whole popup down.
    local ok, list = pcall(completions, {}, index)
    if not ok or type(list) ~= "table" then
        return {}
    end
    local result = {}
    for _,entry in ipairs(list) do
        if type(entry) == "table" then
            result[#result+1] = {id = entry.text, text = entry.summary or entry.text}
        else
            result[#result+1] = {id = entry, text = entry}
        end
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    return result
end

--Bake a surfaced command string: the macro name followed by its arguments in
--params order. Numbers use %g, which keeps floats compact and drops slider
--rounding residue. Choice values go in verbatim (they are ids, never
--multi-word). Text params are appended raw -- a blank one is dropped, and a
--joiner declared on a text param is emitted just before it, which is how a
--macro that takes one free-form line with an internal separator (e.g.
--"/dramaticbanner <title> | <subtitle>") is expressed.
--
--broadcast wraps the whole thing in /broadcast, which runs it locally and
--sends it to every other client on the map (LuaInterface.Broadcast ->
--PlayerMessageMacro; the sender is skipped on receipt, so it fires exactly
--once per client). The wrapper carries no ';' so it stays a single step.
local function BakeParamsCommand(macroName, params, values, broadcast)
    local parts = {macroName}
    for i,param in ipairs(params or {}) do
        if ParamIsText(param) then
            local text = string.trim(SanitizeText(tostring(values[i] or "")))
            if text ~= "" then
                if param.joiner ~= nil then
                    parts[#parts+1] = param.joiner
                end
                parts[#parts+1] = text
            end
        elseif ParamIsString(param) then
            parts[#parts+1] = tostring(values[i] or "")
        else
            parts[#parts+1] = string.format("%g", values[i])
        end
    end
    local command = table.concat(parts, " ")
    if broadcast then
        return "broadcast " .. command
    end
    return command
end

--The inverse of BakeParamsCommand's argument half: read `argString` back
--into a values table. Leading non-text params take one whitespace token
--each; the rest of the line belongs to the text params, cut at the joiner
--each subsequent one declares. Missing or unparseable arguments fall back to
--the param's default.
--
--Returns nil when a params-only command carries MORE arguments than its
--params describe -- rebaking such a step would silently drop the extras, so
--it is better to leave it uneditable than to eat part of it.
local function UnbakeParams(argString, params)
    local values = {}
    local rest = argString or ""
    local firstText = FirstTextParam(params)
    local lastPositional = (firstText or (#params + 1)) - 1

    for i = 1, lastPositional do
        local param = params[i]
        local token, remainder = string.match(rest, "^%s*(%S+)(.*)$")
        rest = remainder or ""
        if ParamIsString(param) then
            values[i] = token or param.default or ""
        else
            values[i] = tonumber(token or "") or param.default or param.min or 0
        end
    end

    if firstText == nil then
        if string.match(rest, "%S") ~= nil then
            return nil
        end
        return values
    end

    for i = firstText, #params do
        --a text param after the first is introduced by its joiner, so the
        --previous one ends there.
        local nextJoiner = nil
        if i < #params then
            nextJoiner = params[i+1].joiner
        end
        local at = nil
        if nextJoiner ~= nil then
            at = string.find(rest, nextJoiner, 1, true)
        end
        if at == nil then
            values[i] = string.trim(rest)
            rest = ""
        else
            values[i] = string.trim(string.sub(rest, 1, at - 1))
            rest = string.sub(rest, at + #nextJoiner)
        end
    end

    return values
end

--Whether every param has a usable value, i.e. whether Add Step / Apply
--should be live. Only text params can be empty, and only a required one
--blocks.
local function ParamsAreComplete(params, values)
    for i,param in ipairs(params or {}) do
        --sanitize first: a value of nothing but stripped characters bakes to
        --empty, so it must not read as complete here.
        if param.required and string.trim(SanitizeText(tostring(values[i] or ""))) == "" then
            return false
        end
    end
    return true
end

--The "Send to all players" check. setValue receives the new state.
local function BuildBroadcastRow(value, setValue)
    return gui.Check{
        text = "Send to all players",
        tooltip = "Run this step on every player's screen, not just the screen of whoever presses the button.",
        value = value,
        fontSize = 12,
        width = "100%",
        height = 26,
        change = function(element)
            setValue(element.value)
        end,
    }
end

--Build one label+control row per param: a slider for a number, a dropdown
--for "choices", an input for "text". Edits write into `values` (keyed by
--param index); the caller bakes `values` when the user confirms. onChanged
--(optional) fires after any edit so the host can re-evaluate whether its
--confirm button should be live.
--Shared by the command browser's detail section and the chip cog editor.
local function BuildParamRows(macroName, params, values, onChanged)
    local function Changed()
        if onChanged ~= nil then
            onChanged()
        end
    end

    local rows = {}
    for i,param in ipairs(params or {}) do
        local index = i
        local control
        local rowHeight = 26

        if param.type == "audio" then
            --the app's own sound picker: it shows the sound's name rather
            --than its guid, previews it, and lets the user upload a new one
            --from the popup without leaving the builder.
            rowHeight = 56
            control = gui.AudioEditor{
                value = values[index],
                width = 48,
                height = 48,
                halign = "right",
                valign = "center",
                change = function(element)
                    values[index] = element.value
                    Changed()
                end,
            }
        elseif ParamIsText(param) then
            control = gui.Input{
                text = tostring(values[index] or ""),
                placeholderText = param.placeholder,
                fontSize = 12,
                width = 200,
                height = 22,
                halign = "right",
                valign = "center",
                borderBox = true,
                --editlag keeps every keystroke from rebuilding the host; the
                --change on focus loss catches the final edit either way.
                editlag = 0.25,
                edit = function(element)
                    values[index] = element.text
                    Changed()
                end,
                change = function(element)
                    values[index] = element.text
                    Changed()
                end,
            }
        elseif param.type == "choices" then
            control = gui.Dropdown{
                --the lists behind these come from asset/data tables and can
                --run to hundreds of entries (every audio asset in the game),
                --so the search field is not optional.
                hasSearch = true,
                options = ResolveChoices(macroName, param, index),
                idChosen = values[index],
                fontSize = 12,
                width = 200,
                height = 22,
                halign = "right",
                valign = "center",
                change = function(element)
                    values[index] = element.idChosen
                    Changed()
                end,
            }
        else
            control = gui.Slider{
                minValue = param.min,
                maxValue = param.max,
                value = values[index],
                round = param.round,

                sliderWidth = 150,
                labelWidth = 44,
                labelFormat = param.labelFormat or "%.1f",
                events = {
                    change = function(element)
                        values[index] = element.data.getValue()
                        Changed()
                    end,
                    confirm = function(element)
                        values[index] = element.data.getValue()
                        Changed()
                    end,
                },
                style = {
                    width = 200,
                    height = 22,
                    fontSize = 12,
                    halign = "right",
                    valign = "center",
                },
            }
        end

        rows[#rows+1] = gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = rowHeight,

            gui.Label{
                classes = {"commandBrowserParamLabel"},
                text = string.format("%s:", param.name),
                fontSize = 12,
                width = 90,
                height = "auto",
                valign = "center",
                textWrap = false,
            },

            control,
        }
    end
    return rows
end

--If a recorded step's command invokes a macro surfaced with something the
--step editor can edit, return the macro name, its commandInfo, the parsed
--positional values (falling back to a param's default for missing or
--non-numeric arguments), and whether the step is broadcast-wrapped. Returns
--nil for anything else -- including a surfaced macro given MORE arguments
--than its params describe, since rebaking such a step would silently drop
--the extras.
--
--A leading "broadcast" is peeled off first: BakeParamsCommand may have added
--it, and /broadcast itself is not surfaced, so without this a wrapped step
--would look unrecognizable and lose its cog.
function CommandBuilder.ParseSurfacedStep(command)
    if command == nil then
        return nil
    end
    local rest = string.trim(command)
    local broadcast = false
    local head, tail = string.match(rest, "^(%S+)%s*(.*)$")
    if head ~= nil and string.lower(head) == "broadcast" then
        broadcast = true
        rest = tail
        head, tail = string.match(rest, "^(%S+)%s*(.*)$")
    end
    if head == nil then
        return nil
    end
    local macros = Commands.GetAllMacros()
    local macroName = head
    local macroInfo = macros[macroName] or macros[string.lower(macroName)]
    local info = macroInfo ~= nil and macroInfo.commandInfo or nil
    if info == nil then
        return nil
    end
    local params = info.params or {}
    local broadcastOptional = BroadcastOption(info)
    --nothing to put in the editor: no params and no broadcast choice.
    if #params == 0 and not broadcastOptional then
        return nil
    end
    local values = UnbakeParams(tail, params)
    if values == nil then
        return nil
    end
    return macroName, info, values, broadcast
end

--The popup opened by a step chip's cog: the surfaced macro's param controls
--seeded with the step's current values, and Apply rebakes them into the step.
function CommandBuilder.CreateStepEditorPopup(iconElement, stepIndex)
    local step = CommandBuilder.GetSteps()[stepIndex]
    if step == nil then
        return nil
    end
    local macroName, info, values, broadcast = CommandBuilder.ParseSurfacedStep(step.command)
    if macroName == nil then
        return nil
    end

    --a command declared "always" stays wrapped even if the step predates the
    --declaration; otherwise the step's own state is what the check shows.
    local broadcastOptional, broadcastDefault = BroadcastOption(info)
    if not broadcastOptional then
        broadcast = broadcastDefault
    end

    local m_applyButton

    local children = {
        gui.Label{
            text = info.name or macroName,
            bold = true,
            fontSize = 13,
            width = "auto",
            height = "auto",
            bmargin = 4,
        },
    }
    local rows = BuildParamRows(macroName, info.params, values, function()
        if m_applyButton ~= nil and m_applyButton.valid then
            m_applyButton:SetClass("disabled", not ParamsAreComplete(info.params, values))
        end
    end)
    for _,row in ipairs(rows) do
        children[#children+1] = row
    end
    if broadcastOptional then
        children[#children+1] = BuildBroadcastRow(broadcast, function(value)
            broadcast = value
        end)
    end
    m_applyButton = gui.Button{
        text = "Apply",
        classes = {cond(ParamsAreComplete(info.params, values), nil, "disabled")},
        fontSize = 12,
        width = "auto",
        height = 24,
        hpad = 10,
        borderBox = true,
        halign = "right",
        tmargin = 6,
        click = function(element)
            if element:HasClass("disabled") then
                return
            end
            CommandBuilder.UpdateStep(stepIndex, {
                command = BakeParamsCommand(macroName, info.params, values, broadcast),
            })
            iconElement.popup = nil
        end,
    }
    children[#children+1] = m_applyButton

    return gui.Panel{
        classes = {"bordered", "bg"},
        styles = BrowserStyles(),
        flow = "vertical",
        width = 340,
        height = "auto",
        pad = 8,
        borderBox = true,
        children = children,
    }
end

--The small dialog opened by the recorder's + button: a filterable list of
--surfaced commands; selecting one shows a slider per parameter, and Add
--Step bakes the chosen values into the recorded command as positional
--arguments. Closes itself by clearing iconElement.popup.
function CommandBuilder.CreateCommandBrowserPopup(iconElement)
    local commands = CommandBuilder.GetSurfacedCommands()

    local resultPanel
    local m_detailPanel
    local m_addButton
    local m_browsePanel      --title + filter + the list of rows
    local m_selectionPanel   --the chosen command's name, params and buttons
    local m_selectionTitle
    local m_selectionDescription

    local m_selected = nil    --entry from commands
    local m_values = {}       --current value per param index for the selection
    local m_broadcast = false --whether to wrap the selection in /broadcast

    local function BakedCommand()
        return BakeParamsCommand(m_selected.macro, m_selected.info.params, m_values, m_broadcast)
    end

    local function RefreshAddButton()
        if m_addButton == nil or not m_addButton.valid then
            return
        end
        local ready = m_selected ~= nil and ParamsAreComplete(m_selected.info.params, m_values)
        m_addButton:SetClass("disabled", not ready)
    end

    local function RebuildDetail()
        if m_detailPanel == nil or not m_detailPanel.valid then
            return
        end
        local children = {}
        if m_selected ~= nil then
            children = BuildParamRows(m_selected.macro, m_selected.info.params, m_values, RefreshAddButton)
            if BroadcastOption(m_selected.info) then
                children[#children+1] = BuildBroadcastRow(m_broadcast, function(value)
                    m_broadcast = value
                end)
            end
        end
        m_detailPanel.children = children
        m_detailPanel:SetClass("collapsed", m_selected == nil or #children == 0)
        RefreshAddButton()
    end

    --The popup is either browsing or configuring, never both: picking a
    --command swaps the list out for that command's parameters, and Back
    --swaps it back.
    local function RefreshMode()
        local hasSelection = m_selected ~= nil
        if m_browsePanel ~= nil and m_browsePanel.valid then
            m_browsePanel:SetClass("collapsed", hasSelection)
        end
        if m_selectionPanel ~= nil and m_selectionPanel.valid then
            m_selectionPanel:SetClass("collapsed", not hasSelection)
        end
        if hasSelection then
            if m_selectionTitle ~= nil and m_selectionTitle.valid then
                m_selectionTitle.text = m_selected.info.name or m_selected.macro
            end
            if m_selectionDescription ~= nil and m_selectionDescription.valid then
                local description = m_selected.info.description or ""
                m_selectionDescription.text = description
                m_selectionDescription:SetClass("collapsed", description == "")
            end
        end
    end

    local function SelectCommand(entry)
        m_selected = entry
        m_values = {}
        for i,param in ipairs(entry.info.params or {}) do
            if ParamIsText(param) or param.type == "audio" then
                m_values[i] = param.default or ""
            elseif param.type == "choices" then
                --a required choice starts empty on purpose: Add Step stays
                --disabled until the user picks, rather than silently
                --defaulting to whatever sorted first.
                if param.default ~= nil or param.required then
                    m_values[i] = param.default or ""
                else
                    local options = ResolveChoices(entry.macro, param, i)
                    m_values[i] = (options[1] ~= nil and options[1].id) or ""
                end
            else
                m_values[i] = param.default or param.min or 0
            end
        end
        --"always" commands have no check to show, so the state the bake reads
        --comes straight from the declaration.
        local _, broadcastDefault = BroadcastOption(entry.info)
        m_broadcast = broadcastDefault
        if resultPanel ~= nil then
            resultPanel:FireEventTree("selectedCommand")
        end
        RebuildDetail()
        RefreshMode()
    end

    local function ClearSelection()
        m_selected = nil
        m_values = {}
        m_broadcast = false
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:FireEventTree("selectedCommand")
        end
        RebuildDetail()
        RefreshMode()
    end

    local rows = {}
    for _,entry in ipairs(commands) do
        local captured = entry
        local displayName = entry.info.name or entry.macro
        local description = entry.info.description or ""
        local searchText = string.lower(string.format("%s %s %s", displayName, description, entry.macro))

        rows[#rows+1] = gui.Panel{
            classes = {"commandBrowserRow"},
            flow = "vertical",
            width = "100%",
            height = "auto",
            pad = 4,
            borderBox = true,

            refreshCommandFilter = function(element, filterText)
                local filter = string.lower(filterText or "")
                local visible = #filter == 0 or string.find(searchText, filter, 1, true) ~= nil
                element:SetClass("collapsed", not visible)
            end,
            selectedCommand = function(element)
                element:SetClass("selected", m_selected == captured)
            end,
            press = function(element)
                SelectCommand(captured)
            end,

            gui.Label{
                classes = {"commandBrowserName"},
                text = displayName,
                bold = true,
                fontSize = 13,
                width = "100%",
                height = "auto",
                interactable = false,
            },
            gui.Label{
                classes = {"commandBrowserDescription", cond(description == "", "collapsed")},
                text = description,
                fontSize = 11,
                width = "100%",
                height = "auto",
                interactable = false,
            },
        }
    end

    if #rows == 0 then
        rows[#rows+1] = gui.Label{
            classes = {"commandBrowserDescription"},
            text = "No commands available.",
            fontSize = 12,
            width = "100%",
            height = "auto",
            pad = 4,
        }
    end

    m_detailPanel = gui.Panel{
        classes = {"collapsed"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        tmargin = 6,
    }

    m_addButton = gui.Button{
        text = "Add Step",
        classes = {"disabled"},
        fontSize = 12,
        width = "auto",
        height = 24,
        hpad = 10,
        borderBox = true,
        halign = "right",
        valign = "center",
        click = function(element)
            if element:HasClass("disabled") or m_selected == nil then
                return
            end
            CommandBuilder.RecordStep{
                command = BakedCommand(),
                text = m_selected.info.name or m_selected.macro,
            }
            iconElement.popup = nil
        end,
    }

    m_browsePanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",

        gui.Label{
            text = "Add a Command",
            bold = true,
            fontSize = 13,
            width = "auto",
            height = "auto",
            bmargin = 4,
        },

        gui.Input{
            placeholderText = "Filter commands...",
            fontSize = 12,
            width = "100%",
            height = 22,
            borderBox = true,
            bmargin = 4,
            editlag = 0.25,
            edit = function(element)
                if resultPanel ~= nil and resultPanel.valid then
                    resultPanel:FireEventTree("refreshCommandFilter", element.text)
                end
            end,
        },

        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            maxHeight = 200,
            vscroll = true,
            children = rows,
        },
    }

    m_selectionTitle = gui.Label{
        classes = {"commandBrowserName"},
        text = "",
        bold = true,
        fontSize = 13,
        width = "100%",
        height = "auto",
    }

    m_selectionDescription = gui.Label{
        classes = {"commandBrowserDescription", "collapsed"},
        text = "",
        fontSize = 11,
        width = "100%",
        height = "auto",
        tmargin = 2,
    }

    m_selectionPanel = gui.Panel{
        classes = {"collapsed"},
        flow = "vertical",
        width = "100%",
        height = "auto",

        m_selectionTitle,
        m_selectionDescription,
        m_detailPanel,

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            tmargin = 6,

            gui.Button{
                text = "Back",
                fontSize = 12,
                width = "auto",
                height = 24,
                hpad = 10,
                borderBox = true,
                halign = "left",
                valign = "center",
                click = function(element)
                    ClearSelection()
                end,
            },

            m_addButton,
        },
    }

    resultPanel = gui.Panel{
        classes = {"bordered", "bg"},
        styles = BrowserStyles(),
        flow = "vertical",
        width = 340,
        height = "auto",
        pad = 8,
        borderBox = true,

        m_browsePanel,
        m_selectionPanel,
    }

    --with a single command there is nothing to browse; preselect it so the
    --sliders are immediately in front of the user. Back still returns to the
    --(one row) list rather than dead-ending.
    if #commands == 1 then
        SelectCommand(commands[1])
    end

    return resultPanel
end

--Zero-overhead-when-inactive attachment for lightning affordances. Hosts do
--NOT construct an icon up front; instead they register the (essentially
--free) mode monitor themselves and call this from both their create and
--monitor handlers:
--
--    multimonitor = {"commandcreationmode"},
--    create = function(element) CommandBuilder.EnsureLightningIcon(element, opts) end,
--    monitor = function(element) CommandBuilder.EnsureLightningIcon(element, opts) end,
--
--While the mode is inactive this is a single boolean check per event -- no
--panel, no styles, no tooltip. The first activation builds the icon and adds
--it to the host; from then on the icon manages its own visibility through
--its own monitor, and the class guard here makes repeat calls no-ops.
function CommandBuilder.EnsureLightningIcon(hostPanel, options)
    if not CommandBuilder.IsActive() then
        return
    end
    if hostPanel:HasClass("commandBuilderLightningHost") then
        return
    end
    hostPanel:SetClass("commandBuilderLightningHost", true)
    hostPanel:AddChild(CommandBuilder.LightningIcon(options))
end

--The lightning affordance: an icon a piece of UI shows next to itself while
--command creation mode is active. Clicking it opens a menu of recordable
--actions for that piece of UI. Prefer attaching it lazily through
--EnsureLightningIcon (above) so inactive mode costs nothing; construct it
--directly only in UI that is itself built while the mode is active.
--
--options.entries: function(element) returning a list of
--  { text = menu item text, command = command string (no leading /),
--    stepText = optional chip label; defaults to the menu item text }
--  An entry may instead supply click = function(iconElement): it runs a
--  custom flow (open a picker popup, start a map location selection via
--  CommandBuilder.SelectLocation) rather than recording a fixed command,
--  and owns closing or replacing iconElement.popup itself.
--options.createPopup: alternative to entries for affordances that need a
--  richer picker than a menu (e.g. choosing a slider value):
--  function(iconElement) returning a popup panel. The popup records its own
--  steps via CommandBuilder.RecordStep and closes itself by assigning
--  iconElement.popup = nil.
--All other options (floating, halign, margins, width, height, ...) are passed
--through to the panel.
function CommandBuilder.LightningIcon(options)
    local profileStart = os.clock()

    options = options or {}
    local getEntries = options.entries
    local createPopup = options.createPopup
    options.entries = nil
    options.createPopup = nil

    local classes = {"commandBuilderLightning"}
    if not CommandBuilder.IsActive() then
        classes[#classes+1] = "collapsed"
    end

    local args = {
        classes = classes,
        width = 20,
        height = 20,
        valign = "center",

        --the icon is often hosted inside/over another interactable (object
        --command buttons, settings rows, map appearance tiles): stop pointer
        --routing here so clicking the bolt does not also activate the host,
        --and hovering it does not highlight the host. swallowPress covers
        --the press/hover routing, but the CLICK event routes separately:
        --the engine bubbles it to the parent unless this panel's own click
        --handler consumes it (ExecuteOnClick returns whether a handler
        --exists), so the empty click/rightClick handlers below are load-
        --bearing -- they are what keeps a bolt click from also firing a
        --click-driven host like a map appearance tile.
        swallowPress = true,
        click = function(element)
        end,
        rightClick = function(element)
        end,

        --resting and hover images both live in styles: an inline bgimage
        --could never be overridden by the hover rule.
        styles = LightningStyles(),

        multimonitor = {"commandcreationmode"},
        monitor = function(element)
            element:SetClass("collapsed", not CommandBuilder.IsActive())
        end,

        linger = gui.Tooltip("Add a step to the command you are building."),

        press = function(element)
            if not CommandBuilder.IsActive() then
                return
            end
            if createPopup ~= nil then
                element.popupsInheritStyles = true
                element.popup = createPopup(element)
                return
            end
            local entries = {}
            for _,entry in ipairs(getEntries(element) or {}) do
                local captured = entry
                entries[#entries+1] = {
                    text = captured.text,
                    click = function()
                        --custom-flow entries run their own logic and manage
                        --the icon's popup themselves (see the entries doc).
                        if captured.click ~= nil then
                            captured.click(element)
                            return
                        end
                        CommandBuilder.RecordStep{
                            command = captured.command,
                            text = captured.stepText or captured.text,
                        }
                        element.popup = nil
                    end,
                }
            end
            element.popup = gui.ContextMenu{
                entries = entries,
            }
        end,
    }

    for k,option in pairs(options) do
        args[k] = option
    end

    local resultPanel = gui.Panel(args)

    CommandBuilder.profile.count = CommandBuilder.profile.count + 1
    CommandBuilder.profile.seconds = CommandBuilder.profile.seconds + (os.clock() - profileStart)

    return resultPanel
end

--The active "click a spot on the map" picker, if any. Only one selection can
--be in flight at a time.
local g_locationPicker = nil

--Abort any in-progress map location selection (fires its cancel callback).
function CommandBuilder.CancelLocationSelection()
    if g_locationPicker ~= nil and g_locationPicker.valid then
        --the picker's destroy handler fires the cancel callback and clears
        --g_locationPicker.
        g_locationPicker:DestroySelf()
    end
    g_locationPicker = nil
end

--Generic "pick a location on the map" flow for command creation mode: shows
--a prompt over the map, marks the hovered tile, and hands the clicked Loc to
--the caller. Lightning-menu entries that record location-taking commands
--(walk here, teleport here, place something here, ...) share this rather
--than each building their own map-capture UI.
--
--options.prompt: the instruction shown to the user.
--options.complete: function(loc) called with the chosen Loc.
--options.cancel: optional function() called if the selection is aborted
--  (escape, the Cancel button, the recording session ending, or a new
--  selection starting).
function CommandBuilder.SelectLocation(options)
    CommandBuilder.CancelLocationSelection()

    --mounted on the game hud's popup layer, like other transient map-capture
    --UI (e.g. the creature placement tweaker).
    local hudClass = rawget(_G, "GameHud")
    local gamehud = hudClass ~= nil and hudClass.instance or nil
    local popupParent = nil
    if gamehud ~= nil and gamehud ~= false then
        popupParent = rawget(gamehud, "popupPanel")
    end
    if popupParent == nil or not CommandBuilder.IsActive() then
        if options.cancel ~= nil then
            options.cancel()
        end
        return
    end

    local hoverMarker = nil
    local function DestroyHoverMarker()
        if hoverMarker ~= nil then
            hoverMarker:Destroy()
            hoverMarker = nil
        end
    end

    --set before DestroySelf on a successful pick so the destroy handler
    --knows not to fire the cancel callback.
    local completed = false

    local promptContent = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "center",
        interactable = true,

        gui.Label{
            halign = "center",
            width = "auto",
            minWidth = 260,
            maxWidth = 700,
            height = "auto",
            bold = true,
            fontSize = 16,
            textAlignment = "center",
            text = options.prompt or "Click a location on the map.",
            vmargin = 2,
        },
        gui.Label{
            halign = "center",
            width = "auto",
            height = "auto",
            fontSize = 13,
            color = "#cccccc",
            textAlignment = "center",
            text = "Click a spot to record it. Press Escape to cancel.",
            vmargin = 2,
        },
        gui.PrettyButton{
            text = "Cancel",
            halign = "center",
            vmargin = 6,
            width = 160,
            height = 36,
            fontSize = 18,
            click = function(element)
                CommandBuilder.CancelLocationSelection()
            end,
        },
    }

    local picker
    picker = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        --no bgimage: the panel itself is not hit-testable, so the map stays
        --interactable underneath; mapfocus is what routes the clicks here.
        bgcolor = "clear",
        interactable = true,
        mapfocus = true,
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,

        gui.TooltipFrame(promptContent, { vmargin = 85 }),

        --the recording session ended (Done/Cancel) while we were waiting for
        --a click: nothing to record into any more.
        multimonitor = {"commandcreationmode"},
        monitor = function(element)
            if not CommandBuilder.IsActive() then
                element:DestroySelf()
            end
        end,

        mappress = function(element, loc, point)
            if loc == nil then
                return
            end
            completed = true
            element:DestroySelf()
            if options.complete ~= nil then
                options.complete(loc)
            end
        end,

        maphover = function(element, loc, point)
            DestroyHoverMarker()
            if loc ~= nil then
                hoverMarker = dmhub.MarkLocs{
                    locs = { loc },
                    color = "#ffffffcc",
                }
            end
        end,

        escape = function(element)
            element:DestroySelf()
        end,

        destroy = function(element)
            DestroyHoverMarker()
            if g_locationPicker == element then
                g_locationPicker = nil
            end
            if not completed and options.cancel ~= nil then
                options.cancel()
            end
        end,
    }

    g_locationPicker = picker
    popupParent:AddChild(picker)
end

local g_helpText =
[[You are building a command for your journal button.

While this mode is active, parts of the app that can be recorded show a lightning icon -- for example the checkboxes in the Settings dialog, or the tokens on the map, whose icon records token commands such as focusing the camera, walking somewhere, or playing an emote.

Click a lightning icon and choose an action to add it as a step. You can also press Add Command below to browse a list of commands and add one with the settings you choose. Steps run in order when the button is pressed.

Click a step's x to remove it, or drag a step between two others to reorder them. Steps with a cog can have their settings adjusted. Drag this dialog by its body to move it, or drag its edges to resize it. Done applies the command to your button; Cancel (or closing the dialog) discards it.]]

--Sizing for the recorder dialog.
local DIALOG_DEFAULT_WIDTH = 460
local DIALOG_DEFAULT_HEIGHT = 520
local DIALOG_MIN_WIDTH = 340
local DIALOG_MIN_HEIGHT = 280

--gui.WindowResizePanel persists window placement to a document-like object
--via :try_get("_tmp_location") / ._tmp_location; this scratch table quacks
--like one. The dialog's own move handler writes the same shape, so a
--reopened session brings the dialog back where the user left it (per Lua
--load only -- a reload forgets it, which is fine for a scratch placement).
local g_dialogLocation = {
    try_get = function(self, key)
        return rawget(self, key)
    end,
}

--The recorder dialog: a floating window showing the recording session --
--one row per step with its full label and the underlying command, drag a
--row between two others to reorder, a cog on editable steps, an x to
--remove, an Add Command button opening the command browser, and
--Cancel/Done. Moveable (drag anywhere on its body), resizable (drag any
--edge or corner), closeable (the X cancels the session, like Cancel).
--Opened by CreateDialogHost when a session begins; closes itself whenever
--the session ends.
function CommandBuilder.CreateDialog()
    local resultPanel
    local m_rowsPanel
    local m_doneButton

    --restore the remembered placement, clamped so the dialog stays
    --reachable if the app window shrank since it was saved.
    local screen = dmhub.screenDimensionsBelowTitlebar
    local dialogWidth = DIALOG_DEFAULT_WIDTH
    local dialogHeight = DIALOG_DEFAULT_HEIGHT
    local dialogX
    local dialogY
    local loc = g_dialogLocation:try_get("_tmp_location")
    if loc ~= nil then
        dialogWidth = clamp(loc.width or dialogWidth, DIALOG_MIN_WIDTH, screen.x)
        dialogHeight = clamp(loc.height or dialogHeight, DIALOG_MIN_HEIGHT, screen.y)
        dialogX = clamp(loc.x or 0, 0, math.max(0, screen.x - DIALOG_MIN_WIDTH))
        dialogY = clamp(loc.y or 0, 0, math.max(0, screen.y - DIALOG_MIN_HEIGHT))
    else
        dialogX = math.floor((screen.x - dialogWidth) / 2)
        dialogY = math.floor((screen.y - dialogHeight) / 2)
    end

    local function SaveLocation(dialog)
        g_dialogLocation._tmp_location = {
            x = dialog.x,
            y = dialog.y,
            width = dialog.selfStyle.width,
            height = dialog.selfStyle.height,
            moved = true,
            screenx = screen.x,
            screeny = screen.y,
        }
    end

    local function Close()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:DestroySelf()
        end
    end

    local function RebuildRows()
        if m_rowsPanel == nil or not m_rowsPanel.valid then
            return
        end
        local steps = CommandBuilder.GetSteps()

        --a slim full-width drop zone before each row plus one after the
        --last, the vertical-list counterpart of the chip strip's gaps.
        --data.index is the insertion position handed to
        --CommandBuilder.MoveStep.
        local function DropTarget(insertIndex)
            return gui.Panel{
                classes = {"commandBuilderDialogDropTarget"},
                dragTarget = true,
                data = {
                    index = insertIndex,
                },
            }
        end

        local children = {}
        for i,step in ipairs(steps) do
            local index = i
            local editable = CommandBuilder.ParseSurfacedStep(step.command) ~= nil

            children[#children+1] = DropTarget(index)

            --assembled as a list rather than positional children: the cog
            --is only present on editable steps, and a nil in the middle of
            --a table constructor would silently drop the entries after it.
            local iconChildren = {}
            if editable then
                iconChildren[#iconChildren+1] = gui.Panel{
                    classes = {"commandBuilderIcon"},
                    bgimage = "phosphor/gear-fine-fill.png",
                    width = 14,
                    height = 14,
                    valign = "center",
                    lmargin = 6,
                    linger = gui.Tooltip("Adjust this step's settings."),
                    press = function(element)
                        element.popupsInheritStyles = true
                        element.popup = CommandBuilder.CreateStepEditorPopup(element, index)
                    end,
                }
            end
            iconChildren[#iconChildren+1] = gui.Panel{
                classes = {"commandBuilderIcon"},
                bgimage = "phosphor/x-bold.png",
                width = 14,
                height = 14,
                valign = "center",
                lmargin = 6,
                linger = gui.Tooltip("Remove this step."),
                press = function(element)
                    CommandBuilder.RemoveStep(index)
                end,
            }

            children[#children+1] = gui.Panel{
                classes = {"commandBuilderDialogRow"},
                flow = "none",
                width = "100%",
                height = "auto",
                pad = 6,
                borderBox = true,

                draggable = true,
                canDragOnto = function(element, target)
                    return target:HasClass("commandBuilderDialogDropTarget")
                end,
                drag = function(element, target)
                    if target ~= nil then
                        CommandBuilder.MoveStep(index, target.data.index)
                    else
                        --dropped outside any zone: rebuild so the row snaps
                        --back into place.
                        RebuildRows()
                    end
                end,

                --the text cluster gets everything the cog/x cluster on the
                --right does not need (up to 56px with margins), tracking the
                --dialog's live width so resizing gives the labels the room.
                gui.Panel{
                    flow = "horizontal",
                    width = "100%-56",
                    height = "auto",
                    halign = "left",
                    valign = "center",

                    gui.Label{
                        classes = {"commandBuilderDialogIndex"},
                        text = string.format("%d.", index),
                        fontSize = 12,
                        width = 22,
                        height = "auto",
                        valign = "center",
                        textWrap = false,
                        interactable = false,
                    },

                    gui.Panel{
                        flow = "vertical",
                        width = "100%-22",
                        height = "auto",
                        valign = "center",

                        gui.Label{
                            classes = {"commandBuilderDialogLabel"},
                            text = step.text,
                            bold = true,
                            fontSize = 13,
                            width = "auto",
                            maxWidth = "100%",
                            height = "auto",
                            textWrap = false,
                            textOverflow = "ellipsis",
                            interactable = false,
                        },

                        --the raw command the step will run.
                        gui.Label{
                            classes = {"commandBuilderDialogCommand"},
                            text = "/" .. step.command,
                            fontSize = 10,
                            width = "auto",
                            maxWidth = "100%",
                            height = "auto",
                            textWrap = false,
                            textOverflow = "ellipsis",
                            interactable = false,
                        },
                    },
                },

                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    children = iconChildren,
                },
            }
        end

        if #steps > 0 then
            children[#children+1] = DropTarget(#steps + 1)
        else
            children[#children+1] = gui.Label{
                classes = {"commandBuilderDialogCommand"},
                text = "No steps recorded yet. Click a lightning icon somewhere in the app, or press Add Command below.",
                fontSize = 12,
                width = "100%",
                height = "auto",
                pad = 4,
            }
        end

        m_rowsPanel.children = children

        if m_doneButton ~= nil and m_doneButton.valid then
            m_doneButton:SetClass("disabled", #steps == 0)
        end
    end

    --the step list takes all the height the header and footer leave, so
    --resizing the dialog taller shows more steps before scrolling.
    m_rowsPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100% available",
        vscroll = true,
        vmargin = 6,
    }

    m_doneButton = gui.Button{
        text = "Done",
        classes = {"disabled"},
        fontSize = 12,
        width = "auto",
        height = 24,
        hpad = 10,
        borderBox = true,
        valign = "center",
        hmargin = 2,
        click = function(element)
            if element:HasClass("disabled") then
                return
            end
            CommandBuilder.Complete()
        end,
    }

    resultPanel = gui.Panel{
        classes = {"framedPanel"},
        styles = DialogStyles(),
        flow = "vertical",
        pad = 12,
        borderBox = true,

        --gui.WindowResizePanel's contract: anchor top-left with numeric x/y
        --and numeric selfStyle width/height, so the handles can move the
        --window's origin while resizing its left/top edges.
        style = {
            width = dialogWidth,
            height = dialogHeight,
            halign = "left",
            valign = "top",
        },
        x = dialogX,
        y = dialogY,
        floating = true,

        --moveable: drag anywhere on the body that is not itself a control.
        --Presses inside stay inside (swallowPress) so dragging the dialog
        --never pans the map underneath.
        swallowPress = true,
        draggable = true,
        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()
            SaveLocation(element)
        end,
        click = function(element)
            element:SetAsLastSibling()
        end,

        --the session can end from outside the dialog (Done writing the
        --command back, a new session beginning); both notification paths
        --close it -- the explicit refresh below and the setting monitor as
        --backup.
        multimonitor = {"commandcreationmode"},
        monitor = function(element)
            if not CommandBuilder.IsActive() then
                Close()
            end
        end,
        refreshCommandBuilder = function(element)
            if not CommandBuilder.IsActive() then
                Close()
                return
            end
            RebuildRows()
        end,
        destroy = function(element)
            if g_dialog == element then
                g_dialog = nil
            end
        end,

        gui.Panel{
            flow = "none",
            width = "100%",
            height = 24,

            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "100%",
                halign = "left",
                valign = "center",

                gui.Label{
                    classes = {"commandBuilderTitle"},
                    text = "Creating Command",
                    bold = true,
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    textWrap = false,
                    interactable = false,
                },

                gui.Panel{
                    classes = {"commandBuilderIcon"},
                    bgimage = "phosphor/question.png",
                    width = 16,
                    height = 16,
                    valign = "center",
                    lmargin = 4,
                    linger = gui.Tooltip(g_helpText),
                },
            },

            --closing the dialog abandons the recording, exactly like Cancel;
            --the session ending is what actually closes the window.
            gui.Panel{
                classes = {"commandBuilderIcon"},
                bgimage = "phosphor/x-bold.png",
                width = 14,
                height = 14,
                halign = "right",
                valign = "center",
                linger = gui.Tooltip("Cancel this command and close."),
                press = function(element)
                    CommandBuilder.Cancel()
                end,
            },
        },

        m_rowsPanel,

        --footer: browse-and-add on the left, the session controls on the
        --right, pinned to their edges.
        gui.Panel{
            flow = "none",
            width = "100%",
            height = 28,
            tmargin = 4,

            gui.Button{
                text = "Add Command...",
                fontSize = 12,
                width = "auto",
                height = 24,
                hpad = 10,
                borderBox = true,
                halign = "left",
                valign = "center",
                click = function(element)
                    element.popupsInheritStyles = true
                    element.popup = CommandBuilder.CreateCommandBrowserPopup(element)
                end,
            },

            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "100%",
                halign = "right",
                valign = "center",

                gui.Button{
                    text = "Cancel",
                    fontSize = 12,
                    width = "auto",
                    height = 24,
                    hpad = 10,
                    borderBox = true,
                    valign = "center",
                    hmargin = 2,
                    click = function(element)
                        CommandBuilder.Cancel()
                    end,
                },

                m_doneButton,
            },
        },

        --resize handles on every edge and corner. MUST be the window's last
        --child (sibling order is z-order) so the handles sit above content
        --that reaches the border.
        gui.WindowResizePanel(g_dialogLocation, dialogWidth, dialogHeight, {
            minWidth = DIALOG_MIN_WIDTH,
            minHeight = DIALOG_MIN_HEIGHT,
        }),
    }

    RebuildRows()

    g_dialog = resultPanel
    return resultPanel
end

--Open the recorder dialog if a session is active and it is not already
--open. Mounted on the game hud's popup layer when available (full-screen,
--already hosts the command builder's other transient UI such as the
--location picker); fallbackElement's root is the fallback for hosts that
--have one (Begin passes nil -- every Begin call site is in-game, so the
--hud path covers it, and the dialog host's monitor is the backstop).
EnsureDialogOpen = function(fallbackElement)
    if not CommandBuilder.IsActive() then
        return
    end
    if g_dialog ~= nil and g_dialog.valid then
        return
    end

    local dialogParent = nil
    local hudClass = rawget(_G, "GameHud")
    local gamehud = hudClass ~= nil and hudClass.instance or nil
    if gamehud ~= nil and gamehud ~= false then
        dialogParent = rawget(gamehud, "popupPanel")
    end
    if (dialogParent == nil or not dialogParent.valid) and fallbackElement ~= nil and fallbackElement.valid then
        dialogParent = fallbackElement.root
    end
    if dialogParent ~= nil and dialogParent.valid then
        dialogParent:AddChild(CommandBuilder.CreateDialog())
    end
end

--The invisible mount point CodexTitleBar embeds: opens the recorder dialog
--when a session begins (and when the host is rebuilt while one is active).
--Closing is the dialog's own job -- it watches the session itself.
function CommandBuilder.CreateDialogHost()
    local function Sync(element)
        EnsureDialogOpen(element)
    end

    return gui.Panel{
        classes = {"collapsed"},
        width = 0,
        height = 0,
        multimonitor = {"commandcreationmode"},
        monitor = Sync,
        create = Sync,
    }
end
