# PIT Timer (FiveM • ESX • wasabi\_multijob)

A dead-simple, server-authoritative **on-screen PIT timer** for ESX servers.
Shows a shared countdown to all **police** and **sheriff** players, enforces rank-gated control, and after expiry displays **“PIT Maneuver Authorized”** (auto-clears after 90s in case someone forgets to stop it).

No vehicle actions. No handling changes. **HUD only.**

---

## ✨ Features

* **Shared HUD:** One timer for everyone in `police` or `sheriff` to see.
* **Rank-gated control:**

  * `police`: grades **3–8** (Sergeant → Commissioner) can start/stop
  * `sheriff`: grades **3–6** (Sergeant → Commissioner) can start/stop
* **Server-authoritative:** Prevents double timers and keeps everyone in sync.
* **Persistent authorization:** When time hits 0, shows **“PIT Maneuver Authorized”** until stopped.
* **Auto-clear fail-safe:** After **90s** of authorization, auto-stops globally (as if `/stoppit`).
* **Job menu aware:** **wasabi\_multijob** support — off duty? If you **hold** police/sheriff in your job menu, you still **see** the HUD. (Control still respects grade limits.)
* **Late join sync:** New or reconnecting cops get the correct state immediately.
* **Top-center HUD:** Clean, readable text in the upper middle of the screen.
* **Loud diagnostics:** Clear server & client logs; `/ptping` to confirm networking.

---

## 📦 Requirements

* [`es_extended`](https://github.com/esx-framework/esx-legacy) (required)
* [`wasabi_multijob`](https://wasabiscripts.com/) (optional but supported)
* FiveM fxserver (cerulean)

---

## 📁 Files

```
PitTimerSynced/
├─ fxmanifest.lua
├─ server.lua            # server authority: permissions, broadcasts, auto-clear
├─ pt_timer.lua          # client HUD + viewer detection (ESX/wasabi)
└─ config.lua            # (optional) legacy client config; safe to keep
```

> The resource folder name (e.g., `PT`) must match what you `ensure` in your server config.

---

## 🚀 Installation

1. Drag the folder (e.g., `PT`) into your server resources.
2. Ensure order in `server.cfg`:

   ```cfg
   ensure es_extended
   ensure wasabi_multijob   # optional; keep if you use it
   ensure PT                # must match the folder name exactly
   ```
3. Start/Restart the resource and check the server console for:

   ```
   [pt] **SERVER LOADED** resource=PT
   ```

---

## 🎮 Commands (in-game)

* `/startpit` — Start (or rebroadcast) the shared timer

  * **Allowed:** `police` grades **3–8**, `sheriff` grades **3–6**
* `/stoppit` — Stop/clear HUD for everyone

  * Same permission rules as above
* `/ptping` — Client ↔ server ping (debug)
* `/pittest` — Client-side 5s self-test display (debug; local only)
* `/pittestserver` — Server-side 15s test broadcast (debug; ignores permissions)
* `/pitcver` — Print client version (debug)

---

## 👮 Visibility & Permissions

* **Who sees the HUD?**
  Anyone who **holds** `police` or `sheriff` (wasabi menu) or **is actively** on those jobs (ESX fallback).
* **Who can control?**

  * `police`: grades **3–8**
  * `sheriff`: grades **3–6**

> Using **wasabi\_multijob**: being off duty is fine for **visibility**; **control** still requires the right grade in any held entry.

---

## ⚙️ Customization

All customization is in **`server.lua`** and **`pt_timer.lua`**.

### Timings (server.lua)

```lua
local DEFAULT_DURATION      = 120  -- seconds; countdown time
local AUTHORIZED_AUTO_CLEAR = 90   -- seconds to keep "PIT Maneuver Authorized" before auto-stop
```

### Grades (server.lua)

```lua
local CONTROL_WINDOWS = {
    police  = {min=3, max=8},
    sheriff = {min=3, max=6},
}
```

### Which jobs see the HUD (server.lua)

```lua
local VIEWABLE = { police=true, sheriff=true }
```

### HUD text & position (pt\_timer.lua)

* The running label uses **“PIT Timer:”**
  Change the string here if you want:

  ```lua
  AddTextComponentString("PIT Timer: "..t)
  ```
* Position (top-center):

  ```lua
  DrawText(0.5, 0.08)   -- x (0.5 = center), y (0.08 = near top)
  ```

  Lower/higher: tweak the **y** value (`0.06` = higher; `0.10` = lower).
* Size / style:

  ```lua
  SetTextFont(4)
  SetTextScale(0.7, 0.7)
  SetTextColour(255,255,255,255)   -- running
  -- Authorized:
  SetTextColour(0,255,0,255)
  ```

### Debug logging (pt\_timer.lua)

```lua
local DEBUG = true  -- set to false to silence F8 spam
```

---

## 🔌 Events (for devs)

**Server → Clients**

* `pt:clientStart (duration:number)` — Begin/rebroadcast a running timer for all viewers
* `pt:clientStop` — Clear HUD for everyone
* `pt:clientAuthorized` — Show **“PIT Maneuver Authorized”** (persists until stop)

**Clients → Server**

* `pt:serverStart` — Request to start (permission-checked)
* `pt:serverStop` — Request to stop (permission-checked)
* `pt:requestState` — Ask for current state (used on join/job change)
* `ptping` — Ping the server (debug)

**Server → Client (debug)**

* `pt:pong` — Pong reply to confirm networking

---

## 🧠 How it works

1. A controller runs `/startpit`. The server validates their **job & grade**.
2. If allowed, the server broadcasts `pt:clientStart` with the remaining time (or default).
3. Clients who are **viewers** (police/sheriff via ESX/wasabi) show the HUD and count down locally.
4. When time is up, the server broadcasts `pt:clientAuthorized` and starts a **90s** auto-clear timer.
5. After 90s (or `/stoppit`), the server broadcasts `pt:clientStop`, clearing HUD for everyone.

---

## 🧪 Troubleshooting

* **“HUD is local only / server didn’t respond.”**
  The server file isn’t loading or events aren’t reaching it. Check:

  * Server console shows `**SERVER LOADED** resource=PT` on start.
  * `fxmanifest.lua` includes:

    ```lua
    server_scripts { 'server.lua' }
    ```
  * `ensure PT` matches the **exact** folder name (case-sensitive on some hosts).
* **Timer runs fast (2×).**
  You’re likely starting locally and via broadcast. This build is server-authoritative (single source) with a guard to prevent double loops.
* **Not seeing HUD off duty (with wasabi).**
  Make sure `wasabi_multijob` is running *before* `PT` and you actually **hold** the job in your wasabi menu.

---

## 🗂️ Example `fxmanifest.lua`

```lua
shared_script "@ReaperV4/bypass.lua"
lua54 "yes"

fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Mr.kujo934'
description 'On-screen PIT timer (police/sheriff)'

client_scripts {
    'config.lua',
    'pt_timer.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'es_extended'
}
```

---

## 🧾 Example `server.cfg`

```cfg
# order matters
ensure es_extended
ensure wasabi_multijob   # if you use it
ensure PT                # must match the resource folder name
```

---

## ❓ FAQ

* **Does this modify vehicles or driving?**
  No. It’s a HUD-only tool.

* **Can I change who sees/controls it?**
  Yes — edit `VIEWABLE` and `CONTROL_WINDOWS` in `server.lua`.

* **Can I change the timer length or auto-clear time?**
  Yep — `DEFAULT_DURATION` & `AUTHORIZED_AUTO_CLEAR` in `server.lua`.

* **Can I move the text?**
  Change the `DrawText(0.5, 0.08)` Y value and/or `SetTextScale`.

* **Does it require wasabi\_multijob?**
  No — it works with vanilla ESX. With wasabi, viewers include off-duty holders in the job menu.