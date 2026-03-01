--- @class tutorial Provides tutorial management for creating, tracking, and completing in-app tutorials.
--- @field text nil|string The display text for the current tutorial step, the completion text if the tutorial is complete, or nil if no tutorial is active.
--- @field tutorialName nil|string The name of the currently active tutorial, or nil if no tutorial is active.
--- @field eventSource EventSourceLua The event source for tutorial events such as completeTutorial and refreshTutorial.
tutorial = {}

--- SetTutorial: Sets the active tutorial from a table describing its name, entries, completion condition, and completion text.
--- @param tutorial table A table with fields: name (string), entries (list of {target: string, text: string, condition: function}), complete (function), completeText (string).
function tutorial.SetTutorial(tutorial)
	-- dummy implementation for documentation purposes only
end

--- ClearTutorial: Clears the currently active tutorial.
--- @return nil
function tutorial.ClearTutorial()
	-- dummy implementation for documentation purposes only
end

--- CompleteTutorial: Marks the current tutorial as complete and fires the completeTutorial event.
--- @return nil
function tutorial.CompleteTutorial()
	-- dummy implementation for documentation purposes only
end

--- IsTutorialComplete: True if the tutorial with the given name has been completed.
--- @param name string
--- @return boolean
function tutorial.IsTutorialComplete(name)
	-- dummy implementation for documentation purposes only
end

--- MarkTutorialComplete: Marks the tutorial with the given name as complete and fires the completeTutorial event.
--- @param name string
--- @return nil
function tutorial.MarkTutorialComplete(name)
	-- dummy implementation for documentation purposes only
end
