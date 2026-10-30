-- Show Hero Lifespans 0.1.2. Pure presentation; no engine access.
HLS_Presentation = {};
HLS_Presentation.VERSION = "0.1.2";

function HLS_Presentation.IsLifespan(value)
    return type(value) == "number" and value >= 0 and value < math.huge;
end

function HLS_Presentation.IsWarning(remaining)
    return HLS_Presentation.IsLifespan(remaining) and remaining <= 5;
end

function HLS_Presentation.Card(hero, lookup)
    local card = {warning=false};
    if hero.state == "active" then
        card.statLabel = lookup("LOC_HLS_TURNS_LEFT");
        card.statValue = HLS_Presentation.IsLifespan(hero.remaining) and tostring(hero.remaining) or lookup("LOC_HLS_UNAVAILABLE");
        card.warning = HLS_Presentation.IsWarning(hero.remaining);
    elseif hero.state == "unclaimed" or hero.state == "fallen" then
        card.statLabel = lookup("LOC_HLS_LIFESPAN");
        card.statValue = HLS_Presentation.IsLifespan(hero.baseLifespan) and tostring(hero.baseLifespan) or lookup("LOC_HLS_UNAVAILABLE");
        if hero.state == "fallen" then card.fallenText = lookup("LOC_GREAT_PEOPLE_HEROES_DECEASED"); end
    else
        card.statLabel = lookup("LOC_HLS_TURNS_LEFT");
        card.statValue = lookup("LOC_HLS_UNAVAILABLE");
    end
    return card;
end

local function Group(hero)
    if hero.state == "active" then return hero.isLocal and 1 or 2; end
    if hero.state == "unclaimed" then return 3; end
    if hero.state == "fallen" then return 4; end
    return 5;
end

function HLS_Presentation.Less(a, b)
    local ga, gb = Group(a), Group(b);
    if ga ~= gb then return ga < gb; end
    if ga <= 2 then
        local ar = HLS_Presentation.IsLifespan(a.remaining) and a.remaining or math.huge;
        local br = HLS_Presentation.IsLifespan(b.remaining) and b.remaining or math.huge;
        if ar ~= br then return ar < br; end
    end
    -- Definition keys are stable and independent of localized names/unit IDs.
    if a.definition.HeroClassType ~= b.definition.HeroClassType then
        return a.definition.HeroClassType < b.definition.HeroClassType;
    end
    return a.definition.Index < b.definition.Index;
end

return HLS_Presentation;
