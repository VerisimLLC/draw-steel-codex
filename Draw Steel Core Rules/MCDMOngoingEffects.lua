local mod = dmhub.GetModLoading()


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
        id = 'end_of_any_turn',
        text = 'Until Any Creature Ends Their Turn',
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