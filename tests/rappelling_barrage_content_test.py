"""Exercise the live Rappelling YAML through production ability synthesis.

Run from any directory with Python/PyYAML and the repository's bundled Lua.
The engine object boundary is stubbed; modifier and synthesis code is unchanged.
"""
import json
from pathlib import Path
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[1]


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, list):
        return '{' + ','.join(map(lua, value)) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'


def source(path):
    return (ROOT / path).read_text(encoding='utf-8')


grant = yaml.safe_load(source('data/objectTables/characterongoingeffects/rappelling-free-strike-available.yaml'))
modify = source('DMHub Game Rules/ModifierModifyAbilities.lua')
keyword_code = modify[modify.index('CharacterModifier.RegisterAbilityModifier\n{\n\tid = "modkeywords"'):modify.index('CharacterModifier.RegisterAbilityModifier\n{\n\tid = "modproperties"')]
modify_code = modify[modify.index('\tmodifyAbility = function(modifier, creature, ability)'):modify.index('\n\tcreateEditor = function(modifier, element)', modify.index('\tmodifyAbility = function(modifier, creature, ability)'))]
modify_code = 'CharacterModifier.TypeInfo.modifyability = {' + modify_code + '\n}'
synthesis = source('Draw Steel Core Rules/DSAugmentAbilities.lua')
synthesis = synthesis[:synthesis.index('function ActivatedAbilityAugmentedAbilityBehavior.AbilityModifierEditor')]
cast = source('DMHub Game Rules/ActivatedAbility.lua')
cast_start = cast.index('\tfor i,behavior in ipairs(self.behaviors) do\n\t\tprint("CastCoroutine::"')
cast_loop = cast[cast_start:cast.index('\n\tprint("CastCoroutine::", self.name, "end behaviors")', cast_start)]
script = r'''
local function object(t)
    if type(t) ~= 'table' then return t end
    for k,v in pairs(t) do t[k] = object(v) end
    return setmetatable(t, {__index = {
        try_get = function(s,k,d) if rawget(s,k)==nil then return d end return s[k] end,
        has_key = function(s,k) return rawget(s,k)~=nil end,
        get_or_add = function(s,k,d) if s[k]==nil then s[k]=d end return s[k] end,
        MakeTemporaryClone = function(s) return DeepCopy(s) end,
        HasKeyword = function(s,k) return (s.keywords or {})[k] == true end,
    }})
end
function DeepCopy(t)
    if type(t)~='table' then return t end
    local r={} for k,v in pairs(t) do r[k]=DeepCopy(v) end
    return setmetatable(r,getmetatable(t))
end
dmhub = {GetModLoading=function() return {} end}
function RegisterGameType(name) _G[name]={}; return _G[name] end
CharacterModifier = {TypeInfo={}}
local abilityModifierOptionsById={}
function CharacterModifier.RegisterAbilityModifier(t) abilityModifierOptionsById[t.id]=t end
function GenerateSymbols(o) return o end
function ExecuteGoblinScript() return 1 end
function ReplaceBehaviorToEnum(v) return v end
'''
script += keyword_code + '\n' + modify_code + '\n' + synthesis + '\nlocal grant=object(' + lua(grant) + ')\n'
script += r'''
local wrapper=grant.modifiers[1].activatedAbility
local invoke=wrapper.behaviors[1]
local ability=invoke.customAbility
local behavior=ability.behaviors[1]
local paid={name='Melee Free Strike',typeName='ActivatedAbility',
    actionResourceId='main-action',actionNumber=1,resourceCost='special-resource',resourceNumber='2',
    meleeAndRanged=false,keywords={Strike=true,Melee=true,Charge=true},
    behaviors={{__typeName='ActivatedAbilityPowerRollBehavior',tiers={'damage'}}}}
local actor={GetActivatedAbilities=function() return {object(paid)} end}
CharacterModifier.TypeInfo.modifyability.willModifyAbility=function() return true end
local result=ActivatedAbilityAugmentedAbilityBehavior.SynthesizeAbilities(behavior,ability,actor)
assert(#result==1)
local strike=result[1]
assert(strike.keywords.Strike and strike.keywords.Melee and not strike.keywords.Charge)
assert(strike.actionResourceId=='none', 'grant must not spend a main action')
assert(strike.resourceCost=='special-resource' and strike.resourceNumber=='2', 'alternative free strikes retain resource costs')
assert(paid.keywords.Charge and #paid.behaviors==1, 'synthesis cannot mutate normal free strike')
local purge, attack, trigger
for i,b in ipairs(strike.behaviors) do
    if b.__typeName=='ActivatedAbilityPurgeEffectsBehavior' then purge=i end
    if b.__typeName=='ActivatedAbilityPowerRollBehavior' then attack=i end
    if b.__typeName=='ActivatedAbilityCustomTriggerBehavior' then trigger=i end
end
assert(purge and attack and trigger, 'consumption and free strike event must survive synthesis')
assert(attack<trigger and trigger<purge, 'strike must resolve before the event and grant consumption')
assert(strike.behaviors[purge].ongoingEffect==grant.id and strike.behaviors[purge].applyto=='caster')
assert(invoke.useSquadCoordination==false, 'individual minion invocation must opt out')
assert(wrapper.actionResourceId=='none')
print('PASS: live YAML synthesized with production modifier/augment functions; no action cost, preserved resource costs, removed Charge, grant-only purge, original strike unchanged')
print('Behavior order: free-strike event='..trigger..', grant consumption='..purge..', attack='..attack)
'''
script += '\nlocal function runBehaviors(self,casterToken,targets,options)\n' + cast_loop + '\nend\n'
script += r'''
CharacterPanel={HighlightAbilitySection=function() end}
local consumed=false
local cancel=false
for _,b in ipairs(strike.behaviors) do
    b.hasCast=true
    b.typeName=b.__typeName
    b.IsFiltered=function() return false end
    b.ApplyToTargets=function(_,_,_,targets) return targets end
    b.Cast=function(self,_,_,_,options)
        if self.typeName=='ActivatedAbilityPowerRollBehavior' then
            if cancel then options.abort=true else options.pay=true end
        elseif self.typeName=='ActivatedAbilityPurgeEffectsBehavior' then consumed=true end
    end
end
cancel=true
runBehaviors(strike,{}, {}, {})
assert(not consumed,'canceling the attack roll must not consume the strike grant')
cancel=false
runBehaviors(strike,{}, {}, {})
assert(consumed,'resolving the strike must consume its grant')
print('PASS: production cast loop preserves grant on canceled roll and consumes it after a resolved strike')
'''

with tempfile.TemporaryDirectory(prefix='dmhub-rappelling-') as folder:
    path = Path(folder) / 'test.lua'
    path.write_text(script, encoding='ascii')
    subprocess.run([str(ROOT.parent / 'dependencies/lua/bin/lua.exe'), str(path)], check=True)
