# 🚓 PIT Timer (FiveM Script)

A lightweight, optimized **PIT Maneuver Timer** script for **FiveM** with full **wasabi\_multijob** integration.
Only **police** and **sheriff** officers **who are clocked in** can start or see the timer.

---

## ✨ Features

* **/startpit** – Starts a visible countdown for all on-duty Police & Sheriff officers.
* **/stoppit** – Stops and removes the timer from all officers' screens.
* **PIT Maneuver Authorized** message shows after countdown ends.
* **Auto-close after 90 seconds** if not stopped manually.
* **Job check every 5 minutes** – Ensures only on-duty police/sheriff see the timer.
* Fully **optimized** for low resource usage.

---

## 🔧 Customization (config.lua)

You can easily edit these settings:

* **Authorized jobs** (`police`, `sheriff`)
* **Minimum job grade** allowed to start the timer
* **Countdown time** in seconds
* **Authorized duration** (how long “PIT Maneuver Authorized” stays on screen before auto-closing)
* **Text labels and colors**
* **Command names** for starting/stopping the timer

---

## 📦 Installation

1. **Download & place** the script folder into your `resources` directory.
2. Open your server.cfg and **add this line**:

   ```cfg
   ensure PitTimerSynced
   ```
3. Make sure **wasabi\_multijob** is running before this script.
4. Restart your server.

---

## 🕹 Commands

| Command     | Description                                                   |
| ----------- | ------------------------------------------------------------- |
| `/startpit` | Starts PIT timer (Police/Sheriff only, on duty, correct rank) |
| `/stoppit`  | Stops PIT timer for all officers                              |

---

## 📝 Notes

* This script uses **wasabi\_multijob** callbacks to check if you’re clocked in as Police or Sheriff.
* The timer **will not show** to civilians or off-duty officers.
* If you forget to stop the PIT timer, it **auto-closes after 90 seconds** of authorization.