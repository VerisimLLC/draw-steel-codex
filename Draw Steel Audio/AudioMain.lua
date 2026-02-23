local mod = dmhub.GetModLoading()

--Register Audio Mod
audio.RegisterAudioMod(mod)

--Mix Groups

audio.MixGroup{
    id = "gameplay",
    name = tr("Gameplay"),
}

audio.MixGroup{
    id = "ui",
    name = tr("UI"),
}

audio.MixGroup{
    id = "dice",
    name = tr("Dice"),
}

audio.MixGroup{
    id = "footsteps",
    parent = "gameplay",
    name = tr("Footsteps"),
}


--UI Sounds

--Implemented: plays when combat begins.
audio.SoundEvent{
    name = "UI.DrawSteel",
    mixgroup = "ui",
    sounds = {"CombatStart_DrawSteel_v1_01.wav"},
    volume = 0.5,
}

audio.SoundEvent{
    name = "UI.TurnStart_Hero",
    mixgroup = "ui",
    sounds = {"TurnStart_Hero_v1_01.wav"},
    volume = 0.25,
}

audio.SoundEvent{
    name = "UI.TurnStart_Enemy",
    mixgroup = "ui",
    sounds = {"TurnStart_Enemy_v1_01.wav"},
    volume = 0.25,
}

audio.SoundEvent{
    name = "UI.RoundStart",
    mixgroup = "ui",
    sounds = {"RoundStart_v1_01.wav"},
    volume = 0.25,
}


--Implemented: currently just on initiative swords.
audio.SoundEvent{
    name = "Mouse.Click",
    mixgroup = "ui",
    sounds = {"Mouse_Click_Generic_v1_01.wav"},
    volume = 0.25,
}

--Implemented: currently just on initiative swords.
audio.SoundEvent{
    name = "Mouse.Hover",
    mixgroup = "ui",
    sounds = {"Mouse_Hover_Generic_v1_01.wav"},
    volume = 0.5,
}

--Director Pasume/Resume Game


audio.SoundEvent{
    name = "Notify.TimeFreeze_Start",
    mixgroup = "ui",
    sounds = {"Notify_TimeFreeze_Start_v1_01.wav"},
    volume = 0.5,
    ignoreDuplicates = 1,
}

audio.SoundEvent{
    name = "Notify.TimeFreeze_End",
    mixgroup = "ui",
    sounds = {"Notify_TimeFreeze_End_v1_01.wav"},
    volume = 0.5,
    ignoreDuplicates = 1,
}

--Rewind/Undo actions

audio.SoundEvent{
    name = "Notify.Director_Undo",
    mixgroup = "ui",
    sounds = {"Notify_Director_Undo_v1_01.wav"},
    volume = 0.5,
    ignoreDuplicates = 1,
}






--Implemented: plays when a player is prompted to do a dice roll.
audio.SoundEvent{
    name = "Notify.Diceroll",
    mixgroup = "ui",
    sounds = {"Notify_DiceRoll_v3_01.wav","Notify_DiceRoll_v3_02.wav","Notify_DiceRoll_v3_03.wav"},
    volume = 0.75,
    pitchRand = 0.2,
    ignoreDuplicates = 1,

}

--Implemented: plays when a player gains a heroic resource.
--Note that similar sound events play for other types of resources.
--example: Notify.Surges_Gain.
audio.SoundEvent{
    name = "Notify.HeroicResource_Gain",
    mixgroup = "ui",
    sounds = {"Notify_HeroicResource_Gain_v1_01.wav"},
    volume = 0.5,

    --example of custom 'play' function. It can be used to customize the sound
    --dynamically. If you gain multiple resources at once the sound will play
    --multiple times, with the sequence number increasing each time. We can
    --customize the volume and pitch based on the sequence number.
    play = function(sound)
        sound.volume = 0.7^(sound.args.sequence-1)
        sound.pitch = 1.1^(sound.args.sequence-1)
    end,
}

--Implemented: plays when a trigger that you control is activated.
audio.SoundEvent{
    name = "Notify.Trigger",
    mixgroup = "ui",
    sounds = {"Notify_Trigger_v1_01.wav"},
    volume = 0.7,
    ignoreDuplicates = 0.2, --ignore duplicates for 0.2 seconds
}

--Temp Stamina Gain
audio.SoundEvent{
    name = "Notify.TempStamina_Gain",
    mixgroup = "ui",
    sounds = {"Notify_TempStam_Gain_v1_01.wav"},
    volume = 0.3,
    ignoreDuplicates = 0.2,
    ignoreDuplicates = 0.2,--ignore duplicates for 0.2 seconds
}


--Implemented
--plays when a trigger is used
audio.SoundEvent{
    name = "Notify.TriggerUse",
    mixgroup = "ui",
    sounds = {"Notify_TriggerUse_v1_01.wav"},
    volume = 0.5,
    ignoreDuplicates = 0.2, --ignore duplicates for 0.2 seconds
}

--Implemented
--plays when an opportunity attack is warned
audio.SoundEvent{
    name = "Notify.OpportunityAttackWarn",
    mixgroup = "ui",
    sounds = {"Notify_OpportunityAttackWarn_v1_01.wav"},
    volume = 0.1,
    ignoreDuplicates = 0.2, --ignore duplicates for 0.2 seconds
}


--for when anyone pings a part of the play space
audio.SoundEvent{
    name = "Notify.Ping",
    mixgroup = "ui",
    sounds = {"Notify_Ping_v1_01.wav"},
    volume = 1.0,
    ignoreDuplicates = 1, --ignore duplicates for 1 seconds
}


audio.SoundEvent{
    name = "Notify.Secret_Reveal",
    mixgroup = "ui",
    sounds = {"Notify_Secret_Reveal_v1_01.wav"},
    volume = 0.20,
    ignoreDuplicates = 1, --ignore duplicates for 1 seconds
}






---User Join Session
audio.SoundEvent{
    name = "Notify.UserJoin",
    mixgroup = "ui",
    sounds = {"Notify_UserJoin_v1_01.wav"},
    volume =0.5,
    ignoreDuplicates = 1, --ignore duplicates for 1 seconds
}

--User Leave Session
audio.SoundEvent{
    name = "Notify.UserLeave",
    mixgroup = "ui",
    sounds = {"Notify_UserLeave_v1_01.wav"},
    volume = 0.5,
    ignoreDuplicates = 1, --ignore duplicates for 1 seconds
}


----Surge Gain

audio.SoundEvent{
    name = "Notify.Surges_Gain",
    mixgroup = "ui",
    sounds = {"Notify_Surge_Gain_v1_01.wav"},
    volume = 0.2,
    ignoreDuplicates = 0.2,
}

---Surge Use

audio.SoundEvent{
    name = "Notify.Surges_Spend",
    mixgroup = "ui",
    sounds = {"Notify_Surge_Use_v1_01.wav"},
    volume = 0.08,
    ignoreDuplicates = 0.2,
}

--Conditions

audio.SoundEvent{
    name = "Notify.Status_Dying_Hero",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Dying_Hero_v1_01.wav"},
    volume = 0.3,
    ignoreDuplicates = 0.2,
}

audio.SoundEvent{
    name = "Notify.Status_Dead_Hero",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Dead_Hero_v1_01.wav"},
    volume = 0.4,
    ignoreDuplicates = 0.2,
}

audio.SoundEvent{
    name = "Notify.Status_Dead_Enemy",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Dead_Enemy_v1_01.wav"},
    volume = 0.4,
    pitchRand = 0.05,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Notify.Status_Dead_Minion",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Dead_Minion_v1_01.wav"},
    volume = 0.4,
    pitchRand = 0.05,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Slowed",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Slowed_Start_v1_01.wav"},
    volume = 0.4,
    pitchRand = 0.2,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Prone",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Prone_v1_01.wav"},
    volume = 0.4,
    pitchRand = 0.2,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Bleeding",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Bleed_v1_01.wav"},
    volume = 0.4,
    pitchRand = 0.2,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Frightened",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Frightened_v1_01.wav"},
    volume = 0.2,
    pitchRand = 0.2,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Winded",
    mixgroup = "ui",
    sounds = {"status/Notify_Status_Start_Winded_v1_01.wav"},
    volume = 0.3,
    pitchRand = 0.05,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Dazed",
    mixgroup = "ui",
    sounds = {"status/Notify_Cond_Start_Dazed_v1_01.wav"},
    volume = 0.3,
    pitchRand = 0.05,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Taunted",
    mixgroup = "ui",
    sounds = {"status/Notify_Cond_Start_Taunted_v1_01.wav"},
    volume = 0.3,
    pitchRand = 0.05,
    ignoreDuplicates = 0.02,
}

audio.SoundEvent{
    name = "Condition.Restrained",
    mixgroup = "ui",
    sounds = {"status/Notify_Cond_Start_Restrained_v1_01.wav"},
    volume = 0.3,
    pitchRand = 0.05,
    ignoreDuplicates = 0.02,
}







audio.SoundEvent{
    name = "UI.WindowClose",
    mixgroup = "ui",
    sounds = {"Window_Close_v1_01.wav"},
    volume = 0.25,
}

audio.SoundEvent{
    name = "UI.WindowOpen",
    mixgroup = "ui",
    sounds = {"Window_Open_v1_01.wav"},
    volume = 0.25,
    ignoreDuplicates = 0.5,
}

audio.SoundEvent{
    name = "UI.ChatMsgRegular",
    mixgroup = "ui",
    sounds = {"Chat_Msg_Regular_v1_01.wav"},
    volume = 1.0,
}

audio.SoundEvent{
    name = "UI.ChatMsgSpecial",
    mixgroup = "ui",
    sounds = {"Chat_Msg_Special_v1_01.wav"},
    volume = 1.0,
}

audio.SoundEvent{
    name = "UI.Error_Generic",
    mixgroup = "ui",
    sounds = {"Notify_Error_Gnrc_v1_01.wav"},
    volume = 0.2,
}

audio.SoundEvent{
    name = "UI.Inv_Grab",
    mixgroup = "ui",
    sounds = {"inv/Inv_Grab_Gnrc_v1_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "UI.Inv_Place",
    mixgroup = "ui",
    sounds = {"inv/Inv_Place_Gnrc_v1_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "UI.Inv_Item_Pickup_Gnrc",
    mixgroup = "ui",
    sounds = {"inv/Inv_Item_Pickup_Gnrc_v1_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "UI.Inv_Item_Pickup_Special",
    mixgroup = "ui",
    sounds = {"inv/Inv_Item_Pickup_Special_v1_01.wav"},
    volume = 0.3,
}











--Gameplay Sounds


--Torch On/Off
audio.SoundEvent{
    name = "Ability.Torch_On",
    mixgroup = "gameplay",
    sounds = {"abl/Abl_Torch_On_v1_01.wav","abl/Abl_Torch_On_v1_02.wav","abl/Abl_Torch_On_v1_03.wav","abl/Abl_Torch_On_v1_04.wav","abl/Abl_Torch_On_v1_05.wav","abl/Abl_Torch_On_v1_06.wav"},
    volume = 0.1,
    pitchRand = 0.1,
}

audio.SoundEvent{
    name = "Ability.Torch_Off",
    mixgroup = "gameplay",
    sounds = {"abl/Abl_Torch_Off_v1_01.wav","abl/Abl_Torch_Off_v1_02.wav","abl/Abl_Torch_Off_v1_03.wav","abl/Abl_Torch_Off_v1_04.wav"},
    volume = 0.1,
    pitchRand = 0.1,
}


--Reanimate Dead
audio.SoundEvent{
    name = "Ability.Reanimate_Start",
    mixgroup = "gameplay",
    sounds = {"Abl_RaiseDead_Start_01.wav","Abl_RaiseDead_Start_02.wav","Abl_RaiseDead_Start_03.wav"},
    volume = 0.5,
    pitchRand = 0.05,
}


--Any form of healing done
audio.SoundEvent{
    name = "Ability.Heal_Generic",
    mixgroup = "gameplay",
    sounds = {"Abl_Heal_Gnrc_v1_01.wav"},
    volume = 0.5,
    pitchRand = 0.05,
}

--Any teleport done
audio.SoundEvent{
    name = "Ability.Teleport_Generic",
    mixgroup = "gameplay",
    sounds = {"Abl_Teleport_Gnrc_v2_01.wav"},
    volume = 0.4,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

--Hide

audio.SoundEvent{
    name = "Ability.Hide_Start",
    mixgroup = "gameplay",
    sounds = {"Abl_Hide_Start_v1_01.wav"},
    volume = 0.5,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

audio.SoundEvent{
    name = "Ability.Hide_End",
    mixgroup = "gameplay",
    sounds = {"Abl_Hide_End_v1_01.wav"},
    volume = 0.5,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

--Disguise

audio.SoundEvent{
    name = "Ability.Disguise_Start",
    mixgroup = "gameplay",
    sounds = {"Abl_Disguise_Start_v1_01.wav"},
    volume = 0.5,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

audio.SoundEvent{
    name = "Ability.Disguise_End",
    mixgroup = "gameplay",
    sounds = {"Abl_Disguise_End_v1_01.wav"},
    volume = 0.2,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}




--Implemented: plays when landing after a fall.
audio.SoundEvent{
    name = "Attack.FallLand",
    mixgroup = "gameplay",
    sounds = {"Atk_FallLand_v1_01.wav"},
    volume = 1.0,
}

--Implemented: plays when the grabbed condition is applied.
audio.SoundEvent{
    name = "Condition.Grabbed",
    mixgroup = "gameplay",
    sounds = {"Atk_Grab_v1_01.wav"},
    volume = 1.0,
}

--Implemented: plays when a character is shoved.
audio.SoundEvent{
    name = "Attack.Shove",
    mixgroup = "gameplay",
    sounds = {"Atk_Shove_v1_01.wav"},
    volume = 1.0,
}

--Implemented: plays when a creature *takes damage* from any source/reason. (Should review if this is best)
audio.SoundEvent{
    name = "Attack.Hit",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Gnrc_v1_01.wav","Atk_Hit/Atk_Hit_Gnrc_v1_02.wav","Atk_Hit/Atk_Hit_Gnrc_v1_03.wav","Atk_Hit/Atk_Hit_Gnrc_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_acid",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Acid_v1_01.wav","Atk_Hit/Atk_Hit_Acid_v1_02.wav","Atk_Hit/Atk_Hit_Acid_v1_03.wav","Atk_Hit/Atk_Hit_Acid_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_cold",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Cold_v1_01.wav","Atk_Hit/Atk_Hit_Cold_v1_02.wav","Atk_Hit/Atk_Hit_Cold_v1_03.wav","Atk_Hit/Atk_Hit_Cold_v1_04.wav","Atk_Hit/Atk_Hit_Cold_v1_05.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_corruption",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Corruption_v1_01.wav","Atk_Hit/Atk_Hit_Corruption_v1_02.wav","Atk_Hit/Atk_Hit_Corruption_v1_03.wav","Atk_Hit/Atk_Hit_Corruption_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_fire",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Fire_v1_01.wav","Atk_Hit/Atk_Hit_Fire_v1_02.wav","Atk_Hit/Atk_Hit_Fire_v1_03.wav","Atk_Hit/Atk_Hit_Fire_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_holy",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Holy_v2_01.wav","Atk_Hit/Atk_Hit_Holy_v2_02.wav","Atk_Hit/Atk_Hit_Holy_v2_03.wav","Atk_Hit/Atk_Hit_Holy_v2_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_lightning",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Lightning_v1_01.wav","Atk_Hit/Atk_Hit_Lightning_v1_02.wav","Atk_Hit/Atk_Hit_Lightning_v1_03.wav","Atk_Hit/Atk_Hit_Lightning_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_poison",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Poison_v1_01.wav","Atk_Hit/Atk_Hit_Poison_v1_02.wav","Atk_Hit/Atk_Hit_Poison_v1_03.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_psychic",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Psychic_v2_01.wav","Atk_Hit/Atk_Hit_Psychic_v2_02.wav","Atk_Hit/Atk_Hit_Psychic_v2_03.wav","Atk_Hit/Atk_Hit_Psychic_v2_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_sonic",
    mixgroup = "gameplay",
    sounds = {"Atk_Hit/Atk_Hit_Sonic_v1_01.wav","Atk_Hit/Atk_Hit_Sonic_v1_02.wav","Atk_Hit/Atk_Hit_Sonic_v1_03.wav","Atk_Hit/Atk_Hit_Sonic_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

--Implemented
--plays when creature takes environmental damage
audio.SoundEvent{
    name = "Attack.Enviro",
    mixgroup = "gameplay",
    sounds = {"Atk_Enviro_Gnrc_v1_01.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
}


---Falling in water
audio.SoundEvent{
    name = "Fol.Splash",
    mixgroup = "gameplay",
    sounds = {"Fol_Splash_v1_01.wav"},
    volume = 0.75,
    ignoreDuplicates = 0.2,
}



--Dice Sounds

audio.SoundEvent{
    name = "Dice.ThrowStart",
    mixgroup = "ui",
    sounds = {"Dice_ThrowStart_v1_01.wav"},
    volume = 0.3,
}
--Dice Power Roll
audio.SoundEvent{
    name = "UI.PowerRoll_Tier1",
    mixgroup = "ui",
    sounds = {"PowerRoll_Rolled_Tier1_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "UI.PowerRoll_Tier2",
    mixgroup = "ui",
    sounds = {"PowerRoll_Rolled_Tier2_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "UI.PowerRoll_Tier3",
    mixgroup = "ui",
    sounds = {"PowerRoll_Rolled_Tier3_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "UI.PowerRoll_Crit",
    mixgroup = "ui",
    sounds = {"PowerRoll_Rolled_Crit_01.wav"},
    volume = 0.3,
}













--Dice Impacts

audio.SoundEvent{
    mixgroup = "dice",
    name = "Dice.Impact",
    play = function(instance)
        local speed = instance.args.speed or 0
        local soundEvent = "DiceImp.Soft"
        local volume = 1
        if speed > 10 then
            soundEvent = "DiceImp.Hard"
            volume = 0.6 + (speed - 8) * 0.1
        elseif speed > 3 then
            soundEvent = "DiceImp.Mild"
            volume = 0.6 + (speed - 1) * 0.1
        else
            soundEvent = "DiceImp.Soft"
            volume = speed
        end

        local child = audio.FireSoundEvent(soundEvent, {})
        child.volume = volume
    end,
}

audio.SoundEvent{
    name = "DiceImp.Hard",
    mixgroup = "dice",
    sounds = {"dice/copper/DiceImp_CopperD20_Cuttingboard_Hard_01.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Hard_02.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Hard_03.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Hard_04.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Hard_05.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Hard_06.wav"},
    volume = 1.0,
    pitchRand = 0.1,
}

audio.SoundEvent{
    name = "DiceImp.Mild",
    mixgroup = "dice",
    sounds = {"dice/copper/DiceImp_CopperD20_Cuttingboard_Mild_01.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Mild_02.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Mild_03.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Mild_04.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Mild_05.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Mild_06.wav"},
    volume = 0.5,
    pitchRand = 0.1,
}

audio.SoundEvent{
    name = "DiceImp.Soft",
    mixgroup = "dice",
    sounds = {"dice/copper/DiceImp_CopperD20_Cuttingboard_Soft_01.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Soft_02.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Soft_03.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Soft_04.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Soft_05.wav","dice/copper/DiceImp_CopperD20_Cuttingboard_Soft_06.wav"},
    volume = 0.1,
    pitchRand = 0.1,
}



--FrontEnd

--Slide In
audio.SoundEvent{
    name = "UI.FrontEnd_SlideIn",
    mixgroup = "ui",
    sounds = {"FrontEnd_SlideIn_v1_01.wav"},
    volume = 0.3,
}





--Object Interactions
audio.SoundEvent{
    name = "Obj.Break_GlassGnrcMed",
    mixgroup = "gameplay",
    sounds = {"obj_break/Obj_Break_Glass_Gnrc_Med_01.wav","obj_break/Obj_Break_Glass_Gnrc_Med_02.wav","obj_break/Obj_Break_Glass_Gnrc_Med_03.wav","obj_break/Obj_Break_Glass_Gnrc_Med_04.wav","obj_break/Obj_Break_Glass_Gnrc_Med_05.wav","obj_break/Obj_Break_Glass_Gnrc_Med_06.wav"},
    volume = 0.4,
    pitchRand = 0.3,
}

audio.SoundEvent{
    name = "Obj.Break_MetalGnrcMed",
    mixgroup = "gameplay",
    sounds = {"obj_break/Obj_Break_Metal_Gnrc_Med_01.wav","obj_break/Obj_Break_Metal_Gnrc_Med_02.wav","obj_break/Obj_Break_Metal_Gnrc_Med_03.wav","obj_break/Obj_Break_Metal_Gnrc_Med_04.wav","obj_break/Obj_Break_Metal_Gnrc_Med_05.wav","obj_break/Obj_Break_Metal_Gnrc_Med_06.wav"},
    volume = 0.2,
    pitchRand = 0.3,
}

audio.SoundEvent{
    name = "Obj.Break_StoneGnrcMed",
    mixgroup = "gameplay",
    sounds = {"obj_break/Obj_Break_Stone_Gnrc_Med_01.wav","obj_break/Obj_Break_Stone_Gnrc_Med_02.wav","obj_break/Obj_Break_Stone_Gnrc_Med_03.wav","obj_break/Obj_Break_Stone_Gnrc_Med_04.wav","obj_break/Obj_Break_Stone_Gnrc_Med_05.wav","obj_break/Obj_Break_Stone_Gnrc_Med_06.wav"},
    volume = 0.4,
    pitchRand = 0.3,
}

audio.SoundEvent{
    name = "Obj.Break_WoodGnrcMed",
    mixgroup = "gameplay",
    sounds = {"obj_break/Obj_Break_Wood_Gnrc_Med_01.wav","obj_break/Obj_Break_Wood_Gnrc_Med_02.wav","obj_break/Obj_Break_Wood_Gnrc_Med_03.wav","obj_break/Obj_Break_Wood_Gnrc_Med_04.wav","obj_break/Obj_Break_Wood_Gnrc_Med_05.wav","obj_break/Obj_Break_Wood_Gnrc_Med_06.wav"},
    volume = 0.4,
    pitchRand = 0.3,
}

--Traps


audio.SoundEvent{
    name = "Obj.Trap_Trigger_Scythe",
    mixgroup = "gameplay",
    sounds = {"obj/OBJ_Trap_Trigger_Scythe_01.wav"},
    volume = 0.4,
    ignoreDuplicates = 1,
}

audio.SoundEvent{
    name = "Obj.Trap_Disarm",
    mixgroup = "gameplay",
    sounds = {"obj/OBJ_Trap_Disarm_v1_01.wav"},
    volume = 0.2,
    ignoreDuplicates = 1,
}

audio.SoundEvent{
    name = "Obj.Trap_Trigger_Generic",
    mixgroup = "gameplay",
    sounds = {"obj/OBJ_Trap_Trigger_Generic_v1_01.wav"},
    volume = 0.2,
    ignoreDuplicates = 1,
}


audio.SoundEvent{
    name = "Obj.Trap_Trigger_Snare",
    mixgroup = "gameplay",
    sounds = {"obj/OBJ_Trap_Trigger_Snare_v1_01.wav"},
    volume = 0.2,
    ignoreDuplicates = 1,
}





--Doors

audio.SoundEvent{
    name = "Obj.Door_Open",
    mixgroup = "gameplay",
    sounds = {"OBJ_Door_Open_Gnrc_v1_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "Obj.Door_Shut",
    mixgroup = "gameplay",
    sounds = {"OBJ_Door_Shut_Gnrc_v1_01.wav"},
    volume = 0.3,
}

audio.SoundEvent{
    name = "Obj.Door_Open_Lid_Stone",
    mixgroup = "gameplay",
    sounds = {"obj/Obj_StoneLid_Open_01.wav","obj/Obj_StoneLid_Open_02.wav","obj/Obj_StoneLid_Open_03.wav"},
    volume = 0.3,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Obj.Door_Open_Stone",
    mixgroup = "gameplay",
    sounds = {"obj/Obj_Door_Open_Stone_01.wav","obj/Obj_Door_Open_Stone_02.wav","obj/Obj_Door_Open_Stone_03.wav"},
    volume = 0.3,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}



audio.SoundEvent{
    name = "Obj.Lever_Pull_Open",
    mixgroup = "gameplay",
    sounds = {"obj/Obj_Lever_Pull_Open_01.wav"},
    volume = 0.3,
}








--Footsteps

--Generic Boot Generic Surface
audio.SoundEvent{
    name = "Foot.Generic_Generic",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_Gnrc_v1_01.wav","foot/FS_Walk_Gnrc_Gnrc_v1_02.wav","foot/FS_Walk_Gnrc_Gnrc_v1_03.wav","foot/FS_Walk_Gnrc_Gnrc_v1_04.wav","foot/FS_Walk_Gnrc_Gnrc_v1_05.wav","foot/FS_Walk_Gnrc_Gnrc_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Foot.Generic_Dirt",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_Dirt_v1_01.wav","foot/FS_Walk_Gnrc_Dirt_v1_02.wav","foot/FS_Walk_Gnrc_Dirt_v1_03.wav","foot/FS_Walk_Gnrc_Dirt_v1_04.wav","foot/FS_Walk_Gnrc_Dirt_v1_05.wav","foot/FS_Walk_Gnrc_Dirt_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Foot.Generic_Grass",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_Grass_v1_01.wav","foot/FS_Walk_Gnrc_Grass_v1_02.wav","foot/FS_Walk_Gnrc_Grass_v1_03.wav","foot/FS_Walk_Gnrc_Grass_v1_04.wav","foot/FS_Walk_Gnrc_Grass_v1_05.wav","foot/FS_Walk_Gnrc_Grass_v1_06.wav"},
    volume = 0.1,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Foot.Generic_MetalHollow",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_MetalHollow_v1_01.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_02.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_03.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_04.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_05.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Foot.Generic_MetalSolid",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_MetalSolid_v1_01.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_02.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_03.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_04.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_05.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Foot.Generic_Stone",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_Stone_v1_01.wav","foot/FS_Walk_Gnrc_Stone_v1_02.wav","foot/FS_Walk_Gnrc_Stone_v1_03.wav","foot/FS_Walk_Gnrc_Stone_v1_04.wav","foot/FS_Walk_Gnrc_Stone_v1_05.wav","foot/FS_Walk_Gnrc_Stone_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}

audio.SoundEvent{
    name = "Foot.Generic_Wood",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_Wood_v1_01.wav","foot/FS_Walk_Gnrc_Wood_v1_02.wav","foot/FS_Walk_Gnrc_Wood_v1_03.wav","foot/FS_Walk_Gnrc_Wood_v1_04.wav","foot/FS_Walk_Gnrc_Wood_v1_05.wav","foot/FS_Walk_Gnrc_Wood_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.3,
    ignoreDuplicates = 0.05,
}









--Other locomotion actions

audio.SoundEvent{
    name = "Foot.Fly_Wing",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Fly_Wing_Gnrc_v1_01.wav","foot/FS_Fly_Wing_Gnrc_v1_02.wav","foot/FS_Fly_Wing_Gnrc_v1_03.wav","foot/FS_Fly_Wing_Gnrc_v1_04.wav","foot/FS_Fly_Wing_Gnrc_v1_05.wav","foot/FS_Fly_Wing_Gnrc_v1_06.wav","foot/FS_Fly_Wing_Gnrc_v1_07.wav","foot/FS_Fly_Wing_Gnrc_v1_08.wav","foot/FS_Fly_Wing_Gnrc_v1_09.wav","foot/FS_Fly_Wing_Gnrc_v1_10.wav"},
    volume = 0.15,
    pitchRand = 0.15,
    ignoreDuplicates = 0.3,
}

audio.SoundEvent{
    name = "Foot.Swim_Generic",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Swim_Gnrc_v1_01.wav","foot/FS_Swim_Gnrc_v1_02.wav","foot/FS_Swim_Gnrc_v1_03.wav","foot/FS_Swim_Gnrc_v1_04.wav","foot/FS_Swim_Gnrc_v1_05.wav","foot/FS_Swim_Gnrc_v1_06.wav","foot/FS_Swim_Gnrc_v1_07.wav","foot/FS_Swim_Gnrc_v1_08.wav","foot/FS_Swim_Gnrc_v1_09.wav","foot/FS_Swim_Gnrc_v1_10.wav"},
    volume = 0.12,
    pitchRand = 0.1,
    ignoreDuplicates = 0.3,
}

audio.SoundEvent{
    name = "Foot.Crawl_Generic",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Crawl_Gnrc_v1_01.wav","foot/FS_Crawl_Gnrc_v1_02.wav","foot/FS_Crawl_Gnrc_v1_03.wav","foot/FS_Crawl_Gnrc_v1_04.wav","foot/FS_Crawl_Gnrc_v1_05.wav","foot/FS_Crawl_Gnrc_v1_06.wav"},
    volume = 0.06,
    pitchRand = 0.1,
    ignoreDuplicates = 0.2,
}

audio.SoundEvent{
    name = "Foot.Burrow_Generic",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Burrow_Gnrc_v1_01.wav","foot/FS_Burrow_Gnrc_v1_02.wav","foot/FS_Burrow_Gnrc_v1_03.wav","foot/FS_Burrow_Gnrc_v1_04.wav","foot/FS_Burrow_Gnrc_v1_05.wav","foot/FS_Burrow_Gnrc_v1_06.wav"},
    volume = 0.08,
    pitchRand = 0.1,
    ignoreDuplicates = 0.2,
}



audio.SoundEvent{
    name = "Foot.Climb_Generic",
    mixgroup = "footsteps",
    sounds = {"foot/Fol_Climb_Start_v1_01.wav"},
    volume = 0.08,
    pitchRand = 0.1,
    ignoreDuplicates = 0.2,
}



dmhub.TokenMovingOnPath = function(args)
    local surface = args.path:GetStepSurfaceType(args.stepIndex) or 1
    local flags = args.path:GetStepFlags(args.stepIndex)
    local inwater = table.contains(flags or {}, "Water")
    local flying = args.path.movementType == "fly"
    local burrowing = args.path.movementType == "burrow"
    local sound = (AudioSurfaceTypes.surfaces[surface] or {}).sound or "Foot.Generic_Generic"

    local puddle = (AudioSurfaceTypes.surfaces[surface] or {}).puddleSound

    if flying then
       sound = "Foot.Fly_Wing"
    elseif burrowing then
       sound = "Foot.Burrow_Generic"
    elseif inwater then
       sound = "Foot.Swim_Generic"
    elseif args.token.properties:HasNamedCondition("Prone") then
        sound = "Foot.Crawl_Generic"
    end

    if burrowing or flying or inwater or args.path.movementType == "walk" or args.path.movementType == "swim" or args.path.movementType == "shift" then
        --the size of the creature. Use the raw token radius squared to emphasize
        --large creatures being large.
        --local creatureSize = args.token.radiusInTiles*args.token.radiusInTiles

        --trying out raw token radius added to itself so the value range is smaller between largest and smallest
        local creatureSize = args.token.radiusInTiles+args.token.radiusInTiles


        --how many seconds between footsteps. Larger creatures
        --will play less frequent footsteps.
        local playFrequency = 2.0*creatureSize
        

        --make it so the first footstep plays quickly, to ensure we
        --get at least one footstep and to make sure that there is a quick
        --audible response to moving.
        if args.lastPlayed == nil then
            playFrequency = playFrequency*0.1
        end

        --the larger the creature, the louder their footsteps.
        local volumeScale = creatureSize*1.5

        if args.path.movementType == "shift" then
            --when shifting we play footsteps at a lower volume and frequency
            volumeScale = volumeScale * 0.3
            playFrequency = playFrequency * 1.2
        end

        --as creatures get larger, their footsteps become deeper.
        local pitch = math.max(0.5, 1.8 - args.token.radiusInTiles*1.6)


        
        if args.distanceMoved - (args.lastPlayed or 0) >= playFrequency then
            audio.FireSoundEvent(sound, {
                volume = volumeScale,
                pitch = pitch,
            })

            if puddle then
                audio.FireSoundEvent("Foot.Swim_Generic", {
                    volume = volumeScale*0.4,
                    pitch = pitch,
                })
            end

            args.lastPlayed = (args.lastPlayed or 0) + playFrequency
        end
    end
end


Commands.downloadaudio = function()
    audio.DevDownloadAudio()
end