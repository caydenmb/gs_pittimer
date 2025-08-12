---------------------------------------
-- 0) DEBUG / LOGGING SWITCH
---------------------------------------
local DEBUG_SERVER = false
local function slog(msg) if DEBUG_SERVER then print(('[pt] %s'):format(msg)) end end

-- Loud banner so you know the server file loaded
print(('[pt] **SERVER LOADED** resource=%s'):format(GetCurrentResourceName()))

---------------------------------------
-- 1) EASY CUSTOMIZATION (EDIT THESE)
---------------------------------------
-- Who can start/stop (by job & grade window)
local CONTROL_WINDOWS = {
    police  = { min = 3, max = 8 },   -- Sergeant .. Commissioner
    sheriff = { min = 3, max = 6 },   -- Sergeant .. Commissioner
}

-- How long the main countdown runs (in seconds)
local DEFAULT_DURATION      = 120

-- After countdown ends, how long to keep "PIT Maneuver Authorized" (seconds)
-- before automatically clearing the HUD (as if /stoppit was issued)
local AUTHORIZED_AUTO_CLEAR = 90

---------------------------------------
-- 2) ESX BOOTSTRAP
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
    for i = 1, 60 do if initESX() then break end Wait(250) end
    print(ESX and '[pt] ESX ready' or '[pt] ESX NOT ready (ping still works)')
end)

---------------------------------------
-- 3) PERMISSION HELPERS (CLOCKED-IN ONLY)
---------------------------------------
local function getActiveJob(src)
    if not ESX then return nil end
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.job or nil
end

-- View = on-duty police/sheriff
local function isViewer(src)
    local j = getActiveJob(src)
    return j and (j.name == 'police' or j.name == 'sheriff') or false
end

-- Control = on-duty + within grade window
local function canControl(src)
    local j = getActiveJob(src); if not j then return false end
    local win = CONTROL_WINDOWS[j.name]; if not win then return false end
    local g = tonumber(j.grade) or 0
    return g >= win.min and g <= win.max
end

local function reply(src, msg)
    TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', msg or '' } })
end

---------------------------------------
-- 4) AUTHORITATIVE STATE
---------------------------------------
local running            = false   -- true while countdown is ticking
local endsAt             = 0       -- Unix epoch when countdown ends
local authorizedActive   = false   -- true while showing "Authorized"
local authorizedEndsAt   = 0       -- Unix epoch when to auto-clear

local function remaining() return math.max(0, endsAt - os.time()) end

-- Broadcast helpers
local function bcastStart(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or DEFAULT_DURATION))
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
-- 5) OPTIONAL PING (handy for diagnostics)
---------------------------------------
RegisterNetEvent('ptping', function()
    if DEBUG_SERVER then print(('[pt] ping from %s'):format(source)) end
    TriggerClientEvent('pt:pong', source)
end)

---------------------------------------
-- 6) START / STOP HANDLERS
---------------------------------------
RegisterNetEvent('pt:serverStart', function()
    local src = source
    slog(('serverStart from %s'):format(src))

    if not initESX() then
        -- ESX missing: allow testing
        running = true; authorizedActive = false; endsAt = os.time() + DEFAULT_DURATION; authorizedEndsAt = 0
        TriggerClientEvent('pt:startAck', src, true, nil)
        return bcastStart(DEFAULT_DURATION)
    end

    if not isViewer(src) then
        TriggerClientEvent('pt:startAck', src, false, 'You must be clocked in as police or sheriff.')
        return reply(src, 'You must be clocked in as police or sheriff.')
    end

    if not canControl(src) then
        local msg = 'Control requires (on-duty) police 3–8 or sheriff 3–6.'
        TriggerClientEvent('pt:startAck', src, false, msg)
        return reply(src, msg)
    end

    if running then
        TriggerClientEvent('pt:startAck', src, true, nil)
        return bcastStart(remaining())  -- re-sync everyone
    end

    running = true
    authorizedActive = false
    endsAt = os.time() + DEFAULT_DURATION
    authorizedEndsAt = 0
    TriggerClientEvent('pt:startAck', src, true, nil)
    bcastStart(DEFAULT_DURATION)
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
        TriggerClientEvent('pt:stopAck', src, false, 'You must be clocked in as police or sheriff.')
        return reply(src, 'You must be clocked in as police or sheriff.')
    end

    if not canControl(src) then
        local msg = 'Control requires (on-duty) police 3–8 or sheriff 3–6.'
        TriggerClientEvent('pt:stopAck', src, false, msg)
        return reply(src, msg)
    end

    running = false
    authorizedActive = false
    endsAt = 0
    authorizedEndsAt = 0
    TriggerClientEvent('pt:stopAck', src, true, nil)
    bcastStop()
end)

---------------------------------------
-- 7) STATE SYNC (for joiners / job changes)
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
-- 8) WATCHDOG (1s resolution: expiry & auto-clear)
---------------------------------------
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()

        -- Countdown finished → switch to AUTHORIZED mode
        if running and now >= endsAt then
            running = false
            authorizedActive = true
            authorizedEndsAt = now + AUTHORIZED_AUTO_CLEAR
            bcastAuthorized()
        end

        -- AUTHORIZED long enough → auto-clear (like /stoppit)
        if authorizedActive and authorizedEndsAt > 0 and now >= authorizedEndsAt then
            authorizedActive = false
            authorizedEndsAt = 0
            bcastStop()
        end
    end
end)
