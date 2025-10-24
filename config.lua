Config = {}

---------------------------------------------------------------------
-- 0) Framework & Multijob Selection
--    Core: 'esx' | 'qbox' | 'auto'  (auto = prefer qbox if found)
---------------------------------------------------------------------
Config.Core = 'qbox'

-- Integration knobs (we don't call these directly; we only enforce presence
-- if you set hardRequire=true).
Config.Integration = {
  esx = {
    multijob = {
      resource    = 'wasabi_multijob',
      enabled     = false,
      hardRequire = false
    }
  },
  qbox = {
    multijob = {
      resource    = 'randol_multijob',  -- qbox branch
      enabled     = true,
      hardRequire = false
    }
  }
}

---------------------------------------------------------------------
-- 1) Roles & Permissions
---------------------------------------------------------------------
Config.Jobs = {
  viewer = { 'police' }, -- who can SEE the HUD (must be on-duty/active)
}

-- Grade window (inclusive) for who can START/STOP
Config.ControlWindows = {
  police = { min = 3, max = 8 },
}

---------------------------------------------------------------------
-- 2) Durations (seconds)
---------------------------------------------------------------------
Config.Durations = {
  countdown  = 120,
  authorized = 90,
}

---------------------------------------------------------------------
-- 3) Commands
---------------------------------------------------------------------
Config.Commands = {
  start = 'startpit',
  stop  = 'stoppit',
}

---------------------------------------------------------------------
-- 4) Client HUD & Behavior
---------------------------------------------------------------------
Config.Client = {
  debug           = false,  -- F8 logging (can also toggle via convar: set pt_debug 1)
  idleSleepMs     = 1000,
  activeSleepMs   = 0,
  pollEnabled     = true,
  pollIntervalMs  = 300000, -- 5 minutes

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
-- 5) Server Debug & Safety
---------------------------------------------------------------------
Config.Server = {
  debug = false,              -- server console logs (also toggle via: set pt_debug 1)
  allowEsxlessTest = false,   -- if true: allow /startpit even if ESX not yet initted (dev only)
}

