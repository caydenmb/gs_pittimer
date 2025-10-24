# PT – PIT Timer (ESX & Qbox)

**What it is:** A simple on-screen PIT countdown for on-duty **police**.

---

## 1) Install (server.cfg)
Put the folder in `resources` and add (only what you use):
```cfg
ensure es_extended            # ESX servers
ensure wasabi_multijob        # (optional) ESX multijob

ensure qbx_core               # Qbox servers
ensure ox_lib                 # Qbox deps (randol uses ox_lib)
ensure randol_multijob        # (optional) Qbox multijob (qbox branch)

ensure PT                     # this resource
````

> Qbox + randol users: make sure your usual qbox/randol multijob config is set up (duty toggles, primary job, etc).

---

## 2) Configure (`config.lua`) — minimal edits

```lua
-- Pick your framework (or leave 'auto')
Config.Core = 'qbox'      -- 'auto' | 'esx' | 'qbox'

-- Multijob integration (optional). If you want to *require* the multijob
-- resource to be running before /startpit works, set hardRequire = true.
Config.Integration = {
  esx = { multijob = { resource = 'wasabi_multijob', enabled = false, hardRequire = false } },
  qbox = { multijob = { resource = 'randol_multijob', enabled = true, hardRequire = false } }
}

-- Who can see/control
Config.Jobs = { viewer = { 'police' } }
Config.ControlWindows = { police = { min = 3, max = 8 } }  -- grades allowed to start/stop

-- Timings (seconds)
Config.Durations = { countdown = 120, authorized = 90 }

-- Commands
Config.Commands = { start = 'startpit', stop = 'stoppit', ping = 'ptping' }

-- Debug switches
Config.Client = { debug = false }
Config.Server = { debug = false }
```

**How “on-duty” is detected**

* **ESX**: your *active* ESX job (wasabi clock-in/out sets it).
* **Qbox**: `PlayerData.job.name == "police"` **and** `job.onduty == true` (primary job).

---

## 3) Use In-Game

* `/startpit` – start countdown (only allowed police grades can run it)
* `/stoppit`  – stop/clear
* `/ptping`   – quick debug ping

Flow: countdown → “PIT Maneuver Authorized” for `authorized` seconds → auto-clear. New joins/duty changes auto-sync.

---

## 4) Quick Troubleshooting

* **No HUD?** You must be **on-duty police** on your framework; verify `Config.Core` and that your framework resource is started.
* **Can’t /startpit?** Check your **grade window** and whether you set `hardRequire=true` for a multijob that isn’t running.
* **Still stuck?** Set `Config.Client.debug = true` and `Config.Server.debug = true`, run `/ptping`, and read console/F8 logs.