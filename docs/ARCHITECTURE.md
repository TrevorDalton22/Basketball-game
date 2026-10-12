# Street Hoops architecture

## Where everything lives in Studio

```
ReplicatedStorage
└─ Shared (Folder)
   ├─ Config          ModuleScript  every tunable value (court size, timing, scoring, match rules, UI colours)
   ├─ Signal          ModuleScript  tiny event object used between modules
   ├─ Net             ModuleScript  names every RemoteEvent; the server creates them, clients wait for them
   └─ BasketballMath  ModuleScript  pure math: court geometry, 2/3-point zone, release timing, ball arc
ServerScriptService
└─ Server (Folder)
   ├─ Main              Script       entry point; starts the services; the single Heartbeat loop
   ├─ CharacterService  ModuleScript collision groups, movement defaults, freeze, teleport
   ├─ CourtBuilder      ModuleScript builds the park, court, hoop, pads and sign from Config
   ├─ BallService       ModuleScript ball possession, physics, pickups, basket detection, out of bounds
   ├─ ShotService       ModuleScript validates shot requests, decides make/miss, launches the ball
   ├─ MatchService      ModuleScript per-court match state machine, scores, clock, results
   ├─ QueueService      ModuleScript Home/Away pads and match start
   └─ RemoteGuard       ModuleScript per-player rate limit + argument checks
StarterPlayer
└─ StarterPlayerScripts
   └─ ClientMain        LocalScript  client entry point; its children:
      ├─ UIKit           ModuleScript UI helpers / theme
      ├─ MatchClient     ModuleScript reads the court/ball attributes the server publishes
      ├─ Hud             ModuleScript scoreboard, banners, toasts, queue panel, results, hints
      ├─ ShotMeter       ModuleScript the timing meter beside your character
      ├─ ShootController ModuleScript keyboard / gamepad / touch shooting
      └─ BallVisuals     ModuleScript cosmetic dribble, shot pose, outline, possession marker
```

## Who decides what

| Thing | Decided by | How the client learns about it |
|---|---|---|
| Who holds the ball | `BallService` (server) | Ball attribute `HolderUserId` |
| Whether a shot is allowed | `ShotService` + `MatchService.GetShotContext` | — (invalid requests are ignored) |
| Release timing | Server's own measurement of the hold. The client's value can only nudge it within ±0.2 s | `Feedback("Release")` |
| Make or miss | `ShotService` roll (timing, distance, defender) → physics arc | The ball's flight |
| Points | `MatchService` on a server-detected basket. Each shot ID counts once and only for its own match | Court attributes + `Feedback("Score")` |
| Match state, clock, winner | `MatchService` | Court attributes |
| Queue claims | `QueueService` (standing on the pad, checked on the server) | Court attributes `PadHomeUserId` / `PadAwayUserId` |

Clients send only three things: `ShootStart`, `ShootRelease(holdTime)` and `LeaveQueue`. Every handler is rate-limited and checks its arguments.

## Ball states

`Held` (welded to the holder's root part) → `InFlight` (shot) → `Scored` or `Loose` (rebound) → `Held` …
`Dead` means the ball can't be picked up: out of bounds, pauses, or between possessions.

A shot that the server has already decided is a make flies in the `BallMake` collision group, which ignores the rim ring. That way physics drift can never turn a decided make into a miss. Misses aim at the rim or backboard and bounce naturally. A lucky bounce that drops in still counts.

## Match flow

```
Idle (practice ball) ─both pads claimed─► Countdown ─► Live ◄─► Dead ─► Check ─┘
                                                        │
                                                        └─► GameOver ─► Idle
```

- **Dead** is the pause after a score, turnover or ball reset. The clock is paused.
- **Check** puts both players on their spots, frozen, with the ball given to the offence.
- The clock runs only while Live. If time runs out with the scores tied, the game goes to overtime and the next basket wins. A shot already in the air when time expires (a buzzer beater) still counts.
- If a player leaves or resets during the match, it's a forfeit. If they leave during the countdown, the match is cancelled with no winner.
- `MatchService.MatchEnded` fires with the result. Phase 5 progression will subscribe to it.

## Performance notes

- There is one server `Heartbeat` connection. The ball update loops over the players only while a ball is loose. The queue polls 5 times a second.
- Attributes are written only when their value changes.
- Clients do per-frame work only for the meter, the clock text and the dribble animation.
