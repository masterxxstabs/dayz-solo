# DayZ Solo

Play DayZ fully single-player, offline from other people, with any mods you like.

DayZ has no real offline mode, so this launcher runs a **private DayZ server on your own PC**
(1 slot, random password), loads your mods on both the server and the game,
connects you to it, and shuts the server down cleanly (saving the world) when you quit.
Your character, bases, stashes and loot persist between sessions like on a normal server.
Turn on **co-op** and up to 9 friends can join your world (see *Co-op with friends*).

## Requirements

- Windows 10/11, DayZ on Steam, Steam running.
- **DayZ Server** (free): Steam > Library > dropdown "Tools" > *DayZ Server* > Install.
  The launcher offers to open this install for you if it is missing.

## Install

1. Download **`DayZSolo-Setup-<version>.exe`** from the
   [latest release](https://github.com/masterxxstabs/dayz-solo/releases/latest) and run it.
   It installs for your Windows user only (in `AppData\Local\Programs\DayZ Solo`), so it needs no
   admin rights, and adds DayZ Solo to the Start menu (and the desktop if you tick it).
   - The installer isn't code-signed, so Windows may say *"Windows protected your PC"*: click
     **More info**, then **Run anyway**.
2. **DayZ Solo** opens its control panel in its own window. Press **Play**. The server starts in
   the background without a window, and DayZ opens and joins it when it's ready. The first start
   takes a few minutes while the world is built.

**Updates install themselves.** The app checks for a new version when it starts and every few
hours. A banner shows what's new; **Update now** closes the app, installs the update and opens
it again. Your settings (`config\`) and your world are kept. Tools > Updates checks right away.
It never updates while your server or DayZ is running.

**Portable zip.** Each release also has `DayZSolo-<version>.zip`: unzip anywhere (not inside the
Steam folders) and double-click `DayZ Solo.bat`. The zip copy tells you about new versions but
doesn't install them; run the installer once to switch to automatic updates. Coming from an
older zip? Copy `config\launcher.json` and `config\SoloSurvivor.json` from the old folder into
the installed folder's `config\` to keep your settings.

Uninstall from Windows Settings > Apps. Your settings files in the install folder are left in place.

Quit from the in-game menu (**Exit**). With "Stop the server when I close DayZ" ticked, the
server then saves the world and stops by itself.

### The control panel

- **Dashboard** - Play, Start server only (headless), Join game, Stop server; uptime, server
  CPU and memory, in-game time; your survivor's health, blood, position and whether you're in
  a safe zone; send a message that pops up in game.
- **Logs** - live launcher output, the server's `.RPT` log and the script log, with a filter.
- **Mods** - everything detected, in load order, with what each mod waits for and anything it
  is missing. Untick a mod to leave it out.
- **Settings** - name, map, loot multiplier, day/night speed, starting items, fixed spawn,
  safe zones, and the raw settings files.
- **Admin** - pick a connected player and give, take or set their Solo Shop money, or
  teleport them to the trader, any event location on the current map, or exact X/Z
  coordinates (they land on the ground; a vehicle they're driving comes along).
- **Tools** - the Loot & Spawn Editor (loads your mission files directly) and shortcuts to the
  mission, server profile and settings folders.

The panel only answers on this PC (`localhost`) and only to the window `DayZ Solo.bat`
opened. Closing the app leaves a running server running; open the app again to see or stop it.

`Launch DayZ Solo.bat` still works if you prefer the old one-click console launcher.

## Co-op with friends

Your world, your server, a few friends. Everyone needs DayZ, this DayZ Solo folder (the same
version) and the same mods.

**Host (once):**

1. App > **Settings > Co-op**: tick **Host co-op**, set how many players (2-10, you included)
   and a password (or leave it empty and DayZ Solo picks one and keeps it). It saves by itself.
2. Pick how friends reach your PC (below), then press **Play** as usual.
3. Open the **Co-op** tab, pick the address, press **Copy invite code** and send it to your
   friends (Discord, Steam chat...). The code holds the address, port, password and the list of
   mods with their Workshop IDs.
4. Press **Allow through Windows Firewall** once and accept the admin prompt.

**Friends:** app > **Co-op** tab > paste the code > **Join** (or double-click
`Join Friend.bat` and paste it there). DayZ Solo checks they have every mod first; anything
missing is listed with an **Open in Workshop** button. Subscribe, let Steam download, press
Join again. No invite code? The "enter the details by hand" box takes an address, port and
password and loads the friend's own mods.

**How friends reach you** - pick one:

| Way | Setup | Address to share |
|---|---|---|
| **Tailscale** (easiest, free) | Everyone installs Tailscale and signs in; invite friends to your tailnet or share this PC with them from the Tailscale admin console | Your `100.x.x.x` address; DayZ Solo lists it as *Tailscale* |
| **ZeroTier** (free) | Create a network at my.zerotier.com, everyone joins it with the network ID, you tick *Auth* for each member | Your ZeroTier address (listed as *ZeroTier*) |
| **Port forwarding** | In your router, forward **UDP 2302-2305** to this PC's home-network address (shown on the Co-op tab). Some ISPs (CGNAT) make this impossible; use Tailscale then | Press **Use my public IP** |
| **Same house** | Nothing | The *Home network* address |

What changes in co-op:

- The server has the slots and password you chose, and **voice chat is on**.
- Shop money, events, safe zones and admin tools work per player; the Admin tab lists everyone.
- **The server keeps running while friends play, even after you quit.** When the last player
  leaves it waits 2 minutes, saves and stops. In the app, closing your own game does the same.
- If a friend is kicked for signatures or "different version", make sure you both have the
  same DayZ Solo version and the same mod versions (let Steam finish updating).

## Adding mods

Just subscribe to mods on the Steam Workshop and let Steam finish downloading them.
The launcher picks up **every subscribed DayZ mod automatically** on the next launch.

- **Load order is worked out for you.** The launcher reads each mod's addon data
  (`CfgPatches` / `requiredAddons` inside its PBOs) and loads dependencies such as
  Community Framework before the mods that need them.
- If a mod needs something you aren't subscribed to, the launcher warns you, for example:
  `@SomeMod needs addons no loaded mod provides: JM_CF_Scripts`. Subscribe to that mod's
  "Required items" on its Workshop page.
- Double-click **`List Mods.bat`** to see every detected mod and the exact load order.
- To skip a subscribed mod, add its Workshop ID or `@Name` to `"excludeMods"`:

  ```json
  "excludeMods": ["1559212036", "@SomeMapMod"]
  ```

- To pick mods by hand instead, set `"autoWorkshopMods": false` and list them in `"mods"`
  (Workshop ID, `@Name` or full folder path). Mods in `"mods"` are always loaded, even if
  they're excluded from auto-detection.
- Mods that should only run on the server go in `"serverMods"` or the `server-mods\` folder.
  These are taken out of the auto-detected list.
- Local, non-Workshop mods: drop the `@Folder` into `mods\` (loaded on both sides).
- Unsigned mods (no `.bikey`): script-only ones load on the server only, so signature checks
  stay on. Unsigned mods with items or models (they need to be on your PC too) load on both
  sides, and signature checks go off on your private server.
- If you are kicked for a signature error, set `"verifySignatures": false`.
- **Mods > Mod settings files** in the app edits the settings files mods keep in the server
  profile (JSON), with a check that they're still valid JSON and a backup of the original.
- Map mods (Namalsk, Deer Isle, ...) and big mods such as DayZ Expansion also need their
  mission folder in the DayZ Server's `mpmissions`; set `"map"` to that mission's suffix.
  Exclude map mods you aren't currently playing to save memory and loading time.

Recommended solo picks: **Community Framework** + **Community Online Tools** (admin menu:
teleport, spawn items, change time/weather — effectively a single-player cheat menu).

## Keeping mods up to date (like DZSA)

Steam normally only updates DayZ Workshop mods when it gets round to it, and a mod that is a
version behind your friend's (or half-downloaded) gets you kicked. DayZ Solo handles it the way
the DZSA launcher does:

- **Before every launch and every join** the launcher asks the Steam Workshop which of your mods
  have a newer version, subscribes to any your friend uses that you don't have, and has Steam
  download them straight away. You see the progress in the launcher output (Dashboard and Logs)
  or, when joining, on the Co-op tab. If Steam can't be reached it carries on with what you have.
- **Mods tab**: every Workshop mod shows *up to date*, *update available*, *not downloaded* or
  *removed from the Workshop*. The tab checks by itself when you open it (at most every 15
  minutes), or press **Check for updates**. **Update all** downloads everything out of date;
  each mod also has its own **Update**/**Download** button.
- **Resubscribe** on a mod: unsubscribes, lets Steam delete it, subscribes again and downloads a
  fresh copy. Use it when a mod is broken, half-updated, or you keep getting kicked for it.
- **Join a friend**: missing mods get a **Subscribe & download** button instead of a link.

How it works: to ask Steam for downloads, DayZ Solo uses DayZ's own `steam_api64.dll` the same
way the DZSA launcher does, so for a moment Steam shows you as *playing DayZ*. Steam must be
running and signed in to the account that owns DayZ. Updating and resubscribing need the server
stopped and DayZ closed (files in use can't be replaced); checking works any time.

Turn it off with Settings > "Update Workshop mods before every launch and join", or
`"modUpdates": { "checkBeforeLaunch": false }`. `"timeoutMinutes"` (default 20) is how long to
wait for one mod to download.

## Loot & Spawn Editor

Double-click **`Loot Editor.bat`**. It copies your mission folder's path to the clipboard and
opens the editor in your browser. Click **Open mission folder**, paste the path into the
address bar, and pick the folder.

- **Items** - every item's `nominal` (how many on the map), `min` (restock threshold),
  lifetime, restock time and quantity. Includes items from mods' own types files listed in
  `cfgeconomycore.xml`. Filter by name, category or location, then apply bulk changes to
  everything that matches, e.g. "Spawn amount ×2" on all weapons, or "Stop spawning".
- **World** - `globals.xml`: max zombies and animals, cleanup timers, loot damage, login and
  logout timers.
- **Events** - `events.xml`: vehicles, heli crashes, animal herds and zombie groups, with
  nominal, min, max and an on/off switch.

Quit the game before saving. Changes take effect on the next launch. The first save of each
file keeps the original as `<file>.dayzsolo-backup` next to it. Use Edge or Chrome; other
browsers can use **Open XML files…** and copy the downloaded files back by hand.

Steam updates to DayZ Server can replace these files, so keep a copy of anything you tune.

## Traders and safe zones

1. Subscribe to **Trader** by Dr. Jones (the trader mod itself) and, for DayZ 1.29+,
   **Trader_FIX** by GloryStar (fixes buying). Nothing to put in the config: both are
   auto-detected. Trader_FIX is listed under `"serverMods"` in `config\launcher.json`
   so it loads on the server only, as its author asks.
2. Launch once. The launcher copies the Trader mod's example setup into `config\Trader\`
   and installs it into the server profile (`DayZServer\profiles_solo\Trader\`) on every
   launch. Edit prices, items and trader positions in `config\Trader\`; the copy in the
   server folder is overwritten each launch.
3. **Mod items are added to the trader automatically.** On each launch the launcher reads the
   base game's item list (cached after the first time) and every loaded mod, finds the items
   the mods add, and appends them to the last trader in categories like
   `Modded Weapons`, `Modded Clothing` and `Modded Food & Drink`.
   - Prices per category are in `config\launcher.json` under `autoTraderPrices`
     as `[buy, sell]`.
   - `autoTraderTarget` picks which trader gets them (the name after `<Trader>`); empty
     means the last one.
   - The list of what was added is in `config\trader-mod-items.txt`. To give an item its
     own price, add its line to `config\Trader\TraderConfig.txt`; items already in your
     config are never duplicated or repriced.
   - Set `"autoTraderItems": false` to turn this off.
4. **One central trader.** The default setup has a single safe zone, `Central Trader`, near
   the middle of Livonia (approximately 6400, 6400). To put it exactly where you want it, stand
   on the spot in game and press **Put the trader here** on the app's Dashboard; the safe zone
   and its map markers move there from the next server start. The trader NPC itself is placed
   by the Trader mod's own config (`config\Trader\`), so move it to the same spot there.

Note: the Trader mod's own config format is documented on its Workshop page. If it
expects its files somewhere other than the server profile's `Trader` folder, follow its
instructions.

## Heli crashes and airdrops

The Solo Survivor server mod runs its own events while you play:

- **Heli crash** - a downed UH-1Y or Mi-8 wreck, military loot scattered around it and a
  few soldier zombies guarding it.
- **Airdrop** - a wooden crate full of supplies, a red smoke grenade going off beside it and
  some zombies nearby.

When one happens you get a notification such as *"A helicopter went down - about 3.2 km
north-east of you, near Stary Sobor."* With the minimap on, it also shows up there.

- By default the first event comes after 10 minutes, then one every 30-60 minutes, at most
  2 at a time. Each lasts 45 minutes, and is never removed while you are within 150 m.
  Anything you've picked up is yours to keep.
- Events avoid safe zones, buildings, trees, water and your own position.
- In the app: **Dashboard > Events** lists active events and has **Trigger heli crash**,
  **Trigger airdrop** and **Clear events**. **Settings > Events** switches them on/off and
  sets how often they happen.
- Everything else is under `"Events"` in `config\SoloSurvivor.json`: the wreck and crate
  classes (`Objects`), `Loot` and `LootCount`, `Zombies` and `ZombieCount`, the
  `Announcement` text, and the `Locations` list (`Name`, `MapName`, `Position`, `Radius`).
  The defaults cover 9 Livonia areas (Lukow airfield, Brena, Topolin, Sitnik, Radunin,
  Nadbor, Grabin, Polana, Kolembrody) and 10 Chernarus areas; only the ones for the map you
  play are used. For Sakhal add locations with `"MapName": "sakhal"`.
- Class names that don't exist are skipped and logged in the server's script log, so mod
  items can be added to the loot lists too.
- The base game also has its own heli crashes. To only get these, switch off
  `StaticHeliCrash` in the Loot Editor's **Events** tab.

## Modded cars

Subscribe to a car mod and it joins the car spawns automatically (`"moddedVehicles": true`,
or Settings > "Add modded cars to the car spawns"). On each launch the launcher:

1. finds the cars and boats your mods add (classes built on the game's car/boat base);
2. adds them to the server's `types.xml` - using the mod's own entry when it ships one,
   otherwise a standard car entry;
3. adds them to every car spawn event in `events.xml` (boats to the boat events), so they
   spawn at the same spots as the base-game cars, mixed in with them;
4. copies the mod's **parts setup** (`cfgspawnabletypes`) and its parts' loot entries when the
   mod ships them as XML files, so the cars spawn with wheels, doors, battery and so on.

If a car mod doesn't ship a parts setup, the launcher builds one: it reads which attachment
slots the car has (wheels, doors, hood, trunk, battery, radiator, spark plug, lights...) and
which parts fit each slot, preferring the car mod's own parts, and spawns them on the car
(`moddedVehiclePartChance`, default `1` = complete). The launcher output lists the cars it
added and the ones it built a parts setup for. Only a car with no matching parts at all is
reported as spawning without parts. Everything
is put back when the server stops, like the other settings.

## Solo Shop (trader on a key)

A full trader you open anywhere with **B** (Esc or the X closes it). Turn it on in the app's
**Trader** tab (or `"shop": { "enabled": true }` in `config\launcher.json`).

### The Trader tab

- **Shop**: on/off, only inside the trader safe zone, starting money, how much the trader pays
  (% of the buy price), a **price multiplier** for the whole shop, and whether rare items cost
  more.
- **Categories**: rename them, change their order (↑ ↓), hide them, set the base price of an
  average item and a category's own sell %. **Add category** makes your own (e.g.
  *Favourites*, *Base building*), then move items into it.
- **Items**: every item the shop can sell, from the base game and your mods (press **Scan
  items** once; starting the server with the shop on refreshes the list too). Search, filter by
  category, "changed by you", hidden, mod items or vehicles; per item set a fixed buy and sell
  price, move it to another category or hide it. **Bulk buttons** (move, price ×, hide, show,
  reset) apply to everything matching the search and filters. Empty price boxes show the
  automatic price in grey.
- **Trader mod (NPC)**: the buy/sell prices per category for mod items added to Dr. Jones'
  Trader mod, and the switch for adding them.

Changes save by themselves to `config\launcher.json` and apply the next time the server starts. The
trader never pays more than the buy price, so a typo can't make free money.

- **Layout** (in the style of TraderPlus): your name and money in the header; **Market**,
  **Inventory** and **Vehicles** on the left; in the middle a search box, a category bar
  with < > arrows and a 5x3 grid of item cards (3D preview, name, price, and a green dot on
  items you already own) with pages; on the right **Product Information** with a large
  preview, how many you own, quantity < > and side-by-side **BUY** and **SELL** buttons.
- **Inventory** lists what you're carrying that the trader buys. The price scales with how
  full a magazine, ammo stack or bottle is. Clothes you're wearing and anything with items
  inside or attachments on it aren't offered, so you can't sell your gear by accident.
- **Vehicles**: bought cars and boats are delivered 8 m in front of you with every part fitted
  (wheels, doors, battery, radiator, spark plug, lights...) and fuel, oil, coolant and brake
  fluid filled. Modded cars are included.
- **Money** is a balance kept by the server per survivor
  (`DayZServer\profiles_solo\SoloShop\balances.json`), starting at `startingBalance`. You earn
  it by selling. Every purchase and sale is checked by the server.
- **The catalog** is rebuilt by the launcher every launch: every base-game item in the loot
  files (including event-only gear and car parts) plus every item your mods add, each in its category. Prices come from `prices` per category,
  scaled by rarity (very common items 0.6x, rare ones up to 3x); set exact prices for single
  items on the Trader tab. The trader pays `sellPercent` (40%) of the buy price.
- `"requireTraderZone": true` only lets you shop inside the trader safe zone.

It is part of the `@DayZSolo` mod and off by default; the server tells the game whether it is
on, and B does nothing while it's off.

## Cash, Bitcoin mining and ATMs (QoL Mining + QoL ATM + MoreMoney)

These three Workshop mods work together with the Solo Shop:

| Mod | What it adds |
|---|---|
| **QoL Mining** (damninja) | Bitcoin mining rigs for your base: graphics cards, fans, batteries, solar panels |
| **QoL ATM** (damninja, required by QoL Mining) | ATMs with a bank account for cash and Bitcoin, and a Bitcoin price that moves every hour |
| **CJ187-MoreMoney** | The cash itself: DayZ Solo uses its US dollar bills |

Subscribe to all three and launch. They are picked up like any other mod (both sides, in the
right order, with their keys). Then:

1. **First launch**: QoL ATM and QoL Mining write their settings files, and the server measures
   the ground at your trader. Nothing else to do.
2. **From the second launch**:
   - **Cash.** The shop gets **CASH OUT** (type an amount: you get it in dollar bills, biggest
     first) and **PAY IN ALL CASH** (every bill you carry, wallets included, goes into your
     shop money). The same bills, at the same worth, are added to the ATM's money list, so the
     ATM takes and pays out the same cash. Bills are never sold as items.
   - **ATMs.** One ATM stands 4 m east of every trader safe zone. Add more where you stand
     with **Dashboard > Place an ATM here**; it appears 1.5 m in front of you, facing you,
     after the next restart.
   - **Mining speed.** In solo the server only runs while you play, so a rig only mines while you
     play. DayZ Solo sets the best rig to one Bitcoin per **120 minutes of play** instead of the
     mod's 8 hours.
   - **Loot.** QoL Mining's `mining_ce` loot (rig parts in offices, towns and industry; the best
     cards, batteries and panels rare) is added to the server for every session (see *Mods' own
     loot* below).
3. **The money loop**: mine Bitcoin, carry it to an ATM, deposit it and sell it at that hour's
   price, withdraw dollars, then press PAY IN at the shop (B). Or keep the Bitcoin in the bank
   and wait for a better price.

Change it all on the app's **Trader** tab under *Cash, ATMs and Bitcoin mining*:

- Cash on/off and the currency (dollars, or MoreMoney's rubles, euros or marks). Each bill's
  worth comes from the number in its class name; set your own in the table.
- The trader ATM on/off and which way it faces, and your placed ATMs (turn around, remove).
- Minutes of play per Bitcoin (0 leaves the mod's own setting alone).
- `QoL_Bitcoin` is hidden from the shop so the ATM is its only market. To let the shop buy it
  too, find it in the item list, tick **Show**, **per piece** and **sell only**.

Everything else (card speeds, battery sizes, ATM fees, price limits...) is in
`QoL\Mining.json` and `QoL\ATM.json`: **Mods > Mod settings files** in the app.

## Mods' own loot

Some mods ship loot tables for the server in folders named like `mining_ce` (for example in
their `ServerFiles` folder) and ask server owners to copy them into the mission and list them in
`cfgeconomycore.xml`. The launcher does that for you every launch, and puts `cfgeconomycore.xml`
back when the server stops:

- The folder is copied into the mission folder (with a `.dayzsolo-modloot` note in it). If you
  already have a folder of that name without the note, yours is used and left alone. Delete the
  note to keep your own edits.
- By default the loot multiplier is **not** applied to mods' own loot, so rare items stay rare.
  Settings > "Apply the loot multiplier to mods' own loot too" changes that.
- Settings > "Spawn mods' own loot" turns the whole thing off, or list folder names in
  `"modLoot": { "exclude": ["mining_ce"] }`.

## Roaming bandits (Expansion AI)

Hostile AI groups that wander the map, using **Expansion AI**'s `Raiders` faction.

1. Subscribe to **DayZ-Expansion-AI** on the Workshop, plus the mods its page lists under
   *Required items*. The launcher loads them automatically and warns if one is missing.
2. Launch once: Expansion creates its settings, and the Solo Survivor mod measures the
   ground height along the bandits' routes (the same areas as the heli crash and airdrop
   locations for your map).
3. From the next launch the launcher adds the bandit groups to
   `mpmissions\dayzOffline.<map>\expansion\settings\AIPatrolSettings.json` (entries named
   `DayZSolo Bandits ...`, replaced every launch; any other patrols are left alone) and
   turns patrols on.

Settings are under `"bandits"` in `config\launcher.json`, or **Settings > Bandits** in the app:
`groups`, `groupSize` (each group spawns 1 to this many), `accuracy` `[min, max]`,
`damageMultiplier`, `respawnMinutes`, `chance`, `behaviour` (`ROAMING` by default; Expansion
also offers `ROAMING_LOCAL`, `LOOP`, `ALTERNATE` and more), `militaryGear` and `loadout`.

With `"militaryGear": true` (the default) the launcher writes `DayZSoloBanditLoadout.json` next
to Expansion's own loadouts, built from Expansion's `HumanLoadout.json` with every clothing slot
swapped for base-game military gear: Gorka/TTsKO/M65/USMC camo, military/combat/jungle boots,
ballistic/MICH/Gorka helmets, plate carriers and tactical vests, tactical gloves, balaclavas,
military bags and belt. Each bandit gets one random item per slot. Weapons are left as
Expansion's loadout has them. To pick the clothing yourself, add for example
`"clothing": { "Body": ["GorkaEJacket_Summer"], "Headgear": ["BallisticHelmet_Green"] }` to
`"bandits"`. Set `"loadout"` to use a specific Expansion loadout file instead.
Any Expansion AI that walks into the trader safe zone is killed, so the trader stays safe.

## Random toxic gas strikes

With `"gasZones": "random"` (Settings > Toxic gas), the game's fixed and drifting gas zones
are switched off, and the Solo Survivor mod calls in **one gas strike at a time**:

- every 90-150 minutes (first one after 20), at a random spot anywhere on the map - never in
  a safe zone, in water or within 400 m of you;
- you get an alert like *"Toxic gas incoming - about 2.3 km north-east of you, near Brena."*
  and it shows on the minimap and in the app's Events list for 45 minutes;
- it is the game's own artillery gas: shells whistle in, then a green gas cloud settles over
  a ~120 m radius, thins out and disappears on its own;
- **Dashboard > Events > Trigger gas strike** calls one in straight away.

Timings are under `"Events" > "Gas"` in `config\SoloSurvivor.json`: `FirstStrikeMinutes`,
`MinIntervalMinutes`, `MaxIntervalMinutes`, `MarkerMinutes`, `MinDistanceFromPlayer` and the
`Announcement` text. Bring a gas mask and NBC gear if you want to loot inside.

## Minimap and map markers

**Solo Minimap** (part of the `@DayZSolo` mod) shows a small north-up map in the
top-right corner with you and the trader markers. Turn it on with **Settings > Minimap** in the
app (or `"enableMinimap": true` in `config\launcher.json`); the server tells the game whether
it is on, so nothing needs to be loaded or unloaded.

- **N** shows/hides it, **numpad +** zooms in, **numpad −** zooms out.
- It hides itself while a menu, the inventory or the map is open.

**Trader markers** come from your safe zones (`SafeZones` in `config\SoloSurvivor.json`, or
Settings > Safe zones in the app). Each one becomes a marker named `Trader: <zone name>`:

- on the Solo Minimap, and
- on **VanillaPlusPlusMap** - the launcher adds them to the server's `VPPMapConfig.json`
  each launch, replacing the ones it added before. VPP Map creates that file the first
  time the server runs with it, so the markers appear from the **second** launch. Markers
  whose names start with `Trader: ` are managed by the launcher; name your own something else.

## Settings

**Your settings are kept.** Everything you change in the app (Settings, Trader, Co-op, Mods,
the Dashboard switches) saves by itself as you change it; the header shows *Saving…* and then
*All changes saved*. There are no Save buttons to forget, except in the two raw file editors
(Settings > Advanced and Mods > Mod settings files), which warn you before you close the app
with unsaved text.

- Your settings live in `config\launcher.json` and `config\SoloSurvivor.json`. They are **not
  in the download**: the first start makes them from `config\defaults\`. So unzipping a new
  version over your folder never resets them, and options added by the new version are filled
  in from the defaults without changing anything you set.
- The app also remembers which tab you had open, the log you were reading and its filter, the
  Trader tab's search and filters, the co-op address you picked and what you typed to join a
  friend (`config\app-ui.json`).
- To start over, delete `config\launcher.json` and/or `config\SoloSurvivor.json`.
- Updating from a version before this one: your old zip *did* contain those two files, so
  extracting this one over it keeps whatever is there now.

`config\launcher.json`

| Key | Meaning |
|---|---|
| `autoWorkshopMods` | Load every subscribed Workshop mod automatically (default `true`) |
| `shop` | The Solo Shop trader (easiest from the Trader tab): `enabled`, `startingBalance`, `sellPercent`, `requireTraderZone`, `priceMultiplier`, `rarityPricing`, `prices` (base price per category), `categories` (order, `name`, `hidden`, `sellPercent`; your own have ids like `custom-...`) and `items` per class name: `buy`, `sell`, `category`, `hidden`, `perPiece`, `sellOnly`. Older `itemPrices` still work |
| `enableMinimap` | Show the Solo Minimap (part of `@DayZSolo`) |
| `cash` | Cash for the shop and QoL ATM: `enabled`, `currency` (`dollar`, `ruble`, `euro`, `mark`), `values` (class name: worth) to override the worth read from a bill's name, `pattern` for another money mod |
| `atm` | QoL ATMs placed by DayZ Solo: `atTrader` (one at every trader safe zone), `traderHeading` (degrees, 0 = north) and `machines` (`x`, `y`, `z`, `heading`) |
| `miningMinutesPerBitcoin` | Written into QoL Mining's `MinutesPerBitcoin` every launch (default 120); `0` leaves the mod's setting alone |
| `modLoot` | Mods' own loot folders: `enabled`, `applyLootMultiplier`, `exclude` (folder names) |
| `modUpdates` | `checkBeforeLaunch` (default `true`): before each launch and join, subscribe to missing Workshop mods and have Steam download any that are out of date. `timeoutMinutes` (default 20) per mod |
| `coop` | Co-op hosting: `enabled`, `maxPlayers` (2-10, you included) and `password` (letters, digits, `-`, `_`; empty = generated once and kept in `config\.coop-password`) |
| `excludeMods` | Workshop IDs or `@Names` to leave out of auto-detection |
| `zombieMultiplier` | Scales zombie spawns while you play: the nominal/min/max of every `Infected...` event in `events.xml` and the map-wide `ZombieMaxCount`. `0.5` = half, `0` = none. Restored when the server stops |
| `vehicleMultiplier` | Scales car (and boat) spawns while you play: the nominal/min/max of every `Vehicle...` event in `events.xml`. Each car type can only appear at its spawn spots in `cfgeventspawns.xml`, so that caps how far this goes. Restored when the server stops |
| `moddedVehiclePartChance` | For modded cars whose mod ships no parts setup: the chance each part (wheels, doors, battery, ...) spawns on the car. `1` = always complete |
| `moddedVehicles` | Find cars and boats added by your mods and spawn them alongside the base-game ones (see below) |
| `lootRespawnSpeed` | `normal`, `fast` (restock timers halved; each respawn cycle covers 40 item types but at most 8 of each, so loot stays varied) or `veryfast` (timers quartered; 60 types, at most 10 each) |
| `gasZones` | `"random"` (default): the map's own gas zones are off, and instead one random toxic gas strike lands somewhere on the map every 90-150 minutes, with an alert telling you how far and in which direction it is and the nearest place. `"off"`: no gas at all. `"default"`: the game's normal gas zones. Settings > "Toxic gas" in the app |
| `lootVariety` | `true` (default): the loot multiplier gives rare items the full boost but common ones at most double (or +40 on the map), so common items don't crowd everything else out of the spawn spots |
| `globalsOverrides` | World settings from `globals.xml` to change while you play, e.g. `{"FoodDecay": 0}` so food never rots. Restored when the server stops |
| `lootCategoryMultipliers` | Extra multipliers per loot category on top of `lootMultiplier`, e.g. `{"food": 2}` for double food and drink (all eating and drinking items are in the `food` category). Other categories: `weapons`, `tools`, `clothes`, `containers`, `explosives` |
| `lootMultiplier` | Multiplies every item's spawn amount (`nominal` and `min` in all types files) while you play, e.g. `5` for 5x loot. Originals are restored when the server stops |
| `map` | `enoch` (Livonia, the default; needs the Livonia DLC), `chernarusplus`, `sakhal` (Frostline DLC) or a modded mission suffix |
| `playerName` | Your survivor's name |
| `serverTimeAcceleration` / `serverNightTimeAcceleration` | Speed up day / night (e.g. 4 and 8 for short nights) |
| `disable3rdPerson`, `disableCrosshair` | Hardcore toggles |
| `clientPath`, `serverPath` | Only needed if auto-detection of the Steam folders fails |
| `extraClientArgs`, `extraServerArgs` | Extra command-line flags |

`config\SoloSurvivor.json` (read by the `@DayZSolo` mod on the server)

| Key | Meaning |
|---|---|
| `ShutdownServerWhenEmpty` | Save and stop the server after the last player leaves (keep `true`; 2 minutes after in co-op) |
| `UseFixedSpawn` / `FixedSpawnPosition` | Always spawn fresh characters at `[x, y, z]` (y is ignored) |
| `ExtraStartingItems` | Class names added to new characters, e.g. `["Hatchet", "Canteen", "BandageDressing"]` |
| `AlwaysDay` / `DayStartHour` / `DayEndHour` | Keep it daytime: the server starts at 09:00 on a summer day, and whenever the clock passes `DayEndHour` (19) or is before `DayStartHour` (7) it jumps back to `DayStartHour`. Turn off for normal day/night |
| `WelcomeMessage` | Notification shown when you join (`""` to disable) |
| `SafeZones` | Areas where you can't be hurt and zombies/animals are removed. Each has `Name`, `Position` `[x, y, z]` (y ignored) and `Radius` in metres. Defaults: Green Mountain and Kumyrna (Chernarus) |

Loot, zombie counts, animals and vehicles are controlled by the server's normal mission files:
`DayZServer\mpmissions\dayzOffline.<map>\db\types.xml`, `cfgeconomycore.xml`, `cfggameplay.json`.

## Where things live

- Your settings: `config\launcher.json`, `config\SoloSurvivor.json` and `config\app-ui.json`
  (back them up with your world if you like); the defaults they start from are in
  `config\defaults\`.
- World save: `DayZServer\mpmissions\dayzOffline.<map>\storage_1` — back it up to keep a run.
  Delete it to wipe the world and character.
- Logs: `DayZServer\profiles_solo\*.RPT` (look here first if something fails).
- The launcher creates `SoloMods\` link folders inside both DayZ directories; they're
  rebuilt on every launch and safe to delete.

## Command line

```
powershell -ExecutionPolicy Bypass -File DayZSolo.ps1 [-ListMods] [-ServerOnly] [-Headless] [-ConfigPath other.json]
powershell -ExecutionPolicy Bypass -File DayZSolo.ps1 -Invite DZSOLO1-...
powershell -ExecutionPolicy Bypass -File DayZSolo.ps1 -OpenFirewall
```

`DayZSoloWorkshop.ps1 -Action check|update|resubscribe -Ids 1559212036,1590841260 -ClientDir "<DayZ folder>"`
checks, updates or resubscribes Workshop mods on its own (what the app's Mods tab runs).

`-Invite` joins a friend from their invite code (what `Join Friend.bat` runs). `-OpenFirewall`
adds the Windows Firewall rule for co-op hosting (one admin prompt).

`-ServerOnly` starts just the server and keeps it running until it is stopped (the app sends the
stop command); `-Headless` hides the server window. The app itself is `app\DayZSoloApp.ps1`
(`-Port` to change its port from 7781).
Use different config files (e.g. one per map/mod pack) with `-ConfigPath`.

## The DayZ Solo mod and the Workshop

Everything game-side is one mod, `dayzsolo-mod\@DayZSolo`, loaded on the game and the server
every launch. It holds three PBOs: `SoloSurvivor` (server helpers, events, status for the
app), `SoloShop` and `SoloMinimap`. The shop and minimap switch on and off from the settings,
without loading anything else.

- If you're subscribed to DayZ Solo on the Steam Workshop, the launcher uses that copy (and
  friends in co-op get its Workshop ID in the invite code); otherwise it uses the copy in this
  folder.
- Folders from earlier versions (`server-mods\@SoloSurvivor`, `optional-mods\`) are no longer
  used; delete them.
- Run it on a regular dedicated server: load `@DayZSolo` with `-mod` and copy its
  `Keys\DayZSolo.bikey` to the server's `keys`. Without the launcher everything starts off: no
  events, shop, minimap or auto-shutdown until the profile's `SoloSurvivor\settings.json`,
  `SoloShop\catalog.json` (`"Enabled": true`) and `SoloMinimap\markers.json` say so.

### Rebuilding, signing and releasing

Sources are in `src\SoloSurvivor`, `src\SoloShop` and `src\SoloMinimap`
(`src\SoloSurvivor\config.cpp` holds the `DayZSolo` mod definition for all three).

```
python tools\build_shop_layout.py
python tools\build_pbo.py src\SoloSurvivor dayzsolo-mod\@DayZSolo\Addons\SoloSurvivor.pbo SoloSurvivor
python tools\build_pbo.py src\SoloShop dayzsolo-mod\@DayZSolo\Addons\SoloShop.pbo SoloShop
python tools\build_pbo.py src\SoloMinimap dayzsolo-mod\@DayZSolo\Addons\SoloMinimap.pbo SoloMinimap
powershell -ExecutionPolicy Bypass -File tools\sign_mod.ps1
```

- `tools\sign_mod.ps1` uses **DayZ Tools** (free on Steam): it creates your signing key in
  `signing\` the first time, signs the three PBOs and puts `DayZSolo.bikey` in the mod's `Keys`.
  `-Rebuild` repacks the PBOs with AddonBuilder instead of Python. Keep `signing\` safe and
  private.
- `tools\check_scripts.py` checks the scripts against the game's own (`scripts.pbo`) for the
  mistakes that stop DayZ from compiling them; run it after every DayZ update.
- `tools\make_release.ps1` zips the launcher for sharing, leaving out your key, tokens,
  passwords, logs and Trader setup.
- `workshop\WORKSHOP.md` has the Workshop page text and settings, `workshop\preview.png` the
  preview image, and `workshop\RELEASE-CHECKLIST.md` the steps and in-game tests for each
  release.

## Notes

- This never touches official servers. Your private server runs BattlEye and the game starts
  through `DayZ_BE.exe`, like the official DayZ Launcher does it. On a slow PC BattlEye kicks a
  game that is busy loading for about a minute; untick "Use BattlEye" in Settings to start the
  server without it. The launcher then checks whether the server really left BattlEye off and
  starts the game to match, so you're never kicked for a mismatch. Nothing is patched.
- Steam must be running and you must own DayZ.
