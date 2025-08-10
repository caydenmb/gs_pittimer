local RESOURCE = GetCurrentResourceName()
local ESX = exports['es_extended']:getSharedObject()

local DEBUG = false
local function log(msg) if DEBUG then print(('[pt:client] %s'):format(msg)) end end

AddEventHandler('onClientResourceStart', function(res)
    if res == RESOURCE then
        log(('resource start: %s'):format(res))
        log('Commands: /startpit /stoppit | tests: /pitcver /ptping')
    end
end)

-- ==== Wasabi viewer detection (safe) ====
local function wasabiRunning()
    local st = GetResourceState and GetResourceState('wasabi_multijob') or 'missing'
    return st == 'started'
end

local function tryWasabiExport(fnName)
    return pcall(function()
        return exports['wasabi_multijob'][fnName]()
    end)
end

local function getWasabiJobs()
    if not wasabiRunning() then return nil end
    local candidates = {
        'getPlayerJobs','GetPlayerJobs',
        'getJobs','GetJobs',
        'getAllJobs','GetAllJobs',
        'getPlayerData','GetPlayerData',
    }
    for _, fn in ipairs(candidates) do
        local ok, res = tryWasabiExport(fn)
        if ok and res and type(res) == 'table' then
            local out = {}
            if res[1] ~= nil then
                for _, v in pairs(res) do
                    out[#out+1] = { name = v.name or v.job or v.id or v[1], grade = v.grade or v.level or v.rank or v[2] }
                end
            else
                for k, v in pairs(res) do
                    local name  = (type(k) == 'string' and k) or v.name or v.job
                    local grade = v.grade or v.level or v.rank
                    if name then out[#out+1] = { name = name, grade = grade } end
                end
            end
            if #out > 0 then return out end
        end
    end
    return nil
end

local function isViewerNow()
    local wjobs = getWasabiJobs()
    if wjobs then
        for _, j in ipairs(wjobs) do
            if j and (j.name == 'police' or j.name == 'sheriff') then
                return true
            end
        end
        return false
    end
    local x = ESX.GetPlayerData()
    local j = x and x.job
    return (j and (j.name == 'police' or j.name == 'sheriff')) or false
end

-- ==== HUD state (single loop via timerSeq) ====
local viewer = false
local running, remaining, authorizedText = false, 0, false
local timerSeq = 0  -- bump to cancel older loops

-- Bootstrap viewer + keep it fresh (wasabi menu can change)
CreateThread(function()
    log('waiting for ESX job...')
    while ESX.GetPlayerData().job == nil do Wait(100) end
    viewer = isViewerNow()
    log(('viewer initial -> %s'):format(tostring(viewer)))
    TriggerServerEvent('pt:requestState')
    while true do
        local v = isViewerNow()
        if v ~= viewer then
            viewer = v
            log(('viewer change -> %s'):format(tostring(viewer)))
            TriggerServerEvent('pt:requestState')
        end
        Wait(2000)
    end
end)

-- Version
RegisterCommand('pitcver', function() log('client alive; v1.8.0 (authorized persists)') end, false)

-- Ping
RegisterNetEvent('pt:pong', function()
    log('PONG (server responded).')
    TriggerEvent('chat:addMessage', { args = { '^2[PIT Timer]', 'PONG (server responded)' } })
end)
RegisterCommand('ptping', function()
    log('sending PING')
    TriggerServerEvent('ptping')
end, false)

-- Commands: server-authoritative start; local stop clears immediately
RegisterCommand('startpit', function()
    log('cmd /startpit -> pt:serverStart')
    if not viewer then
        TriggerEvent('chat:addMessage', { args = { '^1[PIT Timer]', 'You are not police or sheriff.' } })
        return
    end
    TriggerServerEvent('pt:serverStart')
end, false)

RegisterCommand('stoppit', function()
    log('cmd /stoppit -> local clear + pt:serverStop')
    timerSeq = timerSeq + 1
    running=false; authorizedText=false; remaining=0
    TriggerServerEvent('pt:serverStop')
end, false)

-- ===== Server -> Client =====
RegisterNetEvent('pt:clientStart', function(duration)
    log(('recv pt:clientStart %s (viewer=%s)'):format(tostring(duration), tostring(viewer)))
    if not viewer then return end
    timerSeq = timerSeq + 1
    local mySeq = timerSeq
    running=true; authorizedText=false; remaining=math.max(0, tonumber(duration) or 0)
    CreateThread(function()
        while timerSeq == mySeq and running and remaining>0 do
            Wait(1000)
            remaining = remaining - 1
        end
        if timerSeq == mySeq and running and remaining<=0 then
            -- We let the SERVER tell us it's authorized to persist (next event),
            -- so we don't flip here. Running will be reset by server's authorized broadcast.
            log('local loop reached zero; awaiting server authorization event')
        end
    end)
end)

-- Natural expiry sync from server: keep "PIT Maneuver Authorized" until /stoppit
RegisterNetEvent('pt:clientAuthorized', function()
    log('recv pt:clientAuthorized')
    timerSeq = timerSeq + 1
    running = false
    authorizedText = true
    remaining = 0
end)

RegisterNetEvent('pt:clientStop', function()
    log('recv pt:clientStop')
    timerSeq = timerSeq + 1
    running=false; authorizedText=false; remaining=0
end)

-- ===== Draw loop (upper middle) =====
CreateThread(function()
    while true do
        Wait(0)
        if viewer then
            if running and remaining>0 then
                local m = math.floor(remaining/60)
                local s = remaining%60
                local t = string.format("%02d:%02d", m, s)
                SetTextFont(4); SetTextProportional(1); SetTextScale(0.7,0.7)
                SetTextColour(255,255,255,255); SetTextOutline(); SetTextCentre(true)
                SetTextEntry("STRING"); AddTextComponentString("PIT Timer: "..t) -- <== label updated
                DrawText(0.5, 0.08)
            elseif authorizedText then
                SetTextFont(4); SetTextProportional(1); SetTextScale(0.7,0.7)
                SetTextColour(0,255,0,255); SetTextOutline(); SetTextCentre(true)
                SetTextEntry("STRING"); AddTextComponentString("PIT Maneuver Authorized")
                DrawText(0.5, 0.08)
            end
        end
    end
end)
