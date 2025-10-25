Config = {}

---------------------------------------------------------------------
-- 0) Locale
---------------------------------------------------------------------
Config.Locale = 'en'  -- see locales/*.lua

---------------------------------------------------------------------
-- 1) Framework & Multijob Selection
--    Core: 'esx' | 'qbox' | 'auto'  (auto = prefer qbox if present)
---------------------------------------------------------------------
Config.Core = 'qbox'

-- Integration knobs (we do not call these directly; we only enforce presence
-- if you set hardRequire=true)
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
-- 2) Roles & Permissions
---------------------------------------------------------------------
Config.Jobs = {
  viewer = { 'police' }, -- who can SEE the HUD (must be on-duty/active per framework)
}

-- Grade window (inclusive) for who can START/STOP
Config.ControlWindows = {
  police = { min = 3, max = 8 },
}

---------------------------------------------------------------------
-- 3) Durations (seconds)
--    Server can also override via convars:
--      set pt_countdown 150
--      set pt_authorized 90
---------------------------------------------------------------------
Config.Durations = {
  countdown  = 120,
  authorized = 90,
}

-- Admins (ACE: pt.admin) can optionally pass a custom duration with /startpit <sec>
-- Clamp for safety:
Config.ServerOverrideClamp = { min = 10, max = 600 }  -- 10..600 seconds

---------------------------------------------------------------------
-- 4) Commands
---------------------------------------------------------------------
Config.Commands = {
  start = 'startpit',
  stop  = 'stoppit',
}

---------------------------------------------------------------------
-- 5) Client HUD & Behavior
---------------------------------------------------------------------
Config.Client = {
  debug           = false,  -- F8 logging (or set convar: set pt_debug 1)
  idleSleepMs     = 1000,
  activeSleepMs   = 0,
  pollEnabled     = true,   -- safety poll to resync if a duty/job event is missed
  pollIntervalMs  = 300000, -- 5 min

  -- Let players adjust HUD position/scale and save to KVP (optional)
  allowHudAdjust  = false,

  hud = {
    -- If not set, fallback to locale strings
    labelPrefix     = nil,  -- e.g., 'PIT Timer: '
    authorizedText  = nil,  -- e.g., 'PIT Maneuver Authorized'

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
-- 6) Server Debug & Options
--    You can toggle debug logs live via: set pt_debug 1
---------------------------------------------------------------------
Config.Server = {
  debug               = false,            -- server console logs
  allowEsxlessTest    = false,            -- dev only: allow start if ESX not yet initialized
  targetedBroadcast   = false,            -- if true: broadcast only to viewers instead of -1
  webhook             = '',               -- Discord webhook for audit trail (leave '' to disable)
}

