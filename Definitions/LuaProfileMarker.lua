--- @class LuaProfileMarker A profiling marker for measuring performance of code sections.
--- @field Begin number Begins the profiling marker. Must be paired with a read of End.
--- @field End number Ends the profiling marker. Must follow a read of Begin.
LuaProfileMarker = {}
