-- Read-only UI snapshot. Engine call evidence: installed Babylon
-- GreatPeopleHeroPanel.lua:29-31,125-161, HeroesPopup.lua:131-136,
-- HeroesSupport.lua:81 and Base/Assets/UI/Panels/UnitPanel.lua:2269.
-- The exact property was verified live for local and unmet AI owners.
-- HLS_Presentation is included first by the child UI, sharing numeric validation.
HLS_HeroData = {};

function HLS_HeroData.Read(definition, manager, localPlayer)
    local hero = {definition=definition, state="unavailable"};
    hero.owner = manager:GetHeroClaimPlayer(definition.Index);
    hero.isLocal = hero.owner == localPlayer;
    local unitInfo = GameInfo.Units[definition.UnitType];
    if unitInfo then
        local base = UnitManager.GetUnitTypeBaseLifespan(unitInfo.Index);
        if HLS_Presentation.IsLifespan(base) then hero.baseLifespan = base; end
    end
    if hero.owner == -1 then
        hero.state = "unclaimed";
        return hero;
    end

    local owner = Players[hero.owner];
    if not owner then return hero; end
    -- A failed read or ambiguous match is never reported as a fallen hero.
    local ok, count, unit = pcall(function()
        local found, match = 0, nil;
        for _, candidate in owner:GetUnits():Members() do
            local unitInfo = GameInfo.Units[candidate:GetType()];
            if unitInfo and unitInfo.UnitType == definition.UnitType then
                found, match = found + 1, candidate;
            end
        end
        return found, match;
    end);
    if not ok or count > 1 then return hero; end
    if count == 0 then hero.state = "fallen"; return hero; end
    hero.state, hero.unit = "active", unit;
    local readable, remaining = pcall(function()
        return unit:GetProperty(UnitPropertyKeys.LifespanRemaining);
    end);
    if readable and HLS_Presentation.IsLifespan(remaining) then hero.remaining = remaining; end
    return hero;
end

return HLS_HeroData;
