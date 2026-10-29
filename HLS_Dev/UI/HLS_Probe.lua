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
        .. " modeEnabled=" .. tostring(snapshot.modeEnabled) .. " probeReadOnly=true; optional meeting/relationship buttons change diplomacy");
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

-- The same ascending alive-major roster is independently validated by gameplay.
-- EFV_Dev_Gameplay.lua:663-677; PlayersVisibility reads EFV_Tracker.lua:263,289.
function Probe.HotseatRoles()
    local humans, ais = {}, {};
    local ok, err = pcall(function()
        for id = 0, 63 do
            local player = Players[id];
            if player and player:IsAlive() and player:IsMajor() then
                local list = player:IsHuman() and humans or ais;
                list[#list + 1] = id;
            end
        end
    end);
    if not ok then return nil, "roster unavailable: " .. tostring(err); end
    if #humans ~= 3 or #ais ~= 1 then return nil, "requires exactly 3 alive major humans and 1 alive major AI"; end
    return {human1=humans[1], human2=humans[2], human3=humans[3], ai=ais[1]};
end

function Probe.CheckVisibility()
    local snapshot = Probe.Snapshot(); -- fresh observer, manager, claims and units on every click
    local report = {pass=0, fail=0, unverified=0, observer=snapshot.localPlayer};
    report.hotseat = Try(function() return GameConfiguration.IsHotseat(); end);
    report.multiplayer = Try(function() return GameConfiguration.IsAnyMultiplayer(); end);
    local roles, reason = Probe.HotseatRoles();
    report.roles = roles;
    local context = "turn=" .. tostring(snapshot.turn) .. " observer=" .. tostring(snapshot.localPlayer);
    print("[HLS][VISIBILITY] " .. context .. " hotseat=" .. tostring(report.hotseat) .. " multiplayer=" .. tostring(report.multiplayer) .. " readOnly=true production=HLS_HeroData.Read+HLS_Presentation.Card");
    local function Record(status, message) Log(report, "VISIBILITY", status, context .. " " .. message); end
    local function Finish()
        print("[HLS][SUMMARY] visibility " .. context .. " " .. report.pass .. " PASS, " .. report.fail .. " FAIL, " .. report.unverified .. " UNVERIFIED; only this observer checked; repeat on all 3 human turns");
        return report;
    end
    if type(report.hotseat) ~= "boolean" or type(report.multiplayer) ~= "boolean" then Record("UNVERIFIED", "session metadata unavailable"); end
    if not snapshot.modeEnabled then Record("UNVERIFIED", "Heroes & Legends disabled or unavailable"); return Finish(); end
    if not roles then Record("UNVERIFIED", tostring(reason)); return Finish(); end
    local observer = snapshot.localPlayer;
    if observer ~= roles.human1 and observer ~= roles.human2 and observer ~= roles.human3 then
        Record("UNVERIFIED", "current observer is not a configured human"); return Finish();
    end
    print("[HLS][VISIBILITY] " .. context .. " roles human1=" .. roles.human1 .. " human2=" .. roles.human2 .. " human3=" .. roles.human3 .. " ai=" .. roles.ai);
    for _, err in ipairs(snapshot.errors) do Record("UNVERIFIED", "snapshot error=" .. err); end
    if HLS_HeroData == nil or HLS_Presentation == nil then
        Record("UNVERIFIED", "production modules unavailable; enable Show Hero Lifespans"); return Finish();
    end
    local manager = Try(function() return Game.GetHeroesManager(); end);
    if not manager then Record("UNVERIFIED", "heroes manager unavailable"); return Finish(); end
    local ids = {roles.human1, roles.human2, roles.human3};
    local counts = {[roles.human1]=0, [roles.human2]=0, [roles.human3]=0};
    local unmet, knownFogged = 0, 0;
    for _, owner in ipairs(ids) do
        if owner ~= observer then
            local met = Try(function() return Players[observer]:GetDiplomacy():HasMet(owner); end);
            local friend = Try(function() return Players[observer]:GetDiplomacy():HasDeclaredFriendship(owner); end);
            local war = Try(function() return Players[observer]:GetDiplomacy():IsAtWarWith(owner); end);
            local allied = Try(function() return Players[observer]:GetDiplomacy():HasAllied(owner); end);
            print("[HLS][VISIBILITY] " .. context .. " relationship owner=" .. owner .. " met=" .. tostring(met) .. " friend=" .. tostring(friend) .. " war=" .. tostring(war) .. " allied=" .. tostring(allied));
            local expectedRelation;
            if (observer == roles.human1 and owner == roles.human2) or (observer == roles.human2 and owner == roles.human1) then expectedRelation = "friend";
            elseif (observer == roles.human1 and owner == roles.human3) or (observer == roles.human3 and owner == roles.human1) then expectedRelation = "war";
            else expectedRelation = "neutral"; end
            local covered = expectedRelation == "friend" and friend == true and war == false or
                expectedRelation == "war" and war == true and friend == false or
                expectedRelation == "neutral" and war == false and friend == false and allied == false;
            Record(covered and "PASS" or "UNVERIFIED", "relationshipCoverage owner=" .. owner .. " expectedFinal=" .. expectedRelation .. " covered=" .. tostring(covered) .. "; final setup is required for the complete matrix");
            if type(met) ~= "boolean" or type(friend) ~= "boolean" or type(war) ~= "boolean" or type(allied) ~= "boolean" then
                Record("UNVERIFIED", "relationship reads unavailable owner=" .. owner);
            end
        end
    end
    for _, raw in ipairs(snapshot.heroes) do
        if counts[raw.owner] ~= nil and raw.state == "active" then
            counts[raw.owner] = counts[raw.owner] + 1;
            local prefix = "hero=" .. tostring(raw.heroClassType) .. " owner=" .. tostring(raw.owner) .. " unit=" .. tostring(raw.unitID) .. " realRemaining=" .. tostring(raw.remaining);
            local definition = nil;
            for row in GameInfo.HeroClasses() do if row.Index == raw.heroIndex then definition = row; break; end end
            local actual, readError = Try(function() return HLS_HeroData.Read(definition, manager, observer); end);
            local card, cardError = Try(function() return HLS_Presentation.Card(actual, Locale.Lookup); end);
            local met = raw.owner == observer or Try(function() return Players[observer]:GetDiplomacy():HasMet(raw.owner); end);
            local expectedOwner = nil;
            if met == false then expectedOwner = Locale.Lookup("LOC_HLS_UNKNOWN_CIV"); unmet = unmet + 1;
            elseif met == true then expectedOwner = Try(function() return Locale.Lookup(PlayerConfigurations[raw.owner]:GetPlayerName()); end); end
            local unit = Try(function() return Players[raw.owner]:GetUnits():FindID(raw.unitID); end);
            local visible, revealed = nil, nil;
            if unit then
                visible = Try(function() return PlayersVisibility[observer]:IsVisible(unit:GetX(), unit:GetY()); end);
                revealed = Try(function() return PlayersVisibility[observer]:IsRevealed(unit:GetX(), unit:GetY()); end);
            end
            local details = prefix .. " met=" .. tostring(met) .. " visible=" .. tostring(visible) .. " revealed=" .. tostring(revealed) ..
                " expectedOwner=" .. tostring(expectedOwner) .. " actualOwner=" .. tostring(card and card.ownerLabel) ..
                " expectedTimer=" .. tostring(raw.remaining) .. " actualTimer=" .. tostring(card and card.statValue);
            if met == true and raw.owner ~= observer and visible == false then knownFogged = knownFogged + 1; end
            if type(visible) ~= "boolean" or type(revealed) ~= "boolean" then Record("UNVERIFIED", details .. " map visibility API unavailable"); end
            if not HLS_Presentation.IsLifespan(raw.remaining) then
                Record("FAIL", details .. " scope=readability expected=numeric nonnegative finite active-hero lifespan");
            elseif not actual or not card or not expectedOwner then
                Record("UNVERIFIED", details .. " reason=" .. tostring(readError or cardError or "required value unavailable"));
            else
                local actualID = actual.unit and Try(function() return actual.unit:GetID(); end);
                local good = actual.owner == raw.owner and actual.state == "active" and actualID == raw.unitID and actual.remaining == raw.remaining and
                    actual.hasMet == met and card.ownerLabel == expectedOwner and card.statValue == tostring(raw.remaining) and card.statLabel == Locale.Lookup("LOC_HLS_TURNS_LEFT");
                Record(good and "PASS" or "FAIL", details .. " production comparison");
            end
        end
    end
    for _, id in ipairs(ids) do
        Record(counts[id] > 0 and "PASS" or "UNVERIFIED", "humanHeroCoverage owner=" .. id .. " activeHeroes=" .. counts[id] .. " expected=at least one manually recruited hero");
    end
    Record(unmet > 0 and "PASS" or "UNVERIFIED", "coverage unmetHumanHeroes=" .. unmet .. "; run before meeting; cannot unmeet");
    Record(knownFogged > 0 and "PASS" or "UNVERIFIED", "coverage metHumanHeroesInFog=" .. knownFogged .. "; meeting/friendship/war never imply map visibility");
    return Finish();
end

return HLS_Probe;
