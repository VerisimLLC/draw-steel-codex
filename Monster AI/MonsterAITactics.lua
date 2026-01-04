local mod = dmhub.GetModLoading()

MonsterAI:RegisterTactic{
    id = "Flanking",
    description = "Monsters using this tactic try to move into position to flank enemies they are attacking in melee",
    score = function(self, token, tokenLoc, enemy, ability)
        local flanking = false
        for _,ally in ipairs(self.allyTokens) do
            if ally.charid ~= token.charid and ally:Distance(enemy) <= 1 then
                if (enemy.loc.y - tokenLoc.y) == (ally.loc.y - enemy.loc.y) and (enemy.loc.x - tokenLoc.x) == (ally.loc.x - enemy.loc.x) then
                    flanking = true
                    break
                end
            end
        end

        if flanking then
            return 1
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "Aid Attack",
    description = "Monsters using this tactic prefer to attack enemies who their allies are aiding attack on.",
    score = function(self, token, tokenLoc, enemy, ability)
        if enemy._tmp_ai_aidAttack == true then
            return 1
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "High Ground",
    description = "Monsters using this tactic prefer to attack from higher ground.",
    score = function(self, token, tokenLoc, enemy, ability)
        local targetAltitude = game.currentFloor:GetAltitudeAtLoc(enemy.loc)
        local ourAltitude = game.currentFloor:GetAltitudeAtLoc(tokenLoc)
        if ourAltitude > targetAltitude then
            return 1
        end
    end,
}