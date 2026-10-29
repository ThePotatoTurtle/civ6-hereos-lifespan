-- TEST GAME ONLY. Source-backed operations, invoked solely by EXECUTE_SCRIPT.
-- No UI/local player reads, random choices, async mutation handlers or saved state.
-- API provenance and the unverified gameplay availability gate: research/devtools.md.
local VERSION = "0.0.0.2"
local m_SetupAttempted = false

local function Log(command, playerID, stamp, message)
  print("[HLS][DEV " .. command .. "] turn=" .. tostring(Game.GetCurrentGameTurn()) ..
    " player=" .. tostring(playerID) .. " stamp=" .. tostring(stamp) .. " " .. message)
end

local function HeroRows()
  local rows = {}
  for row in GameInfo.HeroClasses() do rows[#rows + 1] = row end
  table.sort(rows, function(a, b) return a.Index < b.Index end)
  return rows
end

local function FindUnit(owner, row)
  local player = Players[owner]
  if player == nil then return nil end
  local found = nil
  for _, unit in player:GetUnits():Members() do
    local definition = GameInfo.Units[unit:GetType()]
    if definition and definition.UnitType == row.UnitType then
      if found == nil or unit:GetID() < found:GetID() then found = unit end
    end
  end
  return found
end

local function SelectHero(requester, ai)
  local manager = Game.GetHeroesManager()
  if manager == nil then return nil, nil, nil end
  for _, row in ipairs(HeroRows()) do
    local owner = manager:GetHeroClaimPlayer(row.Index)
    if type(owner) == "number" and owner >= 0 then
      local player = Players[owner]
      local eligible = (not ai and owner == requester) or
        (ai and owner ~= requester and player ~= nil and player:IsMajor() and not player:IsHuman())
      if eligible then
        local unit = FindUnit(owner, row)
        if unit then return unit, owner, row end
      end
    end
  end
  return nil, nil, nil
end

local function HeroGrantModifier(row)
  local heroArguments, monumentLocations = {}, {}
  for argument in GameInfo.ModifierArguments() do
    if argument.Name == "HeroClassType" and argument.Value == row.HeroClassType then
      heroArguments[#heroArguments + 1] = argument.ModifierId
    elseif argument.Name == "LocationBuildingType" and argument.Value == "BUILDING_MONUMENT" then
      monumentLocations[argument.ModifierId] = true
    end
  end
  table.sort(heroArguments)
  for _, modifierID in ipairs(heroArguments) do
    local definition = GameInfo.Modifiers[modifierID]
    if definition and definition.ModifierType == "MODIFIER_CITY_GRANT_HERO" and monumentLocations[modifierID] then
      return modifierID
    end
  end
  return nil
end

local function CreateOriginCity(owner, monument)
  local cities = Players[owner]:GetCities()
  for plotIndex = 0, Map.GetPlotCount() - 1 do
    local plot = Map.GetPlotByIndex(plotIndex)
    if plot and cities:IsValidFoundLocation(plot:GetX(), plot:GetY()) == true then
      local city = cities:Create(plot:GetX(), plot:GetY())
      if city then
        if city:GetOwner() ~= owner then error("origin city owner does not match requested player") end
        city:GetBuildQueue():CreateIncompleteBuilding(monument.Index, 100)
        if not city:GetBuildings():HasBuilding(monument.Index) then error("origin city Monument was not created") end
        return city
      end
    end
  end
  error("no valid founding location for an origin city")
end

local function Setup(playerID, stamp)
  if m_SetupAttempted then
    Log("SETUP", playerID, stamp, "UNVERIFIED reason=already attempted; restart a disposable game; no mutation")
    return
  end
  m_SetupAttempted = true
  local manager = Game.GetHeroesManager()
  local aiIDs = {}
  for _, player in ipairs(Game.GetPlayers({Alive = true, Major = true})) do
    if player:GetID() ~= playerID and not player:IsHuman() then aiIDs[#aiIDs + 1] = player:GetID() end
  end
  table.sort(aiIDs)
  local aiID = aiIDs[1]
  local unclaimed = {}
  for _, row in ipairs(HeroRows()) do
    if manager:GetHeroClaimPlayer(row.Index) == -1 then unclaimed[#unclaimed + 1] = row end
  end
  local monument = GameInfo.Buildings["BUILDING_MONUMENT"]
  if #unclaimed < 4 or aiID == nil or monument == nil then
    Log("SETUP", playerID, stamp, "UNVERIFIED actual=unclaimed:" .. tostring(#unclaimed) ..
      ",ai:" .. tostring(aiID) .. ",monumentDefinition:" .. tostring(monument ~= nil) ..
      " expected=4 unclaimed heroes, a major AI and Monument definition; no mutation; attempt locked")
    return
  end
  local modifiers = {}
  for i = 1, 3 do
    modifiers[i] = HeroGrantModifier(unclaimed[i])
    if modifiers[i] == nil then
      Log("SETUP", playerID, stamp, "UNVERIFIED hero=" .. tostring(unclaimed[i].HeroClassType) ..
        " actual=no matching built-in city grant modifier expected=hero class plus Monument arguments; no mutation; attempt locked")
      return
    end
  end
  local created = {}
  local function Cleanup()
    for _, record in ipairs(created) do
      local unit = FindUnit(record.owner, record.row)
      if unit then
        local ok, err = pcall(function() UnitManager.Kill(unit) end)
        Log("SETUP", playerID, stamp, "cleanup hero=" .. tostring(record.row.HeroClassType) ..
          " owner=" .. tostring(record.owner) .. " killOk=" .. tostring(ok) .. " error=" .. (ok and "none" or tostring(err)))
      end
    end
  end
  local function Grant(owner, row, modifierID)
    local city = CreateOriginCity(owner, monument)
    local record = {owner = owner, row = row, city = city}
    created[#created + 1] = record
    Log("SETUP", playerID, stamp, "variant=B city grant hero=" .. tostring(row.HeroClassType) ..
      " owner=" .. tostring(owner) .. " claimBefore=" .. tostring(manager:GetHeroClaimPlayer(row.Index)) ..
      " expectedClaimBefore=-1 city=" .. tostring(city:GetID()) .. " modifier=" .. modifierID ..
      " monument=" .. tostring(city:GetBuildings():HasBuilding(monument.Index)) .. " expectedMonument=true")
    city:AttachModifierByID(modifierID)
    local unit = FindUnit(owner, row)
    local claim = manager:GetHeroClaimPlayer(row.Index)
    local origin = manager:GetHeroOriginCityID(row.Index)
    local isHero = unit ~= nil and unit:IsHero()
    local lifespan = unit ~= nil and unit:GetLifespan() or nil
    local valid = unit ~= nil and claim == owner and origin ~= nil and origin.id == city:GetID() and
      isHero == true and type(lifespan) == "number" and lifespan > 0
    Log("SETUP", playerID, stamp, (valid and "PASS" or "FAIL") .. " variant=B hero=" .. tostring(row.HeroClassType) ..
      " owner=" .. tostring(owner) .. " claimAfter=" .. tostring(claim) .. " expectedClaim=" .. tostring(owner) ..
      " originCity=" .. tostring(origin and origin.id) .. " expectedOriginCity=" .. tostring(city:GetID()) ..
      " isHero=" .. tostring(isHero) .. " expectedIsHero=true lifespan=" .. tostring(lifespan) .. " expectedLifespan=>0")
    if not valid then error("built-in city grant did not register a usable hero and origin city") end
    return unit
  end
  local ok, err = pcall(function()
    for i = 1, 4 do
      manager:SetHeroDiscovered(playerID, unclaimed[i].Index, true)
      if manager:IsHeroDiscovered(playerID, unclaimed[i].Index) ~= true then
        error("hero discovery was not registered for the requesting player")
      end
    end
    Grant(playerID, unclaimed[1], modifiers[1])
    Grant(aiID, unclaimed[2], modifiers[2])
    local third = Grant(playerID, unclaimed[3], modifiers[3])
    UnitManager.Kill(third)
    local localAlive = manager:GetHeroClaimPlayer(unclaimed[1].Index) == playerID and FindUnit(playerID, unclaimed[1]) ~= nil
    local aiAlive = manager:GetHeroClaimPlayer(unclaimed[2].Index) == aiID and FindUnit(aiID, unclaimed[2]) ~= nil
    local fallen = manager:GetHeroClaimPlayer(unclaimed[3].Index) == playerID and FindUnit(playerID, unclaimed[3]) == nil
    local leftUnclaimed = manager:GetHeroClaimPlayer(unclaimed[4].Index) == -1
    local originsValid = true
    for _, record in ipairs(created) do
      local origin = manager:GetHeroOriginCityID(record.row.Index)
      if origin == nil or origin.id ~= record.city:GetID() or record.city:GetOwner() ~= record.owner or
        not record.city:GetBuildings():HasBuilding(monument.Index) then originsValid = false end
    end
    if not (localAlive and aiAlive and fallen and leftUnclaimed and originsValid) then
      error("scenario state incomplete local=" .. tostring(localAlive) .. " ai=" .. tostring(aiAlive) ..
        " registeredFallen=" .. tostring(fallen) .. " unclaimed=" .. tostring(leftUnclaimed) .. " origins=" .. tostring(originsValid))
    end
    Log("SETUP", playerID, stamp, "PASS variant=B actual=localAlive:1,aiAlive:1,registeredFallen:1,unclaimed:1,validOrigins:3" ..
      " expected=localAlive:1,aiAlive:1,registeredFallen:1,unclaimed:1,validOrigins:3" ..
      " localHero=" .. tostring(unclaimed[1].HeroClassType) .. " aiHero=" .. tostring(unclaimed[2].HeroClassType) ..
      " fallenHero=" .. tostring(unclaimed[3].HeroClassType) .. " unclaimedHero=" .. tostring(unclaimed[4].HeroClassType))
  end)
  if not ok then
    Cleanup()
    Log("SETUP", playerID, stamp, "FAIL variant=B actual=" .. tostring(err) ..
      " expected=complete registered scenario; cleanup=units only; support cities, discovery and claim state may remain; restart disposable game; attempt locked")
  end
end

local function Execute(playerID, parameters)
  if type(parameters) ~= "table" then return end
  local command, stamp = parameters.command, parameters.stamp
  if command ~= "extend" and command ~= "killAI" and command ~= "setup" then
    Log("REQUEST", playerID, stamp, "UNVERIFIED reason=unknown command")
    return
  end
  if type(playerID) ~= "number" or Players[playerID] == nil then
    Log(command, playerID, stamp, "UNVERIFIED reason=invalid requesting player")
    return
  end
  if command == "setup" then
    Setup(playerID, stamp)
    return
  end
  local unit, owner, row = SelectHero(playerID, command == "killAI")
  if unit == nil then
    Log(command, playerID, stamp, "UNVERIFIED actual=no eligible live claimed hero expected=eligible live claimed hero; setup unavailable")
    return
  end
  local identity = " hero=" .. tostring(row.HeroClassType) .. " owner=" .. tostring(owner) .. " unit=" .. tostring(unit:GetID())
  if command == "extend" then
    local before = unit:GetLifespan()
    if type(before) ~= "number" then
      Log(command, playerID, stamp, "UNVERIFIED" .. identity .. " actual=" .. tostring(before) .. " expected=numeric live lifespan")
      return
    end
    local expected = before + 5
    unit:SetLifespan(expected)
    local actual = unit:GetLifespan()
    Log(command, playerID, stamp, (actual == expected and "PASS" or "FAIL") .. identity ..
      " before=" .. tostring(before) .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected) ..
      " provenance=synced EXECUTE_SCRIPT; UI checker must observe independently")
  else
    local beforeID = unit:GetID()
    UnitManager.Kill(unit)
    local remainingUnit = FindUnit(owner, row)
    local absent = remainingUnit == nil
    Log(command, playerID, stamp, (absent and "PASS" or "FAIL") .. identity ..
      " actual=" .. (absent and "absent" or tostring(remainingUnit:GetID())) .. " expected=absent priorUnit=" .. tostring(beforeID) ..
      " provenance=synced EXECUTE_SCRIPT; death turn and recall still unverified")
  end
end

local function OnRequest(playerID, parameters)
  local ok, err = pcall(function() Execute(playerID, parameters) end)
  if not ok then
    local command = type(parameters) == "table" and parameters.command or "REQUEST"
    local validAction = command == "setup" or command == "extend" or command == "killAI"
    Log(tostring(command), playerID, type(parameters) == "table" and parameters.stamp or "?",
      (validAction and "FAIL" or "UNVERIFIED") .. " error=" .. tostring(err) ..
      " expected=requested source-backed operation completes; partial mutation possible")
  end
end

GameEvents.HLS_Dev_Request.Add(OnRequest)
print("[HLS][DEV GAMEPLAY] ready version=" .. VERSION .. " mutations=only synchronized setup/extend/killAI requests")
