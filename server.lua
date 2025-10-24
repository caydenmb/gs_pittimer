Config = Config or {}

---------------------------------------
-- 0) LOGGING & DETECTION
---------------------------------------
local DEBUG_SERVER = (Config.Server and Config.Server.debug) or false
local function slog(msg) if DEBUG_SERVER then print(('[pt] %s'):format(msg)) end end

local CORE_MODE = (Config.Core or 'auto')
local ESX_READY = GetResourceState('es_extended') == 'started'
local QBOX_READY = GetResourceState('qbx_core') == 'started'

if CORE_MODE == 'auto' then
  if QBOX_READY then CORE_MODE = 'qbox'
  elseif ESX_READY then CORE_MODE = 'esx'
  else CORE_MODE = 'esx' end
end

print(('[pt] **SERVER LOADED** resource=%s core=%s esx=%s qbx=%s')
  :format(GetCurrentResourceName(), CORE_MODE, tostring(ESX_READY), tostring(QBOX_READY)))

---------------------------------------
-- 1) SHORTHANDS FROM CONFIG
---------------------------------------
local CONTROL_WINDOWS = Config.ControlWindows or { police={min=3,max=8} }
local D_COUNTDOWN     = (Config.Durations and Config.Durations.countdown)  or 120
local D_AUTH          = (Config.Durations and Config.Durations.authorized) or 90

-- Viewer job lookup
local VIEWER_SET = {}
do
  local list = (Config.Jobs and Config.Jobs.viewer) or {'police'}
  for _, name in ipairs(list) do VIEWER_SET[name] = true end
end

-- Multijob enforcement knobs
local ESX_MJ   = Config.Integration and Config.Integration.esx and Config.Integration.esx.multijob or {}
local QBOX_MJ  = Config.Integration and Config.Integration.qbox and Config.Integration.qbox.multijob or {}

---------------------------------------
-- 2) FRAMEWORK ADAPTERS (server)
---------------------------------------
-- ESX bootstrap  :contentReference[oaicite:13]{index=13}
local ESX
local function initESX()
  if ESX or CORE_MODE ~= 'esx' then return true end
  local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
  if ok and obj then ESX = obj return true end
  TriggerEvent('esx:getSharedObject', function(o) ESX = o end)
  return ESX ~= nil
end

-- ESX helpers: wasabi sets active ESX job for on-duty/off-duty
local function esxGetActiveJob(src)
  if not ESX then return nil end
  local xPlayer = ESX.GetPlayerFromId(src)
  return xPlayer and xPlayer.job or nil
end

local function esxIsViewer(src)
  local j = esxGetActiveJob(src)
  return j and VIEWER_SET[j.name] or false
end

local function esxCanControl(src)
  if ESX_MJ.hardRequire and GetResourceState(ESX_MJ.resource or 'wasabi_multijob') ~= 'started' then
    return false
  end
  local j = esxGetActiveJob(src); if not j then return false end
  local win = CONTROL_WINDOWS[j.name]; if not win then return false end
  local g = tonumber(j.grade) or 0
  return g >= (win.min or 0) and g <= (win.max or 0)
end

-- Qbox helpers: job + onduty from qbx_core (primary job)  :contentReference[oaicite:14]{index=14}
-- Also supports grade via job.grade.level and duty via job.onduty. :contentReference[oaicite:15]{index=15}
local function qboxGetPrimaryJob(src)
  local qb = exports.qbx_core:GetPlayer(src)
  if not qb or not qb.PlayerData or not qb.PlayerData.job then return nil end
  return qb.PlayerData.job
end

local function qboxIsViewer(src)
  local job = qboxGetPrimaryJob(src)
  if not job then return false end
  return (VIEWER_SET[job.name] == true) and (job.onduty == true)
end

local function qboxCanControl(src)
  if QBOX_MJ.hardRequire and GetResourceState(QBOX_MJ.resource or 'randol_multijob') ~= 'started' then
    return false
  end
  local job = qboxGetPrimaryJob(src); if not job then return false end
  if not (VIEWER_SET[job.name] and job.onduty == true) then return false end
  local lvl = (job.grade and (job.grade.level or job.grade)) or 0
  local win = CONTROL_WINDOWS[job.name]; if not win then return false end
  return lvl >= (win.min or 0) and lvl <= (win.max or 0)
end

local function isViewer(src)
  return (CORE_MODE == 'esx') and esxIsViewer(src) or qboxIsViewer(src)
end

local function canControl(src)
  return (CORE_MODE == 'esx') and esxCanControl(src) or qboxCanControl(src)
end

-- ESX init
if CORE_MODE == 'esx' then
  CreateThread(function()
    for i=1,60 do if initESX() then break end Wait(250) end
    local esxReady = ESX ~= nil
    local mjName = ESX_MJ.resource or 'wasabi_multijob'
    print(('[pt] ESX=%s | %s=%s'):format(tostring(esxReady), mjName, GetResourceState(mjName)))
    if ESX_MJ.hardRequire and GetResourceState(mjName) ~= 'started' then
      print(('[pt] WARNING: %s not started but hardRequire=true — PIT controls will be refused on ESX path.'):format(mjName))
    end
  end)
else
  -- Qbox info line (and show randol status)
  local mjName = QBOX_MJ.resource or 'randol_multijob'
  print(('[pt] Qbox detected | %s=%s'):format(mjName, GetResourceState(mjName)))
end

---------------------------------------
-- 3) AUTHORITATIVE STATE (GLOBAL)
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
-- 4) DIAGNOSTIC PING
---------------------------------------
RegisterNetEvent('ptping', function()
  if DEBUG_SERVER then print(('[pt] ping from %s'):format(source)) end
  TriggerClientEvent('pt:pong', source)
end)

---------------------------------------
-- 5) START / STOP (client → server)
---------------------------------------
RegisterNetEvent('pt:serverStart', function()
  local src = source
  slog(('serverStart from %s'):format(src))

  if CORE_MODE == 'esx' and not initESX() then
    -- Allow simple testing if ESX not ready
    running = true; authorizedActive = false; endsAt = os.time() + D_COUNTDOWN; authorizedEndsAt = 0
    return bcastStart(D_COUNTDOWN)
  end

  if not isViewer(src) then
    TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', 'You must be on-duty as Police.' } })
    return
  end

  if not canControl(src) then
    TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', 'Insufficient grade to control the PIT timer.' } })
    return
  end

  if running then
    return bcastStart(remaining()) -- re-sync everyone
  end

  running = true
  authorizedActive = false
  endsAt = os.time() + D_COUNTDOWN
  authorizedEndsAt = 0
  bcastStart(D_COUNTDOWN)
end)

RegisterNetEvent('pt:serverStop', function()
  local src = source
  slog(('serverStop from %s'):format(src))

  if CORE_MODE == 'esx' and not initESX() then
    running = false; authorizedActive = false; endsAt = 0; authorizedEndsAt = 0
    return bcastStop()
  end

  if not isViewer(src) then
    TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', 'You must be on-duty as Police.' } })
    return
  end

  if not canControl(src) then
    TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', 'Insufficient grade to control the PIT timer.' } })
    return
  end

  running = false
  authorizedActive = false
  endsAt = 0
  authorizedEndsAt = 0
  bcastStop()
end)

---------------------------------------
-- 6) STATE SYNC (new joiners / job changes)
---------------------------------------
RegisterNetEvent('pt:requestState', function()
  local src = source
  if CORE_MODE == 'esx' and not initESX() then return end

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
-- 7) WATCHDOG (1s: expiry & auto-clear)
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
