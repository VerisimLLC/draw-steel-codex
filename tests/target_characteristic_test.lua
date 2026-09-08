--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/target_characteristic_test.lua
local path = 'Draw Steel Core Rules/MCDMAbilityRollBehavior.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()
local function obj(t)
    t.try_get = function(self,k,d) if self[k] == nil then return d end return self[k] end
    return t
end
function cond(a,b,c) if a then return b else return c end end
function DeepCopy(x)
    if type(x) ~= 'table' then return x end
    local r = {}; for k,v in pairs(x) do r[k] = DeepCopy(v) end; return r
end
RollCheck = {customChecks={}}
function RollCheck.RegisterCustom(t) RollCheck.customChecks[t.id] = t end
ActivatedAbilityPowerRollBehavior = {}
ActivatedAbility = {Create=obj, GetTokenIds=function(t) local r={} for _,v in ipairs(t) do r[#r+1]=v.token.charid end return r end}
CharacterModifier = {new=obj}
RollPropertiesPowerTable = {new=obj}
creature = {attributesInfo={agl={description='Agility'}}}
local roller = {charid='hero'}
local events = {}
roller.properties = {
    AttributeMod=function(_,a) assert(a=='agl'); return 3 end,
    GetModifiersForPowerRoll=function(_,r,t,o)
        assert(r=='2d10 + 3'); assert(o.attribute=='agl'); assert(o.target==roller.properties)
        if t=='test_power_roll' then assert(o.caster==roller.properties and o.ability.isTest) end
        return {}
    end,
    DispatchEvent=function(_,e,v) events[#events+1]={e,v} end,
}
dmhub={GenerateGuid=function() return 'guid' end, LookupToken=function() return roller end, allTokens={}}
local shown
GameHud={instance={rollDialog={data={ShowDialog=function(o) shown=o; return o end}}}}
RollUtils={SortedDice=function() return {10,9} end}
function DiceResultToTier(r) return r.total>=17 and 3 or (r.total>=12 and 2 or 1) end
ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom=function() return function() end end
local start = assert(source:find('RollCheck.RegisterCustom{\n    id = "resistance_power_roll"',1,true))
local stop = assert(source:find('RollCheck.RegisterCustom{\n    id = "power_roll_custom"',start,true))
assert(load(source:sub(start,stop-1), 'target test implementation'))()
local request
local commands={}
local ability={name='Snaring Line',
    RequireSavingThrowsCo=function(_,_,_,_,o)
        request=o
        return {info={tokens={hero={result=8,naturalRoll=8,tier=3},other={result=15,naturalRoll=15,tier=1}}}}
    end,
    CommitToPaying=function() end,
}
local behavior=obj{isTest=true, resistanceAttr='agl', tiers={'8 damage; restrained (EoT)','6 damage; slowed (EoT)','No effect'}}
setmetatable(behavior,{__index=ActivatedAbilityPowerRollBehavior})
behavior.ExecuteCommand=function(_,_,_,target,_,command) commands[target.charid]=command end
local options={symbols={cast={SetTierResult=function() end}}}
local targets={{token=roller},{token={charid='other'}}}
behavior:CastResistance(ability,{},targets,options)
assert(request.id=='target_test_power_roll' and request.rollType=='test_power_roll')
assert(commands.hero=='No effect' and commands.other=='8 damage; restrained (EoT)', 'forwarded test tiers must win')
local check={info=request.info,options=request.dc_options}
check.CustomInfo=function() return RollCheck.customChecks[request.id] end
check.GetRoll=function(self,c) return self:CustomInfo().GetRoll(self,c) end
local custom=check:CustomInfo()
assert(custom.Describe(check)=='Agility Test')
custom.GetModifiers(check,roller.properties)
local completed=false
custom.ShowDialog(check,{creature=roller.properties,modifiers={},completeRoll=function() completed=true end})
assert(shown.ability.isTest and shown.ability.abilityType=='none')
assert(shown.multitargets[1].token==roller and shown.symbols.caster==roller.properties)
shown.completeRoll{total=19,naturalRoll=19,properties=obj{overrideTier=2},rolls={{numFaces=10,result=10},{numFaces=10,result=9}}}
assert(completed and events[1][1]=='rollpower' and events[1][2].tiertwo)
assert(events[1][2].ability.isTest and events[1][2].highroll==10)
behavior.isTest=false
behavior:CastResistance(ability,{},targets,options)
assert(request.id=='resistance_power_roll' and request.rollType=='resistance_power_roll')
assert(commands.hero=='8 damage; restrained (EoT)' and commands.other=='6 damage; slowed (EoT)', 'resistance must keep legacy tiers')
print('PASS target tests: request, Agility context, forwarded tiers, dialog roller, completion event, legacy resistance')
