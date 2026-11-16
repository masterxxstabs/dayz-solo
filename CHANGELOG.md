# Changelog

Each `## version` section becomes the release notes the app shows under "What's new".

## 1.2.1

- "Use BattlEye" is back in Settings, for slow PCs: BattlEye kicks a game that is busy loading
  for about a minute ("Client not responding"), which happens with many mods on a hard drive.
  Untick it and the server starts without BattlEye. The launcher checks whether the server really
  runs without it (its log and its loaded files) and starts the game to match, so a mismatch
  can't get you kicked either.

## 1.2.0

- Days survived on screen: a "Day N" counter in the top-left corner while you play. It counts
  in-game time your character has stayed alive (fast nights and sleeping count too) and starts
  over at Day 1 when you die. Settings > "Show the days survived on screen" turns it off. It's
  kept in the server profile (SoloSurvivor\days.json), not in the world save, so it can't break
  your world.
- Night is back by default for new installs ("Always daytime" now starts off). If you had it
  on, untick it in Settings.

## 1.1.9

- Tools: "Start a fresh world". It moves your world save (storage_1) aside as a backup, so the
  next start has a new map, loot and character.
- The launcher remembers which mods your world was saved with and warns before starting when
  some are off now: mods save their own data with every item, and a world saved with a mod
  that is gone can crash the server while it loads ("Scripted variables corrupted").
- When the server crashes for that reason, the launcher log says so.

## 1.1.8

- When the server stops while loading, the launcher log now says why in words (for example
  "it crashed (access violation, usually a mod)") and shows the last lines of the server log
  and the server's crash report, instead of only an exit code.
- Logs tab: "Server crash log" (the newest crash_*.log in the server profile).

## 1.1.7

- Fixed "can't join" with many mods: the game was started as soon as the server opened its
  port (or after 3 minutes at most), while the server could still be loading the map and mods
  for several minutes, so the game got dropped back to the menu. DayZ Solo now waits for the
  server log to say it takes players ("Player connect enabled"), up to 15 minutes, and shows
  how long it's taking.

## 1.1.6

- Mods tab: a search bar. Type part of a name, a Workshop ID or a status ("update available",
  "not downloaded", "server only", "excluded") to narrow the list; Esc clears it.

## 1.1.5

- Fixed the game crashing (or being kicked while loading) with many mods: the game is now
  given each mod's real folder. Windows had been refusing to let the game follow DayZ Solo's
  folder links ("untrusted mount point", error 448 in the game log), so the game ran without
  the mods and crashed as soon as a modded item or car came near.

## 1.1.4

- Logs tab: the game's own logs are there too: "Game (.RPT)", "Game script log" and "Game
  crash log" (the newest files in %LocalAppData%\DayZ). When the game crashes, the server only
  sees "Ticket has been canceled"; the reason is in the game crash log.

## 1.1.3

- BattlEye is back on, and the "Use BattlEye" option is gone. The DayZ server runs BattlEye
  whatever its settings say, so 1.1.2 started the game without it and the server kicked you
  for "Client not responding" about a minute in. The game always starts through DayZ_BE.exe
  again.

## 1.1.2

- BattlEye off by default (undone in 1.1.3: the server keeps BattlEye on regardless).
- Fixed "Couldn't add the mods' loot files" at every start: mods' own loot (like QoL Mining's
  rig parts) is now added.
- Fixed the trader setup: DayZ Solo could copy another mod's item list instead of the Trader
  mod's example, which left the NPC trader without a proper setup. A wrong copy is replaced
  automatically (the old one is kept as config\Trader.old-...).
- Workshop mods DayZ still lists but that aren't downloaded are now one line in the log, and
  they show on the Mods tab with a Download button.
- Shorter launcher log: the modded car list is summarised (full list in
  config\modded-vehicles.txt).
- Fixed Resubscribe failing after Steam had already removed the mod's files.

## 1.1.1

- Fixed the Start menu and desktop shortcuts from the 1.1.0 installer, which pointed at a
  PowerShell path Windows Explorer can't open. Updating from 1.1.0 repairs them.

## 1.1.0

- **Installer and automatic updates.** Install DayZ Solo with `DayZSolo-Setup.exe` (no admin
  needed). The app tells you when a new version is out, shows what changed and updates itself
  with one click; your settings and world stay as they are.
- **Mods stay up to date like DZSA**: before every launch and join, Steam downloads newer
  versions of your mods and subscribes to ones your friend uses. The Mods tab shows which mods
  are out of date and has Update and **Resubscribe** buttons.
- Every setting saves by itself and survives updates.
- Cash, ATMs and Bitcoin mining with QoL Mining, QoL ATM and CJ187-MoreMoney.
- Trader tab: prices, categories, per-piece and sell-only items.
- Co-op hosting and joining with invite codes.
- Fixed "Circular addon dependency in 'SoloSurvivor'" when starting DayZ.

## 1.0.0

- First version: private local server, Workshop mod loading, Solo Shop, minimap, events,
  bandits, loot settings and the control panel.
