# PT – PIT Timer (ESX & Qbox)

**What it does:** Simple on-screen PIT countdown for on-duty **police**.

---

## 1) Install (server.cfg)
Start your framework first, then this resource. Add only what you use.
```cfg
# ESX
ensure es_extended
ensure wasabi_multijob        # optional

# Qbox
ensure qbx_core
ensure ox_lib                 
ensure randol_multijob        # optional (qbox branch)

# This resource
ensure PT

# (Optional) enable debug without editing files
set pt_debug 1
````

---

## 2) Configure (config.lua)

```lua
Config.Core = 'qbox'  -- 'auto' | 'esx' | 'qbox'

Config.Integration = {
  esx  = { multijob = { resource='wasabi_multijob',  enabled=true, hardRequire=true  } },
  qbox = { multijob = { resource='randol_multijob', enabled=true, hardRequire=false } }
}

Config.Jobs = { viewer = { 'police' } }                 -- who can SEE (on-duty only)
Config.ControlWindows = { police = { min=3, max=8 } }   -- who can START/STOP

Config.Durations = { countdown=120, authorized=90 }     -- seconds
Config.Commands  = { start='startpit', stop='stoppit' }

Config.Client = { debug=false }                         -- or set pt_debug 1
Config.Server = { debug=false, allowEsxlessTest=false } -- dev shortcut for ESX init
```

**Duty logic:**

* **ESX** = active ESX job (wasabi clock-in/out).
* **Qbox** = `job.name == "police"` **and** `job.onduty == true` (grade enforced).

---

## 3) Use In-Game

* `/startpit` – start the countdown (allowed police grades only)
* `/stoppit`  – stop/clear

Flow: **countdown → “PIT Maneuver Authorized” → auto-clear**.
Joins/duty changes auto-sync. Timers are monotonic (no drift from system clock).

---

## 4) Admin

```cfg
# Let admins bypass grade window
add_ace group.admin pt.admin allow
```

```lua
-- Call from other scripts
exports.PT:StartPIT(source)  -- optional source to enforce checks
exports.PT:StopPIT(source)
```

---

## 5) Quick Fixes

* **No HUD?** Be **on-duty police** and confirm your framework is started.
* **Can’t start?** Check grade window and any `hardRequire` multijob setting.

* **Logs:** set `pt_debug 1` (or flip `Config.Client/Server.debug = true`) and run `/ptping`.


