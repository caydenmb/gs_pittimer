# PIT Timer (FiveM)

A lightweight **shared countdown timer** for authorized PIT maneuvers in **ESX-based police roleplay** servers.
Only **on-duty police and sheriff** can see the timer, and only specific ranks can start/stop it.

---

## 🚓 Features

* **Shared countdown** — everyone on-duty sees the same timer.
* **Role & rank restrictions** — only certain grades of police/sheriff can start/stop.
* **HUD display** —

  * Countdown format: `PIT Timer: mm:ss`
  * After time runs out → shows **PIT Maneuver Authorized** for 90 seconds.
  * Auto-clears after 90 seconds if not manually stopped.
* **Clocked-in only** — requires being on-duty as `police` or `sheriff`.
* **Lightweight & optimized** — sleeps when not active, minimal performance impact.

---

## ⚙️ Commands

| Command     | Description                                             |
| ----------- | ------------------------------------------------------- |
| `/startpit` | Starts the PIT countdown (restricted to allowed ranks). |
| `/stoppit`  | Stops the PIT timer for everyone.                       |
| `/ptping`   | (Optional) Tests connection to the server script.       |

---

## 🛠️ Installation

1. **Download** or copy the resource folder to your FiveM server's `resources` directory.
2. **Ensure dependencies are installed:**

   * ESX (any current build).
3. Add the resource to your `server.cfg`:

   ```cfg
   ensure PitTimerSynced
   ```
4. Restart your server or run:

   ```
   refresh
   ensure PitTimerSynced
   ```

---

## 🔧 Customization

Open **`server.lua`** and edit the **"EASY CUSTOMIZATION"** section:

* **Control Ranks**:

  ```lua
  local CONTROL_WINDOWS = {
      police  = { min = 3, max = 8 },  -- Allowed police ranks
      sheriff = { min = 3, max = 6 },  -- Allowed sheriff ranks
  }
  ```
* **Timer Duration**:

  ```lua
  local DEFAULT_DURATION = 120  -- seconds
  ```
* **Authorized Text Duration**:

  ```lua
  local AUTHORIZED_AUTO_CLEAR = 90  -- seconds after "Authorized" before auto-clear
  ```

Open **`pt_timer.lua`** for HUD tweaks:

* Text position, size, and colors.
* How often the job status is re-checked (`JOB_STATUS_POLL_MS`).

---

## 📋 Notes

* Works with **ESX** and **wasabi\_multijob** for clocked-in detection.
* Very low resource usage (event-driven design.)
* Tested with police grades 3–8 and sheriff grades 3–6 by default.