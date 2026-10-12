# 🏀 Street Hoops

A competitive **1v1 street basketball** game for Roblox. You challenge other players on outdoor courts with a timing-based shot meter. The server decides scoring, possession and results.

This is a standalone project. It isn't connected to any other game.

---

## Contents

1. [What's in this version](#whats-in-this-version)
2. [Controls](#controls)
3. [Build it in Roblox Studio from scratch](#build-it-in-roblox-studio-from-scratch)
4. [Test it](#test-it)
5. [Tuning](#tuning)
6. [Troubleshooting](#troubleshooting)
7. [How it works](#how-it-works)
8. [Roadmap](#roadmap)
9. [Updating your copy](#updating-your-copy)

---

## What's in this version

**Phase 3, the first playable prototype**

- **Street park:** grass, a concrete plaza, trees, benches, floodlights, a STREET HOOPS entrance arch and a sunset lighting setup. It's all built by script when the server starts.
- **One 1v1 half court:** painted floor, key, three-point line with corners, a glass backboard, a physical rim (the ball can bounce off it), a net, a fence and a live status sign.
- **Queue pads:** stand on the blue **HOME** or red **AWAY** pad. When both are taken, the match starts after 2 seconds. You can step off or press **LEAVE** at any time. While a court is in a game its pads show **IN GAME**, and anyone who walks onto the court is moved off.
- **Ball possession:** walk into a loose ball to pick it up. Only one player can hold it at a time, and the server decides who has it.
- **Timed shooting:** hold the shoot button and release when the meter is in the green. The release decides the shot: early means short, late means long or off the glass, and perfect almost always goes in. A defender standing in front of you lowers your chances.
- **Scoring:** 2 points inside the arc, 3 outside (configurable). Every basket is checked on the server and counted once, for the right player.
- **Match flow:** 3-2-1 countdown, 4-minute clock, first to 15.
  - **Overtime:** a tie when time runs out goes to "next basket wins". Overtime ends in a draw after 2 minutes.
  - **Buzzer beaters:** a shot already in the air when time runs out still counts.
  - **20-second shot clock:** you can't stall with the ball. It resets on a change of possession or when a shot hits the rim or glass. Grabbing your own airball doesn't reset it.
  - **Check ball:** after every score or turnover, both players are reset to their spots.
  - **Out of bounds:** a ball or ball carrier that goes out is a turnover.
  - **Results screen:** shown at the end, then both players go back to the lobby.
- **Leaving and resetting:** leaving the game or pressing **LEAVE MATCH** twice forfeits. Resetting your character is a turnover, and play waits up to 15 seconds for you to respawn. A shot already in the air still lands and counts. Resetting more than 3 times in one match forfeits it.
- **No shots from behind the backboard:** the glass is in the way, so the shot is refused.
- **Practice mode:** when a court has no match, anyone can shoot around with its ball. No points count.
- **HUD:** scoreboard with a possession dot, shot clock, shot meter, queue panel, banners, toasts, results and context hints. Works on **PC, phone and controller**.

Progression (wins, losses, points and currency saved with DataStores) and the extra moves are planned for Phase 5. See the [Roadmap](#roadmap).

## Controls

| Action | Keyboard | Controller | Phone |
|---|---|---|---|
| Move / jump | WASD / Space | Left stick / A (✕) | Thumbstick / jump button |
| Pick up the ball | Walk into it | Walk into it | Walk into it |
| Shoot (hold, release in the green) | **E** | **R2** (or X / □) | **SHOOT** button |
| Leave the queue | Backspace or the LEAVE button | B (○) | LEAVE button |
| Leave the match (press twice) | LEAVE MATCH button | D-pad down | LEAVE MATCH button |

---

## Build it in Roblox Studio from scratch

This takes about 15 minutes. You create **2 folders and 19 scripts** and paste the code from the [`scripts/`](scripts) folder into each one. Rojo and plugins aren't needed.

### Step 1: Create a new, empty place

1. Open **Roblox Studio** and click **New**, then choose the **Baseplate** template.
2. Click **File → Save to Roblox As…**, name it **Street Hoops** and choose **Create new experience**.

### Step 2: Delete the template's baseplate and spawn

In the **Explorer**, under **Workspace**, right-click and **Delete** these two items:

- `Baseplate`
- `SpawnLocation`

Why: the game builds its own ground, park and lobby spawn when the server starts. The template versions would overlap them and spawn players in the wrong place. If you forget, the Output window prints a warning.

> The park and court appear **when you press Play**. In edit mode the Workspace is empty. That's normal.

### Step 3 (optional): Better lighting

Select **Lighting** in the Explorer and set **Technology** to **Future** in Properties. Scripts can't change this setting. It gives the floodlights real shadows. The game works either way.

### Step 4: Create the folders and scripts

How to add an object: hover over the parent in the Explorer, click **⊕**, and type the class name (`Folder`, `Script`, `LocalScript` or `ModuleScript`). To rename it, select it and press **F2**. **Names must match exactly**, including capital letters.

| # | Where to create it | Name | Type | Code file |
|---|---|---|---|---|
| — | ReplicatedStorage | `Shared` | Folder | — |
| 1 | ReplicatedStorage › Shared | `Config` | ModuleScript | [`01_Shared_Config.luau`](scripts/01_Shared_Config.luau) |
| 2 | ReplicatedStorage › Shared | `Signal` | ModuleScript | [`02_Shared_Signal.luau`](scripts/02_Shared_Signal.luau) |
| 3 | ReplicatedStorage › Shared | `Net` | ModuleScript | [`03_Shared_Net.luau`](scripts/03_Shared_Net.luau) |
| 4 | ReplicatedStorage › Shared | `BasketballMath` | ModuleScript | [`04_Shared_BasketballMath.luau`](scripts/04_Shared_BasketballMath.luau) |
| — | ServerScriptService | `Server` | Folder | — |
| 5 | ServerScriptService › Server | `Main` | **Script** | [`05_Server_Main.luau`](scripts/05_Server_Main.luau) |
| 6 | ServerScriptService › Server | `CharacterService` | ModuleScript | [`06_Server_CharacterService.luau`](scripts/06_Server_CharacterService.luau) |
| 7 | ServerScriptService › Server | `RemoteGuard` | ModuleScript | [`07_Server_RemoteGuard.luau`](scripts/07_Server_RemoteGuard.luau) |
| 8 | ServerScriptService › Server | `CourtBuilder` | ModuleScript | [`08_Server_CourtBuilder.luau`](scripts/08_Server_CourtBuilder.luau) |
| 9 | ServerScriptService › Server | `BallService` | ModuleScript | [`09_Server_BallService.luau`](scripts/09_Server_BallService.luau) |
| 10 | ServerScriptService › Server | `MatchService` | ModuleScript | [`10_Server_MatchService.luau`](scripts/10_Server_MatchService.luau) |
| 11 | ServerScriptService › Server | `QueueService` | ModuleScript | [`11_Server_QueueService.luau`](scripts/11_Server_QueueService.luau) |
| 12 | ServerScriptService › Server | `ShotService` | ModuleScript | [`12_Server_ShotService.luau`](scripts/12_Server_ShotService.luau) |
| 13 | StarterPlayer › StarterPlayerScripts | `ClientMain` | **LocalScript** | [`13_Client_ClientMain.luau`](scripts/13_Client_ClientMain.luau) |
| 14 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `UIKit` | ModuleScript | [`14_Client_UIKit.luau`](scripts/14_Client_UIKit.luau) |
| 15 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `MatchClient` | ModuleScript | [`15_Client_MatchClient.luau`](scripts/15_Client_MatchClient.luau) |
| 16 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `ShotMeter` | ModuleScript | [`16_Client_ShotMeter.luau`](scripts/16_Client_ShotMeter.luau) |
| 17 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `ShootController` | ModuleScript | [`17_Client_ShootController.luau`](scripts/17_Client_ShootController.luau) |
| 18 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `BallVisuals` | ModuleScript | [`18_Client_BallVisuals.luau`](scripts/18_Client_BallVisuals.luau) |
| 19 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `Hud` | ModuleScript | [`19_Client_Hud.luau`](scripts/19_Client_Hud.luau) |

⚠️ Scripts **14–19 go inside the `ClientMain` LocalScript**. Hover over `ClientMain` itself and click ⊕. Don't add them to StarterPlayerScripts.

When you're done, the Explorer should look like this:

```
ReplicatedStorage
└─ Shared
   ├─ BasketballMath
   ├─ Config
   ├─ Net
   └─ Signal
ServerScriptService
└─ Server
   ├─ BallService
   ├─ CharacterService
   ├─ CourtBuilder
   ├─ Main            ← Script
   ├─ MatchService
   ├─ QueueService
   ├─ RemoteGuard
   └─ ShotService
StarterPlayer
└─ StarterPlayerScripts
   └─ ClientMain      ← LocalScript
      ├─ BallVisuals
      ├─ Hud
      ├─ MatchClient
      ├─ ShootController
      ├─ ShotMeter
      └─ UIKit
```

### Step 5: Paste the code

Do this for each script in the table:

1. Click its **Code file** link in the table above, then click the **Copy raw file** button (two overlapping squares, at the top right of the code).
2. In Studio, double-click the script to open it, press **Ctrl+A** to select the starter text (`local module = {}` or `print("Hello world!")`), and press **Ctrl+V**.

Check each paste: line 2 of every file says where it belongs, for example:
`-- Config (ModuleScript) — ReplicatedStorage > Shared > Config`. If that doesn't match where you pasted it, it's the wrong file.

### Step 6: Save

Click **File → Save to Roblox** (Ctrl+S).

---

## Test it

### Solo (practice)

1. Press **Play** (F5) and open **View → Output**. You should see `[Main] Street Hoops server ready — 1 court(s)` and **no red errors**.
2. Walk through the arch toward the court and pick up the orange ball on the free-throw line.
3. **Hold E**. A meter appears beside your character, and your player jumps. **Release when the white bar is in the green band.**
4. Made shots show `+2 BUCKET! (practice)` or `+3 SPLASH! (practice)`.

### Two players (a real 1v1)

1. Go to the **Test** tab. In **Clients and Servers**, set the dropdown to **2 Players** and click **Start**. A server window and two player windows open.
2. In **Player1's** window, walk onto the blue **HOME** pad. In **Player2's** window, walk onto the red **AWAY** pad.
3. After about 2 seconds both players are moved onto the court, frozen in place for the **3-2-1** countdown. One player, chosen at random, starts with the ball.
4. What to check:
   - [ ] The scoreboard shows both names, the scores, the game clock, "FIRST TO 15" and the **SHOT** clock.
   - [ ] Only the ball carrier can shoot. The other player can grab rebounds and loose balls. (Steals come in Phase 5.)
   - [ ] Shots from beyond the arc score **3** and shots inside score **2**. After a basket, the player who was scored on gets the ball at the top of the key.
   - [ ] Keeping the ball for 20 seconds without hitting the rim gives it to the opponent (**SHOT CLOCK**).
   - [ ] Stepping out of bounds with the ball, or letting it roll out, is a turnover.
   - [ ] First to 15 wins. Lower `TargetScore` in `Config` to test faster. The results screen appears, then both players return to the lobby.
   - [ ] **Reset** a character (Esc → Reset): that's a turnover, and play waits for them to respawn. A shot already in the air still counts. The 4th reset in a match forfeits it.
   - [ ] Press **LEAVE MATCH** twice: that's a forfeit, and the other player sees **VICTORY · Opponent forfeited**.
   - [ ] Close Player2's window mid-match: Player1 wins by forfeit.
   - [ ] On a pad, press **LEAVE** or Backspace: you're moved off the pad.
   - [ ] While a match is running, the pads say **IN GAME**, and walking onto the court sends you back.
5. Click **Cleanup** (the red square in the Test tab) to stop.

### Phone and controller

- **Phone:** in the **Test** tab, use **Device** emulation and pick a phone. Press Play. While you hold the ball, a **SHOOT** button appears next to the jump button.
- **Controller:** plug one in and press Play. Hold **R2** to shoot, and press **B** to leave a queue.

---

## Tuning

Every gameplay number is in **ReplicatedStorage › Shared › Config**. The most useful ones:

| Setting | Default | What it does |
|---|---|---|
| `Match.TargetScore` | 15 | Points needed to win |
| `Match.Duration` | 240 | Game clock in seconds (runs only while the ball is live) |
| `Match.ShotClock` | 20 | Seconds per possession (resets on a rim touch) |
| `Match.MaxResets` | 3 | Character resets allowed per match before it counts as a forfeit |
| `Match.MakeItTakeIt` | false | `true`: the scorer keeps the ball |
| `Scoring.InsideArc` / `OutsideArc` | 2 / 3 | Point values |
| `Shot.FillTime` | 0.6 | Seconds for the meter to fill |
| `Shot.PerfectWindow` / `GoodWindow` | 0.05 / 0.13 | Size of the green and yellow zones |
| `Shot.MakeChance` | 0.97 / 0.5 / 0.05 | Make chance for Perfect / Good / Early or Late releases |
| `Movement.WalkSpeed` | 18 | Player run speed |
| `Ball.Gravity` | 80 | Lower than characters' gravity for a nicer arc |

## Troubleshooting

| You see | Fix |
|---|---|
| `Infinite yield possible on ... WaitForChild("Config")` (or another name) | A script or folder is missing or misspelled. Compare with the tree in Step 4. |
| `Requested module experienced an error while loading` | Code was pasted into the wrong script. Check line 2 of each script. |
| No court appears when you press Play | `Main` isn't a **Script**, or it isn't inside `ServerScriptService › Server`. |
| No HUD or meter | `ClientMain` isn't a **LocalScript**, or modules 14–19 aren't its direct children. |
| Warning about `Baseplate` / `SpawnLocation` | Delete them (Step 2). |

If you see a red error, copy it from the Output window and send it to me, including the script name and line number.

---

## How it works

**Who decides what.** The client only ever sends three requests: *I started a shot*, *I released after N seconds*, and *leave the queue or match*. Every request is rate-limited and checked on the server.

| Decision | Made by | Notes |
|---|---|---|
| Who holds the ball | Server (`BallService`) | One holder at a time. Pickups are refused right after a suspicious teleport. |
| Release timing | Server's own measurement | The client's value may only nudge it by ±0.025 s to smooth out network lag. |
| Make or miss | Server (`ShotService`) | Based on timing, distance and a defender in front. Then real physics plays the shot. A decided miss counts only if it really bounces in off the rim or glass. |
| Points | Server (`MatchService`) | Counted from a server-detected basket, once per shot, only for that match's shooter. |
| Clock, shot clock, winner | Server (`MatchService`) | Published as attributes on the court model. |
| Queue | Server (`QueueService`) | Checked by standing on the pad. |

**Ball states:** `Held` → `InFlight` (shot) → `Scored` or `Loose` (rebound) → `Held`. A `Dead` ball can't be picked up (out of bounds, pauses). A shot the server has decided is a make passes cleanly through the hoop's collision group. A decided miss is aimed outside the rim tube, so it bounces away naturally.

**Match states:** `Idle` (practice) → `Countdown` → `Live` ⇄ `Dead` → `Check` → `Live` … → `GameOver` → `Idle`.

**Script roles**

| Script | Job |
|---|---|
| Config | Every tunable value |
| Signal | Tiny event helper used between modules |
| Net | Names of all remotes (the server creates them) |
| BasketballMath | Court geometry, 2/3-point zones, release timing, shot arcs |
| Main | Starts every server system; runs the single update loop |
| CharacterService | Collision groups, freezing (anchored on the server), teleports, speed-hack check |
| RemoteGuard | Rate limit + argument checks for remotes |
| CourtBuilder | Builds the park and courts from Config |
| BallService | Ball physics, possession, pickups, basket detection, out of bounds |
| MatchService | Match state machine, scores, clocks, results, practice mode |
| QueueService | Home/Away pads and match start |
| ShotService | Validates shots, decides make or miss, launches the ball |
| ClientMain | Starts the client modules |
| UIKit | UI helpers and theme |
| MatchClient | Reads the match state the server publishes |
| ShotMeter | The timing meter |
| ShootController | Keyboard, controller and touch shooting |
| BallVisuals | Dribble animation, shot pose, ball outline, possession marker (visual only) |
| Hud | Scoreboard, banners, toasts, queue panel, results, hints |

---

## Roadmap

Each step is added on its own and tested before the next one starts:

1. **Phase 4:** test and fix the prototype with real Studio play sessions *(next)*.
2. **Dribbling moves:** crossovers and hesitation, using animations you upload in the Animation Editor.
3. **Layups and dunks:** context shots near the rim.
4. **Defense:** steals (timed reach, server-validated) and blocks.
5. **Progression:** wins, losses, total points and currency saved with DataStoreService, with retries and safe error handling.
6. **More courts:** add entries to `Config.Courts`.
7. **Cosmetics:** ball skins, outfits, court effects and emotes, unlocked with currency.

## Updating your copy

When the code changes, I'll list exactly which numbered files changed. Re-paste only those scripts, the same way as in Step 5.
