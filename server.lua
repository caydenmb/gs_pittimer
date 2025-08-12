-- Safe fallback if config is missing
Config = Config or {}

---------------------------------------
-- 0) READ CONFIG / LOGGING
---------------------------------------
local DEBUG_SERVER = (Config.Server and Config.Server.debug) or false
local function slog(msg) if DEBUG_SERVER then print(('[pt] %s'):format(msg)) end end

-- Integration flags
local INTEG = Config.Integration and Config.Integration.wasabi or {enabled=true, resource='wasabi_multijob', hardRequire=false}
local WASABI_NAME   = INTEG.resource or 'wasabi_multijob'
local HARD_REQUIRE  = not not INTEG.hardRequire

print(('[pt] **SERVER LOADED** resource=%s (wasabi=%s, hardRequire=%s)')
  :format(GetCurrentResourceName(), tostring(INTEG.enabled), tostring(HARD_REQUIRE)))

---------------------------------------
-- 1) SHORTHANDS FROM CONFIG
---------------------------------------
local CONTROL_WINDOWS = Config.ControlWindows or { police={min=3,max=8}, sheriff={min=3,max=6} }
local D_COUNTDOWN     = (Config.Durations and Config.Durations.countdown)  or 120
local D_AUTH          = (Config.Durations and Config.Durations.authorized) or 90

-- Viewer job lookup
local VIEWER_SET = {}
do
  local list = (Config.Jobs and Config.Jobs.viewer) or {'police','sheriff'}
  for _, name in ipairs(list) do VIEWER_SET[name] = true end
end

---------------------------------------
-- 2) ESX BOOTSTRAP + WASABI CHECK
---------------------------------------
local ESX
local function initESX()
  if ESX then return true end
  local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
  if ok and obj then ESX = obj return true end
  TriggerEvent('esx:getSharedObject', function(o) ESX = o end)
  return ESX ~= nil
end

CreateThread(function()
  for i=1,60 do if initESX() then break end Wait(250) end
  local esxReady = ESX ~= nil
  local wasabiState = GetResourceState(WASABI_NAME)
  print(('[pt] ESX=%s | %s=%s'):format(tostring(esxReady), WASABI_NAME, wasabiState))
  if HARD_REQUIRE and wasabiState ~= 'started' then
    print(('[pt] ERROR: %s not started but hardRequire=true — controls will be refused.'):format(WASABI_NAME))
  end
end)

---------------------------------------
-- 3) PERMISSION HELPERS (CLOCKED-IN ONLY)
---------------------------------------
local function getActiveJob(src)
  if not ESX then return nil end
  local xPlayer = ESX.GetPlayerFromId(src)
  return xPlayer and xPlayer.job or nil
end

-- View = on-duty with a job in VIEWER_SET
local function isViewer(src)
  local j = getActiveJob(src)
  return j and VIEWER_SET[j.name] or false
end

-- Control = on-duty + within grade window for that job
local function canControl(src)
  if HARD_REQUIRE and GetResourceState(WASABI_NAME) ~= 'started' then
    return false -- enforce wasabi presence if requested
  end
  local j = getActiveJob(src); if not j then return false end
  local win = CONTROL_WINDOWS[j.name]; if not win then return false end
  local g = tonumber(j.grade) or 0
  return g >= (win.min or 0) and g <= (win.max or 0)
end

local function reply(src, msg)
  TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', msg or '' } })
end

---------------------------------------
-- 4) AUTHORITATIVE STATE (GLOBAL)
---------------------------------------
local running            = false   -- true while countdown ticking
local endsAt             = 0       -- epoch when countdown ends
local authorizedActive   = false   -- "Authorized" state visible
local authorizedEndsAt   = 0       -- epoch to auto-clear authorized

local function remaining() return math.max(0, endsAt - os.time()) end

-- Broadcast helpers
local function bcastStart(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or D_COUNTDOWN))
  slog(('broadcast START -> %ds'):format(seconds))
  TriggerClientEvent('pt:clientStart', -1, seconds)
end
local function bcastStop()
  slog('broadcast STOP')
  TriggerClientEvent('pt:clientStop', -1)
end
local function bcastAuthorized()
  slog('broadcast AUTHORIZED')
  TriggerClientEvent('pt:clientAuthorized', -1)
end

---------------------------------------
-- 5) DIAGNOSTIC PING (optional)
---------------------------------------
RegisterNetEvent('ptping', function()
  if DEBUG_SERVER then print(('[pt] ping from %s'):format(source)) end
  TriggerClientEvent('pt:pong', source)
end)

---------------------------------------
-- 6) START / STOP (client → server)
---------------------------------------
RegisterNetEvent('pt:serverStart', function()
  local src = source
  slog(('serverStart from %s'):format(src))

  if not initESX() then
    -- Allow test if ESX not ready yet
    running = true; authorizedActive = false; endsAt = os.time() + D_COUNTDOWN; authorizedEndsAt = 0
    TriggerClientEvent('pt:startAck', src, true, nil)
    return bcastStart(D_COUNTDOWN)
  end

  if not isViewer(src) then
    TriggerClientEvent('pt:startAck', src, false, 'You must be clocked in for an authorized job.')
    return reply(src, 'You must be clocked in as an authorized job.')
  end

  if not canControl(src) then
    TriggerClientEvent('pt:startAck', src, false, 'Insufficient grade to control the PIT timer.')
    return reply(src, 'Insufficient grade to control the PIT timer.')
  end

  if running then
    TriggerClientEvent('pt:startAck', src, true, nil)
    return bcastStart(remaining()) -- re-sync everyone
  end

  running = true
  authorizedActive = false
  endsAt = os.time() + D_COUNTDOWN
  authorizedEndsAt = 0
  TriggerClientEvent('pt:startAck', src, true, nil)
  bcastStart(D_COUNTDOWN)
end)

RegisterNetEvent('pt:serverStop', function()
  local src = source
  slog(('serverStop from %s'):format(src))

  if not initESX() then
    running = false; authorizedActive = false; endsAt = 0; authorizedEndsAt = 0
    TriggerClientEvent('pt:stopAck', src, true, nil)
    return bcastStop()
  end

  if not isViewer(src) then
    TriggerClientEvent('pt:stopAck', src, false, 'You must be clocked in for an authorized job.')
    return reply(src, 'You must be clocked in as an authorized job.')
  end

  if not canControl(src) then
    TriggerClientEvent('pt:stopAck', src, false, 'Insufficient grade to control the PIT timer.')
    return reply(src, 'Insufficient grade to control the PIT timer.')
  end

  running = false
  authorizedActive = false
  endsAt = 0
  authorizedEndsAt = 0
  TriggerClientEvent('pt:stopAck', src, true, nil)
  bcastStop()
end)

---------------------------------------
-- 7) STATE SYNC (new joiners / job changes)
---------------------------------------
RegisterNetEvent('pt:requestState', function()
  local src = source
  if not initESX() then return end

  if not isViewer(src) then
    return TriggerClientEvent('pt:clientStop', src) -- ensure HUD is off
  end

  if running then
    local r = remaining()
    if r > 0 then
      return TriggerClientEvent('pt:clientStart', src, r)
    end
  end

  if authorizedActive then
    return TriggerClientEvent('pt:clientAuthorized', src)
  end

  TriggerClientEvent('pt:clientStop', src)
end)

---------------------------------------
-- 8) WATCHDOG (1s: expiry & auto-clear)
---------------------------------------
CreateThread(function()
  while true do
    Wait(1000)
    local now = os.time()

    if running and now >= endsAt then
      running = false
      authorizedActive = true
      authorizedEndsAt = now + D_AUTH
      bcastAuthorized()
    end

    if authorizedActive and authorizedEndsAt > 0 and now >= authorizedEndsAt then
      authorizedActive = false
      authorizedEndsAt = 0
      bcastStop()
    end
  end
end)
