local mod = dmhub.GetModLoading()

--How each duration reads in a Block Editor sentence ("Apply Slowed to the target until the end of the turn").
Block.DurationWords = {
    turn = "until the end of the turn",
    endround = "until the end of the round",
    endnextround = "until the end of the next round",
    end_of_next_turn = "until the end of their next turn",
    save_ends = "(save ends)",
    rounds = "for some rounds",
    rounds_end_turn = "for some rounds, from the end of the turn",
    until_rest = "until they take a respite",
    eoe = "until the end of the encounter",
    eoe_or_dying = "until the end of the encounter or they are dying",
    indefinite = "indefinitely",
}

CharacterOngoingEffect.durationOptions = {
	{
		id = 'turn',
		text = 'Until End of Turn',
	},
    {
        id = 'endround',
        text = 'Until End of Round',
    },
    {
        id = 'endnextround',
        text = 'Until End of Next Round',
    },
    {
        id = 'end_of_next_turn',
        text = "Until End of Target's Next Turn",
    },
	{
		id = "save_ends",
		text = "Save Ends",
	},
	{
		id = 'rounds',
		text = 'Rounds (From Start of Turn)',
	},
	{
		id = 'rounds_end_turn',
		text = 'Rounds (From End of Turn)',
	},
	{
		id = 'until_rest',
		text = 'Until Respite',
	},
	{
		id = 'eoe',
		text = 'End of Encounter',
	},
	{
		id = 'eoe_or_dying',
		text = 'End of Encounter or Dying',
	},
	{
		id = 'indefinite',
		text = 'Indefinitely',
	},
}