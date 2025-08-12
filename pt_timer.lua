-- Safe fallback if config missing
Config = Config or {}

---------------------------------------
-- 0) IMPORT ESX + CONFIG SHORTHANDS
---------------------------------------
local ESX = exports['es_extended']:getSharedObject()

local C         = Config.Client or {}
local HUD       = C.hud or {}
local DEBUG     = C.debug or false
local IDLE_MS   = C.idleSleepMs or 1000
local ACTIVE_MS = C.activeSleepMs or 0
local POLL_ON   = (C.pollEnabled ~= false)
local POLL_MS   = C.pollIntervalMs or 300000

local CMD_START = (Config.Commands and Config.Commands.start) or 'startpit'
local CMD_STOP  = (Config.Commands and Config.Commands.stop ) or 'stoppit'
local CMD_PING  = (Config.Commands and Config.Commands.ping ) or 'ptping'

local INTEG     = Config.Integration and Config.Integration.wasabi or {enabled=true,resource='wasabi_multijob'}
local WASABI    = INTEG.resource or 'wasabi_multijob'

-- viewer jobs set (clocked-in only)
local VIEWER_SET = {}
do
  local list = (Config.Jobs and Config.Jobs.viewer) or {'police','sheriff'}
  for _, name in ipairs(list) do VIEWER_SET[name] = true end
end

local function log(msg) if DEBUG then print(('[pt:client] %s'):format(msg)) end end

---------------------------------------
-- 1) VIEWER CHECK (CLOCKED-IN)
---------------------------------------
local function isViewerNow()
  local pdata = ESX.GetPlayerData()
  local job = pdata and pdata.job
  return job and VIEWER_SET[job.name] or false
end

---------------------------------------
-- 2) CLIENT HUD STATE
---------------------------------------
local viewer         = false
local running        = false
local remaining      = 0
local authorizedText = false
local timerSeq       = 0   -- cancel token; any new start/stop bumps this

---------------------------------------
-- 3) DRAW HELPER
---------------------------------------
local function drawCenteredText(text, scale, r,g,b,a, x, y, font, outline, center)
  SetTextFont(font or 4)
  SetTextProportional(1)
  SetTextScale(scale or 0.7, scale or 0.7)
  SetTextColour(r or 255, g or 255, b or 255, a or 255)
  if outline ~= false then SetTextOutline() end
  SetTextCentre(center ~= false)
  SetTextEntry("STRING")
  AddTextComponentString(text)
  DrawText(x or 0.5, y or 0.08)
end

---------------------------------------
-- 4) BOOTSTRAP + JOB CHANGE + WASABI RESTART
---------------------------------------
CreateThread(function()
  -- Wait until ESX has loaded a job into PlayerData (wasabi sets this)
  while ESX.GetPlayerData().job == nil do Wait(100) end

  viewer = isViewerNow()
  TriggerServerEvent('pt:requestState')

  -- ESX notifies on active job change (wasabi clock in/out triggers this)
  AddEventHandler('esx:setJob', function()
    local newViewer = isViewerNow()
    if newViewer ~= viewer then
      viewer = newViewer
      TriggerServerEvent('pt:requestState')
    end
  end)

  -- If wasabi is restarted, resync our HUD state (server script fires this)
  AddEventHandler(WASABI..':resourceRestart', function()
    log('wasabi resource restart — requesting PIT state sync')
    TriggerServerEvent('pt:requestState')
  end)

  -- Optional periodic poll (safety net if any event was missed)
  if POLL_ON then
    CreateThread(function()
      while true do
        Wait(POLL_MS)
        local newViewer = isViewerNow()
        if newViewer ~= viewer then
          viewer = newViewer
          TriggerServerEvent('pt:requestState')
          log('Periodic job-status poll triggered a resync')
        end
      end
    end)
  end
end)

---------------------------------------
-- 5) COMMANDS (client → server)
---------------------------------------
RegisterCommand(CMD_START, function()
  if not viewer then
    TriggerEvent('chat:addMessage', { args = { '^1[PIT Timer]', 'You must be clocked in for an authorized job.' } })
    return
  end
  TriggerServerEvent('pt:serverStart')
end, false)

RegisterCommand(CMD_STOP, function()
  timerSeq = timerSeq + 1
  running = false; authorizedText = false; remaining = 0
  TriggerServerEvent('pt:serverStop')
end, false)

-- Optional ping (small, async, no cost when disabled)
RegisterCommand(CMD_PING, function()
  TriggerServerEvent('ptping')
end, false)
RegisterNetEvent('pt:pong', function()
  if DEBUG then print('[pt:client] PONG (server responded)') end
end)

---------------------------------------
-- 6) SERVER → CLIENT EVENTS
---------------------------------------
RegisterNetEvent('pt:clientStart', function(duration)
  if not viewer then return end
  timerSeq = timerSeq + 1
  local mySeq = timerSeq

  running = true
  authorizedText = false
  remaining = math.max(0, tonumber(duration) or 0)

  -- precise countdown via GetGameTimer to avoid drift
  local nextTick = GetGameTimer() + 1000
  CreateThread(function()
    while timerSeq == mySeq and running and remaining > 0 do
      local now = GetGameTimer()
      if now >= nextTick then
        remaining = remaining - 1
        nextTick = nextTick + 1000
      else
        Wait(50)
      end
    end
    -- do not flip to authorized here; server will broadcast pt:clientAuthorized
  end)
end)

RegisterNetEvent('pt:clientAuthorized', function()
  timerSeq = timerSeq + 1
  running = false
  authorizedText = true
  remaining = 0
end)

RegisterNetEvent('pt:clientStop', function()
  timerSeq = timerSeq + 1
  running = false
  authorizedText = false
  remaining = 0
end)

---------------------------------------
-- 7) ADAPTIVE RENDER LOOP
---------------------------------------
CreateThread(function()
  local cr = HUD.colorRunning    or {255,255,255,255}
  local ca = HUD.colorAuthorized or {  0,255,  0,255}
  while true do
    local active = viewer and ((running and remaining > 0) or authorizedText)

    if active then
      if running and remaining > 0 then
        local m = math.floor(remaining / 60)
        local s = remaining % 60
        drawCenteredText(
          (tostring(HUD.labelPrefix or 'PIT Timer: '))..(("%02d:%02d"):format(m, s)),
          HUD.scale, cr[1],cr[2],cr[3],cr[4], HUD.x, HUD.y, HUD.font, HUD.outline, HUD.center
        )
      elseif authorizedText then
        drawCenteredText(
          tostring(HUD.authorizedText or 'PIT Maneuver Authorized'),
          HUD.scale, ca[1],ca[2],ca[3],ca[4], HUD.x, HUD.y, HUD.font, HUD.outline, HUD.center
        )
      end
      Wait(ACTIVE_MS)   -- 0 = paint every frame while visible
    else
      Wait(IDLE_MS)     -- sleep while idle to save CPU
    end
  end
end)
