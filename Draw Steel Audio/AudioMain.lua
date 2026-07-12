local mod = dmhub.GetModLoading()

--Register Audio Mod
audio.RegisterAudioMod(mod)

--Local (this-client-only) mute. Read per-frame by the engine (AudioController
--folds it into globalSliderVolume); driven by the player-facing mute buttons
--in the Audio dock panel and the top-bar mini mixer. Distinct from audio.muted,
--which is the GAME-WIDE mute synced to every client.
setting{
    id = "localmuted",
    default = false,
    storage = "preference",
}

--Mix Groups

--Parent bus for the app's own feedback SFX (UI clicks, dice, gameplay, damage).
audio.MixGroup{
    id = "uisounds",
    name = tr("UI Sounds"),
}

--Library category buses: the DM's uploaded sounds.
audio.MixGroup{
    id = "music",
    name = tr("Music"),
}

audio.MixGroup{
    id = "ambience",
    name = tr("Ambience"),
}

audio.MixGroup{
    id = "effects",
    name = tr("Effects"),
}

--App feedback SFX, parented under UI Sounds.
audio.MixGroup{
    id = "gameplay",
    parent = "uisounds",
    name = tr("Gameplay"),
}

audio.MixGroup{
    id = "ui",
    parent = "uisounds",
    name = tr("UI"),
}

audio.MixGroup{
    id = "dice",
    parent = "uisounds",
    name = tr("Dice"),
}

audio.MixGroup{
    id = "damage",
    parent = "uisounds",
    name = tr("Damage"),
}

--Footsteps: standalone (Settings-only slider; carved out after a user complaint).
audio.MixGroup{
    id = "footsteps",
    name = tr("Footsteps"),
}

--Anthem: its own top-level bus so the Anthem panel fader scales all anthems. NOT a duck
--target (anthems ride full over the ducked music bed), so nothing ever DuckGroups it.
audio.MixGroup{
    id = "anthem",
    name = tr("Anthem"),
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



audio.SoundEvent{
    name = "Notify.LockIn",
    mixgroup = "ui",
    sounds = {"Notify_LockIn_v1_01.wav","Notify_LockIn_v1_02.wav","Notify_LockIn_v1_03.wav","Notify_LockIn_v1_04.wav","Notify_LockIn_v1_05.wav","Notify_LockIn_v1_06.wav"},
    volume = 0.1,
    ignoreDuplicates = 0.5,
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
    mixgroup = "dice",
    sounds = {"Notify_DiceRoll_v3_01.wav","Notify_DiceRoll_v3_02.wav","Notify_DiceRoll_v3_03.wav"},
    volume = 0.25,
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



--TO DO
--UI Palette Change

audio.SoundEvent{
    name = "Notify.PalleteChange_Preview",
    mixgroup = "ui",
    sounds = {"Notify_PaletteChange_Preview_v1_01.wav"},
    volume = 0.05,
    pitchRand = 0.05,
    ignoreDuplicates = 1,
}

audio.SoundEvent{
    name = "Notify.PalleteChange_Apply",
    mixgroup = "ui",
    sounds = {"Notify_PaletteChange_Apply_v1_01.wav"},
    volume = 0.1,
    pitchRand = 0.05,
    ignoreDuplicates = 1,
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



--TODO
--Shapeshift


audio.SoundEvent{
    name = "Ability.Shapeshift_Generic_Start",
    mixgroup = "gameplay",
    sounds = {"abl/shapeshift/Abl_Shapeshift_Start_Generic_Whoosh_v1_01.wav"},
    volume = 0.2,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

audio.SoundEvent{
    name = "Ability.Shapeshift_Generic_End",
    mixgroup = "gameplay",
    sounds = {"abl/shapeshift/Abl_Shapeshift_End_Generic_Whoosh_v1_01.wav"},
    volume = 0.2,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

audio.SoundEvent{
    name = "Ability.Shapeshift_Bear_Start",
    mixgroup = "gameplay",
    play = function(sound)
    audio.FireSoundEvent("Ability.Shapeshift_Generic_Start")
    end,
    sounds = {"abl/shapeshift/Abl_Shapeshift_Start_Bear_v1_01.wav","abl/shapeshift/Abl_Shapeshift_Start_Bear_v1_02.wav","abl/shapeshift/Abl_Shapeshift_Start_Bear_v1_03.wav"},
    volume = 1.0,
    delay = 0.75,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

audio.SoundEvent{
    name = "Ability.Shapeshift_Crow_Start",
    mixgroup = "gameplay",
    play = function(sound)
    audio.FireSoundEvent("Ability.Shapeshift_Generic_Start")
    end,
    sounds = {"abl/shapeshift/Abl_Shapeshift_Start_Crow_v1_01.wav","abl/shapeshift/Abl_Shapeshift_Start_Crow_v1_02.wav","abl/shapeshift/Abl_Shapeshift_Start_Crow_v1_03.wav"},
    volume = 0.1,
    delay = 0.75,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
}

audio.SoundEvent{
    name = "Ability.Shapeshift_Rat_Start",
    mixgroup = "gameplay",
    play = function(sound)
    audio.FireSoundEvent("Ability.Shapeshift_Generic_Start")
    end,
    sounds = {"abl/shapeshift/Abl_Shapeshift_Start_Rat_v1_01.wav","abl/shapeshift/Abl_Shapeshift_Start_Rat_v1_02.wav"},
    volume = 0.1,
    delay = 0.75,
    pitchRand = 0.05,
    ignoreDuplicates = 0.1,
    
    
}

audio.SoundEvent{
    name = "Ability.Shapeshift_Wolf_Start",
    mixgroup = "gameplay",
    play = function(sound)
    audio.FireSoundEvent("Ability.Shapeshift_Generic_Start")
    end,
    sounds = {"abl/shapeshift/Abl_Shapeshift_Start_Wolf_v1_01.wav","abl/shapeshift/Abl_Shapeshift_Start_Wolf_v1_02.wav","abl/shapeshift/Abl_Shapeshift_Start_Wolf_v1_03.wav"},
    volume = 0.2,
    delay = 0.75,
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
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Gnrc_v1_01.wav","Atk_Hit/Atk_Hit_Gnrc_v1_02.wav","Atk_Hit/Atk_Hit_Gnrc_v1_03.wav","Atk_Hit/Atk_Hit_Gnrc_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_acid",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Acid_v1_01.wav","Atk_Hit/Atk_Hit_Acid_v1_02.wav","Atk_Hit/Atk_Hit_Acid_v1_03.wav","Atk_Hit/Atk_Hit_Acid_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_cold",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Cold_v1_01.wav","Atk_Hit/Atk_Hit_Cold_v1_02.wav","Atk_Hit/Atk_Hit_Cold_v1_03.wav","Atk_Hit/Atk_Hit_Cold_v1_04.wav","Atk_Hit/Atk_Hit_Cold_v1_05.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_corruption",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Corruption_v1_01.wav","Atk_Hit/Atk_Hit_Corruption_v1_02.wav","Atk_Hit/Atk_Hit_Corruption_v1_03.wav","Atk_Hit/Atk_Hit_Corruption_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_fire",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Fire_v1_01.wav","Atk_Hit/Atk_Hit_Fire_v1_02.wav","Atk_Hit/Atk_Hit_Fire_v1_03.wav","Atk_Hit/Atk_Hit_Fire_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_holy",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Holy_v2_01.wav","Atk_Hit/Atk_Hit_Holy_v2_02.wav","Atk_Hit/Atk_Hit_Holy_v2_03.wav","Atk_Hit/Atk_Hit_Holy_v2_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_lightning",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Lightning_v1_01.wav","Atk_Hit/Atk_Hit_Lightning_v1_02.wav","Atk_Hit/Atk_Hit_Lightning_v1_03.wav","Atk_Hit/Atk_Hit_Lightning_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_poison",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Poison_v1_01.wav","Atk_Hit/Atk_Hit_Poison_v1_02.wav","Atk_Hit/Atk_Hit_Poison_v1_03.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_psychic",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Psychic_v2_01.wav","Atk_Hit/Atk_Hit_Psychic_v2_02.wav","Atk_Hit/Atk_Hit_Psychic_v2_03.wav","Atk_Hit/Atk_Hit_Psychic_v2_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

audio.SoundEvent{
    name = "Attack.Hit_sonic",
    mixgroup = "damage",
    sounds = {"Atk_Hit/Atk_Hit_Sonic_v1_01.wav","Atk_Hit/Atk_Hit_Sonic_v1_02.wav","Atk_Hit/Atk_Hit_Sonic_v1_03.wav","Atk_Hit/Atk_Hit_Sonic_v1_04.wav"},
    volume = 1.0,
    ignoreDuplicates = 0.2,
    pitchRand = 0.2,
}

--Implemented
--plays when creature takes environmental damage
audio.SoundEvent{
    name = "Attack.Enviro",
    mixgroup = "damage",
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



--Generic numglow when numbers glow afer a power roll. one sound call for each die

audio.SoundEvent{
    name = "Dice.Numglow_Generic",
    mixgroup = "dice",
    sounds = {"dice/Dice_NumGlow_Generic_01.wav","dice/Dice_NumGlow_Generic_02.wav","dice/Dice_NumGlow_Generic_03.wav"},
    volume = 0.01,
    ignoreDuplicates = 0.01,
}


--Back ash version of numglow
audio.SoundEvent{
    name = "Dice.Numglow_BlackAsh",
    mixgroup = "dice",
    sounds = {"dice/cust/Dice_NumGlow_BlackAsh_01.wav","dice/cust/Dice_NumGlow_BlackAsh_02.wav","dice/cust/Dice_NumGlow_BlackAsh_03.wav","dice/cust/Dice_NumGlow_BlackAsh_04.wav","dice/cust/Dice_NumGlow_BlackAsh_05.wav"},
    volume = 0.1,
    pitchRand = 0.1,
    ignoreDuplicates = 0.01,
}

--Spectral version of numglow
audio.SoundEvent{
    name = "Dice.Numglow_Spectral",
    mixgroup = "dice",
    sounds = {"dice/spectral/Dice_NumGlow_spectral_01.wav","dice/spectral/Dice_NumGlow_spectral_02.wav","dice/spectral/Dice_NumGlow_spectral_03.wav","dice/spectral/Dice_NumGlow_spectral_04.wav","dice/spectral/Dice_NumGlow_spectral_05.wav"},
    volume = 0.1,
    pitchRand = 0.01,
    ignoreDuplicates = 0.01,
}

--when black ash dice teleport at end of roll. one sound call for each die
audio.SoundEvent{
    name = "Dice.Teleport_BlackAsh",
    mixgroup = "dice",
    sounds = {"dice/cust/Dice_Teleport_BlackAsh_01.wav","dice/cust/Dice_Teleport_BlackAsh_02.wav","dice/cust/Dice_Teleport_BlackAsh_03.wav","dice/cust/Dice_Teleport_BlackAsh_04.wav","dice/cust/Dice_Teleport_BlackAsh_05.wav"},
    volume = 0.2,
    pitchRand = 0.1,
    ignoreDuplicates = 0.01,
}

--when black ash dice disappear at end of roll. one sound call for each die
audio.SoundEvent{
    name = "Dice.Remove_BlackAsh",
    mixgroup = "dice",
    sounds = {"dice/cust/Dice_Remove_BlackAsh_01.wav","dice/cust/Dice_Remove_BlackAsh_02.wav","dice/cust/Dice_Remove_BlackAsh_03.wav","dice/cust/Dice_Remove_BlackAsh_04.wav","dice/cust/Dice_Remove_BlackAsh_05.wav"},
    volume = 0.01,
    pitchRand = 0.1,
    ignoreDuplicates = 0.01,
}


--crucible die explosion chargeup
audio.SoundEvent{
    name = "Dice.Numglow_Crucible_Charge",
    mixgroup = "dice",
    sounds = {"dice/cust/crucible/Dice_NumGlow_Crucible_Charge_01.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Charge_02.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Charge_03.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Charge_04.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Charge_05.wav"},
    volume = 0.1,
    pitchRand = 0.1,
    ignoreDuplicates = 0.01,
}

--crucible die explosion uh explosion
audio.SoundEvent{
    name = "Dice.Numglow_Crucible_Explo",
    mixgroup = "dice",
    sounds = {"dice/cust/crucible/Dice_NumGlow_Crucible_Explo_01.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Explo_02.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Explo_03.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Explo_04.wav","dice/cust/crucible/Dice_NumGlow_Crucible_Explo_05.wav"},
    volume = 0.1,
    pitchRand = 0.1,
    ignoreDuplicates = 0.01,
}


--Circle of Spring Numglow

audio.SoundEvent{
    name = "Dice.Numglow_CircleOfSpring",
    mixgroup = "dice",
    sounds = {"dice/cust/circleofSpring/Dice_NumGlow_circleofSpring_01.wav","dice/cust/circleofSpring/Dice_NumGlow_circleofSpring_02.wav","dice/cust/circleofSpring/Dice_NumGlow_circleofSpring_03.wav","dice/cust/circleofSpring/Dice_NumGlow_circleofSpring_04.wav","dice/cust/circleofSpring/Dice_NumGlow_circleofSpring_05.wav"},
    volume = 0.1,
    pitchRand = 0.1,
    ignoreDuplicates = 0.01,
}








--Dice Impacts
--
-- A dice set's impact sound is chosen by "family": a speed-tiered group of soft/mild/hard
-- impact sounds (e.g. Copper, Glass, Stone). On a die collision the engine always fires the
-- single "Dice.Impact" sound event and passes the die's chosen family (args.family) plus the
-- impact speed (args.speed) and an optional volume multiplier (args.volume). The dispatcher
-- below resolves the family to "DiceImp.{Soft,Mild,Hard}[_suffix]" by speed.
--
-- DiceImpactFamilies is the formal, enumerable registry of families. It mirrors the
-- AudioSurfaceTypes / AudioObjectDestructionTypes idiom (an ordered list of {id, text, ...}).
-- The Dice Studio "Impact" picker lists DiceImpactFamilies.families, so any family added here
-- shows up automatically. id is stored on the dice set ("" = the default/copper family); suffix
-- maps to the DiceImp.* leaf sound events defined below (the default family uses an empty suffix).

DiceImpactFamilies = {}

-- Ordered list of registered families. id is stored on the dice set ("" = the default/copper
-- family); text is the picker label; suffix maps to the DiceImp.* leaf sound events.
DiceImpactFamilies.families = {
    { id = "",           text = "Copper (Default)", suffix = ""           },
    { id = "BlackAsh",   text = "Black Ash",        suffix = "BlackAsh"   },
    { id = "Glass",      text = "Glass",            suffix = "Glass"      },
    { id = "Stone",      text = "Stone",            suffix = "Stone"      },
    { id = "MetalTiny",  text = "Metal (Small)",    suffix = "MetalTiny"  },
    { id = "MetalBlade", text = "Metal Blade",      suffix = "MetalBlade" },
    { id = "MetalSparkle",text = "Metal Sparkle",   suffix = "MetalSparkle"},
    { id = "GlassSparkle",text = "Glass Sparkle",   suffix = "GlassSparkle"},
    { id = "MetalShield", text = "Metal Shield",    suffix = "MetalShield" },
    { id = "Spectral",   text = "Spectral",         suffix = "Spectral" },
}

-- Look up a family by id. Returns the default (copper) family for a nil/unknown id so a stale
-- or missing choice still makes a sound.
function DiceImpactFamilies.Get(id)
    for _,family in ipairs(DiceImpactFamilies.families) do
        if family.id == id then
            return family
        end
    end
    return DiceImpactFamilies.families[1]
end

-- Fires the soft/mild/hard leaf sound for a family suffix, scaled by impact speed and an
-- optional volume multiplier (a dice set's bound impact volume; 1 = the authored volume).
local function FireImpactSound(suffix, speed, volumeMult)
    speed = speed or 0
    volumeMult = volumeMult or 1

    local soundEvent = "DiceImp.Soft" .. suffix
    local volume = speed
    if speed > 10 then
        soundEvent = "DiceImp.Hard" .. suffix
        volume = 0.6 + (speed - 8) * 0.1
    elseif speed > 4 then
        soundEvent = "DiceImp.Mild" .. suffix
        volume = 0.6 + (speed - 1) * 0.1
    end

    local child = audio.FireSoundEvent(soundEvent, {})
    if child ~= nil then
        child.volume = volume * volumeMult
    end
end

-- Registers an impact dispatcher. The base "Dice.Impact" (name == nil) resolves the die's chosen
-- family from args.family at fire time; a suffixed "Dice.Impact_<name>" is locked to its own
-- family (kept so a family can be fired directly, and for back-compat with dice sets that bound
-- "Dice.Impact_<Family>" before the family picker existed).
local function RegisterImpactEvent(name)
    local suffix = ""
    if name ~= nil then
        suffix = "_" .. name
    end

    audio.SoundEvent{
        mixgroup = "dice",
        name = "Dice.Impact" .. suffix,
        play = function(instance)
            local familySuffix = suffix
            if suffix == "" then
                local family = DiceImpactFamilies.Get(instance.args.family)
                if family.suffix ~= "" then
                    familySuffix = "_" .. family.suffix
                end
            end
            FireImpactSound(familySuffix, instance.args.speed, instance.args.volume)
        end,
    }
end


-- The base Dice.Impact dispatcher plus one Dice.Impact_<suffix> per non-default family.
RegisterImpactEvent()
for _,family in ipairs(DiceImpactFamilies.families) do
    if family.suffix ~= "" then
        RegisterImpactEvent(family.suffix)
    end
end

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






--Black Ash Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_BlackAsh",
    mixgroup = "dice",
    sounds = {"dice/cust/DiceImp_BlackAsh_Hard_v1_01.wav","dice/cust/DiceImp_BlackAsh_Hard_v1_02.wav","dice/cust/DiceImp_BlackAsh_Hard_v1_03.wav","dice/cust/DiceImp_BlackAsh_Hard_v1_04.wav","dice/cust/DiceImp_BlackAsh_Hard_v1_05.wav","dice/cust/DiceImp_BlackAsh_Hard_v1_06.wav"},
    volume = 0.05,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_BlackAsh",
    mixgroup = "dice",
    sounds = {"dice/cust/DiceImp_BlackAsh_Mild_v1_01.wav","dice/cust/DiceImp_BlackAsh_Mild_v1_02.wav","dice/cust/DiceImp_BlackAsh_Mild_v1_03.wav","dice/cust/DiceImp_BlackAsh_Mild_v1_04.wav","dice/cust/DiceImp_BlackAsh_Mild_v1_05.wav","dice/cust/DiceImp_BlackAsh_Mild_v1_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_BlackAsh",
    mixgroup = "dice",
    sounds = {"dice/cust/DiceImp_BlackAsh_Soft_v1_01.wav","dice/cust/DiceImp_BlackAsh_Soft_v1_02.wav","dice/cust/DiceImp_BlackAsh_Soft_v1_03.wav","dice/cust/DiceImp_BlackAsh_Soft_v1_04.wav","dice/cust/DiceImp_BlackAsh_Soft_v1_05.wav","dice/cust/DiceImp_BlackAsh_Soft_v1_06.wav"},
    volume = 0.05,
    pitchRand = 0.1,
}





--Glass Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_Glass",
    mixgroup = "dice",
    sounds = {"dice/glass/DiceImp_Glass_Hard_01.wav","dice/glass/DiceImp_Glass_Hard_02.wav","dice/glass/DiceImp_Glass_Hard_03.wav","dice/glass/DiceImp_Glass_Hard_04.wav","dice/glass/DiceImp_Glass_Hard_05.wav","dice/glass/DiceImp_Glass_Hard_06.wav"},
    volume = 0.1,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_Glass",
    mixgroup = "dice",
    sounds = {"dice/glass/DiceImp_Glass_Mild_01.wav","dice/glass/DiceImp_Glass_Mild_02.wav","dice/glass/DiceImp_Glass_Mild_03.wav","dice/glass/DiceImp_Glass_Mild_04.wav","dice/glass/DiceImp_Glass_Mild_05.wav","dice/glass/DiceImp_Glass_Mild_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_Glass",
    mixgroup = "dice",
    sounds = {"dice/glass/DiceImp_Glass_Soft_01.wav","dice/glass/DiceImp_Glass_Soft_02.wav","dice/glass/DiceImp_Glass_Soft_03.wav","dice/glass/DiceImp_Glass_Soft_04.wav","dice/glass/DiceImp_Glass_Soft_05.wav","dice/glass/DiceImp_Glass_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}

--glassSparkle Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_GlassSparkle",
    mixgroup = "dice",
    sounds = {"dice/glasssparkle/DiceImp_glasssparkle_Hard_01.wav","dice/glasssparkle/DiceImp_glasssparkle_Hard_02.wav","dice/glasssparkle/DiceImp_glasssparkle_Hard_03.wav","dice/glasssparkle/DiceImp_glasssparkle_Hard_04.wav","dice/glasssparkle/DiceImp_glasssparkle_Hard_05.wav","dice/glasssparkle/DiceImp_glasssparkle_Hard_06.wav"},
    volume = 0.05,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_GlassSparkle",
    mixgroup = "dice",
    sounds = {"dice/glasssparkle/DiceImp_glasssparkle_Mild_01.wav","dice/glasssparkle/DiceImp_glasssparkle_Mild_02.wav","dice/glasssparkle/DiceImp_glasssparkle_Mild_03.wav","dice/glasssparkle/DiceImp_glasssparkle_Mild_04.wav","dice/glasssparkle/DiceImp_glasssparkle_Mild_05.wav","dice/glasssparkle/DiceImp_glasssparkle_Mild_06.wav"},
    volume = 0.07,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_GlassSparkle",
    mixgroup = "dice",
    sounds = {"dice/glasssparkle/DiceImp_glasssparkle_Soft_01.wav","dice/glasssparkle/DiceImp_glasssparkle_Soft_02.wav","dice/glasssparkle/DiceImp_glasssparkle_Soft_03.wav","dice/glasssparkle/DiceImp_glasssparkle_Soft_04.wav","dice/glasssparkle/DiceImp_glasssparkle_Soft_05.wav","dice/glasssparkle/DiceImp_glasssparkle_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}


--spectral Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_Spectral",
    mixgroup = "dice",
    sounds = {"dice/spectral/DiceImp_spectral_Hard_01.wav","dice/spectral/DiceImp_spectral_Hard_02.wav","dice/spectral/DiceImp_spectral_Hard_03.wav","dice/spectral/DiceImp_spectral_Hard_04.wav","dice/spectral/DiceImp_spectral_Hard_05.wav","dice/spectral/DiceImp_spectral_Hard_06.wav"},
    volume = 0.02,
    pitchRand = 0.1,
}

audio.SoundEvent{
    name = "DiceImp.Mild_Spectral",
    mixgroup = "dice",
    sounds = {"dice/spectral/DiceImp_spectral_Mild_01.wav","dice/spectral/DiceImp_spectral_Mild_02.wav","dice/spectral/DiceImp_spectral_Mild_03.wav","dice/spectral/DiceImp_spectral_Mild_04.wav","dice/spectral/DiceImp_spectral_Mild_05.wav","dice/spectral/DiceImp_spectral_Mild_06.wav"},
    volume = 0.02,
    pitchRand = 0.1,
}

audio.SoundEvent{
    name = "DiceImp.Soft_Spectral",
    mixgroup = "dice",
    sounds = {"dice/spectral/DiceImp_spectral_Soft_01.wav","dice/spectral/DiceImp_spectral_Soft_02.wav","dice/spectral/DiceImp_spectral_Soft_03.wav","dice/spectral/DiceImp_spectral_Soft_04.wav","dice/spectral/DiceImp_spectral_Soft_05.wav","dice/spectral/DiceImp_spectral_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}



--Stone Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_Stone",
    mixgroup = "dice",
    sounds = {"dice/Stone/DiceImp_Stone_Hard_01.wav","dice/Stone/DiceImp_Stone_Hard_02.wav","dice/Stone/DiceImp_Stone_Hard_03.wav","dice/Stone/DiceImp_Stone_Hard_04.wav","dice/Stone/DiceImp_Stone_Hard_05.wav","dice/Stone/DiceImp_Stone_Hard_06.wav"},
    volume = 0.1,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_Stone",
    mixgroup = "dice",
    sounds = {"dice/Stone/DiceImp_Stone_Mild_01.wav","dice/Stone/DiceImp_Stone_Mild_02.wav","dice/Stone/DiceImp_Stone_Mild_03.wav","dice/Stone/DiceImp_Stone_Mild_04.wav","dice/Stone/DiceImp_Stone_Mild_05.wav","dice/Stone/DiceImp_Stone_Mild_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_Stone",
    mixgroup = "dice",
    sounds = {"dice/Stone/DiceImp_Stone_Soft_01.wav","dice/Stone/DiceImp_Stone_Soft_02.wav","dice/Stone/DiceImp_Stone_Soft_03.wav","dice/Stone/DiceImp_Stone_Soft_04.wav","dice/Stone/DiceImp_Stone_Soft_05.wav","dice/Stone/DiceImp_Stone_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}

--MetalTiny Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_MetalTiny",
    mixgroup = "dice",
    sounds = {"dice/MetalTiny/DiceImp_MetalTiny_Hard_01.wav","dice/MetalTiny/DiceImp_MetalTiny_Hard_02.wav","dice/MetalTiny/DiceImp_MetalTiny_Hard_03.wav","dice/MetalTiny/DiceImp_MetalTiny_Hard_04.wav","dice/MetalTiny/DiceImp_MetalTiny_Hard_05.wav","dice/MetalTiny/DiceImp_MetalTiny_Hard_06.wav"},
    volume = 0.1,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_MetalTiny",
    mixgroup = "dice",
    sounds = {"dice/MetalTiny/DiceImp_MetalTiny_Mild_01.wav","dice/MetalTiny/DiceImp_MetalTiny_Mild_02.wav","dice/MetalTiny/DiceImp_MetalTiny_Mild_03.wav","dice/MetalTiny/DiceImp_MetalTiny_Mild_04.wav","dice/MetalTiny/DiceImp_MetalTiny_Mild_05.wav","dice/MetalTiny/DiceImp_MetalTiny_Mild_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_MetalTiny",
    mixgroup = "dice",
    sounds = {"dice/MetalTiny/DiceImp_MetalTiny_Soft_01.wav","dice/MetalTiny/DiceImp_MetalTiny_Soft_02.wav","dice/MetalTiny/DiceImp_MetalTiny_Soft_03.wav","dice/MetalTiny/DiceImp_MetalTiny_Soft_04.wav","dice/MetalTiny/DiceImp_MetalTiny_Soft_05.wav","dice/MetalTiny/DiceImp_MetalTiny_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}


--metalblade Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_MetalBlade",
    mixgroup = "dice",
    sounds = {"dice/metalblade/DiceImp_metalblade_Hard_01.wav","dice/metalblade/DiceImp_metalblade_Hard_02.wav","dice/metalblade/DiceImp_metalblade_Hard_03.wav","dice/metalblade/DiceImp_metalblade_Hard_04.wav","dice/metalblade/DiceImp_metalblade_Hard_05.wav","dice/metalblade/DiceImp_metalblade_Hard_06.wav"},
    volume = 0.1,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_MetalBlade",
    mixgroup = "dice",
    sounds = {"dice/metalblade/DiceImp_metalblade_Mild_01.wav","dice/metalblade/DiceImp_metalblade_Mild_02.wav","dice/metalblade/DiceImp_metalblade_Mild_03.wav","dice/metalblade/DiceImp_metalblade_Mild_04.wav","dice/metalblade/DiceImp_metalblade_Mild_05.wav","dice/metalblade/DiceImp_metalblade_Mild_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_MetalBlade",
    mixgroup = "dice",
    sounds = {"dice/metalblade/DiceImp_metalblade_Soft_01.wav","dice/metalblade/DiceImp_metalblade_Soft_02.wav","dice/metalblade/DiceImp_metalblade_Soft_03.wav","dice/metalblade/DiceImp_metalblade_Soft_04.wav","dice/metalblade/DiceImp_metalblade_Soft_05.wav","dice/metalblade/DiceImp_metalblade_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}


--metalshield Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_MetalShield",
    mixgroup = "dice",
    sounds = {"dice/metalshield/DiceImp_metalshield_Hard_01.wav","dice/metalshield/DiceImp_metalshield_Hard_02.wav","dice/metalshield/DiceImp_metalshield_Hard_03.wav","dice/metalshield/DiceImp_metalshield_Hard_04.wav","dice/metalshield/DiceImp_metalshield_Hard_05.wav","dice/metalshield/DiceImp_metalshield_Hard_06.wav"},
    volume = 0.1,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_MetalShield",
    mixgroup = "dice",
    sounds = {"dice/metalshield/DiceImp_metalshield_Mild_01.wav","dice/metalshield/DiceImp_metalshield_Mild_02.wav","dice/metalshield/DiceImp_metalshield_Mild_03.wav","dice/metalshield/DiceImp_metalshield_Mild_04.wav","dice/metalshield/DiceImp_metalshield_Mild_05.wav","dice/metalshield/DiceImp_metalshield_Mild_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_MetalShield",
    mixgroup = "dice",
    sounds = {"dice/metalshield/DiceImp_metalshield_Soft_01.wav","dice/metalshield/DiceImp_metalshield_Soft_02.wav","dice/metalshield/DiceImp_metalshield_Soft_03.wav","dice/metalshield/DiceImp_metalshield_Soft_04.wav","dice/metalshield/DiceImp_metalshield_Soft_05.wav","dice/metalshield/DiceImp_metalshield_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
}




--MetalSparkle Dice Impacts

audio.SoundEvent{
    name = "DiceImp.Hard_MetalSparkle",
    mixgroup = "dice",
    sounds = {"dice/metalsparkle/DiceImp_metalsparkle_Hard_01.wav","dice/metalsparkle/DiceImp_metalsparkle_Hard_02.wav","dice/metalsparkle/DiceImp_metalsparkle_Hard_03.wav","dice/metalsparkle/DiceImp_metalsparkle_Hard_04.wav","dice/metalsparkle/DiceImp_metalsparkle_Hard_05.wav","dice/metalsparkle/DiceImp_metalsparkle_Hard_06.wav"},
    volume = 0.1,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Mild_MetalSparkle",
    mixgroup = "dice",
    sounds = {"dice/metalsparkle/DiceImp_metalsparkle_Mild_01.wav","dice/metalsparkle/DiceImp_metalsparkle_Mild_02.wav","dice/metalsparkle/DiceImp_metalsparkle_Mild_03.wav","dice/metalsparkle/DiceImp_metalsparkle_Mild_04.wav","dice/metalsparkle/DiceImp_metalsparkle_Mild_05.wav","dice/metalsparkle/DiceImp_metalsparkle_Mild_06.wav"},
    volume = 0.15,
    pitchRand = 0.0,
}

audio.SoundEvent{
    name = "DiceImp.Soft_MetalSparkle",
    mixgroup = "dice",
    sounds = {"dice/metalsparkle/DiceImp_metalsparkle_Soft_01.wav","dice/metalsparkle/DiceImp_metalsparkle_Soft_02.wav","dice/metalsparkle/DiceImp_metalsparkle_Soft_03.wav","dice/metalsparkle/DiceImp_metalsparkle_Soft_04.wav","dice/metalsparkle/DiceImp_metalsparkle_Soft_05.wav","dice/metalsparkle/DiceImp_metalsparkle_Soft_06.wav"},
    volume = 0.05,
    pitchRand = 0.01,
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






--Tokens

--To implement: cat purr when petting large cats

audio.SoundEvent{
    name = "Token_Catpurr_Large",
    mixgroup = "gameplay",
    sounds = {"Token/Token_CatPurr_Large_01.wav","Token/Token_CatPurr_Large_02.wav","Token/Token_CatPurr_Large_03.wav","Token/Token_CatPurr_Large_04.wav"},
    volume = 0.3,
    pitchRand = 0.3,
    ignoreDuplicates = 1,
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

audio.SoundEvent{
    name = "Foot.Generic_Snow",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Walk_Gnrc_Snow_v1_01.wav","foot/FS_Walk_Gnrc_Snow_v1_02.wav","foot/FS_Walk_Gnrc_Snow_v1_03.wav","foot/FS_Walk_Gnrc_Snow_v1_04.wav","foot/FS_Walk_Gnrc_Snow_v1_05.wav","foot/FS_Walk_Gnrc_Snow_v1_06.wav"},
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
    name = "Foot.Float_Generic",
    mixgroup = "footsteps",
    sounds = {"foot/FS_Float_Gnrc_v1_01.wav","foot/FS_Float_Gnrc_v1_02.wav","foot/FS_Float_Gnrc_v1_03.wav","foot/FS_Float_Gnrc_v1_04.wav","foot/FS_Float_Gnrc_v1_05.wav","foot/FS_Float_Gnrc_v1_06.wav"},
    volume = 0.08,
    pitchRand = 0.0,
    ignoreDuplicates = 0.5,
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


Commands.RegisterMacro{
    name = "downloadaudio",
    summary = "download audio assets",
    doc = "Usage: /downloadaudio/nDownloads audio assets for development.",
    command = function()
        audio.DevDownloadAudio()
    end,
}