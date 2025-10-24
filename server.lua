Config = Config or {}

---------------------------------------
-- 0) LOGGING & DETECTION
---------------------------------------
local DEBUG_SERVER = (Config.Server and Config.Server.debug) or false
local function slog(msg) if DEBUG_SERVER then print(('[pt] %s'):format(msg)) end end
local function L(key, ...) return _L and _L(key, ...) or key end

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
local QB_FALLBACK = (GetResourceState('qb-core') == 'started') and not QBOX_READY

if CORE_MODE == 'auto' then
  if QBOX_READY then CORE_MODE = 'qbox'
  elseif ESX_READY then CORE_MODE = 'esx'
  else CORE_MODE = 'esx' end
end

print(('[pt] SERVER LOADED | core=%s esx=%s qbox=%s qbcoreFallback=%s')
  :format(CORE_MODE, tostring(ESX_READY), tostring(QBOX_READY), tostring(QB_FALLBACK)))

---------------------------------------
-- 1) CONFIG SHORTHANDS
---------------------------------------
local CONTROL_WINDOWS  = Config.ControlWindows or { police = { min = 3, max = 8 } }
local ESX_MJ           = Config.Integration and Config.Integration.esx  and Config.Integration.esx.multijob  or {}
local QBOX_MJ          = Config.Integration and Config.Integration.qbox and Config.Integration.qbox.multijob or {}
local ALLOW_ESXLESS    = Config.Server and Config.Server.allowEsxlessTest or false
local TARGETED_CAST    = Config.Server and Config.Server.targetedBroadcast or false
local WEBHOOK_URL      = Config.Server and Config.Server.webhook or ''

-- Durations (authoritative)
local D_COUNTDOWN      = (Config.Durations and Config.Durations.countdown)  or 120
local D_AUTH           = (Config.Durations and Config.Durations.authorized) or 90

-- Convars can override durations (ops friendly)
do
  local cvCountdown = GetConvarInt('pt_countdown', -1)
  local cvAuth      = GetConvarInt('pt_authorized', -1)
  if cvCountdown and cvCountdown > 0 then D_COUNTDOWN = cvCountdown end
  if cvAuth and cvAuth > 0 then D_AUTH = cvAuth end
end

-- Admin override clamp
local OV_MIN = (Config.ServerOverrideClamp and Config.ServerOverrideClamp.min) or 10
local OV_MAX = (Config.ServerOverrideClamp and Config.ServerOverrideClamp.max) or 600

-- Viewer jobs (police only)
local VIEWER_SET = {}
do
  local list = (Config.Jobs and Config.Jobs.viewer) or {'police'}
  for _, name in ipairs(list) do VIEWER_SET[name] = true end
end

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

-- Qbox / qb-core fallback
local function qbCoreGetPrimaryJob(src)
  if not QB_FALLBACK then return nil end
  local ok, qb = pcall(function() return exports['qb-core']:GetCoreObject() end)
  if not ok or not qb or not qb.Functions or not qb.Functions.GetPlayer then return nil end
  local ply = qb.Functions.GetPlayer(src)
  if not ply or not ply.PlayerData or not ply.PlayerData.job then return nil end
  return ply.PlayerData.job
end

local function qboxGetPrimaryJob(src)
  if QBOX_READY then
    local qb = exports.qbx_core:GetPlayer(src)
    if qb and qb.PlayerData and qb.PlayerData.job then return qb.PlayerData.job end
  end
  -- fallback if user forced 'qbox' mode but only qb-core is present
  return qbCoreGetPrimaryJob(src)
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
local function notify(src, msgKey)
  local msg = L(msgKey)
  if GetResourceState('ox_lib') == 'started' then
    TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = msg })
  end
  TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', msg } })
end

---------------------------------------
-- 5) STATE & TIME (MONOTONIC) + GLOBALSTATE
---------------------------------------
local running            = false
local endsAtMs           = 0
local authorizedActive   = false
local authorizedEndsMs   = 0

local function nowMs() return GetGameTimer() end
local function remainingSec() return math.max(0, math.floor((endsAtMs - nowMs()) / 1000)) end

local function publishState()
  GlobalState.PT = {
    running          = running,
    endsAtMs         = endsAtMs,
    authorized       = authorizedActive,
    authorizedEndsMs = authorizedEndsMs
  }
  slog(('publishState running=%s endsAt=%s auth=%s authEnds=%s')
    :format(tostring(running), tostring(endsAtMs), tostring(authorizedActive), tostring(authorizedEndsMs)))
end

-- Broadcast helpers
local function forEachViewerDo(cb)
  if not cb then return end
  for _, id in ipairs(GetPlayers()) do
    id = tonumber(id)
    if isViewer(id) then cb(id) end
  end
end

local function bcastStart(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or D_COUNTDOWN))
  slog(('broadcast START -> %ds (targeted=%s)'):format(seconds, tostring(TARGETED_CAST)))
  if TARGETED_CAST then
    forEachViewerDo(function(id) TriggerClientEvent('pt:clientStart', id, seconds) end)
  else
    TriggerClientEvent('pt:clientStart', -1, seconds)
  end
end

local function bcastStop()
  slog(('broadcast STOP (targeted=%s)'):format(tostring(TARGETED_CAST)))
  if TARGETED_CAST then
    forEachViewerDo(function(id) TriggerClientEvent('pt:clientStop', id) end)
  else
    TriggerClientEvent('pt:clientStop', -1)
  end
end

local function bcastAuthorized()
  slog(('broadcast AUTHORIZED (targeted=%s)'):format(tostring(TARGETED_CAST)))
  if TARGETED_CAST then
    forEachViewerDo(function(id) TriggerClientEvent('pt:clientAuthorized', id) end)
  else
    TriggerClientEvent('pt:clientAuthorized', -1)
  end
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
-- 7) DISCORD WEBHOOK
---------------------------------------
local function postWebhook(msg)
  if not WEBHOOK_URL or WEBHOOK_URL == '' then return end
  PerformHttpRequest(WEBHOOK_URL, function() end, 'POST',
    json.encode({ content = msg }),
    { ['Content-Type'] = 'application/json' }
  )
end

---------------------------------------
-- 8) INTERNAL START/STOP (shared by events & exports)
---------------------------------------
local function StartPITInternal(actorSrc, overrideSeconds)
  -- If ESX path requires init, allow dev override only if configured
  if CORE_MODE == 'esx' and not initESX() then
    if ALLOW_ESXLESS then
      running = true; authorizedActive = false
      endsAtMs = nowMs() + (D_COUNTDOWN * 1000)
      authorizedEndsMs = 0
      publishState()
      bcastStart(D_COUNTDOWN)
      return true
    else
      if actorSrc and actorSrc > 0 then notify(actorSrc, 'err_esx_not_inited') end
      return false
    end
  end

  -- If actor is a player, enforce perms; allow nil actor (console/other script)
  if actorSrc and actorSrc > 0 then
    if tooSoon(actorSrc, 'start', 1000) then return false end
    if not isViewer(actorSrc) then notify(actorSrc, 'err_must_be_on_duty'); return false end
    if not canControl(actorSrc) then notify(actorSrc, 'err_insufficient');  return false end
  end

  if running then
    bcastStart(remainingSec())
    return true
  end

  -- Allow ACE override for custom seconds
  local seconds = D_COUNTDOWN
  if actorSrc and actorSrc > 0 and overrideSeconds and hasAce(actorSrc, 'pt.admin') then
    seconds = math.max(OV_MIN, math.min(OV_MAX, math.floor(overrideSeconds)))
  end

  running = true
  authorizedActive = false
  endsAtMs = nowMs() + (seconds * 1000)
  authorizedEndsMs = 0
  publishState()
  bcastStart(seconds)

  -- Audit trail
  local who = (actorSrc and GetPlayerName(actorSrc)) or 'console/script'
  postWebhook(('[PT] %s started PIT (%ds) [core=%s]'):format(who, seconds, CORE_MODE))
  return true
end

local function StopPITInternal(actorSrc)
  if CORE_MODE == 'esx' and not initESX() then
    if ALLOW_ESXLESS then
      running = false; authorizedActive = false; endsAtMs = 0; authorizedEndsMs = 0
      publishState()
      bcastStop()
      return true
    else
      if actorSrc and actorSrc > 0 then notify(actorSrc, 'err_esx_not_inited') end
      return false
    end
  end

  if actorSrc and actorSrc > 0 then
    if tooSoon(actorSrc, 'stop', 1000) then return false end
    if not isViewer(actorSrc) then notify(actorSrc, 'err_must_be_on_duty'); return false end
    if not canControl(actorSrc) then notify(actorSrc, 'err_insufficient');  return false end
  end

  running = false
  authorizedActive = false
  endsAtMs = 0
  authorizedEndsMs = 0
  publishState()
  bcastStop()

  local who = (actorSrc and GetPlayerName(actorSrc)) or 'console/script'
  postWebhook(('[PT] %s stopped PIT [core=%s]'):format(who, CORE_MODE))
  return true
end

---------------------------------------
-- 9) EVENTS
---------------------------------------
-- Client requests
RegisterNetEvent('pt:serverStart', function(seconds)
  local src = source
  local sec = tonumber(seconds)
  StartPITInternal(src, sec)  -- server clamps + ACE check
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
-- 10) WATCHDOG (monotonic)
---------------------------------------
CreateThread(function()
  while true do
    Wait(200)
    local t = nowMs()

    if running and t >= endsAtMs then
      running = false
      authorizedActive = true
      authorizedEndsMs = t + (D_AUTH * 1000)
      publishState()
      bcastAuthorized()
    end

    if authorizedActive and authorizedEndsMs > 0 and t >= authorizedEndsMs then
      authorizedActive = false
      authorizedEndsMs = 0
      publishState()
      bcastStop()
    end
  end
end)

---------------------------------------
-- 11) CLEAN SHUTDOWN
---------------------------------------
AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then
    running = false
    authorizedActive = false
    endsAtMs = 0
    authorizedEndsMs = 0
    publishState()
    TriggerClientEvent('pt:clientStop', -1)
  end
end)

---------------------------------------
-- 12) EXPORTS
---------------------------------------
exports('StartPIT', function(actorSrc, seconds)
  -- actorSrc optional; when provided, same permission checks apply
  return StartPITInternal(actorSrc, seconds)
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
    publishState() -- publish initial state once ESX is settled
  end)
else
  local mjName = QBOX_MJ.resource or 'randol_multijob'
  print(('[pt] Qbox detected | %s=%s'):format(mjName, GetResourceState(mjName)))
  publishState() -- publish early for Qbox path
end
