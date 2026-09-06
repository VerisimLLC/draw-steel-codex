---@meta

--- Provides tutorial management for creating, tracking, and completing in-app tutorials.
--- @class tutorial
--- @field text nil|string The display text for the current tutorial step, the completion text if the tutorial is complete, or nil if no tutorial is active.
--- @field tutorialName nil|string The name of the currently active tutorial, or nil if no tutorial is active.
--- @field eventSource EventSourceLua The event source for tutorial events such as completeTutorial and refreshTutorial.
tutorial = {}

--- Sets the active tutorial from a table describing its name, entries, completion condition, and completion text.
--- @param tutorial table A table with fields: name (string), entries (list of {target: string, text: string, condition: function}), complete (function), completeText (string).
function tutorial.SetTutorial(tutorial) end

--- Clears the currently active tutorial.
function tutorial.ClearTutorial() end

--- Marks the current tutorial as complete and fires the completeTutorial event.
function tutorial.CompleteTutorial() end

--- True if the tutorial with the given name has been completed.
--- @param name? string
--- @return boolean
function tutorial.IsTutorialComplete(name) end

--- Marks the tutorial with the given name as complete and fires the completeTutorial event.
--- @param name? string
function tutorial.MarkTutorialComplete(name) end
