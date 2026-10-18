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

**Phase 5, step 4: more courts** (after 1v1 defense, layups/dunks and progression), built on the Phase 3 prototype

- **Street park:** grass, a concrete plaza, trees, benches, floodlights, a STREET HOOPS entrance arch and a sunset lighting setup. It's all built by script when the server starts.
- **Three 1v1 half courts, all playable at once,** each with its own look and rules:

  | Court | Look | Game |
  |---|---|---|
  | **COURT 1 · THE PARK** | Blue and orange, straight ahead from the spawn | First to 15, 4-minute clock |
  | **COURT 2 · THE CAGE** | Dark asphalt and red, to the left | Quick game: first to 11, 3 minutes |
  | **COURT 3 · SUNSET** | Warm orange and purple, to the right | Long game: first to 21, 5 minutes |

  Each has a painted floor, key, three-point line with corners, a glass backboard, a physical rim (the ball can bounce off it), a net, a fence with one entrance facing the lobby, and a live sign that shows the court's rules or its score. Signs on the arch point to Court 2 and Court 3. Each court has its own pads, ball and practice mode.
- **Queue pads:** stand on a court's blue **HOME** or red **AWAY** pad (each says which court it belongs to). When both are taken, the match starts after 2 seconds. If someone is already waiting alone on another court, the hint tells you where, so you can go and play them (when two players wait alone on different courts, only the one on the later court is told to walk over). You can step off or press **LEAVE** at any time. While a court is in a game its pads show **IN GAME**, and anyone who walks onto the court is moved off.
- **Ball possession:** walk into a loose ball to pick it up. Only one player can hold it at a time, and the server decides who has it.
- **Timed shooting:** hold the shoot button and release when the meter is in the green. The release decides the shot: early means short, late means long or off the glass, and perfect almost always goes in. A defender standing in front of you lowers your chances.
- **Layups and dunks:** drive at the rim and press shoot. There's no meter; it happens on the press. Running hard from close in is a **dunk**: you leap at the hoop, slam it and drop down in front of the rim. Dunks almost always go in and are very hard to block. A defender standing in your path can stop you short, and then the dunk becomes a layup. Driving from a bit further out, or more slowly, is a **layup**: a quick hop and a soft finish. Layups go in often, but a defender in front can contest them, or jump to block them in the short moment before the ball leaves your hands. It only counts as a drive once you've been moving at the rim for a moment, so a quick first step or a sudden cut still gives you the jump shot. If a layup can't happen (for example you ran past the rim), a message says why. Standing still near the rim still gives you the normal jump shot with the meter, and so does driving along the baseline under the backboard (where shots aren't allowed).
- **Steals:** on defense, get close, face the ball carrier and press steal. The closer you are, the better your chance. A successful steal knocks the ball loose. A miss leaves you slowed for a moment, so spamming it doesn't pay.
- **Blocks:** react to the shot. Be on the ground when the shooter starts, then jump in front of them before they release. If you're in the air, close and between them and the rim, you can reject the shot into a loose ball. Bunny-hopping or hovering doesn't block anything.
- **Crossovers:** on offense, the crossover button bursts you sideways and switches the ball to your other hand. For a split second you can't be stolen from. A defender who reaches during it gets their **ankles broken** and stumbles.
- **Scoring:** 2 points inside the arc, 3 outside (configurable). Every basket is checked on the server and counted once, for the right player.
- **Match flow:** 3-2-1 countdown, then each court's own clock and target (see the table above; the standard game on COURT 1 is first to 15 with a 4-minute clock).
  - **Overtime:** a tie when time runs out goes to "next basket wins". Overtime ends in a draw after 2 minutes.
  - **Buzzer beaters:** a shot already in the air when time runs out still counts.
  - **20-second shot clock:** you can't stall with the ball. It resets on a change of possession or when a shot hits the rim. Grabbing your own airball, or a miss that only hit the glass, doesn't reset it.
  - **Check ball:** after every score or turnover, both players are reset to their spots.
  - **Out of bounds:** a ball or ball carrier that goes out is a turnover.
  - **Results screen:** shown at the end, then both players go back to the lobby.
- **Leaving and resetting:** leaving the game or pressing **LEAVE MATCH** twice forfeits. Resetting your character is a turnover, and play waits up to 15 seconds for you to respawn. A shot already in the air still lands and counts. Resetting more than 3 times in one match forfeits it.
- **Progression, saved between sessions:** every match that counts adds to your **wins**, **losses**, **draws**, **games played**, **points scored** and **coins**. A win earns 30 coins, a draw 15 and a loss 10 on a first-to-15 court (scaled to the court's target, so first to 11 pays 22 for a win and first to 21 pays 42), plus 1 coin per point you scored (up to 20 more). The results screen shows what you earned and your record, and the Roblox player list shows everyone's **Wins** and **Coins**. Practice never counts. Leaving a match counts as a loss with no coins, but a match that ends in its first 45 seconds of game clock (a forfeit or cancel) counts for nobody. Saving needs Step 7 below; until then stats count for the session only, and the game tells you so.
- **No shots from behind or right beside the backboard:** the glass is in the way, so the shot is refused and a message says why.
- **Practice mode:** when a court has no match, anyone can shoot around with its ball. No points count.
- **HUD:** scoreboard with a possession dot, shot clock, shot meter, queue panel, banners, toasts, results and context hints. Works on **PC, phone and controller**.

Animations come next. See the [Roadmap](#roadmap).

## Controls

| Action | Keyboard | Controller | Phone |
|---|---|---|---|
| Move / jump | WASD / Space | Left stick / A (✕) | Thumbstick / jump button |
| Pick up the ball | Walk into it | Walk into it | Walk into it |
| Shoot (hold, release in the green) | **E** | **R2** (or X / □) | **SHOOT** button |
| Layup / dunk | Drive at the rim + **E** | Drive + **R2** | Drive + **SHOOT** |
| Crossover (when you have the ball) | **Q** | **L1** | **MOVE** button |
| Steal (when they have the ball) | **E** (or F) | **R2** (or X / □) | **STEAL** button |
| Block | Jump (Space) in front of the shooter | A (✕) | Jump button |
| Leave the queue | Backspace or the LEAVE button | B (○) | LEAVE button |
| Leave the match (press twice) | LEAVE MATCH button | D-pad down | LEAVE MATCH button |

---

## Build it in Roblox Studio from scratch

This takes about 15 minutes. You create **2 folders and 23 scripts** and paste the code from the [`scripts/`](scripts) folder into each one. Rojo and plugins aren't needed.

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
| 20 | ServerScriptService › Server | `MovesService` | ModuleScript | [`20_Server_MovesService.luau`](scripts/20_Server_MovesService.luau) |
| 21 | StarterPlayer › StarterPlayerScripts › **ClientMain** | `MovesController` | ModuleScript | [`21_Client_MovesController.luau`](scripts/21_Client_MovesController.luau) |
| 22 | ServerScriptService › Server | `DataService` | ModuleScript | [`22_Server_DataService.luau`](scripts/22_Server_DataService.luau) |
| 23 | ServerScriptService › Server | `ProgressionService` | ModuleScript | [`23_Server_ProgressionService.luau`](scripts/23_Server_ProgressionService.luau) |

⚠️ Scripts **14–19 and 21 go inside the `ClientMain` LocalScript**. Hover over `ClientMain` itself and click ⊕. Don't add them to StarterPlayerScripts.

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
   ├─ DataService
   ├─ Main            ← Script
   ├─ MatchService
   ├─ MovesService
   ├─ ProgressionService
   ├─ QueueService
   ├─ RemoteGuard
   └─ ShotService
StarterPlayer
└─ StarterPlayerScripts
   └─ ClientMain      ← LocalScript
      ├─ BallVisuals
      ├─ Hud
      ├─ MatchClient
      ├─ MovesController
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

### Step 7: Turn on saving (DataStores)

Stats are saved with Roblox DataStores, which only work in a place that is on Roblox and allowed to use them. This is a one-time setup:

1. **File → Publish to Roblox** (if you haven't already). It can stay private.
2. Open **File → Experience Settings** (older Studio: **Home → Game Settings**) → **Security**, turn on **Enable Studio Access to API Services**, and click **Save**.
3. Press **Play**. Output should **not** show *"⚠ Player stats won't be saved"*.

Skipping this is fine for trying the game: stats still count for the session, and both Output and a message on screen say they aren't being saved.

---

## Test it

### Solo (practice)

1. Press **Play** (F5) and open **View → Output**. You should see `[Street Hoops] ✓ Server ready — 3 court(s)` (one per entry in `Config.Courts`) and **no red errors**.
2. Walk through the arch toward the court and pick up the orange ball on the free-throw line.
3. **Hold E**. A meter appears beside your character, and your player jumps. **Release when the white bar is in the green band.**
4. Made shots show `+2 BUCKET! (practice)` or `+3 SPLASH! (practice)`.
5. Grab the rebound, back up to the free-throw line, then run straight at the rim and press **E** when you are a few studs from it: you dunk (**SLAM DUNK!**). Press **E** a bit earlier (around the middle of the key) for a layup.

### Two players (a real 1v1)

1. Go to the **Test** tab. In **Clients and Servers**, set the dropdown to **2 Players** and click **Start**. A server window and two player windows open.
2. In **Player1's** window, walk onto the blue **HOME** pad. In **Player2's** window, walk onto the red **AWAY** pad.
3. After about 2 seconds both players are moved onto the court, frozen in place for the **3-2-1** countdown. One player, chosen at random, starts with the ball.
4. What to check:
   - [ ] The scoreboard shows both names, the scores, the game clock, "FIRST TO 15" and the **SHOT** clock.
   - [ ] Only the ball carrier can shoot. The other player can grab rebounds and loose balls.
   - [ ] **Steal:** as the defender, get within a few studs of the ball carrier and press **E**. Your character turns to face them and reaches. You see **STEAL!** and the ball pops loose (not every time). From too far away you're slowed for a moment instead.
   - [ ] **Crossover:** as the ball carrier, press **Q**. You burst sideways and the ball switches hands. If the defender reaches right then, they see **ANKLES!** and stumble.
   - [ ] **Block:** as the defender, stand between the shooter and the hoop on the ground, and jump right after they start their shot. You see **BLOCKED!** and the ball flies loose. Holding jump the whole time doesn't block.
   - [ ] **Dunk:** sprint straight at the rim from just inside the paint and press **E**. You leap at the hoop and see **SLAM DUNK!** (the other player sees **POSTERIZED!**).
   - [ ] **Layup:** drive at the rim from around the free-throw line (or more slowly) and press **E**. A quick hop and a soft shot: **+2 LAYUP** when it drops.
   - [ ] **Block a layup:** as the defender, stand on the ground between the attacker and the rim, and jump as soon as they hop. Sometimes you see **BLOCKED!**.
   - [ ] **Stop a dunk short:** as the defender, stand still in the lane right in the dunker's path. They bump into you and it becomes a layup instead of a slam.
   - [ ] Driving along the baseline right under the backboard and pressing **E** shows **No shots from behind the backboard**.
   - [ ] Standing still next to the rim and holding **E** still gives the normal meter jump shot.
   - [ ] Shots from beyond the arc score **3** and shots inside score **2**. After a basket, the player who was scored on gets the ball at the top of the key.
   - [ ] Keeping possession for 20 seconds without hitting the rim gives the ball to the opponent (**SHOT CLOCK**).
   - [ ] Stepping out of bounds with the ball, or letting it roll out, is a turnover.
   - [ ] First to 15 wins. Lower `TargetScore` in `Config` to test faster. The results screen appears, then both players return to the lobby.
   - [ ] **Progression:** the results screen shows *"+N coins · Record W–L · N coins total"*, and the player list (top right) shows each player's **Wins** and **Coins**. Leaving within the first 45 seconds of game clock shows *"Matches that end in the first 45 seconds don't count"* instead.
   - [ ] **Saving** (after Step 7): click **Cleanup**, then **Start** the same 2-player test again. Player1's and Player2's Wins and Coins in the player list are still there. (Studio's test players always get the same IDs. A solo **Play** uses your own account, which has its own separate stats, so it starts at 0.)
   - [ ] **Reset** a character (Esc → Reset): that's a turnover, and play waits for them to respawn. A shot already in the air still counts. The 4th reset in a match forfeits it.
   - [ ] Press **LEAVE MATCH** twice: that's a forfeit, and the other player sees **VICTORY · Opponent forfeited**.
   - [ ] Close Player2's window mid-match: Player1 wins by forfeit.
   - [ ] On a pad, press **LEAVE** or Backspace: you're moved off the pad.
   - [ ] While a match is running, the pads say **IN GAME**, and walking onto the court sends you back.
5. Click **Cleanup** (the red square in the Test tab) to stop.

### Several courts at once

1. In **Clients and Servers**, pick **4 Players** and click **Start**.
2. Waiting hints, before any match starts:
   - [ ] Put Player1 alone on a **COURT 2** pad (left of the arch). Player2's screen says *"Player1 is waiting on COURT 2 · step onto its free pad to play"*.
   - [ ] Put Player3 alone on a **COURT 3** pad (right of the arch). Player3's queue panel says *"Player1 is waiting on COURT 2 — walk over to play them"*, while Player1's still says *"Waiting for an opponent on the other pad…"* (only one of them is sent walking).
3. Now put Player2 on COURT 2's free pad and Player4 on COURT 3's free pad. Both matches start and run at the same time.
4. What to check:
   - [ ] COURT 2's scoreboard says **COURT 2 · FIRST TO 11** and its clock starts at **3:00**; COURT 3 says **FIRST TO 21** and **5:00**.
   - [ ] Walking a player from one match onto the other court sends them straight back to their own court with *"Your match is on COURT 2"* (or COURT 3).
   - [ ] Winning on COURT 2 shows *+22 coins* (plus points), not +30.

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
| `Match.ShotClock` | 20 | Seconds per possession (also resets when a shot hits the rim) |
| `Match.MaxResets` | 3 | Character resets allowed per match before it counts as a forfeit |
| `Match.MakeItTakeIt` | false | `true`: the scorer keeps the ball |
| `Scoring.InsideArc` / `OutsideArc` | 2 / 3 | Point values |
| `Shot.FillTime` | 0.6 | Seconds for the meter to fill |
| `Shot.PerfectWindow` / `GoodWindow` | 0.05 / 0.13 | Size of the green and yellow zones |
| `Shot.MakeChance` | 0.97 / 0.5 / 0.05 | Make chance for Perfect / Good / Early or Late releases |
| `Movement.WalkSpeed` | 18 | Player run speed |
| `Ball.Gravity` | 80 | Lower than characters' gravity for a nicer arc |
| `Finish.DunkRange` / `LayupRange` | 7 / 11 | How close to the rim a drive can finish |
| `Finish.DunkMinApproach` / `LayupMinApproach` | 12 / 5 | How fast you must be moving toward the rim (studs/s) |
| `Finish.DunkMakeChance` / `LayupMakeChance` | 0.96 / 0.82 | Make chance before any contest |
| `Finish.DunkTime` / `LayupTime` | 0.42 / 0.42 | Seconds from the press until the ball leaves your hands (the defender's window to react) |
| `Defense.StealRange` / `StealBaseChance` / `StealCloseBonus` | 5.5 / 0.4 / 0.3 | Steal reach and success chance |
| `Defense.StealCooldown` | 1.4 | Seconds between steal attempts |
| `Defense.BlockRange` / `BlockChance` | 6.5 / 0.8 | How close a jumping defender must be, and how often it blocks |
| `Moves.CrossoverCooldown` / `CrossoverImmunity` | 1.1 / 0.45 | Crossover spacing and its steal-proof window |
| `Progression.Rewards` | Win 30 / Loss 10 / Draw 15, +1 per point (max 20) | Coins for a match that counts (Win/Loss/Draw scale with the court's target score) |
| `Progression.MinPlayedSeconds` | 45 | A forfeit or cancel before this much game clock counts for nobody |
| `Progression.StoreName` | `StreetHoops_PlayerData_v1` | DataStore name. Changing it starts everyone from zero |

**Courts** are the entries in `Config.Courts`. Each one has:

- `Id`: unique, for example `"Court4"`.
- `DisplayName`: shown on its sign, pads and HUD, for example `"COURT 4"`.
- `Position` and `Yaw`: where it stands and which way it faces. The pads are on its front (local +Z), so turn it to face the spawn. `Yaw` is the angle `atan2(spawn.X − Position.X, spawn.Z − Position.Z)` in degrees; the spawn is at (0, 0, 78).
- `Theme`: a `Name` plus `Floor`, `Key`, `Runoff` and `Accent` colours.
- `Rules`: `TargetScore` and/or `Duration` in seconds. Leave it as `{}` for the standard game.

Keep `Court1` first, because it anchors the lobby. If two courts overlap, or two share an `Id`, the server won't start and the SETUP PROBLEM sign says which ones. Side by side they need roughly 110 studs between centres.

## Troubleshooting

**First, read the Output window** (View → Output) right after you press Play. When the server starts, `Main` checks that all 23 scripts are in the right places and that the shared and server scripts aren't old copies. Then `ClientMain` checks the client scripts (and checks that `Main` is current). You'll see one of these:

- `[Street Hoops] ✓ All 23 scripts found…`, `✓ Shared and server scripts are up to date…`, `✓ Server ready`, and then `✓ Client ready`: everything loaded.
- `[Street Hoops] ✗ … setup problem(s) found`, followed by a numbered list. Each line says exactly what's wrong, for example *"Config is not where it should be. Found: Workspace.Config. Move it to ReplicatedStorage > Shared > Config"*. A grey floor and a red **SETUP PROBLEM** sign also appear in the game, so you don't fall forever. Fix each item and press Play again.
- `[Street Hoops] ✗ … script(s) are out of date` (from `Main`), or `[Street Hoops] ✗ <Name> is an old copy …` (from `ClientMain`): you updated some scripts but missed one. Each line names the file, for example *"ShotService is an old copy (version 2, needs 3). Paste scripts/12_Server_ShotService.luau into ServerScriptService > Server > ShotService again."* If it says *Main is an old copy* or *ClientMain is the old copy*, paste that one again (05 or 13).
- Problems also appear **on screen** in a dark **STREET HOOPS SETUP PROBLEM** box at the top. (If `ClientMain` itself can't run, because it's missing or isn't a LocalScript, you get the grey floor and sign instead, and the numbered details are in Output.)
- `✗ The server never started …` (and no other `[Street Hoops]` lines, or none at all) means `Main` itself isn't running. Check that:
  1. `Main` is a **Script**. Its Explorer icon is a page with a blue arrow. A LocalScript (person icon) or a ModuleScript doesn't run on the server.
  2. It's inside **ServerScriptService** (in the `Server` folder).
  3. Its **Enabled** box is ticked in Properties.
  4. You pasted the code from `scripts/05_Server_Main.luau` into it.

| You see | Fix |
|---|---|
| You fall forever and there's no map | `Main` isn't running. See the four checks above. |
| A **SETUP PROBLEM** sign on a grey floor, or a dark **STREET HOOPS SETUP PROBLEM** box on screen | Read the numbered lines and fix each one (usually: paste one script again). |
| `Config.Courts: … is too close to …` or `two courts are called …` | A court you added or moved overlaps another, or reuses an `Id`. See **Courts** under Tuning. |
| Pressing **E** does nothing at all | A script was missed in the last update. Press Play and look for the **SETUP PROBLEM** box or `✗` lines in Output; they name the file to paste again. |
| `… failed to load`, `… is still loading after 5 seconds`, or `… holds the code from scripts/…` | That script's code is incomplete or from another file. Paste the named file into it again (Ctrl+A in the script, then Ctrl+V). For a load error, the red line just above in Output is the script's own error. |
| No HUD or meter (but the map is there) | `ClientMain` is disabled or is an old copy. After 30 seconds in Studio (90 on a live server) the server says which on screen (*"ClientMain is disabled…"* or *"ClientMain didn't start, or is an old copy…"*). If `ClientMain` isn't a LocalScript, or modules 14–19 and 21 aren't its direct children, the setup check catches it instead and you get the SETUP PROBLEM sign. |
| Warning about `Baseplate` / `SpawnLocation` | Delete them (Step 2). |
| `⚠ Player stats won't be saved on this server` | Do Step 7 (publish, then turn on Studio Access to API Services). Stats still count until you press Stop. |
| `⚠ Couldn't load …'s stats yet … Still trying` | Roblox's DataStores are having trouble. It keeps trying while that player is in the server, and anything they earn meanwhile is added once it loads. Only if it still fails after 10 minutes does it say *won't be saved*; then rejoining loads them normally. |
| `⚠ Couldn't save …'s stats; will try again` | Roblox's DataStores are having trouble. It tries again at the next autosave, and a player's last save when they leave keeps retrying until it works. |
| `Waiting up to 30 s for another server to finish saving …` | That player just came from another server that is still saving their data. It waits for it (up to 30 s), so nothing is overwritten. |

If you see a red error, copy it from the Output window and send it to me, including the script name and line number.

---

## How it works

**Who decides what.** The client only ever sends three requests: *I started a shot*, *I released after N seconds*, and *leave the queue or match*. Every request is rate-limited and checked on the server.

| Decision | Made by | Notes |
|---|---|---|
| Who holds the ball | Server (`BallService`) | One holder at a time. Pickups are refused right after a suspicious teleport. |
| Release timing | Server's own measurement | The client's value may only nudge it by ±0.025 s to smooth out network lag. |
| Make or miss | Server (`ShotService`) | Based on timing, distance and a defender in front. Then real physics plays the shot. A decided miss counts only if it really bounces in off the rim or glass. |
| Steals, crossovers, blocks | Server (`MovesService`, `ShotService`) | Distance, facing, cooldowns and timing are all checked on the server, and the server rolls the chance. |
| Points | Server (`MatchService`) | Counted from a server-detected basket, once per shot, only for that match's shooter. |
| Clock, shot clock, winner | Server (`MatchService`) | Published as attributes on the court model. |
| Queue | Server (`QueueService`) | Checked by standing on the pad. |
| Wins, losses, points, coins | Server (`ProgressionService`) | Worked out from the match result. The client is only told what it earned. |
| Saved stats | Server (`DataService`) | Each player's data is locked to one server at a time, so a quick rejoin elsewhere can't overwrite newer progress. Data that fails to load is never saved over. |

**Ball states:** `Held` → `InFlight` (shot) → `Scored` or `Loose` (rebound) → `Held`. A `Dead` ball can't be picked up (out of bounds, pauses). A shot the server has decided is a make passes cleanly through the hoop's collision group. A decided miss is aimed outside the rim tube, so it bounces away naturally.

**Match states:** `Idle` (practice) → `Countdown` → `Live` ⇄ `Dead` → `Check` → `Live` … → `GameOver` → `Idle`.

**Script roles**

| Script | Job |
|---|---|
| Config | Every tunable value |
| Signal | Tiny event helper used between modules |
| Net | Names of all remotes (the server creates them) |
| BasketballMath | Court geometry, 2/3-point zones, release timing, shot arcs |
| Main | Checks the setup and script versions, starts every server system, runs the single update loop |
| CharacterService | Collision groups, freezing (anchored on the server), teleports, speed-hack check |
| RemoteGuard | Rate limit + argument checks for remotes |
| CourtBuilder | Builds the park and courts from Config |
| BallService | Ball physics, possession, pickups, basket detection, out of bounds |
| MatchService | Match state machine, scores, clocks, results, practice mode |
| QueueService | Home/Away pads and match start |
| ShotService | Validates jump shots, layups and dunks, decides make or miss, launches the ball |
| ClientMain | Checks the client script versions and starts the client modules (any problem shows on screen) |
| UIKit | UI helpers and theme |
| MatchClient | Reads the match state the server publishes |
| ShotMeter | The timing meter |
| ShootController | Keyboard, controller and touch shooting |
| BallVisuals | Dribble animation, shot pose, ball outline, possession marker (visual only) |
| Hud | Scoreboard, banners, toasts, queue panel, results, hints |
| MovesService | Validates steals and crossovers (blocks are checked in ShotService at release) |
| MovesController | Steal and crossover input on keyboard, controller and touch |
| DataService | Loads and saves each player's stats with DataStores: one server at a time per player, retries, autosave every 2 minutes, saves on leave and on shutdown |
| ProgressionService | Turns finished matches into wins, losses, points and coins (decided on the server); shows them in the player list and on the results screen |

---

## Roadmap

Each step is added on its own and tested before the next one starts:

1. ~~Phase 3/4: playable prototype, tested in Studio~~ ✓
2. ~~Defense: steals, blocks, and crossovers to beat them~~ ✓
3. ~~Layups and dunks: context finishes near the rim~~ ✓
4. ~~Progression: wins, losses, total points and coins saved with DataStoreService, with retries and safe error handling~~ ✓
5. ~~More courts: three themed courts with their own rules, all playable at once~~ ✓ *(this version)*
6. **Animations** *(next)*: dribble, shot and dunk animations, made in the Animation Editor and uploaded by you
7. **Cosmetics:** ball skins, outfits, court effects and emotes, unlocked with currency

## Updating your copy

When the code changes, I'll list exactly which numbered files changed. Re-paste only those scripts, the same way as in Step 5. The list always includes `05_Server_Main` and `13_Client_ClientMain`, because they hold the version check.

If you miss one, nothing breaks quietly. When you press Play, the game names the old script (in Output and on screen) so you know exactly which file to paste again.
