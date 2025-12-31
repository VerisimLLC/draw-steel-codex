local mod = dmhub.GetModLoading()

local function GenerateStandardStrikeScoreFunction(score)
    return function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(ability)
        if loc ~= nil then
            return {score = score, loc = loc}
        end
    end
end

local function GenerateStandardStrikeExecuteFunction()
    return function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})

        local targets = ai:FindValidTargetsOfStrike(ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end
end

MonsterAI:RegisterMove{
    id = "Charge and Free Strike",
    abilities = {"Melee Free Strike"},
    score = GenerateStandardStrikeScoreFunction(0.2),
    execute = GenerateStandardStrikeExecuteFunction(),
}

MonsterAI:RegisterMove{
    id = "Ranged Free Strike",
    abilities = {"Ranged Free Strike"},
    score = GenerateStandardStrikeScoreFunction(0.2),
    execute = GenerateStandardStrikeExecuteFunction(),
}


MonsterAI:RegisterMove{
    id = "Spear Charge",
    monsters = {"Goblin Warrior"},
    abilities = {"Spear Charge"},
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(ability)
        if loc ~= nil then
            return {score = 1, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})

        local targets = ai:FindValidTargetsOfStrike(ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Chains",
    monsters = {"Goblin Pirate Assassin", "Goblin Assassin"},
    abilities = {"Shadow Chains"},
    score = function(self, ai, token, ability)
        print("AI:: SCORE CALLED WITH ABILITY", ability)
        local loc = ai:FindBestMoveToUseStrike(ability)
        print("AI:: BEST LOC TO USE STRIKE", loc)
        if loc ~= nil then
            return {score = 2, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})
        ai.Sleep(1.0)
        ai:Speech(token, "Shadow Chains!")

        local targets = ai:FindValidTargetsOfStrike(ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Sword Stab",
    monsters = {"Goblin Pirate Assassin", "Goblin Assassin"},
    abilities = {"Sword Stab"},
    score = function(self, ai, token, ability)
        print("AI:: SCORE CALLED WITH ABILITY", ability)
        local loc = ai:FindBestMoveToUseStrike(ability)
        print("AI:: BEST LOC TO USE STRIKE", loc)
        if loc ~= nil then
            return {score = 1, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})

        ai:Speech(token, {"Take this!", "Feel my blade!", "Die!"})
        local targets = ai:FindValidTargetsOfStrike(ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Hide in Concealment",
    monsters = {"Goblin Pirate Assassin", "Goblin Assassin"},
    abilities = {"Hide"},
    score = function(self, ai, token, ability)
        if token.properties:HasNamedCondition("Hidden") then
            return nil
        end
        local loc = ai:FindReachableConcealment()
        if loc ~= nil then
            return {score = 0.1, loc = loc}
        end

        return nil
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, {"You can't catch me!", "Now you see me, now you don't!", "Try to find me!"})
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})

        ai:ExecuteAbility(token, ability, {})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Drag",
    monsters = {"Bugbear Channeler"},
    abilities = {"Shadow Drag"},
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(ability)
        if loc ~= nil then
            local targets = ai:FindValidTargetsOfStrike(ability, loc)
            return {score = #targets, loc = loc}
        end

        return nil
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})
        ai.Sleep(0.5)
        ai:Speech(token, {"Shadow Drag!", "I'll pull you over here!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Twist Shape",
    monsters = {"Bugbear Channeler"},
    abilities = {"Twist Shape"},
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(ability)
        if loc ~= nil then
            return {score = 2.5, loc = loc}
        end

        return nil
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000})
        ai.Sleep(0.5)
        ai:Speech(token, {"I'll warp your very existence!", "Twist Shape!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}