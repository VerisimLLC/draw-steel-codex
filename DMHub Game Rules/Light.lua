local mod = dmhub.GetModLoading()

--- @class Light: GameType
--- @field color table Color value for the emitted light.
--- @field radius number Outer radius in world units (dim light boundary).
--- @field innerRadius number Inner radius in world units (bright light boundary).
--- @field angle number Cone angle in degrees (360 = full circle).
--- @field size number Light source size/intensity multiplier.
--- Represents a dynamic light source attached to a token or object.
Light = RegisterGameType("Light")

Light.size = 0.1

function Light.Create()
	return Light.new{
		color = core.Color('#ffffff'),
		radius = 8,
		innerRadius = 6,
		angle = 360,
		size = 0.1,
	}
end

function Light:RadiusInFeet()
	return self:BrightRadiusInFeet() + self:DimRadiusInFeet()
end

function Light:BrightRadiusInFeet()
	return round(self.innerRadius*5)
end

function Light:DimRadiusInFeet()
	return round(self.radius*5)
end
