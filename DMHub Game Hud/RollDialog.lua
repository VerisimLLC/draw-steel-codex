local mod = dmhub.GetModLoading()

--This file implements the main roll prompt dialog that appears when you get a dice roll prompt.

setting{
	id = "privaterolls",
	description = "Default Roll Visibility",
	storage = "preference",
	default = "visible",
	editor = "dropdown",
	section = "Game",

	enum = {
		{
			value = "visible",
			text = "Visible to Everyone",
		},
		{
			value = "dm",
			text = cond(dmhub.isDM, "Visible to Director only", "Visible to you and Director"),
		}
	}
}

setting{
	id = "privaterolls:save",
	description = "Save roll visibility preferences",
	storage = "preference",
	default = true,
	editor = "check",
}

local g_rollOptionsDM = {
	{
		id = "visible",
		text = "Visible to Everyone",
	},
	{
		id = "dm",
		text = "Visible to Director only",
	},
}

local g_rollOptionsPlayer = {
	{
		id = "visible",
		text = "Visible to Everyone",
	},
	{
		id = "dm",
		text = "Visible to you and Director",
	},
}

