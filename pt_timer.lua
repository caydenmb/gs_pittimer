---------------------------------------
-- 0) IMPORT ESX
---------------------------------------
local ESX = exports['es_extended']:getSharedObject()

---------------------------------------
-- 1) EASY CUSTOMIZATION (EDIT THESE)
---------------------------------------
-- Debug output in F8 (false in production)
local DEBUG                 = false

-- Drawing cadence:
-- • When HUD is visible, we paint every frame (ACTIVE_SLEEP_MS = 0)
-- • When HUD is hidden, we sleep to save CPU (IDLE_SLEEP_MS)
local IDLE_SLEEP_MS         = 1000     -- ms to sleep when nothing is drawn
local ACTIVE_SLEEP_MS       = 0       -- ms to sleep between frames while drawing

-- Safety net: periodically re-check the player's active job even if we
-- didn't receive an 'esx:setJob' event (framework hiccup protection).
local ENABLE_JOB_STATUS_POLL= true
local JOB_STATUS_POLL_MS    = 300000  -- 5 minutes

local function log(msg) if DEBUG then print(('[pt:client] %s'):format(msg)) end end

---------------------------------------
-- 2) VIEWER CHECK (CLOCKED-IN ONLY)
---------------------------------------
-- Return true if the local player is actively clocked in as police/sheriff.
local function isViewerNow()
    local pdata = ESX.GetPlayerData()
    local job = pdata and pdata.job
    local name = job and job.name
    return name == 'police' or name == 'sheriff'
end

---------------------------------------
-- 3) CLIENT HUD STATE
---------------------------------------
local viewer         = false  -- can we see the HUD right now?
local running        = false  -- counting down?
local remaining      = 0      -- seconds left (client copy)
local authorizedText = false  -- showing "PIT Maneuver Authorized"?
local timerSeq       = 0      -- cancel token; any new start/stop bumps this

---------------------------------------
-- 4) DRAW HELPERS
---------------------------------------
-- Draw centered text at a given screen point.
-- x ∈ [0,1] left→right ; y ∈ [0,1] top→bottom
local function drawCenteredText(text, scale, r,g,b,a, x, y)
    SetTextFont(4)                 -- 4 = clean GTA font
    SetTextProportional(1)
    SetTextScale(scale, scale)     -- text size (0.7 looks good for top-center)
    SetTextColour(r, g, b, a)      -- RGBA
    SetTextOutline()
    SetTextCentre(true)            -- horizontal center
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)                 -- (0.5, 0.08) = center / upper region
end

---------------------------------------
-- 5) BOOTSTRAP (wait for ESX, wire job change)
---------------------------------------
CreateThread(function()
    -- Wait until ESX has loaded a job into PlayerData
    while ESX.GetPlayerData().job == nil do Wait(100) end

    -- Initial viewer flag + state sync
    viewer = isViewerNow()
    TriggerServerEvent('pt:requestState')

    -- React immediately to clock in/out (ESX fires this when active job changes)
    AddEventHandler('esx:setJob', function()
        local newViewer = isViewerNow()
        if newViewer ~= viewer then
            viewer = newViewer
            TriggerServerEvent('pt:requestState')  -- server pushes current state
        end
    end)

    -- Safety net: periodic job status poll (helps if an event is missed)
    if ENABLE_JOB_STATUS_POLL then
        CreateThread(function()
            while true do
                Wait(JOB_STATUS_POLL_MS)
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
-- 6) COMMANDS (client → server)
---------------------------------------
-- Start: gated by viewer status (must be on-duty police/sheriff)
RegisterCommand('startpit', function()
    if not viewer then
        TriggerEvent('chat:addMessage', { args = { '^1[PIT Timer]', 'You must be clocked in as police or sheriff.' } })
        return
    end
    TriggerServerEvent('pt:serverStart')
end, false)

-- Stop: clear locally immediately; server will broadcast to everyone
RegisterCommand('stoppit', function()
    timerSeq = timerSeq + 1
    running = false; authorizedText = false; remaining = 0
    TriggerServerEvent('pt:serverStop')
end, false)

-- Optional ping (handy to confirm server events are flowing)
RegisterCommand('ptping', function()
    TriggerServerEvent('ptping')
end, false)
RegisterNetEvent('pt:pong', function()
    if DEBUG then print('[pt:client] PONG (server responded)') end
end)

---------------------------------------
-- 7) SERVER → CLIENT EVENTS
---------------------------------------
-- Begin the shared countdown for all viewers.
RegisterNetEvent('pt:clientStart', function(duration)
    if not viewer then return end   -- ignore if we are not a viewer
    timerSeq = timerSeq + 1
    local mySeq = timerSeq

    running = true
    authorizedText = false
    remaining = math.max(0, tonumber(duration) or 0)

    -- Single precise countdown using GetGameTimer (less drift than Wait(1000))
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
        -- Do NOT flip to Authorized here; the server will tell us explicitly.
    end)
end)

-- Switch to persistent "PIT Maneuver Authorized" until /stoppit or auto-clear
RegisterNetEvent('pt:clientAuthorized', function()
    timerSeq = timerSeq + 1
    running = false
    authorizedText = true
    remaining = 0
end)

-- Clear everything
RegisterNetEvent('pt:clientStop', function()
    timerSeq = timerSeq + 1
    running = false
    authorizedText = false
    remaining = 0
end)

---------------------------------------
-- 8) ADAPTIVE RENDER LOOP
---------------------------------------
-- Paint only when there's something to paint; otherwise, sleep.
CreateThread(function()
    while true do
        local active = viewer and ((running and remaining > 0) or authorizedText)

        if active then
            if running and remaining > 0 then
                local m = math.floor(remaining / 60)
                local s = remaining % 60
                drawCenteredText(("PIT Timer: %02d:%02d"):format(m, s), 0.7, 255,255,255,255, 0.5, 0.08)
            elseif authorizedText then
                drawCenteredText("PIT Maneuver Authorized", 0.7, 0,255,0,255, 0.5, 0.08)
            end
            Wait(ACTIVE_SLEEP_MS)  -- typically 0 to draw every frame
        else
            Wait(IDLE_SLEEP_MS)    -- sleep while idle to save CPU
        end
    end
end)
