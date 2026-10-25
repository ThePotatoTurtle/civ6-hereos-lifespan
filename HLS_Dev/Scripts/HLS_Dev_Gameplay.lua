-- TEST GAME ONLY. Source-backed operations, invoked solely by EXECUTE_SCRIPT.
-- No UI/local player reads, random choices, async mutation handlers or saved state.
-- API provenance and the unverified gameplay availability gate: research/devtools.md.
local VERSION = "0.0.0.1"
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

local function AnchorFor(owner)
  local player = Players[owner]
  local capital = player:GetCities():GetCapitalCity()
  if capital then return capital:GetX(), capital:GetY() end
  local first = nil
  for _, unit in player:GetUnits():Members() do
    if first == nil or unit:GetID() < first:GetID() then first = unit end
  end
  if first then return first:GetX(), first:GetY() end
  return nil, nil
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
  local x, y = AnchorFor(playerID)
  local aiX, aiY
  if aiID then aiX, aiY = AnchorFor(aiID) end
  if #unclaimed < 4 or x == nil or aiX == nil then
    Log("SETUP", playerID, stamp, "UNVERIFIED actual=unclaimed:" .. tostring(#unclaimed) ..
      ",localAnchor:" .. tostring(x) .. ",aiAnchor:" .. tostring(aiX) ..
      " expected=4 unclaimed heroes and local/AI anchors; no mutation; attempt locked")
    return
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
  local function Spawn(owner, row, px, py)
    Log("SETUP", playerID, stamp, "variant=A generic InitUnit hero=" .. tostring(row.HeroClassType) ..
      " owner=" .. tostring(owner) .. " claimBefore=" .. tostring(manager:GetHeroClaimPlayer(row.Index)) ..
      " expectedClaimBefore=-1 x=" .. tostring(px) .. " y=" .. tostring(py))
    UnitManager.InitUnit(owner, row.UnitType, px, py)
    local unit = FindUnit(owner, row)
    if unit then created[#created + 1] = {owner = owner, row = row} end
    local claim = manager:GetHeroClaimPlayer(row.Index)
    local isHero = unit ~= nil and unit:IsHero()
    local lifespan = unit ~= nil and unit:GetLifespan() or nil
    local valid = unit ~= nil and claim == owner and isHero == true and type(lifespan) == "number" and lifespan > 0
    Log("SETUP", playerID, stamp, (valid and "PASS" or "FAIL") .. " variant=A hero=" .. tostring(row.HeroClassType) ..
      " owner=" .. tostring(owner) .. " claimAfter=" .. tostring(claim) .. " expectedClaim=" .. tostring(owner) ..
      " isHero=" .. tostring(isHero) .. " expectedIsHero=true lifespan=" .. tostring(lifespan) .. " expectedLifespan=>0")
    if not valid then error("generic InitUnit did not register a usable claimed hero") end
    return unit
  end
  local ok, err = pcall(function()
    Spawn(playerID, unclaimed[1], x, y)
    Spawn(aiID, unclaimed[2], aiX, aiY)
    local third = Spawn(playerID, unclaimed[3], x, y)
    UnitManager.Kill(third)
    local localAlive = FindUnit(playerID, unclaimed[1]) ~= nil
    local aiAlive = FindUnit(aiID, unclaimed[2]) ~= nil
    local fallen = manager:GetHeroClaimPlayer(unclaimed[3].Index) == playerID and FindUnit(playerID, unclaimed[3]) == nil
    local leftUnclaimed = manager:GetHeroClaimPlayer(unclaimed[4].Index) == -1
    if not (localAlive and aiAlive and fallen and leftUnclaimed) then
      error("scenario state incomplete local=" .. tostring(localAlive) .. " ai=" .. tostring(aiAlive) ..
        " registeredFallen=" .. tostring(fallen) .. " unclaimed=" .. tostring(leftUnclaimed))
    end
    Log("SETUP", playerID, stamp, "PASS variant=A actual=localAlive:1,aiAlive:1,registeredFallen:1,unclaimed:1" ..
      " expected=localAlive:1,aiAlive:1,registeredFallen:1,unclaimed:1" ..
      " localHero=" .. tostring(unclaimed[1].HeroClassType) .. " aiHero=" .. tostring(unclaimed[2].HeroClassType) ..
      " fallenHero=" .. tostring(unclaimed[3].HeroClassType) .. " unclaimedHero=" .. tostring(unclaimed[4].HeroClassType))
  end)
  if not ok then
    Cleanup()
    Log("SETUP", playerID, stamp, "FAIL variant=A actual=" .. tostring(err) ..
      " expected=complete registered scenario; cleanup=units only; claim state may remain; restart disposable game; attempt locked")
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
