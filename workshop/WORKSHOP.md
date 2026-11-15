# Steam Workshop page for DayZ Solo

What to fill in when you upload `dayzsolo-mod\@DayZSolo` with **DayZ Tools > Publisher**.

## Item settings

| Field | Value |
|---|---|
| Title | `DayZ Solo` |
| Content folder | `<your DayZ Solo folder>\dayzsolo-mod\@DayZSolo` (signed: `Addons\*.pbo`, `Addons\*.bisign`, `Keys\DayZSolo.bikey`, `mod.cpp`) |
| Preview image | `workshop\preview.png` (512x512, under 1 MB) |
| Tags | Scripts, Gameplay (whatever Publisher offers that fits) |
| Visibility | **Private** for the first upload, then **Friends only** to test with a friend, then **Public** |
| Change note | The version and the highlights, e.g. `1.0.0 - first release` |

## Required items

**None.** The mod has no dependencies, so leave Required items empty.

Don't add the optional mods below as Required items: Steam would then force every subscriber
to download them.

## Description (paste into the description box, Steam BBCode)

```
[h1]DayZ Solo - single-player and small co-op DayZ[/h1]

DayZ has no offline mode. [b]DayZ Solo[/b] gives you one: a launcher runs a private DayZ server on your own PC, loads your mods on both sides, joins you to it and saves the world when you quit. Your character, bases and stashes stay between sessions. Invite a few friends and it becomes a private co-op world.

[b]This Workshop item is the game-side part. It does nothing on its own - you need the free DayZ Solo launcher:[/b]
[url=https://github.com/masterxxstabs/dayz-solo/releases/latest]Download the DayZ Solo launcher[/url]

[h2]Features[/h2]
[list]
[*][b]One-click single-player[/b] with any Workshop mods (load order worked out automatically)
[*][b]Co-op[/b]: host for 2-10 players with a password, share an invite code, friends join with one click. Works over Tailscale, ZeroTier or port forwarding
[*][b]Control panel[/b]: start/stop, live logs, players, events, admin tools (money, teleport)
[*][b]Loot tuning[/b]: loot multiplier with variety protection, more food, food that never rots, faster respawns, fewer zombies, more cars, modded cars with all their parts
[*][b]World events[/b]: heli crashes, airdrops and random toxic gas strikes with alerts
[*][b]Solo Shop[/b]: press B for a full trader with categories, search, vehicles and selling (optional)
[*][b]Minimap[/b] with trader and event markers (optional)
[*][b]Bandits[/b]: roaming AI groups in military gear (needs DayZ-Expansion-AI, optional)
[*]Always-day mode, safe zone around the trader, loot and spawn editor
[/list]

[h2]How to play[/h2]
[olist]
[*]Install [b]DayZ Server[/b] (free): Steam > Library > Tools > DayZ Server
[*]Download and unzip the DayZ Solo launcher
[*]Double-click [b]DayZ Solo.bat[/b] and press [b]Play[/b]
[/olist]
The launcher uses this Workshop copy when you're subscribed, so you get updates automatically. It also carries its own copy, so subscribing is optional.

[h2]Optional mods it works with[/h2]
[list]
[*][b]DayZ-Expansion-AI[/b] (and its required items) for roaming bandits
[*][b]Trader[/b] + [b]Trader_FIX[/b] for an NPC trader at the safe zone
[*][b]VanillaPlusPlusMap[/b] for trader markers on the map
[*]Community Online Tools for an admin menu
[*][b]QoL Mining[/b] + [b]QoL ATM[/b] + [b]CJ187-MoreMoney[/b]: mine Bitcoin in your base, sell it at an ATM for dollars and spend them at the shop. DayZ Solo places the ATMs, adds the cash and sets mining up for solo play
[/list]

[h2]Server owners[/h2]
You can run it on a normal dedicated server too: load it with -mod and copy Keys\DayZSolo.bikey to the server's keys folder. Everything starts switched off (no events, shop, minimap or auto-shutdown); turn things on in the server profile's SoloSurvivor\settings.json, SoloShop\catalog.json and SoloMinimap\markers.json (see the launcher README).

[h2]Notes[/h2]
[list]
[*]Never touches official servers. BattlEye stays on; nothing in the game is patched
[*]Everyone in co-op needs the same DayZ Solo version and the same mods; the invite code lists them
[*]Free, as all DayZ Workshop content must be. Please don't re-upload it
[/list]
```

`LAUNCHER_DOWNLOAD_URL` is https://github.com/masterxxstabs/dayz-solo/releases/latest (the
installer updates itself after that).

## Launcher download page (GitHub release / Nexus description)

> DayZ Solo turns DayZ into a single-player or small co-op game on your own PC.
> Needs DayZ and the free DayZ Server tool on Steam. Unzip anywhere outside the Steam folders and
> run `DayZ Solo.bat`. Optional: subscribe to DayZ Solo on the Steam Workshop for automatic
> updates of the game-side mod.
