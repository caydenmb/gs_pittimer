Config = {}

---------------------------------------------------------------------
-- 1) Integrations
---------------------------------------------------------------------
Config.Integration = {
  wasabi = {
    enabled = true,              -- Keep true. I use ESX active job set by wasabi.
    resource = 'wasabi_multijob',
    hardRequire = true,         -- true = refuse to run if wasabi is not started
                                 -- false = still works with plain ESX if wasabi is missing
  }
}

---------------------------------------------------------------------
-- 2) Roles & Permissions
---------------------------------------------------------------------
-- Jobs that can SEE the HUD (must be clocked-in on these via wasabi)
Config.Jobs = {
  viewer = { 'police', 'sheriff' },
}

-- Grade windows (inclusive) who can START/STOP
-- Tip: adjust per your ranking scheme.
Config.ControlWindows = {
  police  = { min = 3, max = 8 },    -- Sergeant .. Commissioner
  sheriff = { min = 3, max = 6 },    -- Sergeant .. Commissioner
}

---------------------------------------------------------------------
-- 3) Timings (seconds)
---------------------------------------------------------------------
Config.Durations = {
  countdown  = 120,   -- main PIT countdown
  authorized = 90,    -- keep "PIT Maneuver Authorized" before auto-clear
}

---------------------------------------------------------------------
-- 4) Commands (without the slash)
---------------------------------------------------------------------
Config.Commands = {
  start = 'startpit',   -- /startpit
  stop  = 'stoppit',    -- /stoppit
  ping  = 'ptping',     -- /ptping (debug helper)
}

---------------------------------------------------------------------
-- 5) Client HUD & Performance
---------------------------------------------------------------------
Config.Client = {
  debug           = false,     -- F8 logging
  idleSleepMs     = 1000,       -- sleep when HUD hidden (higher = lighter)
  activeSleepMs   = 0,         -- sleep while drawing (0 = every frame)
  pollEnabled     = true,      -- periodic job-status re-check (safety net)
  pollIntervalMs  = 300000,    -- 5 minutes

  hud = {
    labelPrefix     = 'PIT Timer: ',           -- label in front of mm:ss
    authorizedText  = 'PIT Maneuver Authorized',
    x               = 0.5,     -- 0.5 = centered horizontally
    y               = 0.08,    -- closer to top = smaller number
    scale           = 0.7,     -- 0.6–0.8 recommended
    colorRunning    = {255,255,255,255},  -- RGBA while counting
    colorAuthorized = {  0,255,  0,255},  -- RGBA when authorized
    font            = 4,       -- GTA font index
    outline         = true,    -- add outline
    center          = true,    -- text centered horizontally
  }
}

---------------------------------------------------------------------
-- 6) Server Debug
---------------------------------------------------------------------
Config.Server = {
  debug = false,  -- server console debug logs
}
