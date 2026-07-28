# ClaudeBridge Module

This is a standalone DMHub module that provides Claude AI integration. It is **separate** from the draw-steel-codex project and has its own module registration.

## Important

- Do NOT add `require` entries for ClaudeBridge files in `draw-steel-codex/main.lua`. ClaudeBridge has its own module loader and main.lua.
- Do NOT modify files outside of the `ClaudeBridge/` directory when working on this module.
- Changes to this module should be self-contained within this directory.

## Structure

| File | Purpose |
|---|---|
| `Claude.lua` | Core API bridge (`claude.Chat`), agent/tool registries, settings, and the chat panel UI. |
| `ClaudeTools.lua` | Registers tools (e.g. `search_reference`) that Claude can call during conversation. |
| `ClaudeReference.lua` | Initializes the `ClaudeRef = {}` namespace for reference data. |
| `ClaudeRefHeroes.lua` | Full text of Draw Steel: Heroes book stored in `ClaudeRef.heroes`. |
| `ClaudeRefMonsters.lua` | Full text of Draw Steel: Monsters book stored in `ClaudeRef.monsters`. |
| `ClaudePrompt.lua` | Registers the default "DMHub Assistant" agent with its system prompt. |

## Settings

All settings use `preference` storage (local per-user):

| ID | Description |
|---|---|
| `claude_api_key` | Anthropic API key |
| `claude_model` | Model ID (default: `claude-sonnet-4-20250514`) |
| `claude_agent` | Currently selected agent ID |
| `claude_history` | Chat history (capped at 40 messages) |

## Agent Registry

Other modules can register agents via:
```lua
claude.RegisterAgent{
    id = "myagent",
    name = "My Agent",
    description = "What this agent does.",
    system = "System prompt text...",
    temperature = 1,      -- optional, default 1
    max_tokens = 4096,    -- optional, default 4096
}
```

Agents appear in the dropdown in the Claude chat panel.

## Tool Registry

Tools give Claude the ability to look up information during a conversation. When Claude needs data, it responds with a tool call; the Lua code executes it locally, feeds the result back, and Claude continues.

Register tools via:
```lua
claude.RegisterTool{
    name = "my_tool",
    description = "What this tool does.",
    input_schema = {
        type = "object",
        properties = {
            query = { type = "string", description = "..." },
        },
        required = { "query" },
    },
    execute = function(input)
        -- input is a table matching the schema
        -- return a string with the result
        return "result text"
    end,
}
```

The tool-use loop in `claude.Chat` automatically handles multiple rounds of tool calls (up to 10) before returning the final text response.

## Load Order

Files must be loaded in this order (ClaudeReference before RefHeroes/RefMonsters, Claude before Tools/Prompt):
1. `ClaudeReference.lua` -- creates `ClaudeRef = {}`
2. `Claude.lua` -- creates `claude` global with Chat, RegisterAgent, RegisterTool
3. `ClaudeRefHeroes.lua` -- populates `ClaudeRef.heroes`
4. `ClaudeRefMonsters.lua` -- populates `ClaudeRef.monsters`
5. `ClaudeTools.lua` -- registers tools (needs both `claude` and `ClaudeRef`)
6. `ClaudePrompt.lua` -- registers agents (needs `claude`)
