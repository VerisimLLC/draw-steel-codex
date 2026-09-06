---@meta

--- @class ChatMessageDiceRollInfoLua:ChatMessageInfoLua
--- @field messageType string
--- @field formattedText string Nicely formatted text describing the roll.
--- @field waitingOnDice boolean True if we don't have dice information yet about this roll.
--- @field timeRemaining number The projected time remaining for the dice to finish rolling. If @see waitingOnDice returns true we don't have this value yet and it will return -1.
--- @field isComplete boolean Indicates that the roll is finished.
--- @field resultInfo table<string,{mod: number, total: number, rolls: {guid: string, partnerguid: string, roll: number, faces: number, multiply: nil|number, subtract: boolean}}>
--- @field diceStyle any
--- @field advantage boolean
--- @field disadvantage boolean
--- @field rolls {guid: string, result: number, numFaces: number, dropped: boolean, explodes: boolean, category: string}[]
--- @field tiers number
--- @field boons number
--- @field banes number
--- @field total number
--- @field categories any
--- @field numVisibleCharacters any
--- @field token any
--- @field naturalRoll number The result of the roll only including the 'natural' component. i.e. the actual dice rolled.
--- @field nat1 boolean
--- @field forcedResult boolean
--- @field autosuccess boolean
--- @field autofailure boolean
--- @field nottierone boolean
--- @field nottierthree boolean
--- @field nat20 boolean
--- @field autocrit boolean
--- @field playerName string
--- @field playerColor string
--- @field description string
--- @field rollStr any
--- @field result string
ChatMessageDiceRollInfoLua = {}

--- SetInfo
--- @param info? any
--- @return boolean
function ChatMessageDiceRollInfoLua:SetInfo(info) end
