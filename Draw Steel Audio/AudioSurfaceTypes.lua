local mod = dmhub.GetModLoading()

AudioObjectDestructionTypes = {
    types = {
        {
            id = "none",
            text = "None",
            sound = nil,
        },
        {
            id = "glass",
            text = "Glass",
            sound = "Obj.Break_GlassGnrcMed",
        },
        {
            id = "metal",
            text = "Metal",
            sound = "Obj.Break_MetalGnrcMed",
        },
        {
            id = "stone",
            text = "Stone",
            sound = "Obj.Break_StoneGnrcMed",
        },
        {
            id = "wood",
            text = "Wood",
            sound = "Obj.Break_WoodGnrcMed",
        },
    },
}

AudioSurfaceTypes = {
    surfaces = {
        {
            id = 1,
            text = "Generic",
            sound = "Foot.Generic_Generic",
        },
        {
            id = 2,
            text = "Dirt",
            sound = "Foot.Generic_Dirt",
        },
        {
            id = 3,
            text = "Grass",
            sound = "Foot.Generic_Grass",
        },
        {
            id = 4,
            text = "Hollow Metal",
            sound = "Foot.Generic_MetalHollow",
        },
        {
            id = 5,
            text = "Solid Metal",
            sound = "Foot.Generic_MetalSolid",
        },
        {
            id = 6,
            text = "Stone",
            sound = "Foot.Generic_Stone",
        },
        {
            id = 7,
            text = "Wood",
            sound = "Foot.Generic_Wood",
        },
        {
            id = 8,
            text = "Puddle",
            sound = "Foot.Generic_Dirt",
            puddleSound = true,
        }
    }
}