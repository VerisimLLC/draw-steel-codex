local mod = dmhub.GetModLoading()
--- @class CharacterDescription
--- @field weight string
--- @field height string
--- @field hair string
--- @field eyes string
--- @field skinTone string
--- @field build string
--- @field genderPresentation string
--- @field pronouns string
--- @field physicalFeatures string
CharacterDescription = RegisterGameType("CharacterDescription")

CharacterDescription.CHARACTER_KEY = "characterDescription"
CharacterDescription.weight = ""
CharacterDescription.height = ""
CharacterDescription.hair = ""
CharacterDescription.eyes = ""
CharacterDescription.skinTone = ""
CharacterDescription.build = ""
CharacterDescription.genderPresentation = ""
CharacterDescription.pronouns = ""
CharacterDescription.physicalFeatures = ""

function CharacterDescription:SetWeight(weight)
    self.weight = weight
    return self
end

function CharacterDescription:GetWeight()
    return self:try_get("weight")
end

function CharacterDescription:SetHeight(height)
    self.height = height
    return self
end

function CharacterDescription:GetHeight()
    return self:try_get("height")
end

function CharacterDescription:SetHair(hair)
    self.hair = hair
    return self
end

function CharacterDescription:GetHair()
    return self:try_get("hair")
end

function CharacterDescription:SetEyes(eyes)
    self.eyes = eyes
    return self
end

function CharacterDescription:GetEyes()
    return self:try_get("eyes")
end

function CharacterDescription:SetSkinTone(skinTone)
    self.skinTone = skinTone
    return self
end

function CharacterDescription:GetSkinTone()
    return self:try_get("skinTone")
end

function CharacterDescription:SetBuild(build)
    self.build = build
    return self
end

function CharacterDescription:GetBuild()
    return self:try_get("build")
end

function CharacterDescription:SetGenderPresentation(genderPresentation)
    self.genderPresentation = genderPresentation
    return self
end

function CharacterDescription:GetGenderPresentation()
    return self:try_get("genderPresentation")
end

function CharacterDescription:SetPronouns(pronouns)
    self.pronouns = pronouns
    return self
end

function CharacterDescription:GetPronouns()
    return self:try_get("pronouns")
end

function CharacterDescription:SetPhysicalFeatures(physicalFeatures)
    self.physicalFeatures = physicalFeatures
    return self
end

function CharacterDescription:GetPhysicalFeatures()
    return self:try_get("physicalFeatures")
end

character.Description = function(self)
    return self:try_get(CharacterDescription.CHARACTER_KEY)
end
