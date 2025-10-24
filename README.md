# PT – PIT Timer (ESX & Qbox) — Simple README

On-screen PIT countdown for **on-duty police**  
Works on **ESX** (active job via wasabi) and **Qbox** (primary job + onduty + grade).

---

## 1) Install (server.cfg)
Start your framework first, then this resource.
```cfg
# ESX
ensure es_extended
ensure wasabi_multijob       # optional

# Qbox
ensure qbx_core
ensure ox_lib                # for randol + optional notifications
ensure randol_multijob       # optional (qbox branch)

# This resource
ensure PT

# Optional ops toggles
set pt_debug 1              # verbose logs
set pt_countdown 150        # override default countdown (sec)
set pt_authorized 60        # override "Authorized" time (sec)
````

---

## 2) Commands

* `/startpit` — start countdown (only allowed police grades). Admins with `pt.admin` may do `/startpit <seconds>` (clamped).
* `/stoppit`  — stop/clear.

Flow: **countdown → “PIT Maneuver Authorized” → auto-clear**.
Joins/duty changes auto-sync; timers are monotonic (no clock drift).

---

## 3) Config (config.lua)

```lua
-- Pick framework: 'auto' | 'esx' | 'qbox'
Config.Core = 'qbox'

-- Language (strings live in locales/)
Config.Locale = 'en'

-- Multijob integrations (set hardRequire=true to *require* the resource)
Config.Integration = {
  esx  = { multijob = { resource='wasabi_multijob',  enabled=true, hardRequire=true  } },
  qbox = { multijob = { resource='randol_multijob', enabled=true, hardRequire=false } }
}

-- Who sees HUD (must be on-duty), and who can control (grade window)
Config.Jobs = { viewer = { 'police' } }
Config.ControlWindows = { police = { min=3, max=8 } }

-- Timings (server can be overridden by convars)
Config.Durations = { countdown=120, authorized=90 }
Config.ServerOverrideClamp = { min=10, max=600 }  -- admin /startpit <sec> clamp

-- Command names
Config.Commands = { start='startpit', stop='stoppit' }

-- Client options
Config.Client = {
  debug=false,               -- or `set pt_debug 1`
  pollEnabled=true,          -- safety resync poll
  pollIntervalMs=300000,     -- 5m
  allowHudAdjust=false,      -- if true: /ptsetpos x y scale (saves via KVP)
  hud = {
    -- leave nil to use locale defaults:
    -- labelPrefix='PIT Timer: ', authorizedText='PIT Maneuver Authorized'
    x=0.5, y=0.08, scale=0.7,
    colorRunning={255,255,255,255}, colorAuthorized={0,255,0,255},
    font=4, outline=true, center=true
  }
}

-- Server options
Config.Server = {
  debug=false,               -- or `set pt_debug 1`
  allowEsxlessTest=false,    -- dev only: allow start if ESX not inited
  targetedBroadcast=false,   -- true = send updates only to viewer players
  webhook=''                 -- Discord webhook URL ('' = off)
}
```

**Duty logic:**

* **ESX** → active ESX job (wasabi clock-in/out).
* **Qbox** → `job.name == "police"` **and** `job.onduty == true` (grade enforced).

---

## 4) Admin & Integrations (optional)

```cfg
# Let admins bypass grade window + allow /startpit <seconds>
add_ace group.admin pt.admin allow
```

```lua
-- Call from other scripts
exports.PT:StartPIT(source, seconds)  -- seconds optional; clamped; ACE needed to override
exports.PT:StopPIT(source)
```

```cfg
# Discord audit trail (if you set Config.Server.webhook)
# Logs: "[PT] <name> started/stopped PIT ..."
```

```lua
-- Per-player HUD adjust (if enabled)
-- /ptsetpos <x 0..1> <y 0..1> <scale 0.3..1.5>
```

---

## 5) Quick fixes

* **No HUD?** You must be **on-duty police**; check framework started and `Config.Core`.
* **Can’t start?** Check grade window and any `hardRequire` multijob setting.
* **Logs:** `set pt_debug 1` (or set `Config.Client/Server.debug = true`).