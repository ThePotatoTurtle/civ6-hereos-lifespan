-- UI only: reads through HLS_Probe and sends flat synchronized dev requests.
-- API provenance: research/devtools.md. This context never mutates gameplay.
print("[HLS][DEV UI] loading version=0.1.0.1")
include("HLS_Probe")

local m_Open = true
local m_Stamp = 0
local m_HeroesEnabled = false
local m_CheckerArmed = false
local m_CheckPending = false
local MODE_OFF_MESSAGE = "Heroes & Legends is off or unavailable. Start a new Gathering Storm game with Heroes & Legends enabled to test hero timers, extension and removal. Run All Spikes remains available for diagnostics."

local function Status(message)
  Controls.StatusLabel:SetText(message)
  print("[HLS][DEV UI] " .. message)
end

local function SetOpen(open)
  m_Open = open
  ContextPtr:SetHide(false)
  Controls.Main:SetHide(not open)
end

local function Toggle()
  SetOpen(not m_Open)
end

local function Send(command)
  if not m_HeroesEnabled then
    Status("UNVERIFIED request=" .. command .. " reason=Heroes & Legends mode is off or unavailable; no request sent")
    return
  end
  local playerID = Game.GetLocalPlayer()
  if type(playerID) ~= "number" or playerID < 0 then
    Status("UNVERIFIED request=" .. command .. " reason=no local player")
    return
  end
  local snapshot = HLS_Probe.Snapshot()
  local target = nil
  for _, hero in ipairs(snapshot.heroes or {}) do
    local player = Players[hero.owner]
    local eligible = command == "extend" and hero.owner == playerID or
      command == "killAI" and hero.owner ~= playerID and player ~= nil and player:IsMajor() and not player:IsHuman()
    if hero.state == "active" and hero.unitID ~= nil and eligible then target = hero; break end
  end
  if target == nil then
    Status("UNVERIFIED request=" .. command .. " " ..
      (command == "killAI" and "No AI hero found; nothing changed" or "No own hero found; nothing changed") .. "; no request sent")
    return
  end
  m_Stamp = m_Stamp + 1
  local parameters = {OnStart = "HLS_Dev_Request", command = command, stamp = m_Stamp,
    owner = target.owner, unitID = target.unitID, heroClassType = target.heroClassType,
    unitType = target.unitType, turn = snapshot.turn}
  local ok, err = pcall(function()
    UI.RequestPlayerOperation(playerID, PlayerOperations.EXECUTE_SCRIPT, parameters)
  end)
  if ok then
    Status("Request sent: " .. command .. "; await the gameplay result in Lua.log.")
  else
    Status("UNVERIFIED request=" .. command .. " error=" .. tostring(err))
  end
end

local function RunAll()
  local focusMessage = "No own active hero is available to select; see the spike logs."
  m_CheckerArmed = false
  m_CheckPending = false
  ContextPtr:ClearRequestRefresh()
  local ok, err = pcall(function()
    local report = HLS_Probe.RunAllSpikes()
    if not m_HeroesEnabled then return end
    local snapshot = report and report.snapshot
    m_CheckerArmed = HLS_Probe.StartChecker(snapshot) ~= nil
    if snapshot then
      for _, hero in ipairs(snapshot.heroes or {}) do
        if hero.owner == snapshot.localPlayer and hero.state == "active" and hero.unitID ~= nil then
          local player = Players[hero.owner]
          local unit = player and player:GetUnits():FindID(hero.unitID)
          local definition = unit and GameInfo.Units[unit:GetType()]
          if definition and definition.UnitType == hero.unitType then
            UI.LookAtPlotScreenPosition(unit:GetX(), unit:GetY(), 0.5, 0.5)
            UI.SelectUnit(unit)
            if type(hero.remaining) == "number" and hero.remaining == hero.remaining and hero.remaining >= 0 then
              focusMessage = "Selected hero turns left: " .. tostring(hero.remaining) .. ". Compare the unit panel."
            else
              focusMessage = "Your hero is selected; exact timer unavailable. See Lua.log."
            end
            break
          end
        end
      end
    end
  end)
  if ok then
    if m_HeroesEnabled then
      if m_CheckerArmed then
        Status("Spikes logged. " .. focusMessage .. " Turn checker armed; end two turns.")
      else
        Status("Spikes logged. UNVERIFIED: no active hero; turn checker stays off. Settle your capital, get a Monument and recruit a hero, then run again.")
      end
    else
      Status(MODE_OFF_MESSAGE)
    end
  else
    Status("FAIL Run All Spikes error=" .. tostring(err))
  end
end

local function OnDeferredRefresh()
  ContextPtr:ClearRequestRefresh()
  if not m_CheckPending then return end
  m_CheckPending = false
  if not m_HeroesEnabled or not m_CheckerArmed then return end
  local ok, err = pcall(function() HLS_Probe.CheckTurn() end)
  if not ok then
    Status("UNVERIFIED turn checker error=" .. tostring(err))
  end
end

local function OnTurnBegin()
  if not m_HeroesEnabled or not m_CheckerArmed then return end
  -- LocalPlayerTurnBegin can precede the lifespan property update. Match the
  -- vanilla UnitPanel's deferred UI refresh instead of committing an early read.
  if not m_CheckPending then
    m_CheckPending = true
    ContextPtr:RequestRefresh()
  end
end

local function OnInput(input)
  if input:GetMessageType() == KeyEvents.KeyUp then
    local key = input:GetKey()
    if key == Keys.D and input:IsControlDown() and input:IsShiftDown() then
      Toggle()
      return true
    end
    if key == Keys.VK_ESCAPE and m_Open then
      SetOpen(false)
      return true
    end
  end
  return false
end

local function Initialize()
  ContextPtr:SetHide(false)
  Controls.Main:SetHide(false)
  ContextPtr:SetInputHandler(OnInput, true)
  ContextPtr:SetRefreshHandler(OnDeferredRefresh)
  local snapshot = HLS_Probe.Snapshot()
  m_HeroesEnabled = snapshot.modeEnabled == true
  Controls.ExtendButton:SetDisabled(not m_HeroesEnabled)
  Controls.KillAIButton:SetDisabled(not m_HeroesEnabled)
  Controls.CloseButton:RegisterCallback(Mouse.eLClick, function() SetOpen(false) end)
  Controls.RunAllButton:RegisterCallback(Mouse.eLClick, RunAll)
  Controls.ExtendButton:RegisterCallback(Mouse.eLClick, function() Send("extend") end)
  Controls.KillAIButton:RegisterCallback(Mouse.eLClick, function() Send("killAI") end)
  Events.LocalPlayerTurnBegin.Add(OnTurnBegin)
  Events.GameCoreEventPublishComplete.Add(OnTurnBegin)
  Controls.OpenButton:RegisterCallback(Mouse.eLClick, Toggle)
  if not m_HeroesEnabled then
    Status(MODE_OFF_MESSAGE)
  end
  print("[HLS][DEV UI] ready version=0.1.0.1 heroesMode=" .. tostring(m_HeroesEnabled) .. " toggle=Ctrl+Shift+D gameplayProbes=extend,killAI preparation=manual checker=off_until_RunAll_with_active_hero")
end

Initialize()
