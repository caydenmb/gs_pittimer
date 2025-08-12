# PIT Timer for FiveM

A lightweight, **optimized** FiveM resource for managing PIT maneuver timers for **Police** and **Sheriff** roles.
Shows a countdown to all authorized viewers, automatically switches to **"PIT Maneuver Authorized"** when time runs out, and clears itself after 90 seconds.

---

## 📦 Features

* **Two-way sync** – all eligible players see the same timer.
* **Role + grade restrictions** (police 3–8, sheriff 3–6 by default).
* Works with **ESX** and **wasabi\_multijob** (off-duty still counts).
* **Optimized for performance** – minimal CPU usage when idle.
* `/startpit` and `/stoppit` commands.
* Auto-switch to `"PIT Maneuver Authorized"` when time expires.
* Auto-clear after 90 seconds if forgotten.
* Simple config for customization.

---

## ⚙️ Customization

In **`pt_timer.lua` (client)**:

```lua
DEBUG           = false   -- Client debug logs
JOB_POLL_MS     = 10000    -- How often to re-check jobs (ms)
IDLE_SLEEP_MS   = 500     -- Sleep when HUD hidden
ACTIVE_SLEEP_MS = 0       -- Sleep when HUD visible
```

In **`server.lua`**:

```lua
DEBUG_SERVER         = false   -- Server debug logs
CONTROL_WINDOWS = {
    police  = {min=3, max=8},  -- Allowed police grades
    sheriff = {min=3, max=6},  -- Allowed sheriff grades
}
DEFAULT_DURATION      = 120    -- PIT timer length (seconds)
AUTHORIZED_AUTO_CLEAR = 90     -- Time after "Authorized" to auto-stop (seconds)
```

---

## 📋 Commands

| Command     | Description                               |
| ----------- | ----------------------------------------- |
| `/startpit` | Start the PIT timer (requires rank & job) |
| `/stoppit`  | Stop the PIT timer early                  |
| `/ptping`   | Test ping to server                       |
| `/pittest`  | Local test of HUD (for debug only)        |

---

## 🚀 Installation

1. Place the **PitTimerSynced** folder in your `resources` directory.
2. Add to your **server.cfg**:

   ```
   ensure PitTimerSynced
   ```
3. Edit **`server.lua`** / **`pt_timer.lua`** to your desired settings.
4. Restart the server.

---

## 📝 Notes

* Supports both **ESX** and **wasabi\_multijob** without extra config.
* Automatically handles server-client sync on join.

