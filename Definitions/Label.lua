---@meta

--- @class Label:Panel, LabelArgs
--- @field numeric boolean (default=false) If set to true, this label is configured to accept only numeric input.
--- @field editable boolean (default=false) If set to true, this label can be edited by clicking on it.
--- @field placeholderText any
--- @field editableOnRightClick boolean (default=false) If set to true, this label can be edited by right-clicking on it.
--- @field editableOnDoubleClick boolean (default=false) If set to true, this label can be edited by double-clicking on it.
--- @field editing boolean (read-only) True if the user is currently editing this label.
--- @field text string The text displayed in this label.
--- @field markdown boolean (default=false) If true, this label is formatted using markdown.
--- @field markdownStyle LuaMarkdownStyle The style used for markdown
--- @field characterLimit number The maximum number of characters this label can contain.
--- @field maxVisibleLines number The maximum number of lines this label can display.
--- @field maxVisibleCharacters number The maximum number of lines this label can display. Excess characters will still be stored, but won't be displayed. @see characterLimit to limit the length that text can be.
--- @field links boolean If true, links can be displayed within this panel.
--- @field linkHovered nil|string The id of the currently hovered link.
Label = {}

--- Focus this label and begin editing it.
function Label:BeginEditing() end

--- RefreshText
--- (Undocumented: engine-internal, not part of the modding API.)
function Label:RefreshText() end

--- Returns the logical line of the rendered text nearest the mouse. Lines are split at line breaks only, not word wrap, so a wrapped paragraph is one line. line is 1-based. lineCount is the number of line breaks in the rendered text plus one, so a trailing break counts an empty last line. top and bottom bound every row the line wraps onto, measured down from this label's top edge in panel units (the same units as renderedHeight). It counts what was actually laid out, after markdown and rich-text processing, so compare lineCount against the text you set before mapping lines back to it. Returns nil when nothing is laid out.
--- @return {line: integer, lineCount: integer, top: number, bottom: number}|nil
function Label:GetLineAtMouse() end

--- CalculatePreferredSize
--- Vector2
--- @return any
function Label:CalculatePreferredSize() end

--- @class LabelArgs:PanelArgs
--- @field numeric? boolean (default=false) If set to true, this label is configured to accept only numeric input.
--- @field editable? boolean (default=false) If set to true, this label can be edited by clicking on it.
--- @field placeholderText? any
--- @field editableOnRightClick? boolean (default=false) If set to true, this label can be edited by right-clicking on it.
--- @field editableOnDoubleClick? boolean (default=false) If set to true, this label can be edited by double-clicking on it.
--- @field text? string The text displayed in this label.
--- @field markdown? boolean (default=false) If true, this label is formatted using markdown.
--- @field markdownStyle? LuaMarkdownStyle The style used for markdown
--- @field characterLimit? number The maximum number of characters this label can contain.
--- @field maxVisibleLines? number The maximum number of lines this label can display.
--- @field maxVisibleCharacters? number The maximum number of lines this label can display. Excess characters will still be stored, but won't be displayed. @see characterLimit to limit the length that text can be.
--- @field links? boolean If true, links can be displayed within this panel.
--- @field linkHovered? nil|string The id of the currently hovered link.
LabelArgs = {}
