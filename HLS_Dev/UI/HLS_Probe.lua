-- Show Hero Lifespans research probe. Reads engine state; never changes gameplay.
-- Evidence and the limits of each read are recorded in research/heroes.md.

HLS_Probe = {};
local Probe = HLS_Probe;
local m_baseline = nil;

local function Try(read)
    local ok, value = pcall(read);
    if ok then return value, nil; end
    return nil, tostring(value);
end

local function Number(value)
    return type(value) == "number" and value == value;
end

local function AddError(snapshot, message)
    snapshot.errors[#snapshot.errors + 1] = message;
end

local function OwnerLabel(owner, localPlayer)
    if owner == -1 then return nil, nil; end
    local met = owner == localPlayer;
    if not met then
        met = Try(function()
            return Players[localPlayer]:GetDiplomacy():HasMet(owner);
        end) == true;
    end
    if not met then return false, "Unknown civ"; end
    local name = Try(function()
        return Locale.Lookup(PlayerConfigurations[owner]:GetPlayerName());
    end);
    return true, name;
end

local function ReadLocalRecall(manager, hero, localPlayer)
    -- Vanilla only runs this command query for the local claimant. Do not infer
    -- another owner's eligibility from a local player's command restrictions.
    if hero.owner ~= localPlayer or hero.state ~= "fallen" then return; end
    local result, err = Try(function()
        local origin = manager:GetHeroOriginCityID(hero.heroIndex);
        if origin == nil or origin.id == nil then return nil; end
        local city = Players[hero.owner]:GetCities():FindID(origin.id);
        if city == nil then return nil; end
        local unitDef = GameInfo.Units[hero.unitType];
        local parameters = {};
        parameters[CityCommandTypes.PARAM_UNIT_TYPE] = unitDef.Hash;
        parameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;
        if not CityManager.CanStartCommand(city, CityCommandTypes.PURCHASE, true, parameters, false) then
            return false;
        end
        local canStart = CityManager.CanStartCommand(city, CityCommandTypes.PURCHASE, false, parameters, true);
        return canStart == true;
    end);
    hero.recallAvailable = result;
    hero.recallError = err;
end

function Probe.Snapshot()
    local snapshot = { heroes = {}, errors = {}, modeEnabled = false };
    local turnError, localPlayerError;
    snapshot.turn, turnError = Try(function() return Game.GetCurrentGameTurn(); end);
    snapshot.localPlayer, localPlayerError = Try(function() return Game.GetLocalPlayer(); end);
    if turnError then AddError(snapshot, "Game turn unavailable: " .. turnError); end
    if localPlayerError then AddError(snapshot, "Local player unavailable: " .. localPlayerError); end
    local mode, modeError = Try(function() return GameConfiguration.GetValue("GAMEMODE_HEROES"); end);
    if modeError then
        AddError(snapshot, "Heroes mode configuration unavailable: " .. modeError);
        return snapshot;
    end
    snapshot.modeEnabled = mode == true or mode == 1;
    if not snapshot.modeEnabled then return snapshot; end

    local manager, managerError = Try(function() return Game.GetHeroesManager(); end);
    if manager == nil then
        AddError(snapshot, "Heroes manager unavailable: " .. tostring(managerError));
        return snapshot;
    end
    local ok, errorMessage = pcall(function()
        for definition in GameInfo.HeroClasses() do
            local hero = {
                heroIndex = definition.Index, heroClassType = definition.HeroClassType,
                name = definition.Name, unitType = definition.UnitType,
                state = "unavailable"
            };
            snapshot.heroes[#snapshot.heroes + 1] = hero;
            hero.owner, hero.ownerError = Try(function() return manager:GetHeroClaimPlayer(definition.Index); end);
            hero.discovered = Try(function() return manager:IsHeroDiscovered(snapshot.localPlayer, definition.Index); end);
            hero.baseLifespan, hero.baseError = Try(function()
                return UnitManager.GetUnitTypeBaseLifespan(GameInfo.Units[definition.UnitType].Index);
            end);
            hero.ownerMet, hero.ownerName = OwnerLabel(hero.owner, snapshot.localPlayer);
            if hero.owner == -1 then
                hero.state = "unclaimed";
            elseif Number(hero.owner) then
                local matches, unitsError = Try(function()
                    local found = {};
                    local player = Players[hero.owner];
                    if player == nil then error("Claimant player unavailable"); end
                    for _, unit in player:GetUnits():Members() do
                        if GameInfo.Units[unit:GetType()].UnitType == definition.UnitType then
                            found[#found + 1] = unit;
                        end
                    end
                    return found;
                end);
                hero.unitsError = unitsError;
                if matches ~= nil and #matches == 0 then
                    hero.state = "fallen";
                elseif matches ~= nil and #matches == 1 then
                    local unit = matches[1];
                    hero.state = "active";
                    hero.unitID = Try(function() return unit:GetID(); end);
                    hero.remaining, hero.remainingError = Try(function()
                        return unit:GetProperty(UnitPropertyKeys.LifespanRemaining);
                    end);
                elseif matches ~= nil then
                    hero.unitsError = "Multiple units match the hero class; no unit selected";
                end
            end
            ReadLocalRecall(manager, hero, snapshot.localPlayer);
            -- deathTurn, startingLifespan, bonusTurns and recallsUsed remain nil:
            -- there is no verified source-backed read for them.
        end
    end);
    if not ok then AddError(snapshot, tostring(errorMessage)); end
    if #snapshot.heroes == 0 then AddError(snapshot, "Heroes mode is enabled but no hero definitions were read"); end
    table.sort(snapshot.heroes, function(a, b) return a.heroIndex < b.heroIndex; end);
    return snapshot;
end

local function Log(report, spike, status, message)
    local key = status == "PASS" and "pass" or status == "FAIL" and "fail" or "unverified";
    report[key] = report[key] + 1;
    print("[HLS][SPIKE " .. spike .. "] " .. message .. " " .. status);
end

local function Context(snapshot, hero)
    return "turn=" .. tostring(snapshot.turn) .. " hero=" .. tostring(hero.heroClassType)
        .. " name=" .. tostring(hero.name)
        .. " owner=" .. tostring(hero.owner) .. " met=" .. tostring(hero.ownerMet)
        .. " unit=" .. tostring(hero.unitID);
end

function Probe.RunAllSpikes()
    local snapshot = Probe.Snapshot();
    local report = { pass = 0, fail = 0, unverified = 0, snapshot = snapshot };
    print("[HLS][RUN] turn=" .. tostring(snapshot.turn) .. " localPlayer=" .. tostring(snapshot.localPlayer)
        .. " modeEnabled=" .. tostring(snapshot.modeEnabled) .. " probeReadOnly=true; optional extension/removal buttons can change gameplay");
    for _, message in ipairs(snapshot.errors) do Log(report, "S1", "FAIL", message); end
    local own, other, unmet, fallen = 0, 0, 0, 0;
    for _, hero in ipairs(snapshot.heroes) do
        local context = Context(snapshot, hero);
        if hero.state == "fallen" then fallen = fallen + 1; end
        if hero.state == "active" then
            if hero.owner == snapshot.localPlayer then own = own + 1;
            else other = other + 1; if not hero.ownerMet then unmet = unmet + 1; end end
            local readable = Number(hero.remaining) and hero.remaining >= 0;
            Log(report, "S1", readable and "PASS" or "FAIL", context .. " exactProperty=" .. tostring(hero.remaining)
                .. " error=" .. tostring(hero.remainingError) .. " scope=readability");
        end
        Log(report, "S2", hero.state == "unavailable" and "FAIL" or "PASS", context .. " state=" .. hero.state
            .. " discovered=" .. tostring(hero.discovered) .. " recallAvailable=" .. tostring(hero.recallAvailable)
            .. " scope=state-read deathTurn=unavailable error=" .. tostring(hero.unitsError or hero.ownerError));
        if hero.state == "fallen" and hero.owner == snapshot.localPlayer then
            Log(report, "S2", type(hero.recallAvailable) == "boolean" and "PASS" or "UNVERIFIED",
                context .. " scope=local-recall-read available=" .. tostring(hero.recallAvailable)
                .. " error=" .. tostring(hero.recallError));
        end
        Log(report, "S3", Number(hero.baseLifespan) and "PASS" or "UNVERIFIED",
            context .. " engineBase=" .. tostring(hero.baseLifespan) .. " scope=base-read"
            .. " startingLifespan=unavailable bonusTurns=unavailable recallsUsed=unavailable error=" .. tostring(hero.baseError));
    end
    Log(report, "S1", own > 0 and "PASS" or "UNVERIFIED",
        "coverage own=" .. own .. "; scope=presence; visual UnitPanel comparison and countdown still required; no other owner required");
    Log(report, "S1", other > 0 and "PASS" or "UNVERIFIED", "coverage other=" .. other);
    Log(report, "S1", unmet > 0 and "PASS" or "UNVERIFIED", "coverage unmet=" .. unmet);
    Log(report, "S2", fallen > 0 and "PASS" or "UNVERIFIED", "coverage fallen=" .. fallen);
    Log(report, "S2", "UNVERIFIED", "Historical death turn and other-owner recall eligibility have no verified getter; omitted");
    Log(report, "S3", "UNVERIFIED", "Game-speed scaling needs runs at two speeds; base is never compared with remaining lifespan");
    Log(report, "S4", "UNVERIFIED", "Save add/remove safety requires a separate runtime round trip; read-only code is not proof");
    Log(report, "S1", "UNVERIFIED", "UI GetLifespan is unsupported and is not called; compare exactProperty with the vanilla UnitPanel");
    Log(report, "S5", "UNVERIFIED", "Heroes child panel layout requires a visual runtime check");
    print("[HLS][SUMMARY] " .. report.pass .. " PASS, " .. report.fail .. " FAIL, " .. report.unverified .. " UNVERIFIED");
    return report;
end

function Probe.StartChecker(snapshot)
    m_baseline = nil;
    snapshot = snapshot or Probe.Snapshot();
    local active = 0;
    for _, hero in ipairs(snapshot.heroes or {}) do
        if hero.state == "active" then active = active + 1; end
    end
    if active == 0 then
        print("[HLS][CHECK] UNVERIFIED no active heroes; checker remains unarmed; recruit a hero then Run All Spikes");
        return nil;
    end
    m_baseline = snapshot;
    print("[HLS][CHECK] baseline turn=" .. tostring(m_baseline.turn) .. " activeHeroes=" .. active);
    return m_baseline;
end

function Probe.CheckTurn()
    if m_baseline == nil then
        return { pass = 0, fail = 0, unverified = 0 };
    end
    -- Gamecore publishes many batches per turn. Keep the armed turn baseline
    -- until a later turn, instead of replacing it during movement or selection.
    if Game.GetCurrentGameTurn() <= m_baseline.turn then
        return { pass = 0, fail = 0, unverified = 0 };
    end
    local current = Probe.Snapshot();
    local report = { pass = 0, fail = 0, unverified = 0, snapshot = current };
    for _, message in ipairs(current.errors) do Log(report, "S1", "FAIL", message); end
    local previous = {};
    for _, hero in ipairs(m_baseline.heroes) do previous[hero.heroIndex] = hero; end
    local delta = Number(current.turn) and Number(m_baseline.turn) and current.turn - m_baseline.turn or nil;
    for _, hero in ipairs(current.heroes) do
        local old = previous[hero.heroIndex];
        if hero.state == "active" and (not Number(hero.remaining) or hero.remaining < 0) then
            Log(report, "S1", "FAIL", Context(current, hero) .. " exactProperty=" .. tostring(hero.remaining)
                .. " error=" .. tostring(hero.remainingError));
        elseif hero.state == "active" and old ~= nil and old.state == "active" then
            local context = Context(current, hero);
            if delta ~= nil and delta > 0 and hero.owner == old.owner and hero.unitID == old.unitID
                and Number(old.remaining) and Number(hero.remaining) then
                local expected = old.remaining - delta;
                local status = hero.remaining == expected and "PASS" or "UNVERIFIED";
                Log(report, "S1", status, context .. " before=" .. old.remaining .. " after=" .. hero.remaining
                    .. " turnDelta=" .. delta .. " expectedWithoutExternalChanges=" .. expected
                    .. "; scope=observational; unseen recall with reused unit ID cannot be excluded"
                    .. "; extension/recall/death must be checked against scenario evidence");
            elseif delta ~= nil and delta > 0 then
                Log(report, "S1", "UNVERIFIED", context .. " identity changed or exact timer unavailable");
            end
        elseif old ~= nil and hero.state ~= old.state then
            Log(report, "S2", "UNVERIFIED", Context(current, hero) .. " stateBefore=" .. old.state .. " stateAfter=" .. hero.state);
        end
    end
    m_baseline = current;
    print("[HLS][SUMMARY] countdown " .. report.pass .. " PASS, " .. report.fail .. " FAIL, " .. report.unverified .. " UNVERIFIED");
    return report;
end

return HLS_Probe;
