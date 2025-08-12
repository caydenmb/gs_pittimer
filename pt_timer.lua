-- pt_timer.lua — optimized, event-driven HUD
local ESX = exports['es_extended']:getSharedObject()

-- ===== Tunables for resource usage =====
local DEBUG           = false       -- set true if you need F8 logs
local JOB_POLL_MS     = 10000        -- how often to re-check wasabi jobs when idle
local IDLE_SLEEP_MS   = 500         -- draw loop sleep when HUD hidden
local ACTIVE_SLEEP_MS = 0           -- draw loop sleep when HUD visible (per frame)

local function log(msg) if DEBUG then print(('[pt:client] %s'):format(msg)) end end

-- ===== Lightweight logging helpers =====
local function safeRegisterEvent(name, cb)
    local ok, err = pcall(RegisterNetEvent, name)
    if ok then
        AddEventHandler(name, cb)
        log(('listening to optional event "%s"'):format(name))
    else
        -- ignore; event may not exist on this build
    end
end

-- ===== Viewer detection (ESX + wasabi) =====
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
                    if name then out[#out+1] = { name = name, grade = v.grade or v.level or v.rank } end
                end
            end
            if #out > 0 then return out end
        end
    end
    return nil
end

local function holdsViewerJobNow()
    -- Prefer wasabi (off-duty holders still count)
    local wjobs = getWasabiJobs()
    if wjobs then
        for _, j in ipairs(wjobs) do
            if j and (j.name == 'police' or j.name == 'sheriff') then
                return true
            end
        end
        return false
    end
    -- Fallback: ESX active job
    local x = ESX.GetPlayerData()
    local j = x and x.job
    return (j and (j.name == 'police' or j.name == 'sheriff')) or false
end

-- ===== HUD state (single countdown; seq cancels old loops) =====
local viewer           = false   -- can this client see HUD?
local running          = false
local remaining        = 0
local authorizedText   = false
local timerSeq         = 0       -- bump on any start/stop/authorized

-- Draw helpers (avoid repeat allocations inside the loop)
local function drawCenteredText(text, scale, r,g,b,a, x, y)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- ===== Bootstrap & viewer refresh (low frequency) =====
CreateThread(function()
    while ESX.GetPlayerData().job == nil do Wait(100) end
    viewer = holdsViewerJobNow()
    TriggerServerEvent('pt:requestState')

    -- React instantly to ESX job changes
    AddEventHandler('esx:setJob', function()
        local newViewer = holdsViewerJobNow()
        if newViewer ~= viewer then
            viewer = newViewer
            TriggerServerEvent('pt:requestState')
        end
    end)

    -- Optional: listen to some likely wasabi events if present (no-ops if missing)
    safeRegisterEvent('wasabi_multijob:jobsUpdated', function()
        local newViewer = holdsViewerJobNow()
        if newViewer ~= viewer then
            viewer = newViewer
            TriggerServerEvent('pt:requestState')
        end
    end)
    safeRegisterEvent('wasabi_multijob:clockedIn', function() TriggerServerEvent('pt:requestState') end)
    safeRegisterEvent('wasabi_multijob:clockedOut', function() TriggerServerEvent('pt:requestState') end)

    -- Fallback polling (cheap, every few seconds)
    while true do
        Wait(JOB_POLL_MS)
        local newViewer = holdsViewerJobNow()
        if newViewer ~= viewer then
            viewer = newViewer
            TriggerServerEvent('pt:requestState')
        end
    end
end)

-- ===== Commands =====
RegisterCommand('pitcver', function() if DEBUG then print('client v2.0.0 (optimized)') end end, false)

RegisterCommand('ptping', function()
    TriggerServerEvent('ptping')
end, false)

RegisterNetEvent('pt:pong', function()
    if DEBUG then print('[pt:client] PONG (server responded)') end
end)

RegisterCommand('startpit', function()
    if not viewer then
        TriggerEvent('chat:addMessage', { args = { '^1[PIT Timer]', 'You are not police or sheriff.' } })
        return
    end
    TriggerServerEvent('pt:serverStart')
end, false)

RegisterCommand('stoppit', function()
    timerSeq = timerSeq + 1
    running=false; authorizedText=false; remaining=0
    TriggerServerEvent('pt:serverStop')
end, false)

-- ===== Server -> Client =====
RegisterNetEvent('pt:clientStart', function(duration)
    if not viewer then return end
    timerSeq = timerSeq + 1
    local mySeq = timerSeq
    running = true
    authorizedText = false
    remaining = math.max(0, tonumber(duration) or 0)

    -- Countdown using real time deltas (more precise, fewer wakes if we ever change)
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
        -- Do NOT flip to authorized here; the server will broadcast pt:clientAuthorized
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
    running=false; authorizedText=false; remaining=0
end)

-- ===== Adaptive render loop =====
CreateThread(function()
    while true do
        local active = viewer and (running and remaining > 0 or authorizedText)
        if active then
            -- tight loop only while actually drawing
            if running and remaining > 0 then
                local m = math.floor(remaining / 60)
                local s = remaining % 60
                drawCenteredText(("PIT Timer: %02d:%02d"):format(m, s), 0.7, 255,255,255,255, 0.5, 0.08)
            elseif authorizedText then
                drawCenteredText("PIT Maneuver Authorized", 0.7, 0,255,0,255, 0.5, 0.08)
            end
            Wait(ACTIVE_SLEEP_MS) -- per-frame while HUD visible
        else
            -- sleep when nothing to draw
            Wait(IDLE_SLEEP_MS)
        end
    end
end)

