local mod = dmhub.GetModLoading()

--The isometric "layers" overview screen used to live here: CreateLayersDisplay,
--LayerSettingsDisplay and CreateFloorPanel, driven by dmhub.LayerCamera and the
--"#MapLayers" render. Clicking a floor's settings button opened that whole screen.
--
--It was replaced by a lightweight per-floor settings popup (ShowFloorSettings in
--"DMHub Core Panels/Floors.lua"), which the settings buttons now open directly, so
--this module no longer has anything to do. The file is kept (rather than deleted)
--because it is registered with the DMHub module system and required from main.lua.
