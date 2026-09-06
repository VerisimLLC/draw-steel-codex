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
--- @deprecated
function Label:RefreshText() end

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
