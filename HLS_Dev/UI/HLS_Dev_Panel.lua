-- UI only: reads through HLS_Probe and sends flat synchronized dev requests.
-- API provenance: research/devtools.md. This context never mutates gameplay.
include("HLS_Probe")

local m_Open = true
local m_Stamp = 0
local m_LaunchInstance = {}

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
  local playerID = Game.GetLocalPlayer()
  if type(playerID) ~= "number" or playerID < 0 then
    Status("UNVERIFIED request=" .. command .. " reason=no local player")
    return
  end
  m_Stamp = m_Stamp + 1
  local parameters = {OnStart = "HLS_Dev_Request", command = command, stamp = m_Stamp}
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
  local ok, err = pcall(function()
    local report = HLS_Probe.RunAllSpikes()
    HLS_Probe.StartChecker()
    local snapshot = report and report.snapshot
    if snapshot then
      for _, hero in ipairs(snapshot.heroes or {}) do
        if hero.owner == snapshot.localPlayer and hero.state == "active" and hero.unitID ~= nil then
          local player = Players[hero.owner]
          local unit = player and player:GetUnits():FindID(hero.unitID)
          local definition = unit and GameInfo.Units[unit:GetType()]
          if definition and definition.UnitType == hero.unitType then
            UI.LookAtPlotScreenPosition(unit:GetX(), unit:GetY(), 0.5, 0.5)
            UI.SelectUnit(unit)
            focusMessage = "Your hero is selected for the unit-panel check."
            break
          end
        end
      end
    end
  end)
  if ok then
    Status("Spikes logged. Observational turn checker armed. " .. focusMessage)
  else
    Status("FAIL Run All Spikes error=" .. tostring(err))
  end
end

local function OnTurnBegin()
  local ok, err = pcall(function() HLS_Probe.CheckTurn() end)
  if not ok then
    Status("UNVERIFIED turn checker error=" .. tostring(err))
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

local function AttachLaunchButton()
  local ok, err = pcall(function()
    local stack = ContextPtr:LookUpControl("/InGame/LaunchBar/ButtonStack")
    ContextPtr:BuildInstanceForControl("HLSDevLaunchItem", m_LaunchInstance, stack)
    m_LaunchInstance.LaunchItemButton:RegisterCallback(Mouse.eLClick, Toggle)
    ContextPtr:BuildInstanceForControl("HLSDevLaunchPin", {}, stack)
    stack:CalculateSize()
    ContextPtr:LookUpControl("/InGame/LaunchBar/LaunchBacking"):SetSizeX(stack:GetSizeX() + 116)
    ContextPtr:LookUpControl("/InGame/LaunchBar/LaunchBackingTile"):SetSizeX(stack:GetSizeX() - 20)
    LuaEvents.LaunchBar_Resize(stack:GetSizeX())
  end)
  print("[HLS][DEV UI] launchButton=" .. tostring(ok) .. " error=" .. (ok and "none" or tostring(err)))
end

local function Initialize()
  ContextPtr:SetHide(false)
  Controls.Main:SetHide(false)
  ContextPtr:SetInputHandler(OnInput, true)
  Controls.CloseButton:RegisterCallback(Mouse.eLClick, function() SetOpen(false) end)
  Controls.RunAllButton:RegisterCallback(Mouse.eLClick, RunAll)
  Controls.SetupButton:SetToolTipString("Experimental InitUnit variant A: verifies hero claims, IsHero and lifespan. One attempt per loaded session; an incomplete setup requires a new disposable game.")
  Controls.SetupButton:RegisterCallback(Mouse.eLClick, function()
    Controls.SetupButton:SetDisabled(true)
    Send("setup")
  end)
  Controls.ExtendButton:RegisterCallback(Mouse.eLClick, function() Send("extend") end)
  Controls.KillAIButton:RegisterCallback(Mouse.eLClick, function() Send("killAI") end)
  Events.LocalPlayerTurnBegin.Add(OnTurnBegin)
  AttachLaunchButton()
  print("[HLS][DEV UI] ready version=0.0.0.1 toggle=Ctrl+Shift+D gameplayProbes=setup,extend,killAI setup=EXPERIMENTAL")
end

Initialize()
