local mod = dmhub.GetModLoading()

PDFAugmentations = {}

--Augmentation entries live in their own tables, NOT as fields on the public
--PDFAugmentations namespace, so iterating them never trips over the API
--functions defined here (that crash was an "index a function value" error).
--Two views are kept: by id, and a pdf+page index so the viewer can look up a
--page's augmentations in O(1) instead of walking the whole registry at ~100Hz.
local g_augmentations = {}   --id -> augmentation
local g_byPdfPage = {}        --normalized "pdf|page" -> { augmentation, ... }

--Normalize a (pdf description, page) pair into an index key. Descriptions in
--the documents table can carry trailing whitespace and varied case, and page
--may be a number or string, so trim + lower + tostring everything.
local function AugPageKey(pdf, page)
    return trim(string.lower(pdf or "")) .. "|" .. trim(tostring(page))
end

local function RegisterPDFAugmentation(augmentation)
    --if this id was registered before, drop the stale entry from its page list.
    local existing = g_augmentations[augmentation.id]
    if existing ~= nil then
        local oldList = g_byPdfPage[AugPageKey(existing.pdf, existing.page)]
        if oldList ~= nil then
            for i = #oldList, 1, -1 do
                if oldList[i].id == augmentation.id then
                    table.remove(oldList, i)
                end
            end
        end
    end

    g_augmentations[augmentation.id] = augmentation

    local key = AugPageKey(augmentation.pdf, augmentation.page)
    local list = g_byPdfPage[key]
    if list == nil then
        list = {}
        g_byPdfPage[key] = list
    end
    list[#list + 1] = augmentation
end

--Augmentations on a given PDF (by description) and displayed page. O(1) lookup,
--no full-registry walk. Returns a shared list -- callers must not mutate it.
function PDFAugmentations.GetForPage(pdfDescription, page)
    return g_byPdfPage[AugPageKey(pdfDescription, page)] or {}
end

function PDFAugmentations.Get(id)
    return g_augmentations[id]
end

function PDFAugmentations.All()
    return g_augmentations
end

--A faithful Lua port of C# PettingGestureDetector (Assets/Scripts/GestureDetection.cs):
--detects a back-and-forth "petting" stroke (no mouse button held). Feed it a
--pixel-space mouse position each frame via :Tick(); it returns true once enough
--rapid direction reversals accumulate, and stays true while stroking continues.
--Target-agnostic and Unity-free, same as the C# original. The PDF viewer host
--owns one per gesture-enabled augmentation (see JournalPDFViewer.lua).
function PDFAugmentations.NewGestureDetector()
    local self = {
        --tuning (mirrors the C# defaults)
        minStrokeDistance = 28,        --min length (px) of a stroke for it to count
        reversalDotThreshold = -0.25,  --dot <= this vs current dir ends a stroke
        strokeWindowSeconds = 1.5,     --sliding window over which strokes are counted
        strokesToStart = 3,            --strokes within the window needed to start
        sustainTimeoutSeconds = 1.2,   --once started, stops if no stroke lands within this
        moveEpsilon = 1.5,             --per-tick movement below this (px) is noise

        --state
        _strokeTimes = {},
        _lastPos = nil,
        _strokeStart = nil,
        _strokeDir = nil,
        _haveStroke = false,
        _lastStrokeTime = -1000,
        _isPetting = false,
    }

    function self:Reset()
        self._strokeTimes = {}
        self._lastPos = nil
        self._strokeStart = nil
        self._strokeDir = nil
        self._haveStroke = false
        self._lastStrokeTime = -1000
        self._isPetting = false
    end

    --Call once per frame. 'active' must be true only while the cursor is over the
    --target and all gameplay guards pass; false resets the gesture. 'now' is a
    --monotonic timestamp in seconds (dmhub.Time()). Returns whether petting.
    function self:Tick(mx, my, now, active)
        if not active then
            if self._isPetting or self._haveStroke or self._lastPos ~= nil or #self._strokeTimes > 0 then
                self:Reset()
            end
            return false
        end

        if self._lastPos == nil then
            self._lastPos = { x = mx, y = my }
            return self._isPetting
        end

        local dx = mx - self._lastPos.x
        local dy = my - self._lastPos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        self._lastPos.x = mx
        self._lastPos.y = my

        if dist >= self.moveEpsilon then
            local dirx = dx / dist
            local diry = dy / dist
            if not self._haveStroke then
                self._strokeStart = { x = mx, y = my }
                self._strokeDir = { x = dirx, y = diry }
                self._haveStroke = true
            elseif (dirx * self._strokeDir.x + diry * self._strokeDir.y) <= self.reversalDotThreshold then
                --direction reversed -> the just-finished stroke is complete.
                local sdx = self._lastPos.x - self._strokeStart.x
                local sdy = self._lastPos.y - self._strokeStart.y
                if math.sqrt(sdx * sdx + sdy * sdy) >= self.minStrokeDistance then
                    self._strokeTimes[#self._strokeTimes + 1] = now
                    self._lastStrokeTime = now
                end
                self._strokeStart = { x = mx, y = my }
                self._strokeDir = { x = dirx, y = diry }
            else
                --still heading the same general way -> extend the current stroke.
                self._strokeDir = { x = dirx, y = diry }
            end
        end

        --drop strokes that have aged out of the sliding window.
        local cutoff = now - self.strokeWindowSeconds
        local kept = {}
        for i = 1, #self._strokeTimes do
            if self._strokeTimes[i] >= cutoff then
                kept[#kept + 1] = self._strokeTimes[i]
            end
        end
        self._strokeTimes = kept

        if not self._isPetting then
            if #self._strokeTimes >= self.strokesToStart then
                self._isPetting = true
            end
        elseif now - self._lastStrokeTime > self.sustainTimeoutSeconds then
            self._isPetting = false
        end

        return self._isPetting
    end

    return self
end

RegisterPDFAugmentation{
    id = "lightbender_bg",
    pdf = "The Beastheart",
    zorder = 1,
    page = 14,
    area = {0.096319079399109, 0.49958267807961, 0.49570560455322, 0.94133573770523 },
    image = "drawsteel/spine/bg_lightbender.png",
    bgcolor = "white",
}

RegisterPDFAugmentation{
    id = "lightbender_fg",
    pdf = "The Beastheart",
    zorder = 2,
    page = 14,
    area = {0.096319079399109, 0.49958267807961, 0.49570560455322, 0.94133573770523 },
    image = "#spinemodel:lightbender",
    bgcolor = "white",
    blend = "premultiplied",
    gesture = function(gestureName)
        spine.modelgesture("lightbender", gestureName)
    end,
}

spine.modelrender{
    id = "lightbender",
    model = "lightbender",
    width = 713,
    height = 1024,
    scale = 1,
    offset = { 0, 0},
}

--smallest power of two >= n (loop form, robust against float log2 rounding).
local function NextPowerOfTwo(n)
    local p = 1
    while p < n do
        p = p * 2
    end
    return p
end

--find a registered PDF document by its (trimmed, case-insensitive) description.
local function FindDocumentByDescription(desc)
    local docs = rawget(_G, "assets")
    if docs == nil or docs.pdfDocumentsTable == nil then
        return nil
    end
    local target = trim(string.lower(desc or ""))
    for _, doc in pairs(docs.pdfDocumentsTable) do
        local d = nil
        pcall(function() d = doc.description end)
        if d ~= nil and trim(string.lower(d)) == target then
            return doc
        end
    end
    return nil
end

--dev macro: report the true aspect ratio of an augmentation's area and a
--recommended source image size to fill it. The area's normalized box is NOT
--its own aspect ratio -- it must be corrected by the page aspect, because x is
--a fraction of pageWidth and y a fraction of pageHeight (different scales).
Commands.RegisterMacro{
    name = "dev:pdfaugmentdim",
    summary = "aspect + recommended image size for a PDF augmentation",
    doc = "Usage: /dev:pdfaugmentdim <augmentation id>\nLooks up a registered PDF augmentation, reads its document's page aspect, and reports the true aspect ratio of its 'area' plus a recommended source image size. Image size assumes the page is displayed at >=1600px across, then rounds up so the dimension that reaches a power of two first lands exactly on one (the other scales proportionally).",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        for id, aug in pairs(PDFAugmentations.All()) do
            result[#result + 1] = {
                text = id,
                summary = string.format("%s p.%s", tostring(aug.pdf), tostring(aug.page)),
            }
        end
        return result
    end,
    command = function(str)
        local id = trim(str or "")
        local aug = PDFAugmentations.Get(id)
        if aug == nil then
            print(string.format("dev:pdfaugmentdim: no augmentation registered with id '%s'", id))
            return
        end

        local doc = FindDocumentByDescription(aug.pdf)
        if doc == nil then
            print(string.format("dev:pdfaugmentdim: no loaded PDF document with description '%s' (open it once so it loads).", tostring(aug.pdf)))
            return
        end

        local summary = doc.doc.summary
        if summary == nil then
            print(string.format("dev:pdfaugmentdim: document '%s' has no summary yet (open the PDF once so it loads).", tostring(aug.pdf)))
            return
        end

        local pageW = summary.pageWidth
        local pageH = summary.pageHeight
        if pageW == nil or pageH == nil or pageW <= 0 or pageH <= 0 then
            print("dev:pdfaugmentdim: document reports invalid page dimensions.")
            return
        end

        local area = aug.area
        local dx = area[3] - area[1]
        local dy = area[4] - area[2]
        if dx <= 0 or dy <= 0 then
            print(string.format("dev:pdfaugmentdim: augmentation '%s' has a degenerate area {%g, %g, %g, %g}.", id, area[1], area[2], area[3], area[4]))
            return
        end

        local pageAspect = pageW / pageH
        local areaAspect = (dx / dy) * pageAspect

        --assume the page is displayed at least 1600px across.
        local displayW = 1600
        local displayH = displayW * (pageH / pageW)
        local imgW = dx * displayW
        local imgH = dy * displayH

        --scale up uniformly until one dimension reaches a power of two; stop at
        --whichever gets there first (the smaller scale factor).
        local scaleW = NextPowerOfTwo(imgW) / imgW
        local scaleH = NextPowerOfTwo(imgH) / imgH
        local scale = math.min(scaleW, scaleH)
        local recW = math.ceil(imgW * scale)
        local recH = math.ceil(imgH * scale)
        local pow2Dim = (scaleW <= scaleH) and "width" or "height"

        print(string.format("=== dev:pdfaugmentdim: %s ===", id))
        print(string.format("PDF:            %s", trim(tostring(aug.pdf))))
        print(string.format("Page:           %s", tostring(aug.page)))
        print(string.format("Page size:      %g x %g pts (aspect W/H = %.4f)", pageW, pageH, pageAspect))
        print(string.format("Area:           {%.4f, %.4f, %.4f, %.4f}", area[1], area[2], area[3], area[4]))
        print(string.format("Area fraction:  %.4f wide x %.4f tall of the page", dx, dy))
        print(string.format("Area aspect:    %.4f (width/height), %.4f (height/width)", areaAspect, 1 / areaAspect))
        print(string.format("At >=1600px across, area renders at %.1f x %.1f px", imgW, imgH))
        print(string.format("Recommended image: %d x %d px (%s rounded up to power of two)", recW, recH, pow2Dim))
    end,
}