Config = Config or {}

---------------------------------------
-- 0) CONFIG & RUNTIME
---------------------------------------
local C           = Config.Client or {}
local HUD         = C.hud or {}
local DEBUG       = C.debug or false
local IDLE_MS     = C.idleSleepMs or 1000
local ACTIVE_MS   = C.activeSleepMs or 0
local POLL_ON     = (C.pollEnabled ~= false)
local POLL_MS     = C.pollIntervalMs or 300000
local ALLOW_ADJ   = (C.allowHudAdjust == true)

local CMD_START   = (Config.Commands and Config.Commands.start) or 'startpit'
local CMD_STOP    = (Config.Commands and Config.Commands.stop ) or 'stoppit'

-- Localized fallbacks for HUD copy (config wins if set)
local LABEL_PREFIX    = HUD.labelPrefix or _L('hud_label_prefix')
local AUTH_TEXT       = HUD.authorizedText or _L('hud_authorized_text')

-- Allow runtime debug via convar (client-side)
CreateThread(function()
  local cv = GetConvarInt and GetConvarInt('pt_debug', -1) or -1
  if cv == 1 then
    DEBUG = true
    print('[pt:client] Debug enabled by convar pt_debug=1')
  end
end)

local CORE_MODE   = (Config.Core or 'auto')
local ESX_READY   = GetResourceState('es_extended') == 'started'
local QBOX_READY  = GetResourceState('qbx_core') == 'started'

if CORE_MODE == 'auto' then
  if QBOX_READY then CORE_MODE = 'qbox'
  elseif ESX_READY then CORE_MODE = 'esx'
  else CORE_MODE = 'esx' end
end

local function log(msg) if DEBUG then print(('[pt:client][%s] %s'):format(CORE_MODE, msg)) end end

-- Job whitelist (viewer)
local VIEWER_SET = {}
do
  local list = (Config.Jobs and Config.Jobs.viewer) or {'police'}
  for _, name in ipairs(list) do VIEWER_SET[name] = true end
end

---------------------------------------
-- 1) FRAMEWORK ADAPTER (client)
---------------------------------------
local ESX
local QBCore -- some Qbox stacks keep qb-core compat

-- Qbox cached state
local qbx_primaryJob = nil
local qbx_gradeLevel = 0
local qbx_onDuty     = false

local function initESX()
  if ESX or CORE_MODE ~= 'esx' then return end
  local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
  if ok and obj then ESX = obj end
  if not ESX then
    TriggerEvent('esx:getSharedObject', function(o) ESX = o end)
  end
end

-- ESX: active job (wasabi toggles this via clock in/out)
local function esxIsViewerNow()
  if not ESX then return false end
  local pdata = ESX.GetPlayerData()
  local job = pdata and pdata.job
  return job and VIEWER_SET[job.name] or false
end

-- Qbox: primary job + onduty + grade
local function qboxIsViewerNow()
  if not qbx_primaryJob then
    if GetResourceState('qb-core') == 'started' then
      QBCore = exports['qb-core']:GetCoreObject()
    end
    if QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData then
      local ok, pd = pcall(QBCore.Functions.GetPlayerData)
      if ok and type(pd) == 'table' and pd.job then
        qbx_primaryJob = pd.job.name
        qbx_onDuty     = not not pd.job.onduty
        qbx_gradeLevel = (pd.job.grade and (pd.job.grade.level or pd.job.grade)) or 0
      end
    end
  end
  return (qbx_primaryJob and VIEWER_SET[qbx_primaryJob] and qbx_onDuty) or false
end

---------------------------------------
-- 2) CLIENT HUD STATE
---------------------------------------
local viewer         = false
local running        = false
local remaining      = 0
local authorizedText = false
local timerSeq       = 0   -- cancellation token

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
-- 4) BOOTSTRAP
---------------------------------------
CreateThread(function()
  -- Chat suggestions (cheap UX)
  TriggerEvent('chat:addSuggestion', '/' .. CMD_START, _L('cmd_start_desc'))
  TriggerEvent('chat:addSuggestion', '/' .. CMD_STOP,  _L('cmd_stop_desc'))

  if CORE_MODE == 'esx' then
    initESX()
    while ESX and ESX.GetPlayerData().job == nil do Wait(100) end
    viewer = esxIsViewerNow()
  else
    viewer = qboxIsViewerNow()
    -- Qbox event wires (QB-compatible)
    RegisterNetEvent('QBCore:Client:SetDuty', function(onDuty)
      qbx_onDuty = not not onDuty
      local newViewer = qboxIsViewerNow()
      if newViewer ~= viewer then
        viewer = newViewer
        TriggerServerEvent('pt:requestState')
        log(('SetDuty=%s -> resync'):format(tostring(onDuty)))
      end
    end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
      if type(job) == 'table' then
        qbx_primaryJob = job.name
        qbx_onDuty     = not not job.onduty
        qbx_gradeLevel = (job.grade and (job.grade.level or job.grade)) or 0
        local newViewer = qboxIsViewerNow()
        if newViewer ~= viewer then
          viewer = newViewer
          TriggerServerEvent('pt:requestState')
          log(('OnJobUpdate %s (duty=%s, grade=%s)'):format(qbx_primaryJob, tostring(qbx_onDuty), tostring(qbx_gradeLevel)))
        end
      end
    end)
  end

  TriggerServerEvent('pt:requestState')

  -- ESX job change
  if CORE_MODE == 'esx' then
    AddEventHandler('esx:setJob', function()
      local newViewer = esxIsViewerNow()
      if newViewer ~= viewer then
        viewer = newViewer
        TriggerServerEvent('pt:requestState')
        log('esx:setJob -> resync')
      end
    end)
  end

  -- Safety poll
  if POLL_ON then
    CreateThread(function()
      while true do
        Wait(POLL_MS)
        local newViewer = (CORE_MODE == 'esx') and esxIsViewerNow() or qboxIsViewerNow()
        if newViewer ~= viewer then
          viewer = newViewer
          TriggerServerEvent('pt:requestState')
          log('Poll -> resync')
        end
      end
    end)
  end
end)

---------------------------------------
-- 5) OPTIONAL: Per-player HUD adjust with persistence
---------------------------------------
if ALLOW_ADJ then
  -- Load saved KVP once
  CreateThread(function()
    local x = GetResourceKvpString('pt_hud_x')
    local y = GetResourceKvpString('pt_hud_y')
    local s = GetResourceKvpString('pt_hud_scale')
    if x then HUD.x = tonumber(x) or HUD.x end
    if y then HUD.y = tonumber(y) or HUD.y end
    if s then HUD.scale = tonumber(s) or HUD.scale end
  end)

  RegisterCommand('ptsetpos', function(_, args)
    local x = tonumber(args[1]); local y = tonumber(args[2]); local sc = tonumber(args[3])
    if x then HUD.x = math.max(0.0, math.min(1.0, x)) end
    if y then HUD.y = math.max(0.0, math.min(1.0, y)) end
    if sc then HUD.scale = math.max(0.3, math.min(1.5, sc)) end
    SetResourceKvp('pt_hud_x', tostring(HUD.x))
    SetResourceKvp('pt_hud_y', tostring(HUD.y))
    SetResourceKvp('pt_hud_scale', tostring(HUD.scale))
    TriggerEvent('chat:addMessage', { args = { '^2[PIT Timer]', _L('hud_set_msg', HUD.x, HUD.y, HUD.scale) } })
  end, false)
end

---------------------------------------
-- 6) COMMANDS (client → server)
---------------------------------------
RegisterCommand(CMD_START, function(_, args)
  if not viewer then
    TriggerEvent('chat:addMessage', { args = { '^1[PIT Timer]', _L('err_must_be_on_duty') } })
    return
  end
  -- Optional: admins can pass a custom duration; server decides if allowed
  local sec = tonumber(args[1])
  TriggerServerEvent('pt:serverStart', sec)
end, false)

RegisterCommand(CMD_STOP, function()
  -- IMPORTANT: do NOT clear local state here; wait for server broadcast.
  TriggerServerEvent('pt:serverStop')
end, false)

---------------------------------------
-- 7) SERVER → CLIENT EVENTS
---------------------------------------
RegisterNetEvent('pt:clientStart', function(duration)
  if not viewer then return end
  timerSeq = timerSeq + 1
  local mySeq = timerSeq

  running = true
  authorizedText = false
  remaining = math.max(0, tonumber(duration) or 0)

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
-- 8) GLOBALSTATE MIRROR
---------------------------------------
AddStateBagChangeHandler('PT', nil, function(bagName, key, value)
  if bagName ~= 'global' or type(value) ~= 'table' then return end
  if not viewer then return end
  -- Apply server-published state to local HUD
  local now = GetGameTimer()
  running        = value.running and (value.endsAtMs or 0) > now
  authorizedText = value.authorized and (value.authorizedEndsMs or 0) > now
  if running then
    remaining = math.max(0, math.floor(((value.endsAtMs or now) - now) / 1000))
  else
    remaining = 0
  end
end)

---------------------------------------
-- 9) RENDER LOOP
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
          (tostring(LABEL_PREFIX))..(("%02d:%02d"):format(m, s)),
          HUD.scale, cr[1],cr[2],cr[3],cr[4], HUD.x, HUD.y, HUD.font, HUD.outline, HUD.center
        )
      elseif authorizedText then
        drawCenteredText(
          tostring(AUTH_TEXT),
          HUD.scale, ca[1],ca[2],ca[3],ca[4], HUD.x, HUD.y, HUD.font, HUD.outline, HUD.center
        )
      end
      Wait(ACTIVE_MS)
    else
      Wait(IDLE_MS)
    end
  end
end)
