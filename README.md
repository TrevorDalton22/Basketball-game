# Street Hoops

A competitive 1v1 street basketball game for Roblox. This is a standalone project, not connected to any other game.

## Status: Phase 3 — first playable prototype

- An outdoor park with one floodlit half court and a lobby spawn
- Home and Away queue pads. You can't join a court that's already in a game, and you can leave the queue at any time.
- Server-authoritative ball possession: pick up loose balls, one holder at a time
- Timed shooting: hold to fill the meter, release in the green. Physics shot arcs, rim and backboard bounces, rebounds.
- 2- and 3-point scoring by shot location (configurable), counted once per shot and only for the shooter's own match
- Match flow: 3-2-1 countdown, game clock, first to 15, overtime on a tie, a buzzer-beater rule, check-ball resets after scores and turnovers, out-of-bounds, forfeits on leave or reset, and a results screen
- HUD: scoreboard, possession indicator, shot meter, queue panel, banners and toasts, results. Works on PC, mobile (SHOOT button) and controller.
- Practice mode: when a court has no match, anyone can shoot around on it

Coming next (Phase 5, added one step at a time): dribble moves, layups, dunks, defence and steals, DataStore progression (wins, losses, points, currency), more courts, cosmetics.

## Getting it into Studio

Rojo isn't used. Follow **[docs/PASTE_GUIDE.md](docs/PASTE_GUIDE.md)**. It covers creating each script in Studio, where to paste it, and how to test with 2 players.

## Layout

```
src/ReplicatedStorage/Shared/      shared config + modules  → ReplicatedStorage.Shared
src/ServerScriptService/Server/    server systems            → ServerScriptService.Server
src/StarterPlayerScripts/ClientMain/  client controllers + UI → StarterPlayer.StarterPlayerScripts.ClientMain
docs/                              setup guide + architecture
tools/                             build/check helpers (optional, for development)
```

Files use Rojo's naming (`.server.luau` = Script, `.client.luau` = LocalScript, everything else = ModuleScript). Moving to Rojo later needs no renames, and `default.project.json` is already set up for it.

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for how the systems fit together and what the server validates.

## Development checks

```
python3 tools/build.py manifest     # list every script with its Studio path and type
tools/check.sh                      # strict type-check with luau-lsp against Roblox API types
```

`tools/check.sh` needs [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) and its Roblox definitions file (`globalTypes.d.luau`). Set the `LUAU_LSP` and `ROBLOX_TYPES` environment variables to point at them.
