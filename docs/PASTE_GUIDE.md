# Setting up Street Hoops in Roblox Studio (paste-in workflow)

This takes about 15 minutes the first time. You create 2 folders and 19 scripts in Studio, then paste each script from this repository. After that, an update means re-pasting only the files that changed. Every update lists them.

> Source of truth: the files in `src/` on the `claude/sweet-clarke-4w3vag` branch of `TrevorDalton22/Basketball-game`. Each file's first comment line says exactly where it goes in Studio.

---

## Step 1 — Create a new, separate place

1. Open **Roblox Studio** and click **New**, then choose the **Baseplate** template.
2. **File → Save to Roblox As…** and name it **Street Hoops**. Choose **Create new experience** so it's separate from Survival-Island-Tycoon.

## Step 2 — Remove the template's baseplate and spawn

In the **Explorer**, under **Workspace**, delete these two items (right-click → Delete):

- `Baseplate`
- `SpawnLocation`

Why: the game builds its own park, ground and lobby spawn when the server starts. The template's baseplate would overlap the park, and its spawn would put players in the wrong place. If you forget, the Output window prints a warning telling you to remove them.

> Note: the park, court and hoop are generated **when you press Play**, so the Workspace looks empty in edit mode. That's expected.

## Step 3 — (Optional) Better lighting

Select **Lighting** in the Explorer. In **Properties**, set **Technology** to **Future**. Scripts can't set this property. It makes the floodlights cast proper shadows. Everything still works without it.

## Step 4 — Create the folders and scripts

How to insert an object: hover over the parent in the Explorer, click the **⊕** button, then type the class name (`Folder`, `Script`, `LocalScript` or `ModuleScript`). To rename it, select it and press **F2**. Names are case-sensitive and must match exactly.

Create this tree. The **Type** column matters. A `Script` is not a `LocalScript`, and neither is a `ModuleScript`.

| # | Studio location (parent → name) | Type | Paste from |
|---|---|---|---|
| 1 | ReplicatedStorage → **Shared** | Folder | — |
| 2 | ReplicatedStorage → Shared → **Config** | ModuleScript | `src/ReplicatedStorage/Shared/Config.luau` |
| 3 | ReplicatedStorage → Shared → **Signal** | ModuleScript | `src/ReplicatedStorage/Shared/Signal.luau` |
| 4 | ReplicatedStorage → Shared → **Net** | ModuleScript | `src/ReplicatedStorage/Shared/Net.luau` |
| 5 | ReplicatedStorage → Shared → **BasketballMath** | ModuleScript | `src/ReplicatedStorage/Shared/BasketballMath.luau` |
| 6 | ServerScriptService → **Server** | Folder | — |
| 7 | ServerScriptService → Server → **Main** | **Script** | `src/ServerScriptService/Server/Main.server.luau` |
| 8 | ServerScriptService → Server → **CharacterService** | ModuleScript | `src/ServerScriptService/Server/CharacterService.luau` |
| 9 | ServerScriptService → Server → **CourtBuilder** | ModuleScript | `src/ServerScriptService/Server/CourtBuilder.luau` |
| 10 | ServerScriptService → Server → **BallService** | ModuleScript | `src/ServerScriptService/Server/BallService.luau` |
| 11 | ServerScriptService → Server → **ShotService** | ModuleScript | `src/ServerScriptService/Server/ShotService.luau` |
| 12 | ServerScriptService → Server → **MatchService** | ModuleScript | `src/ServerScriptService/Server/MatchService.luau` |
| 13 | ServerScriptService → Server → **QueueService** | ModuleScript | `src/ServerScriptService/Server/QueueService.luau` |
| 14 | ServerScriptService → Server → **RemoteGuard** | ModuleScript | `src/ServerScriptService/Server/RemoteGuard.luau` |
| 15 | StarterPlayer → StarterPlayerScripts → **ClientMain** | **LocalScript** | `src/StarterPlayerScripts/ClientMain/init.client.luau` |
| 16 | … → ClientMain → **UIKit** | ModuleScript | `src/StarterPlayerScripts/ClientMain/UIKit.luau` |
| 17 | … → ClientMain → **MatchClient** | ModuleScript | `src/StarterPlayerScripts/ClientMain/MatchClient.luau` |
| 18 | … → ClientMain → **ShotMeter** | ModuleScript | `src/StarterPlayerScripts/ClientMain/ShotMeter.luau` |
| 19 | … → ClientMain → **ShootController** | ModuleScript | `src/StarterPlayerScripts/ClientMain/ShootController.luau` |
| 20 | … → ClientMain → **BallVisuals** | ModuleScript | `src/StarterPlayerScripts/ClientMain/BallVisuals.luau` |
| 21 | … → ClientMain → **Hud** | ModuleScript | `src/StarterPlayerScripts/ClientMain/Hud.luau` |

Rows 16–21 are **children of the ClientMain LocalScript itself**. Hover over `ClientMain` and click ⊕ to add them. Don't add them to StarterPlayerScripts.

When you're done, the Explorer should look like this:

```
ReplicatedStorage
  Shared
    BasketballMath, Config, Net, Signal
ServerScriptService
  Server
    BallService, CharacterService, CourtBuilder, Main, MatchService,
    QueueService, RemoteGuard, ShotService
StarterPlayer
  StarterPlayerScripts
    ClientMain
      BallVisuals, Hud, MatchClient, ShootController, ShotMeter, UIKit
```

## Step 5 — Paste the code

For each script in the table:

1. Open the file on GitHub: go to `github.com/TrevorDalton22/Basketball-game`, switch the branch dropdown to **claude/sweet-clarke-4w3vag**, then open the path from the table.
2. Click the **Copy raw file** button (two overlapping squares, top right of the code view).
3. In Studio, double-click the script to open it. Press **Ctrl+A** (select the template text such as `local module = {}` or `print("Hello world!")`), then **Ctrl+V**.
4. Repeat for every script. You don't need to save each one separately. Studio keeps the changes until you publish or save the place.

Check each paste: the first line of every file is `--!strict` and the second is a comment naming the script, for example `-- Config (ModuleScript) — ReplicatedStorage > Shared > Config`. If that comment doesn't match where you pasted it, you used the wrong file.

## Step 6 — Save

**File → Save to Roblox** (Ctrl+S).

---

## Testing

### Solo practice (quick check)

1. Press **Play** (F5).
2. Open **View → Output**. You should see `[Main] Street Hoops server ready — 1 court(s)` and **no red errors**.
3. Walk forward through the arch toward the court and pick up the orange ball sitting on the free-throw line. You pick it up by walking into it.
4. **Hold E**, watch the meter beside your character, and **release when the white bar is in the green zone**. A perfect release almost always goes in. Releasing early falls short, and releasing late goes long or off the backboard.
5. Made shots show `+2 BUCKET! (practice)` or `+3 SPLASH! (practice)`.

### Two-player 1v1 test

1. Go to the **Test** tab. In the **Clients and Servers** section, set the player dropdown to **2 Players** and click **Start**.
2. Three windows open: one server and two clients (Player1 and Player2).
3. In Player1's window, walk onto the **blue HOME pad** in front of the court. In Player2's window, walk onto the **red AWAY pad**.
4. After about 2 seconds both players are moved onto the court. A 3-2-1 countdown plays, and the player who starts with the ball is chosen at random.
5. Things to check:
   - The scoreboard at the top shows both names, the scores, the clock and "FIRST TO 15".
   - Only the player holding the ball can shoot. The other player can't take it, because steals come in Phase 5. They can grab rebounds and loose balls.
   - Shots from behind the arc score 3 and shots inside it score 2. After each basket, the player who was scored on gets the ball at the top of the key.
   - A ball that rolls out of bounds, or a ball carrier who steps out, gives the ball to the other player.
   - First to 15 wins. You can lower `TargetScore` in `Config` to test faster. The results screen shows, then both players return to the lobby.
   - Leave mid-match: close Player2's window. Player1 should get **VICTORY — Opponent left the match**.
   - Reset mid-match (Esc → Reset Character): counts as a forfeit.
   - Queue and leave: stand on a pad, then press **LEAVE** (or Backspace, or B on a controller). You're moved off the pad.
   - While a match is running, the pads show **IN GAME**, and walking onto the court teleports you out.
6. Click **Cleanup** (the red square) on the Test tab to stop.

### Testing mobile and controller layouts

- **Mobile:** in the **Test** tab, use **Device** emulation (the phone icon). Pick a phone, then press Play. The **SHOOT** button appears above the jump button while you hold the ball.
- **Controller:** plug one in and press Play. Use **X** or **R2** to shoot and **B** to leave a queue.

### Quick tuning

All the gameplay numbers are in `ReplicatedStorage → Shared → Config`. Good ones to try:

| Setting | What it does |
|---|---|
| `Match.TargetScore` | Points needed to win (15) |
| `Match.Duration` | Game clock in seconds (240) |
| `Shot.FillTime` | How fast the meter fills (0.6 s) |
| `Shot.PerfectWindow` / `GoodWindow` | Size of the green / yellow zones |
| `Shot.MakeChance` | Make percentages per release quality |
| `Scoring.InsideArc` / `OutsideArc` | Point values (2 / 3) |

### If something goes wrong

- **`Infinite yield possible on 'ReplicatedStorage.Shared:WaitForChild("Config")'`**: a module is missing or misnamed. Compare with the tree in Step 4.
- **`Requested module experienced an error while loading`**: the code was pasted into the wrong script. Check the second line of each script.
- **No court appears**: `Main` is a LocalScript or a ModuleScript instead of a **Script**, or it isn't inside `ServerScriptService → Server`.
- **No HUD or meter**: `ClientMain` isn't a **LocalScript**, or its modules aren't its direct children.

Copy any red error text from the Output window and send it to me. Include the script name and line number.
