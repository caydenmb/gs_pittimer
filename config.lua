Config = {}

---------------------------------------------------------------------
-- 0) Framework & Multijob Selection
--    Core: 'esx' | 'qbox' | 'auto'  (auto = detect by running resources)
---------------------------------------------------------------------
Config.Core = 'qbox'

-- Multijob resources to be *respected* (not directly called by this script,
-- but we can enforce presence when hardRequire=true)
Config.Integration = {
  esx = {
    multijob = {
      resource    = 'wasabi_multijob',
      enabled     = false,      -- use wasabi’s active-job behavior
      hardRequire = false       -- if true: refuse controls if resource not running
    }
  },
  qbox = {
    multijob = {
      resource    = 'randol_multijob',  -- https://github.com/Randolio/randol_multijob/tree/qbox
      enabled     = true,
      hardRequire = false      -- set true if you want to *require* randol to run
    }
  }
}

---------------------------------------------------------------------
-- 1) Roles & Permissions
---------------------------------------------------------------------
-- Jobs that can SEE the HUD (must be on-duty/active per framework)
Config.Jobs = {
  viewer = { 'police' },
}

-- Grade window (inclusive) who can START/STOP (per job)
Config.ControlWindows = {
  police = { min = 3, max = 8 },  -- Sergeant..Commissioner (adjust to your role scale)
}

---------------------------------------------------------------------
-- 2) Timings (seconds)
---------------------------------------------------------------------
Config.Durations = {
  countdown  = 120,  -- main PIT countdown
  authorized = 60,   -- how long to show "Authorized" after countdown
}

---------------------------------------------------------------------
-- 3) Commands (without slash)
---------------------------------------------------------------------
Config.Commands = {
  start = 'startpit',
  stop  = 'stoppit',
  ping  = 'ptping',  -- debug helper
}

---------------------------------------------------------------------
-- 4) Client HUD & Behavior
---------------------------------------------------------------------
Config.Client = {
  debug           = true,   -- F8 logging
  idleSleepMs     = 1000,    -- sleep when HUD hidden
  activeSleepMs   = 0,       -- sleep while drawing (0 = each frame)
  pollEnabled     = true,    -- periodic job/duty safety poll
  pollIntervalMs  = 300000,  -- 5 minutes

  hud = {
    labelPrefix     = 'PIT Timer: ',
    authorizedText  = 'PIT Maneuver Authorized',
    x               = 0.5,
    y               = 0.08,
    scale           = 0.7,
    colorRunning    = {255,255,255,255},
    colorAuthorized = {  0,255,  0,255},
    font            = 4,
    outline         = true,
    center          = true,
  }
}

---------------------------------------------------------------------
-- 5) Server Debug
---------------------------------------------------------------------
Config.Server = {
  debug = false,  -- prints [pt] traces to server console
}
