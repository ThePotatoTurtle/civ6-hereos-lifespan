-- TEST GAME ONLY. Source-backed operations, invoked solely by EXECUTE_SCRIPT.
-- No UI/local player reads, random choices, async mutation handlers or saved state.
-- API provenance and the unverified gameplay availability gate: research/devtools.md.
local VERSION = "0.0.0.3"

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
  local unit, owner, row = SelectHero(playerID, command == "killAI")
  if unit == nil then
    Log(command, playerID, stamp, "UNVERIFIED actual=no eligible live claimed hero expected=eligible live claimed hero; prepare heroes through normal gameplay")
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
    local validAction = command == "extend" or command == "killAI"
    Log(tostring(command), playerID, type(parameters) == "table" and parameters.stamp or "?",
      (validAction and "FAIL" or "UNVERIFIED") .. " error=" .. tostring(err) ..
      " expected=requested source-backed operation completes; partial mutation possible")
  end
end

GameEvents.HLS_Dev_Request.Add(OnRequest)
print("[HLS][DEV GAMEPLAY] ready version=" .. VERSION .. " mutations=only synchronized extend/killAI requests")
