-- server.lua — optimized watchdogs + optional logging
local DEBUG_SERVER = false
local function slog(msg) if DEBUG_SERVER then print(('[pt] %s'):format(msg)) end end

print(('[pt] **SERVER LOADED** resource=%s'):format(GetCurrentResourceName()))

-- ===== Config =====
local CONTROL_WINDOWS = {
    police  = {min=3, max=8},
    sheriff = {min=3, max=6},
}
local VIEWABLE = { police=true, sheriff=true }
local DEFAULT_DURATION      = 120
local AUTHORIZED_AUTO_CLEAR = 90

-- ===== ESX init =====
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
    print(ESX and '[pt] ESX ready' or '[pt] ESX NOT ready (we still run tests)')
end)

-- ===== wasabi helpers (safe) =====
local function wasabiRunning()
    local st = GetResourceState and GetResourceState('wasabi_multijob') or 'missing'
    return st == 'started'
end
local function tryWasabiExport(fnName, src)
    return pcall(function()
        if src ~= nil then return exports['wasabi_multijob'][fnName](src) end
        return exports['wasabi_multijob'][fnName]()
    end)
end
local function getWasabiJobs(src)
    if not wasabiRunning() then return nil end
    local candidates = {'getPlayerJobs','GetPlayerJobs','getJobs','GetJobs','getAllJobs','GetAllJobs','getPlayerData','GetPlayerData'}
    for _, fn in ipairs(candidates) do
        local ok, res = tryWasabiExport(fn, src)
        if ok and res and type(res) == 'table' then
            local out = {}
            if res[1] ~= nil then
                for _, v in pairs(res) do
                    out[#out+1] = { name = v.name or v.job or v.id or v[1], grade = v.grade or v.level or v.rank or v[2] }
                end
            else
                for k, v in pairs(res) do
                    local name  = (type(k) == 'string' and k) or v.name or v.job
                    if name then out[#out+1] = { name = name, grade = v.grade or v.level or v.rank } end
                end
            end
            if #out > 0 then return out end
        end
    end
    return nil
end
local function getESXActiveJob(src)
    if not ESX then return nil end
    local x = ESX.GetPlayerFromId(src)
    if not x or not x.job then return nil end
    return { { name = x.job.name, grade = x.job.grade } }
end
local function getAllPlayerJobs(src)
    local jobs = getWasabiJobs(src)
    if jobs then slog(('using WASABI jobs for %s'):format(src)) return jobs end
    local ej = getESXActiveJob(src); slog(('using ESX active job for %s'):format(src))
    return ej or {}
end
local function holdsViewerJob(src)
    for _, j in ipairs(getAllPlayerJobs(src)) do if j and VIEWABLE[j.name] then return true end end
    return false
end
local function holdsControllingJob(src)
    for _, j in ipairs(getAllPlayerJobs(src)) do
        local name = j and j.name
        local g = tonumber(j and j.grade) or 0
        local win = CONTROL_WINDOWS[name]
        if win and g >= win.min and g <= win.max then return true, name, g end
    end
    return false, nil, nil
end
local function reply(src, msg) TriggerClientEvent('chat:addMessage', src, { args = { '^2[PIT Timer]', msg or '' } }) end

-- ===== State =====
local running            = false
local endsAt             = 0
local authorizedActive   = false
local authorizedEndsAt   = 0

local function remaining() return math.max(0, endsAt - os.time()) end

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

-- ===== Ping =====
RegisterNetEvent('ptping', function()
    local src = source
    if DEBUG_SERVER then print(('[pt] ping from %s'):format(src)) end
    TriggerClientEvent('pt:pong', src)
end)

-- ===== Start / Stop =====
RegisterNetEvent('pt:serverStart', function()
    local src = source
    slog(('serverStart from %s'):format(src))

    if not initESX() then
        running=true; authorizedActive=false; endsAt=os.time()+DEFAULT_DURATION; authorizedEndsAt=0
        TriggerClientEvent('pt:startAck', src, true, nil)
        return bcastStart(DEFAULT_DURATION)
    end

    if not holdsViewerJob(src) then
        TriggerClientEvent('pt:startAck', src, false, 'Must be police or sheriff to use.')
        return reply(src, 'Must be police or sheriff to use.')
    end

    local ok = holdsControllingJob(src)
    if not ok then
        local msg = 'Control requires police 3–8 or sheriff 3–6.'
        TriggerClientEvent('pt:startAck', src, false, msg)
        return reply(src, msg)
    end

    if running then
        TriggerClientEvent('pt:startAck', src, true, nil)
        return bcastStart(remaining())
    end

    running=true
    authorizedActive=false
    endsAt=os.time()+DEFAULT_DURATION
    authorizedEndsAt=0
    TriggerClientEvent('pt:startAck', src, true, nil)
    bcastStart(DEFAULT_DURATION)
end)

RegisterNetEvent('pt:serverStop', function()
    local src = source
    slog(('serverStop from %s'):format(src))

    if not initESX() then
        running=false; authorizedActive=false; endsAt=0; authorizedEndsAt=0
        TriggerClientEvent('pt:stopAck', src, true, nil)
        return bcastStop()
    end

    if not holdsViewerJob(src) then
        TriggerClientEvent('pt:stopAck', src, false, 'Must be police or sheriff to use.')
        return reply(src, 'Must be police or sheriff to use.')
    end

    local ok = holdsControllingJob(src)
    if not ok then
        local msg = 'Control requires police 3–8 or sheriff 3–6.'
        TriggerClientEvent('pt:stopAck', src, false, msg)
        return reply(src, msg)
    end

    running=false
    authorizedActive=false
    endsAt=0
    authorizedEndsAt=0
    TriggerClientEvent('pt:stopAck', src, true, nil)
    bcastStop()
end)

-- ===== Sync =====
RegisterNetEvent('pt:requestState', function()
    local src = source
    if not initESX() then return end
    if not holdsViewerJob(src) then return TriggerClientEvent('pt:clientStop', src) end

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

-- ===== Watchdog (1s tick) =====
CreateThread(function()
    while true do
        Wait(1000) -- 1s resolution is enough for a seconds timer
        local now = os.time()

        if running and now >= endsAt then
            running=false
            authorizedActive=true
            authorizedEndsAt = now + AUTHORIZED_AUTO_CLEAR
            bcastAuthorized()
        end

        if authorizedActive and authorizedEndsAt > 0 and now >= authorizedEndsAt then
            authorizedActive=false
            authorizedEndsAt=0
            bcastStop()
        end
    end
end)

-- ===== Server test =====
RegisterCommand('pittestserver', function(src)
    running=true; authorizedActive=false; endsAt=os.time()+15; authorizedEndsAt=0
    bcastStart(15)
end, true)
