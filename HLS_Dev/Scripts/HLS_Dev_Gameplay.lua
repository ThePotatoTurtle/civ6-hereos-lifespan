-- TEST GAME ONLY. Source-backed operations, invoked solely by EXECUTE_SCRIPT.
-- No UI/local player reads, random choices, async mutation handlers or saved state.
-- API provenance and the unverified gameplay availability gate: research/devtools.md.
local VERSION = "0.1.0.1"

local function Log(command, playerID, stamp, message)
  print("[HLS][DEV " .. command .. "] turn=" .. tostring(Game.GetCurrentGameTurn()) ..
    " player=" .. tostring(playerID) .. " stamp=" .. tostring(stamp) .. " " .. message)
end

local function Integer(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function ResolveTarget(requester, parameters, ai)
  -- Claims are exposed in UI, not gameplay. Resolve only the UI-selected identity
  -- and reject stale/reused IDs before touching the unit. Never silently retarget.
  local owner, unitID = parameters.owner, parameters.unitID
  if not Integer(owner) or not Integer(unitID) or not Integer(parameters.turn) then
    return nil, "missing or invalid target identity"
  end
  if parameters.turn ~= Game.GetCurrentGameTurn() then return nil, "stale target turn" end
  local player = Players[owner]
  if player == nil then return nil, "target player unavailable" end
  if (not ai and owner ~= requester) or
    (ai and (owner == requester or not player:IsMajor() or player:IsHuman())) then
    return nil, "target owner is not eligible for this command"
  end
  local row = nil
  for candidate in GameInfo.HeroClasses() do
    if candidate.HeroClassType == parameters.heroClassType and candidate.UnitType == parameters.unitType then
      row = candidate
      break
    end
  end
  if row == nil then return nil, "hero class and unit type do not match" end
  local unit = player:GetUnits():FindID(unitID)
  if unit == nil then return nil, "target unit is no longer present" end
  local definition = GameInfo.Units[unit:GetType()]
  if unit:GetID() ~= unitID or definition == nil or definition.UnitType ~= row.UnitType then
    return nil, "target unit identity changed"
  end
  -- IsHero/GetLifespan/SetLifespan have Tuner source evidence only. Their gameplay
  -- availability is still a runtime gate; pcall below reports an unavailable API.
  if not unit:IsHero() then return nil, "target unit is not a hero" end
  return unit, nil, row
end

local function Execute(playerID, parameters)
  if type(parameters) ~= "table" then return end
  local command, stamp = parameters.command, parameters.stamp
  if command ~= "extend" and command ~= "killAI" then
    Log("REQUEST", playerID, stamp, "UNVERIFIED reason=unknown command")
    return
  end
  if type(playerID) ~= "number" or Players[playerID] == nil then
    Log(command, playerID, stamp, "UNVERIFIED reason=invalid requesting player")
    return
  end
  local unit, reason, row = ResolveTarget(playerID, parameters, command == "killAI")
  if unit == nil then
    Log(command, playerID, stamp, "UNVERIFIED reason=" .. tostring(reason) .. "; no mutation")
    return
  end
  local owner = parameters.owner
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
    local remainingUnit = Players[owner]:GetUnits():FindID(beforeID)
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
    local validAction = command == "extend" or command == "killAI"
    Log(tostring(command), playerID, type(parameters) == "table" and parameters.stamp or "?",
      (validAction and "FAIL" or "UNVERIFIED") .. " error=" .. tostring(err) ..
      " expected=requested source-backed operation completes; partial mutation possible")
  end
end

GameEvents.HLS_Dev_Request.Add(OnRequest)
print("[HLS][DEV GAMEPLAY] ready version=" .. VERSION .. " mutations=only synchronized extend/killAI requests")
