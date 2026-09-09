local mod = dmhub.GetModLoading()

RegisterGameType("CharacterSheet")

if rawget(CharacterSheet, "instance") and CharacterSheet.instance.valid then
	CharacterSheet.instance:DestroySelf()
end

CharacterSheet.instance = false

--entry point from engine to create character sheet.
function CreateCharacterSheet(info)

	local sheet
	sheet = CharSheet.CreateCharacterSheet{
		close = function(element)
			if element.data.poppedOut then
				--popped out into its own OS window: closing destroys the
				--sheet (the engine's dead-sheet sweep then closes the
				--window). The next sheet open rebuilds it in-app.
				element:DestroySelf()
			else
				sheet:SetClass("collapsed", true)
			end
		end,
		destroy = function(element)
			if element == CharacterSheet.instance then
				CharacterSheet.instance = false
			end
		end,
	}

	CharacterSheet.instance = sheet

	gamehud.mainDialogPanel:AddChild(sheet)
	return sheet
end

dmhub.RefreshCharacterSheet()