--- @class regex Provides regex pattern matching and replacement utilities. All patterns are case-insensitive.
regex = {}

--- MatchGroups: Matches a string against a regex pattern and returns named capture groups. Group '0' is returned as key 'all'. If options.indexes is true, each group value is a table with value, index, and length fields instead of a plain string.
--- @param str string The string to match against.
--- @param pattern string The regex pattern with named capture groups.
--- @param options nil|{indexes: nil|boolean} If indexes is true, each group is returned as a table with value, index, and length fields.
--- @return nil|table<string, string|{value: string, index: integer, length: integer}> Capture groups keyed by group name, or nil if no match.
function regex.MatchGroups()
	-- dummy implementation for documentation purposes only
end

--- Match: Matches a string against a regex pattern and returns the capture groups as multiple return values.
--- @param str string The string to match against.
--- @param pattern string The regex pattern.
--- @return nil|string ... The full match followed by each capture group, or nil if no match.
function regex.Match(str, pattern)
	-- dummy implementation for documentation purposes only
end

--- MatchAll: Finds all matches of a pattern in a string and returns a table of match group tables.
--- @param str string The string to match against.
--- @param pattern string The regex pattern.
--- @return string[][] A table of matches, where each match is a table of capture group strings.
function regex.MatchAll(str, pattern)
	-- dummy implementation for documentation purposes only
end

--- ReplaceOne: Replaces the first occurrence of a regex pattern in the input string with the replacement string.
--- @param input string
--- @param pattern string
--- @param replacement string
--- @return string
function regex.ReplaceOne(input, pattern, replacement)
	-- dummy implementation for documentation purposes only
end

--- ReplaceAll: Replaces all occurrences of a regex pattern in the input string with the replacement string.
--- @param input string
--- @param pattern string
--- @param replacement string
--- @return string
function regex.ReplaceAll(input, pattern, replacement)
	-- dummy implementation for documentation purposes only
end

--- Split: Splits a string by a regex pattern and returns a table of substrings.
--- @param input string The string to split.
--- @param pattern string The regex pattern to split on.
--- @return string[]
function regex.Split(input, pattern)
	-- dummy implementation for documentation purposes only
end
