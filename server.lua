Config = Config or {}

---------------------------------------
-- 0) LOGGING & DETECTION
---------------------------------------
local DEBUG_SERVER = (Config.Server and Config.Server.debug) or false
local function slog(msg) if DEBUG_SERVER then print(('[pt] %s'):format(msg)) end end

-- Toggle debug via convar without editing config
do
  local cv = GetConvarInt('pt_debug', -1)
  if cv == 1 then
    DEBUG_SERVER = true
    print('[pt] Debug enabled by convar pt_debug=1')
  end
end

local CORE_MODE = (Config.Core or 'auto')
local ESX_READY = GetResourceState('es_extended') == 'started'
local QBOX_READY = GetResourceState('qbx_core') == 'started'

if CORE_MODE == 'auto' then
  if QBOX_READY then CORE_MODE = 'qbox'
  elseif ESX_READY then CORE_MODE = 'esx'
  else CORE_MODE = 'esx' end
end

print(('[pt] SERVER LOADED | core=%s esx=%s qbox=%s'):format(CORE_MODE, tostring(ESX_READY), tostring(QBOX_READY)))

---------------------------------------
-- 1) CONFIG SHORTHANDS
---------------------------------------
local CONTROL_WINDOWS = Config.ControlWindows or { police = { min = 3, max = 8 } }
local D_COUNTDOWN     = (Config.Durations and Config.Durations.countdown)  or 120
local D_AUTH          = (Config.Durations and Config.Durations.authorized) or 90

local VIEWER_SET = {}
do
  local list = (Config.Jobs and Config.Jobs.viewer) or {'police'}
  for _, name in ipairs(list) do VIEWER_SET[name] = true end
end

local ESX_MJ   = Config.Integration and Config.Integration.esx  and Config.Integration.esx.multijob  or {}
local QBOX_MJ  = Config.Integration and Config.Integration.qbox and Config.Integration.qbox.multijob or {}
local ALLOW_ESXLESS = Config.Server and Config.Server.allowEsxlessTest or false

---------------------------------------
-- 2) FRAMEWORK ADAPTERS
---------------------------------------
-- ESX
local ESX
local function initESX()
  if ESX or CORE_MODE ~= 'esx' then return true end
  local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
  if ok and obj then ESX = obj return true end
  TriggerEvent('esx:getSharedObject', function(o) ESX = o end)
  return ESX ~= nil
end

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

-- Qbox (qbx_core)
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

---------------------------------------
-- 3) PERMISSION HELPERS
---------------------------------------
local function hasAce(src, ace) return IsPlayerAceAllowed(src, ace) end

local function isViewer(src)
  return (CORE_MODE == 'esx') and esxIsViewer(src) or qboxIsViewer(src)
end

local function canControl(src)
  -- ACE override
  if hasAce(src, 'pt.admin') then return true end
  return (CORE_MODE == 'esx') and esxCanControl(src) or qboxCanControl(src)
end

---------------------------------------
-- 4) UI NOTIFY HELPER
---------------------------------------
local function notify(src, msg)
  if GetResourceState('ox_lib') == 'started' then
    -- If ox_lib client isn't present, this will no-op; still send chat fallback.
    TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = msg })
  end
  TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', msg } })
end

---------------------------------------
-- 5) STATE & TIME (MONOTONIC)
---------------------------------------
local running            = false
local endsAtMs           = 0
local authorizedActive   = false
local authorizedEndsMs   = 0

local function nowMs() return GetGameTimer() end
local function remainingSec() return math.max(0, math.floor((endsAtMs - nowMs()) / 1000)) end

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
-- 6) SPAM THROTTLE
---------------------------------------
local lastCmd = {}
local function tooSoon(src, key, ms)
  local t = GetGameTimer()
  local k = (src or 0) .. ':' .. key
  if lastCmd[k] and (t - lastCmd[k] < (ms or 1000)) then return true end
  lastCmd[k] = t
  return false
end

---------------------------------------
-- 7) INTERNAL START/STOP (shared by events & exports)
---------------------------------------
local function StartPITInternal(actorSrc)
  -- If ESX path requires init, allow dev override only if configured
  if CORE_MODE == 'esx' and not initESX() then
    if ALLOW_ESXLESS then
      running = true; authorizedActive = false
      endsAtMs = nowMs() + (D_COUNTDOWN * 1000)
      authorizedEndsMs = 0
      bcastStart(D_COUNTDOWN)
      return true
    else
      if actorSrc and actorSrc > 0 then notify(actorSrc, 'ESX not initialized.') end
      return false
    end
  end

  -- If actor is a player, enforce perms (if nil -> called by server/exports without actor; allow)
  if actorSrc and actorSrc > 0 then
    if tooSoon(actorSrc, 'start', 1000) then return false end
    if not isViewer(actorSrc) then notify(actorSrc, 'You must be on-duty as Police.'); return false end
    if not canControl(actorSrc) then notify(actorSrc, 'Insufficient grade to control the PIT timer.'); return false end
  end

  if running then
    bcastStart(remainingSec())
    return true
  end

  running = true
  authorizedActive = false
  endsAtMs = nowMs() + (D_COUNTDOWN * 1000)
  authorizedEndsMs = 0
  bcastStart(D_COUNTDOWN)
  return true
end

local function StopPITInternal(actorSrc)
  if CORE_MODE == 'esx' and not initESX() then
    if ALLOW_ESXLESS then
      running = false; authorizedActive = false; endsAtMs = 0; authorizedEndsMs = 0
      bcastStop()
      return true
    else
      if actorSrc and actorSrc > 0 then notify(actorSrc, 'ESX not initialized.') end
      return false
    end
  end

  if actorSrc and actorSrc > 0 then
    if tooSoon(actorSrc, 'stop', 1000) then return false end
    if not isViewer(actorSrc) then notify(actorSrc, 'You must be on-duty as Police.'); return false end
    if not canControl(actorSrc) then notify(actorSrc, 'Insufficient grade to control the PIT timer.'); return false end
  end

  running = false
  authorizedActive = false
  endsAtMs = 0
  authorizedEndsMs = 0
  bcastStop()
  return true
end

---------------------------------------
-- 8) EVENTS
---------------------------------------
RegisterNetEvent('ptping', function()
  local src = source
  if DEBUG_SERVER then print(('[pt] ping from %s'):format(src)) end
  TriggerClientEvent('pt:pong', src)
end)

RegisterNetEvent('pt:serverStart', function()
  StartPITInternal(source)
end)

RegisterNetEvent('pt:serverStop', function()
  StopPITInternal(source)
end)

RegisterNetEvent('pt:requestState', function()
  local src = source
  if CORE_MODE == 'esx' and not initESX() then return end

  if not isViewer(src) then
    return TriggerClientEvent('pt:clientStop', src)
  end

  if running then
    local r = remainingSec()
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
-- 9) WATCHDOG (monotonic)
---------------------------------------
CreateThread(function()
  while true do
    Wait(200)
    local t = nowMs()

    if running and t >= endsAtMs then
      running = false
      authorizedActive = true
      authorizedEndsMs = t + (D_AUTH * 1000)
      bcastAuthorized()
    end

    if authorizedActive and authorizedEndsMs > 0 and t >= authorizedEndsMs then
      authorizedActive = false
      authorizedEndsMs = 0
      bcastStop()
    end
  end
end)

---------------------------------------
-- 10) CLEAN SHUTDOWN
---------------------------------------
AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then
    TriggerClientEvent('pt:clientStop', -1)
  end
end)

---------------------------------------
-- 11) EXPORTS
---------------------------------------
exports('StartPIT', function(actorSrc)
  -- actorSrc optional; when provided, same permission checks apply
  return StartPITInternal(actorSrc)
end)

exports('StopPIT', function(actorSrc)
  return StopPITInternal(actorSrc)
end)

-- Init info lines
if CORE_MODE == 'esx' then
  CreateThread(function()
    for i=1,60 do if initESX() then break end Wait(250) end
    local esxReady = ESX ~= nil
    local mjName = ESX_MJ.resource or 'wasabi_multijob'
    print(('[pt] ESX=%s | %s=%s'):format(tostring(esxReady), mjName, GetResourceState(mjName)))
    if ESX_MJ.hardRequire and GetResourceState(mjName) ~= 'started' then
      print(('[pt] WARNING: %s not started (hardRequire=true) — PIT controls restricted.'):format(mjName))
    end
  end)
else
  local mjName = QBOX_MJ.resource or 'randol_multijob'
  print(('[pt] Qbox detected | %s=%s'):format(mjName, GetResourceState(mjName)))
end
