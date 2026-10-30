-- Testing only. Gameplay mutations use synchronized EXECUTE_SCRIPT requests.
-- Sources: BlackDeathScenario_PopupHandler.lua:21-28 and BlackDeathScenario.lua:66;
-- BlackDeathScenario.lua:562-565 verifies GetReligion/GetFaithBalance/ChangeFaithBalance.
local VERSION = "1.0.0.1"
local FAITH_AMOUNT = 1000

local function Log(pid, stamp, message)
  print("[HLS][DEV give_faith] turn=" .. tostring(Game.GetCurrentGameTurn()) .. " player=" .. tostring(pid) .. " stamp=" .. tostring(stamp) .. " " .. message)
end

local function Execute(pid, parameters)
  if type(parameters) ~= "table" then Log(pid, "?", "UNVERIFIED reason=malformed request; no mutation"); return end
  local stamp = parameters.stamp
  if parameters.command ~= "give_faith" then Log(pid, stamp, "UNVERIFIED reason=unknown command; no mutation"); return end
  if parameters.turn ~= Game.GetCurrentGameTurn() then Log(pid, stamp, "UNVERIFIED reason=stale turn; no mutation"); return end
  if type(pid) ~= "number" or pid ~= math.floor(pid) or pid < 0 or pid > 63 then
    Log(pid, stamp, "UNVERIFIED reason=invalid requester; no mutation"); return
  end
  local player = Players[pid]
  if not player or not player:IsAlive() or not player:IsMajor() or not player:IsHuman() then
    Log(pid, stamp, "UNVERIFIED reason=requester must be an alive major human; no mutation"); return
  end
  local religion = player:GetReligion()
  if not religion then Log(pid, stamp, "UNVERIFIED reason=religion unavailable; no mutation"); return end
  local before = religion:GetFaithBalance()
  if type(before) ~= "number" or before ~= before or before == math.huge or before == -math.huge then
    Log(pid, stamp, "UNVERIFIED reason=faith balance unavailable; no mutation"); return
  end
  -- The engine supplies pid. Never accept a target player or amount from the UI.
  religion:ChangeFaithBalance(FAITH_AMOUNT)
  local after = religion:GetFaithBalance()
  local status = after == before + FAITH_AMOUNT and "PASS" or "FAIL"
  Log(pid, stamp, status .. " before=" .. tostring(before) .. " after=" .. tostring(after) .. " added=" .. FAITH_AMOUNT)
end

local function OnRequest(pid, parameters)
  local ok, err = pcall(function() Execute(pid, parameters) end)
  if not ok then
    Log(pid, type(parameters) == "table" and parameters.stamp or "?", "UNVERIFIED error=" .. tostring(err) .. "; inspect faith balance before retrying")
  end
end

GameEvents.HLS_Dev_Request.Add(OnRequest)
print("[HLS][DEV GAMEPLAY] ready version=" .. VERSION .. " mutations=only synchronized give_faith requests amount=" .. FAITH_AMOUNT)
