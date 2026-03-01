--- @class Loc Represents a discrete tile location on the map, including x, y coordinates, floor index, and altitude.
--- @field west Loc The location one tile to the west.
--- @field east Loc The location one tile to the east.
--- @field north Loc The location one tile to the north.
--- @field south Loc The location one tile to the south.
--- @field withCurrentFloor Loc A new Loc with the floor index set to the currently active floor.
--- @field isValidFloor boolean True if the floor index of this Loc corresponds to a valid, visible floor.
--- @field x number The x tile coordinate.
--- @field y number The y tile coordinate.
--- @field floor number The floor index.
--- @field altitude number The altitude value at this location.
--- @field xyfloorOnly Loc A new Loc with only x, y, and floor preserved, stripping tiny size and altitude.
--- @field xyOnly Loc A new Loc with only x and y preserved, stripping floor, tiny size, and altitude.
--- @field isOnMap boolean True if this location is a valid position on the current map.
--- @field withGroundAltitude Loc A new Loc with altitude set to the ground level at this position.
--- @field valid boolean True if this Loc has valid coordinates.
--- @field point2 Vector2 The x, y coordinates of this Loc as a Vector2.
--- @field point3 Vector3 The x, y coordinates and altitude of this Loc as a Vector3.
--- @field str string The encoded string representation of this Loc, suitable for serialization.
Loc = {}

--- Deserialize
--- @param dict any
--- @return nil
function Loc:Deserialize(dict)
	-- dummy implementation for documentation purposes only
end

--- Equals
--- @param other any
--- @return boolean
function Loc:Equals(other)
	-- dummy implementation for documentation purposes only
end

--- DistanceInTiles: Returns the distance in tiles between this location and another Loc.
--- @param other Loc
--- @return integer
function Loc:DistanceInTiles(other)
	-- dummy implementation for documentation purposes only
end

--- DistanceInFeet: Returns the distance in feet between this location and another Loc (tiles * 5).
--- @param other Loc
--- @return integer
function Loc:DistanceInFeet(other)
	-- dummy implementation for documentation purposes only
end

--- dir: Returns a new Loc offset by the given x and y tile deltas.
--- @param x integer
--- @param y integer
--- @return Loc
function Loc:dir(x, y)
	-- dummy implementation for documentation purposes only
end

--- WithAltitude: Returns a new Loc with the specified altitude.
--- @param alt integer
--- @return Loc
function Loc:WithAltitude(alt)
	-- dummy implementation for documentation purposes only
end

--- WithDifferentFloor: Returns a new Loc on the specified floor index.
--- @param differentFloor integer
--- @return Loc
function Loc:WithDifferentFloor(differentFloor)
	-- dummy implementation for documentation purposes only
end

--- FloorDifference: Returns the floor index difference between this Loc and another, accounting for parent floor relationships.
--- @param loc Loc
--- @return integer
function Loc:FloorDifference(loc)
	-- dummy implementation for documentation purposes only
end

--- WithGroundLevelAltitude: Returns a new Loc with altitude set to the ground level at this location.
--- @return Loc
function Loc:WithGroundLevelAltitude()
	-- dummy implementation for documentation purposes only
end

--- LocsInRadius: Returns all Locs within the given radius (in tiles) of this location.
--- @param radius integer -- Radius in tiles.
--- @return Loc[]
function Loc:LocsInRadius(radius)
	-- dummy implementation for documentation purposes only
end
