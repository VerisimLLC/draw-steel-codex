--- @class TextEditor:Panel 
--- @field text string The text held in this editor.
--- @field textNoNotify string An alias of @see text, but if set, no events will fire on the panel. Setting this also resets the undo history so the assigned text becomes the baseline.
--- @field editlag number When the text is edited, the lag before calling the 'edit' event. All keypresses during this time are coalesced into one event.
--- @field placeholderText string The grayed text to display when the editor is empty.
--- @field editable boolean (default=true) If the editor is editable by the user.
--- @field multiline boolean (default=true) Multiline editor. Kept for parity with gui.Input; a text editor is always multiline.
--- @field verticalScrollbar boolean (default=false) If true, a vertical scrollbar is shown when content overflows. The handle color can be styled with the scrollHandleColor style property.
--- @field characterLimit number The maximum number of characters this editor can contain.
--- @field hasInputFocus boolean True if this editor has the input focus.
--- @field selectAllOnFocus boolean If set to true, the text will be selected when the user clicks on the editor.
--- @field caretPosition number The position of the cursor within the editor.
--- @field selectionAnchorPosition number The opposite bounds of the selection from @see caretPosition. If equal to caretPosition there is no selection.
--- @field blockChangesWhenEditing boolean If set to true, setting @see text in code will fail if the user is editing the text.
--- @field resetOnDeActivation boolean (default=true) When false, the current selection stays highlighted after the editor loses focus (e.g. to a find bar's search field). Set false while a find UI is open so the match stays visible, then restore to true.
--- @field placeholderAlpha number The alpha value of placeholder text. (default=0.6)
--- @field canUndo boolean True if there is an edit that can be undone.
--- @field canRedo boolean True if there is an edit that can be redone.
--- @field caretWorldPosition {x: number, y: number, lineHeight: number}|nil Returns the world-space position of the caret and the line height at that position, or nil if not available. Use to position popups near the caret.
TextEditor = {}

--- SetTextAndCaret: Sets the text and moves the caret to the given position reliably, even when the editor needs to be re-focused. Fires a 'caretReady' event when the caret is in position.
--- @param caretPos number
--- @param newText string
--- @return nil
function TextEditor:SetTextAndCaret(caretPos, newText)
	-- dummy implementation for documentation purposes only
end

--- GetCharWorldPosition: Returns the world-space position of the character at the given 1-based index and its line height. Returns nil if the text info is not yet available. Use this to position popups near a specific character.
--- @param charIndex number
--- @return any
function TextEditor:GetCharWorldPosition(charIndex)
	-- dummy implementation for documentation purposes only
end

--- Undo: Undo the last edit.
--- @return nil
function TextEditor:Undo()
	-- dummy implementation for documentation purposes only
end

--- Redo: Redo the last undone edit.
--- @return nil
function TextEditor:Redo()
	-- dummy implementation for documentation purposes only
end

--- Find: Begin a search for the given query. Selects and scrolls to the first match. Returns the number of matches found.
--- @param query string
--- @param caseSensitive boolean
--- @return number
function TextEditor:Find(query, caseSensitive)
	-- dummy implementation for documentation purposes only
end

--- FindNext: Move the selection to the next match of the current query. Returns true if a match was selected.
--- @return boolean
function TextEditor:FindNext()
	-- dummy implementation for documentation purposes only
end

--- FindPrev: Move the selection to the previous match of the current query. Returns true if a match was selected.
--- @return boolean
function TextEditor:FindPrev()
	-- dummy implementation for documentation purposes only
end

--- FindCount: The number of matches for the current query.
--- @return number
function TextEditor:FindCount()
	-- dummy implementation for documentation purposes only
end

--- FindCurrent: The index (1-based) of the currently selected match, or 0 if none.
--- @return number
function TextEditor:FindCurrent()
	-- dummy implementation for documentation purposes only
end

--- ReplaceCurrent: Replace the currently selected match with the given replacement and advance to the next match. Returns true if a replacement was made.
--- @param replacement string
--- @return boolean
function TextEditor:ReplaceCurrent(replacement)
	-- dummy implementation for documentation purposes only
end

--- ReplaceAll: Replace every match of query with replacement. Returns the number of replacements made.
--- @param query string
--- @param replacement string
--- @param caseSensitive boolean
--- @return number
function TextEditor:ReplaceAll(query, replacement, caseSensitive)
	-- dummy implementation for documentation purposes only
end

--- ClearFind: Clear the current find state and any match selection.
--- @return nil
function TextEditor:ClearFind()
	-- dummy implementation for documentation purposes only
end

--- SetColorSpans: Apply per-character color highlighting to the text. Pass a list of span tables, each { from = number, to = number, color = color }, where from/to are 1-based character positions (inclusive) and color is any color value (e.g. '#e06c75' or core.Color). Spans should not overlap. The colors are preserved across editing, scrolling and find. Pass an empty list (or call ClearColorSpans) to remove all coloring. This does NOT change the text itself -- only how it is rendered, so the source markdown and caret positions are unaffected.
--- @param spans any
--- @return nil
function TextEditor:SetColorSpans(spans)
	-- dummy implementation for documentation purposes only
end

--- ClearColorSpans: Remove all per-character color highlighting applied by @see SetColorSpans and restore the editor's base text color.
--- @return nil
function TextEditor:ClearColorSpans()
	-- dummy implementation for documentation purposes only
end

--- @class TextEditorArgs:PanelArgs 
--- @field text nil|string The text held in this editor.
--- @field textNoNotify nil|string An alias of @see text, but if set, no events will fire on the panel. Setting this also resets the undo history so the assigned text becomes the baseline.
--- @field editlag nil|number When the text is edited, the lag before calling the 'edit' event. All keypresses during this time are coalesced into one event.
--- @field placeholderText nil|string The grayed text to display when the editor is empty.
--- @field editable nil|boolean (default=true) If the editor is editable by the user.
--- @field multiline nil|boolean (default=true) Multiline editor. Kept for parity with gui.Input; a text editor is always multiline.
--- @field verticalScrollbar nil|boolean (default=false) If true, a vertical scrollbar is shown when content overflows. The handle color can be styled with the scrollHandleColor style property.
--- @field characterLimit nil|number The maximum number of characters this editor can contain.
--- @field hasInputFocus nil|boolean True if this editor has the input focus.
--- @field selectAllOnFocus nil|boolean If set to true, the text will be selected when the user clicks on the editor.
--- @field caretPosition nil|number The position of the cursor within the editor.
--- @field selectionAnchorPosition nil|number The opposite bounds of the selection from @see caretPosition. If equal to caretPosition there is no selection.
--- @field blockChangesWhenEditing nil|boolean If set to true, setting @see text in code will fail if the user is editing the text.
--- @field resetOnDeActivation nil|boolean (default=true) When false, the current selection stays highlighted after the editor loses focus (e.g. to a find bar's search field). Set false while a find UI is open so the match stays visible, then restore to true.
--- @field placeholderAlpha nil|number The alpha value of placeholder text. (default=0.6)
--- @field canUndo nil|boolean True if there is an edit that can be undone.
--- @field canRedo nil|boolean True if there is an edit that can be redone.
--- @field caretWorldPosition {x: number, y: number, lineHeight: number}|nil Returns the world-space position of the caret and the line height at that position, or nil if not available. Use to position popups near the caret.
TextEditorArgs = {}
