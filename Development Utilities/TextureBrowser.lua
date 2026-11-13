local mod = dmhub.GetModLoading()

-- Developer tool: inspect every texture held by the engine ImageManager cache.
-- Backed by dmhub.GetLoadedTextures() (LuaInterface.cs). Shows VRAM and system-memory (the
-- readable CPU copy) per texture, sortable by either, plus format / compressed / pinned / idle.
-- Uncompressed textures are highlighted red (the main memory lever). Hover a row to preview the
-- image. VRAM is estimated from the format + dimensions + mips; system memory is what Unity's
-- Profiler reports (0 for non-readable, GPU-only textures).
-- The "All textures" checkbox (remembered) lists every live texture instead, from
-- dmhub.GetAllTextures(): render targets, font atlases, sprite sheets shipped in the build and
-- the rest, with the image-cache ones still previewable and clickable for their details.

local function FormatBytes(bytes)
    bytes = bytes or 0
    if bytes >= 1048576 then
        return string.format("%.1f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.0f KB", bytes / 1024)
    elseif bytes > 0 then
        return string.format("%d B", bytes)
    end
    return "-"
end

local function ShortId(id)
    if id == nil or id == "" then return "(unnamed)" end
    if #id > 40 then
        return string.sub(id, 1, 20) .. ".." .. string.sub(id, #id - 14)
    end
    return id
end

-- Engine ImageManager keys are usually base64 MD5 hashes; bgimage needs the "md5:" prefix to
-- resolve such a key back to the loaded texture. Images on the new s2 / R2 storage backend are
-- instead keyed by their full download URL (e.g. "https://codexback.com/..."), and the ImageManager
-- cache stores them under that whole URL. bgimage's "md5:" branch uses everything after the prefix
-- verbatim as the cache key, so URL-form ids need the "md5:" prefix too -- without it the raw URL
-- (which contains a ":") fell through the generic pass-through below, missed every resolver, and
-- rendered as a blank white square. (This is the same prefix the rest of the engine adds when it
-- exposes these ids as a bgimage, e.g. LuaObjectInstance.imageid.) Pass through special ("#..."),
-- already-prefixed ("md5:"/"thumb:") ids and asset guids ("-").
local function ImageRef(id)
    if id == nil or id == "" then return nil end
    if string.find(id, "://") then
        return "md5:" .. id
    end
    if string.find(id, "^#") or string.find(id, ":") or string.find(id, "%-") then
        return id
    end
    return "md5:" .. id
end

local function FlagsString(t)
    local flags = {}
    if t.video then flags[#flags+1] = "video" end
    if t.compressed then flags[#flags+1] = "compressed" else flags[#flags+1] = "UNCOMPRESSED" end
    if t.readable then flags[#flags+1] = "readable" end
    if t.pinned then flags[#flags+1] = "pinned" end
    if t.lowdef then flags[#flags+1] = "lowdef" end
    if t.liveedit then flags[#flags+1] = "liveedit" end
    return table.concat(flags, "  ")
end

local sortFields = { vram = "vramBytes", sys = "sysBytes" }

--"All textures": list every live texture (dmhub.GetAllTextures -- render targets, font
--atlases, sprite sheets in the build, ...) instead of only the ImageManager cache.
--Remembered between sessions.
local g_allTexturesSetting = setting{
    id = "dev:texturebrowser:alltextures",
    default = false,
    storage = "preference",
}

--In All textures mode only the largest this many get rows (there are ~1700, mostly tiny
--icons, and a row is 9 panels); the summary still totals every one.
local MAX_ALL_TEXTURE_ROWS = 400

--"Render target: Main/Post" -> "RT: Main/Post", to fit the Source column.
local function ShortSource(source)
    source = source or ""
    local sub = string.match(source, "^Render target: (.*)$")
    if sub ~= nil then
        return "RT: " .. sub
    end
    return source
end

--Unity graphics format names, shortened to fit the Format column:
--"R16G16B16A16_SFloat" -> "RGBA16F", "RGBA_DXT5_SRGB" -> "DXT5 sRGB",
--"depth D32_SFloat_S8_UInt" -> "depth D32S8". The click popup shows the full name.
local function ShortFormat(format)
    local s = tostring(format or "")
    s = string.gsub(s, "^RGBA_(%w+)_", "%1_")
    s = string.gsub(s, "R(%d+)G%d+B%d+A%d+", "RGBA%1")
    s = string.gsub(s, "R(%d+)G%d+B%d+", "RGB%1")
    s = string.gsub(s, "R(%d+)G%d+", "RG%1")
    s = string.gsub(s, "_S8_UInt", "S8")
    s = string.gsub(s, "_SFloat", "F")
    s = string.gsub(s, "_UFloat", "UF")
    s = string.gsub(s, "_UNorm", "")
    s = string.gsub(s, "_SNorm", " snorm")
    s = string.gsub(s, "_SRGB", " sRGB")
    s = string.gsub(s, "_UInt", "UI")
    return s
end

local s_kindAbbrev = {
    Texture2D = "2D",
    RenderTexture = "RT",
    CustomRenderTexture = "RT",
    Cubemap = "Cube",
    Texture3D = "3D",
    Texture2DArray = "Array",
    CubemapArray = "Cubes",
}

-- Session-persistent set (file-scope, so it survives panel reopens; resets on Lua reload) of image
-- ids optimized this session. Used to recolor + annotate rows so we can see at a glance what's
-- already been handled and avoid re-optimizing it.
local g_optimizedThisSession = {}

-- Downscale options for the optimize feature: the shorter dimension steps down through powers of 2
-- (floor 256), the longer dimension is shorter*aspect rounded to the nearest multiple of 4 -- so both
-- end up divisible by 4 (compression-eligible) while preserving aspect ratio. Largest options first.
local function ComputeResizeOptions(w, h)
    local options = {}
    if w == nil or h == nil or w < 8 or h < 8 then
        return options
    end

    local seen = {}
    local function add(ow, oh)
        ow = math.max(4, math.floor(ow + 0.5))
        oh = math.max(4, math.floor(oh + 0.5))
        local key = ow .. "x" .. oh
        if not seen[key] then
            seen[key] = true
            options[#options+1] = { w = ow, h = oh }
        end
    end

    -- powers of 2 in [256, dim) -- the anchor axis steps down to a floor of 256.
    local function powsBelow(dim)
        local list = {}
        local p = 256
        while p < dim do
            list[#list+1] = p
            p = p * 2
        end
        return list
    end

    -- One family per axis: anchor that axis to a power of 2; the OTHER axis is anchor*aspect rounded
    -- to the nearest multiple of 4 (preserves aspect, both dims divisible by 4 -> compression eligible).
    for _, a in ipairs(powsBelow(w)) do
        add(a, math.floor((a * h / w) / 4 + 0.5) * 4)   -- width = power of 2
    end
    for _, a in ipairs(powsBelow(h)) do
        add(math.floor((a * w / h) / 4 + 0.5) * 4, a)   -- height = power of 2
    end

    -- largest first by pixel area
    table.sort(options, function(x, y) return (x.w * x.h) > (y.w * y.h) end)
    return options
end

LaunchablePanel.Register{
    name = "Texture Browser",
    folder = "Development Tools",

    halign = "center",
    valign = "center",
    draggable = true,

    content = function(args)

        local resultPanel
        local summaryLabel
        local headerPanel
        local listPanel
        local Refresh
        local m_sortKey = "vram"

        --Hover preview of an ImageManager cache entry t (a row of dmhub.GetLoadedTextures).
        local function ShowImagePreview(element, t)
            local ref = ImageRef(t.id)
            -- A video with a captured still (poster frame or first-poll capture) previews
            -- that still; a video with no texture yet has nothing to show, as do failed /
            -- not-yet-loaded textures. Gate on hasTexture rather than on "is a video".
            if ref == nil or not t.hasTexture then
                return
            end
            local maxDim = 256
            local w = math.max(1, t.width)
            local h = math.max(1, t.height)
            local scale = maxDim / math.max(w, h)
            local iw = math.max(16, math.floor(w * scale))
            local ih = math.max(16, math.floor(h * scale))
            element.tooltip = gui.TooltipFrame(
                gui.Panel{
                    width = iw + 16,
                    height = ih + 16,
                    halign = "center",
                    valign = "center",
                    gui.Panel{
                        width = iw,
                        height = ih,
                        halign = "center",
                        valign = "center",
                        bgimage = ref,
                        bgcolor = "white",
                    },
                },
                { halign = "left", valign = "center" }
            )
        end

        --The click popup for an ImageManager cache entry t: live usage, optimize, load trace.
        local ShowImageDetails

        local function MakeRow(index, t)
            local uncompressed = (t.compressed == false) and (t.video == false)
            local optimized = g_optimizedThisSession[t.id] == true
            local rowColor
            if optimized then
                rowColor = "#1d4a2eaa"
            elseif t.video then
                rowColor = "#2a1d4eaa"   -- indigo tint: this row is a video
            elseif uncompressed then
                rowColor = "#4a1d1daa"
            else
                rowColor = cond(index % 2 == 0, "#00000055", "#20202055")
            end

            return gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 26,
                bgimage = true,
                bgcolor = rowColor,

                hover = function(element)
                    ShowImagePreview(element, t)
                end,

                click = function(element)
                    ShowImageDetails(element, t)
                end,

                gui.Label{ width = 250, height = "auto", halign = "left", valign = "center", lmargin = 6, fontSize = 14, color = "white", text = ShortId(t.id) },
                gui.Label{ width = 88, height = "auto", halign = "left", valign = "center", fontSize = 14, color = "#cccccc", text = cond(t.width > 0, string.format("%d x %d", t.width, t.height), "video") },
                gui.Label{ width = 116, height = "auto", halign = "left", valign = "center", fontSize = 14, color = cond(t.video, "#c79bff", cond(uncompressed, "#ff9090", "#a0e0a0")), text = cond(t.video, "Video", t.format) },
                gui.Label{ width = 160, height = "auto", halign = "left", valign = "center", fontSize = 13, color = cond(optimized, "#80ff80", "#dddddd"), text = cond(optimized, "OPTIMIZED  ", "") .. FlagsString(t) },
                gui.Label{ width = 54, height = "auto", halign = "right", valign = "center", fontSize = 13, color = "#999999", text = string.format("%.0fs", t.idleSeconds) },
                gui.Label{ width = 96, height = "auto", halign = "right", valign = "center", fontSize = 14, color = "#9fd0ff", text = FormatBytes(t.vramBytes) },
                gui.Label{ width = 96, height = "auto", halign = "right", valign = "center", fontSize = 14, color = "#6f9fbf", text = FormatBytes(t.cumVram) },
                gui.Label{ width = 96, height = "auto", halign = "right", valign = "center", rmargin = 8, fontSize = 14, color = "#cccccc", text = FormatBytes(t.sysBytes) },
            }
        end

        ShowImageDetails = function(element, t)
                    local trace = t.trace
                    if trace == nil or trace == "" then
                        trace = "(no load trace captured -- traces are recorded only in dev mode, at the moment an image is first loaded; reload the image to capture one)"
                    end

                    local children = {}

                    children[#children+1] = gui.Label{
                        width = "97%", height = "auto", halign = "left", valign = "top",
                        fontSize = 12, color = "white",
                        text = "ID: " .. tostring(t.id) .. "\nFormat: " .. tostring(t.format) .. "    VRAM: " .. FormatBytes(t.vramBytes) .. "    Sys: " .. FormatBytes(t.sysBytes),
                    }

                    if g_optimizedThisSession[t.id] then
                        children[#children+1] = gui.Label{
                            width = "97%", height = "auto", halign = "left", fontSize = 13, color = "#80ff80",
                            text = "** optimized this session **",
                        }
                    end

                    children[#children+1] = gui.Label{
                        width = "97%", height = "auto", halign = "left", fontSize = 13, color = "#ffd080", vmargin = 4,
                        text = "=== LIVE USAGE  (click a token to jump to it) ===",
                    }

                    local usageEntries = dmhub.FindImageUsage(t.id)
                    if usageEntries == nil or #usageEntries == 0 then
                        children[#children+1] = gui.Label{
                            width = "97%", height = "auto", halign = "left", fontSize = 12, color = "#888888",
                            text = "(no live usage found among tokens / map objects / panels)",
                        }
                    else
                        for _, e in ipairs(usageEntries) do
                            if e.kind == "token" then
                                local charid = e.charid
                                local tok = dmhub.GetCharacterById(charid)
                                local nm = charid
                                if tok ~= nil then
                                    nm = tok.name
                                end
                                local suffix = cond(e.onmap, "   [on current map -- click to focus]", "   [not on current map]")
                                children[#children+1] = gui.Label{
                                    width = "97%", height = "auto", halign = "left", fontSize = 13,
                                    color = cond(e.onmap, "#9fd0ff", "#bbbbbb"),
                                    text = "Token '" .. tostring(nm) .. "'  --  " .. tostring(e.slot) .. suffix,
                                    click = function()
                                        dmhub.FocusToken(charid)
                                    end,
                                }
                            else
                                children[#children+1] = gui.Label{
                                    width = "97%", height = "auto", halign = "left", fontSize = 13, color = "#dddddd",
                                    text = tostring(e.label),
                                }
                            end
                        end
                    end

                    local optInfo = dmhub.GetImageAssetOptimizeInfo(t.id)
                    if optInfo ~= nil and optInfo.assets ~= nil and #optInfo.assets > 0 then
                        local srcW = optInfo.width
                        local srcH = optInfo.height
                        if srcW == nil or srcW <= 0 then srcW = t.width end
                        if srcH == nil or srcH <= 0 then srcH = t.height end

                        children[#children+1] = gui.Label{
                            width = "97%", height = "auto", halign = "left", fontSize = 13, color = "#80ff80", vmargin = 4,
                            text = string.format("=== OPTIMIZE  (backed by %d editable asset(s); click a size to rescale + re-upload) ===", #optInfo.assets),
                        }

                        local resizeOptions = ComputeResizeOptions(srcW, srcH)
                        if #resizeOptions == 0 then
                            children[#children+1] = gui.Label{
                                width = "97%", height = "auto", halign = "left", fontSize = 12, color = "#888888",
                                text = "(already at or below the minimum offered size of 256)",
                            }
                        else
                            for _, opt in ipairs(resizeOptions) do
                                local ow = opt.w
                                local oh = opt.h
                                -- Derive bytes/pixel from the CURRENT texture's real VRAM (so the
                                -- estimate honors its actual format -- compressed stays compressed --
                                -- and its mip overhead) rather than assuming RGBA32.
                                local bytesPerPixel = (t.vramBytes or 0) / math.max(1, (t.width or 0) * (t.height or 0))
                                local estMB = (ow * oh * bytesPerPixel) / 1048576
                                children[#children+1] = gui.Label{
                                    width = "97%", height = "auto", halign = "left", fontSize = 13, color = "#80ff80",
                                    text = string.format("Resize to %d x %d   (~%.1f MB VRAM)", ow, oh, estMB),
                                    click = function(element)
                                        local r = dmhub.OptimizeImageAsset(t.id, ow, oh)
                                        if r ~= nil and r.ok then
                                            g_optimizedThisSession[t.id] = true
                                            if r.newid ~= nil and r.newid ~= "" then
                                                g_optimizedThisSession[r.newid] = true
                                            end
                                            element.text = string.format("[done]  resize to %d x %d -- uploaded as %s, updating %d asset(s)", ow, oh, tostring(r.newid), r.count)
                                            -- Rebuild the table on the next frame -- deferred so we are not
                                            -- mutating the list while still inside this row's click event
                                            -- (which would yank the popup out from under us). pcall guards
                                            -- against the panel having been closed in the meantime.
                                            dmhub.Schedule(0.01, function()
                                                if mod.unloaded then return end
                                                pcall(Refresh)
                                            end)
                                        else
                                            element.text = string.format("[failed]  resize to %d x %d -- %s", ow, oh, tostring(r and r.error or "unknown"))
                                        end
                                    end,
                                }
                            end
                        end
                    end

                    children[#children+1] = gui.Label{
                        width = "97%", height = "auto", halign = "left", fontSize = 13, color = "#ffd080", vmargin = 4,
                        text = "=== LOAD TRACE ===",
                    }
                    children[#children+1] = gui.Label{
                        width = "97%", height = "auto", halign = "left", fontSize = 12, color = "white",
                        text = trace,
                    }

                    local contentPanel = gui.Panel{
                        width = 740,
                        height = "auto",
                        maxHeight = 640,
                        flow = "vertical",
                        vscroll = true,
                        hpad = 10,
                        vpad = 8,
                        borderBox = true,
                    }
                    contentPanel.children = children

                    element.popup = gui.TooltipFrame(contentPanel, { halign = "center", valign = "center" })
        end

        --Click popup for a texture outside the image cache (All textures mode).
        local function ShowTextureInfo(element, t)
            local lines = {
                "Name: " .. tostring(t.name),
                "Source: " .. tostring(t.source),
                "Kind: " .. tostring(t.kind) .. "    instance " .. tostring(t.instanceId),
                string.format("Size: %d x %d%s    Format: %s    Mips: %s%s",
                    t.width or 0, t.height or 0, cond((t.depth or 1) > 1, " x " .. tostring(t.depth), ""),
                    tostring(t.format), tostring(t.mips), cond((t.msaa or 1) > 1, "    MSAA x" .. tostring(t.msaa), "")),
                string.format("VRAM (estimated): %s%s", FormatBytes(t.vramBytes),
                    cond(t.resident, "", "    -- NOT allocated on the GPU yet (counts nothing until it is created)")),
            }
            if t.owner ~= nil then
                lines[#lines+1] = cond(t.source == "Font atlas", "Font: ", "Rendered by camera: ") .. tostring(t.owner)
            end
            element.popup = gui.TooltipFrame(
                gui.Label{
                    width = 600, height = "auto", hpad = 10, vpad = 8, borderBox = true,
                    fontSize = 13, color = "white",
                    text = table.concat(lines, "\n"),
                },
                { halign = "center", valign = "center" }
            )
        end

        --A row of dmhub.GetAllTextures. imageEntry: the matching dmhub.GetLoadedTextures row
        --for an image-cache texture (gives it the preview and the usage/optimize/trace popup).
        local function MakeAllRow(index, t, imageEntry)
            local rowColor
            if not t.resident then
                rowColor = "#00000033"
            elseif string.find(t.source or "", "^Render target") then
                rowColor = "#1d2f4aaa"   -- blue tint: a render target
            elseif imageEntry ~= nil and (t.compressed == false) then
                rowColor = "#4a1d1daa"   -- an uncompressed image-cache texture
            else
                rowColor = cond(index % 2 == 0, "#00000055", "#20202055")
            end
            local textColor = cond(t.resident, "white", "#777777")
            local dims = string.format("%d x %d", t.width or 0, t.height or 0)
            if (t.depth or 1) > 1 then
                dims = dims .. " x" .. tostring(t.depth)
            end

            return gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 26,
                bgimage = true,
                bgcolor = rowColor,

                hover = function(element)
                    if imageEntry ~= nil then
                        ShowImagePreview(element, imageEntry)
                    end
                end,

                click = function(element)
                    if imageEntry ~= nil then
                        ShowImageDetails(element, imageEntry)
                    else
                        ShowTextureInfo(element, t)
                    end
                end,

                gui.Label{ width = 250, height = "auto", halign = "left", valign = "center", lmargin = 6, fontSize = 14, color = textColor, text = ShortId(t.imageId or t.name) },
                gui.Label{ width = 88, height = "auto", halign = "left", valign = "center", fontSize = 14, color = "#cccccc", text = dims },
                gui.Label{ width = 116, height = "auto", halign = "left", valign = "center", fontSize = 14, color = cond(t.compressed, "#a0e0a0", "#dddddd"), text = ShortFormat(t.format) },
                gui.Label{ width = 160, height = "auto", halign = "left", valign = "center", fontSize = 13, color = "#dddddd", text = ShortSource(t.source) },
                gui.Label{ width = 54, height = "auto", halign = "right", valign = "center", fontSize = 13, color = "#999999", text = s_kindAbbrev[t.kind] or tostring(t.kind) },
                gui.Label{ width = 96, height = "auto", halign = "right", valign = "center", fontSize = 14, color = cond(t.resident, "#9fd0ff", "#777777"), text = cond(t.resident, FormatBytes(t.vramBytes), "not alloc.") },
                gui.Label{ width = 96, height = "auto", halign = "right", valign = "center", fontSize = 14, color = "#6f9fbf", text = FormatBytes(t.cumVram) },
                gui.Label{ width = 96, height = "auto", halign = "right", valign = "center", rmargin = 8, fontSize = 14, color = "#cccccc", text = cond((t.msaa or 1) > 1, "x" .. tostring(t.msaa), "") },
            }
        end

        local function MakeHeader(label, width, halign, sortKey)
            local active = (sortKey ~= nil and sortKey == m_sortKey)
            return gui.Label{
                width = width,
                height = "auto",
                fontSize = 13,
                halign = halign or "left",
                valign = "center",
                lmargin = cond(halign == "left", 6, 0),
                rmargin = cond(halign == "right", 8, 0),
                color = cond(active, "white", "#888888"),
                text = cond(active, label .. " (v)", label),
                click = cond(sortKey ~= nil, function()
                    m_sortKey = sortKey
                    Refresh()
                end, nil),
            }
        end

        local function BuildHeaders()
            return {
                MakeHeader("Image ID", 250, "left", nil),
                MakeHeader("Dimensions", 88, "left", nil),
                MakeHeader("Format", 116, "left", nil),
                MakeHeader("Flags", 160, "left", nil),
                MakeHeader("Idle", 54, "right", nil),
                MakeHeader("VRAM", 96, "right", "vram"),
                MakeHeader("Cum VRAM", 96, "right", nil),
                MakeHeader("Sys Mem", 96, "right", "sys"),
            }
        end

        local function BuildAllHeaders()
            return {
                MakeHeader("Name / Image ID", 250, "left", nil),
                MakeHeader("Dimensions", 88, "left", nil),
                MakeHeader("Format", 116, "left", nil),
                MakeHeader("Source", 160, "left", nil),
                MakeHeader("Kind", 54, "right", nil),
                MakeHeader("VRAM", 96, "right", "vram"),
                MakeHeader("Cum VRAM", 96, "right", nil),
                MakeHeader("MSAA", 96, "right", nil),
            }
        end

        --All textures mode: every live texture, largest resident first (the engine's order).
        local function RefreshAll()
            local report = dmhub.GetAllTextures()
            local s = report.summary

            --the image cache's own rows, for the preview and the usage/optimize/trace popup.
            local imageEntries = {}
            for _, e in ipairs(dmhub.GetLoadedTextures().textures) do
                imageEntries[e.id] = e
            end

            local parts = {}
            for _, src in ipairs(s.sources) do
                parts[#parts+1] = string.format("%s %.0f MB (%d)", ShortSource(src.source), src.vramMB, src.count)
            end

            local shown = math.min(#report.textures, MAX_ALL_TEXTURE_ROWS)
            summaryLabel.text = string.format(
                "%d textures (%d on the GPU)      VRAM ~%.0f MB      + %.0f MB of render targets not allocated\n%s%s",
                s.count, s.residentCount, s.vramMB, s.notResidentMB,
                table.concat(parts, "    "),
                cond(shown < #report.textures, string.format("\n(listing the %d largest)", shown), ""))

            headerPanel.children = BuildAllHeaders()

            local rows = {}
            local cumVram = 0
            for i, t in ipairs(report.textures) do
                if i > shown then
                    break
                end
                if t.resident then
                    cumVram = cumVram + (t.vramBytes or 0)
                end
                t.cumVram = cumVram
                local imageEntry = nil
                if t.imageId ~= nil then
                    imageEntry = imageEntries[t.imageId]
                end
                rows[#rows+1] = MakeAllRow(i, t, imageEntry)
            end
            listPanel.children = rows
        end

        Refresh = function()
            if g_allTexturesSetting:Get() then
                RefreshAll()
                return
            end

            local report = dmhub.GetLoadedTextures()
            local s = report.summary

            local field = sortFields[m_sortKey] or "vramBytes"
            table.sort(report.textures, function(a, b) return (a[field] or 0) > (b[field] or 0) end)

            summaryLabel.text = string.format(
                "%d textures      VRAM ~%.0f MB  +  Sys ~%.0f MB  =  ~%.0f MB total      %.0f / %d MP GC budget\nuncompressed: %d      compressed: %d      readable (CPU copy): %d      pinned: %d      video: %d",
                s.count, s.vramMB, s.sysMB, s.totalMB, s.megapixels, report.budgetMegapixels,
                s.uncompressed, s.compressed, s.readable, s.pinned, s.video)

            headerPanel.children = BuildHeaders()

            local rows = {}
            local cumVram = 0
            for i, t in ipairs(report.textures) do
                cumVram = cumVram + (t.vramBytes or 0)
                t.cumVram = cumVram
                rows[#rows+1] = MakeRow(i, t)
            end
            listPanel.children = rows
        end

        summaryLabel = gui.Label{
            width = 820,
            height = "auto",
            halign = "left",
            valign = "center",
            fontSize = 16,
            color = "white",
            text = "Loading...",
        }

        headerPanel = gui.Panel{
            flow = "horizontal",
            width = "98%",
            height = 22,
            halign = "center",
        }

        listPanel = gui.Panel{
            width = "100%",
            height = 540,
            flow = "vertical",
            vscroll = true,
        }

        resultPanel = gui.Panel{
            width = 1000,
            height = 740,
            flow = "vertical",
            halign = "center",
            valign = "center",

            gui.Label{
                width = "auto", height = "auto", halign = "center", valign = "top",
                fontSize = 24, color = "white", vmargin = 6,
                text = "Texture Browser",
            },

            gui.Label{
                width = "auto", height = "auto", halign = "center", valign = "top",
                fontSize = 12, color = "#999999",
                text = "hover a row for image preview   |   click a row for its details   |   click VRAM / Sys Mem headers to sort",
            },

            gui.Panel{
                flow = "horizontal",
                width = "98%",
                height = "auto",
                halign = "center",
                vmargin = 4,

                summaryLabel,

                --the checkbox stacked over Refresh, so the summary keeps the row's width.
                gui.Panel{
                    flow = "vertical",
                    width = 140,
                    height = "auto",
                    halign = "right",
                    valign = "center",

                    gui.Check{
                        text = "All textures",
                        halign = "right",
                        valign = "center",
                        value = g_allTexturesSetting:Get(),
                        change = function(element)
                            g_allTexturesSetting:Set(element.value)
                            Refresh()
                        end,
                    },

                    gui.Button{
                        text = "Refresh",
                        width = 110,
                        height = 34,
                        halign = "right",
                        valign = "center",
                        tmargin = 6,
                        click = function()
                            Refresh()
                        end,
                    },
                },
            },

            headerPanel,
            listPanel,

            create = function(element)
                Refresh()
            end,
        }

        return resultPanel
    end,
}
