# Release checklist

Go through this for every release, in order. Tick each box in a copy of this file.

## 1. Version

- [ ] Put the new version in the `VERSION` file, e.g. `1.2.0`. The launcher, the app, co-op
      invite codes and the installer all read it from there.
- [ ] Add a `## 1.2.0` section at the top of `CHANGELOG.md`: it becomes the release notes the app
      shows under "What's new".
- [ ] If the mod changed: `version` in `dayzsolo-mod\@DayZSolo\mod.cpp` and in
      `src\SoloSurvivor\config.cpp` (`CfgMods > DayZSolo`).

## 2. Scripts still compile against the current DayZ

Do this after every DayZ update too, even without changes of your own.

- [ ] Unpack the game's scripts:
      `python -I tools\unpbo.py "<DayZ>\Addons\scripts.pbo" "%TEMP%\dayz-scripts"`
- [ ] `python -I tools\check_scripts.py "%TEMP%\dayz-scripts" src` reports
      `name clashes: 0 | duplicate declarations: 0 | reserved words: 0` and `config problems: 0`
      (no addon that needs itself or loops through other addons: DayZ refuses to start with
      "Circular addon dependency").

## 3. Build and sign

- [ ] Shop layout changed? `python tools\build_shop_layout.py`
- [ ] Pack the three PBOs, either
      `python tools\build_pbo.py src\<Name> dayzsolo-mod\@DayZSolo\Addons\<Name>.pbo <Name>` for
      `SoloSurvivor`, `SoloShop` and `SoloMinimap`, or `tools\sign_mod.ps1 -Rebuild` (AddonBuilder).
- [ ] `powershell -ExecutionPolicy Bypass -File tools\sign_mod.ps1`
      - first time only: it creates `signing\DayZSolo.biprivatekey` and `.bikey`.
        **Back up `signing\`. Never upload or share the `.biprivatekey`.** Use the same key for
        every release, or servers and friends with the old `.bikey` reject the new files.
      - it ends with DSCheckSignatures passing.
- [ ] `dayzsolo-mod\@DayZSolo` now has `Addons\*.pbo`, one `.bisign` per PBO,
      `Keys\DayZSolo.bikey` and `mod.cpp`, and nothing else.

## 4. Test in game (local copy)

Solo:
- [ ] Play from the app: the server starts, DayZ joins, `Mods` shows `@DayZSolo` first.
- [ ] `Logs > Script log` has no `SCRIPT (E)` lines from `SoloSurvivor`, `SoloShop` or `SoloMinimap`.
- [ ] Signature checks stay on when every loaded mod is signed (the launcher output does
      **not** say "Turning off mod signature checks").
- [ ] Shop off: B does nothing. Shop on (Settings > Trader shop, restart): B opens the shop,
      buy, sell and buy a vehicle.
- [ ] Trader tab: Scan items lists base-game and mod items. Rename the Vehicles category, add a
      custom category, move an item into it, give it a fixed price, hide another; restart: the
      shop shows all of it, and the Vehicles button still opens the renamed category.
- [ ] Minimap off: nothing on screen. On: shows, N toggles it, numpad +/- zoom, trader marker.
- [ ] Events: Trigger heli crash, airdrop and gas strike; each gives an alert and a marker.
- [ ] Admin tab: give money, teleport to the trader.
- [ ] Quit DayZ: the server saves and stops; your character is still there next time.
- [ ] Bandits with DayZ-Expansion-AI subscribed (if you ship that feature).

QoL Mining + QoL ATM + MoreMoney (subscribe to all three; launch twice):
- [ ] Second launch output lists the dollar bills and "ATMs placed by DayZ Solo", and
      "QoL Mining: the best rig mines a Bitcoin in 120 minutes of play".
- [ ] An ATM stands next to the trader; Place an ATM here adds one in front of you after a
      restart; Turn around on the Trader tab turns it.
- [ ] Shop: CASH OUT 1,234 gives bills worth exactly that, and the balance drops by the same;
      PAY IN ALL CASH (with bills in a wallet too) puts it all back. Full inventory: bills land at
      your feet, nothing is lost.
- [ ] ATM: deposit and withdraw dollars; sell a mined Bitcoin; pay the cash in at the shop.
- [ ] Rig parts spawn as loot (mining_ce), and `cfgeconomycore.xml` is back to normal after
      the server stops.
- [ ] Shown + per piece + sell only on QoL_Bitcoin: the shop buys a stack of 3 for 3x the
      price and won't sell Bitcoin.

Mod updates and Resubscribe (Steam running):
- [ ] Mods tab: opening it shows a badge on every Workshop mod; Check for updates finishes.
- [ ] Unsubscribe from a small mod in Steam, then press Download on it: Steam subscribes and
      downloads it, the badge turns *updated*.
- [ ] Resubscribe a small mod: its folder disappears and comes back, the badge turns *updated*,
      and the game still loads it.
- [ ] Play with an out-of-date mod: the launcher output shows "Checking N Workshop mods for
      updates" and the download progress before the server starts.
- [ ] Steam closed: Update all says it couldn't reach Steam; Play still starts.

Co-op (two PCs, ideally two Steam accounts):
- [ ] Host: Settings > Co-op on, Play. The Co-op tab shows the addresses and an invite code.
- [ ] Host: Allow through Windows Firewall (accept the admin prompt).
- [ ] Friend: Co-op tab > paste the code > Join. With a mod missing it lists the mod with
      "Open in Workshop"; after subscribing, Join gets in.
- [ ] Both see each other, voice chat works, both can use the shop with their own money.
- [ ] Host quits first: the server keeps running while the friend plays, and stops by itself
      about 2 minutes after the last player leaves.
- [ ] `Join Friend.bat` with the same code works too.

## 5. Publish the Workshop item

- [ ] DayZ Tools > Publisher: content folder `dayzsolo-mod\@DayZSolo`, preview
      `workshop\preview.png`, title and description from `workshop\WORKSHOP.md`, no Required items.
- [ ] First upload as **Private**. Subscribe, let Steam download it, and check `List Mods.bat`
      shows `@DayZSolo` coming from the Workshop folder (`...\workshop\content\221100\<id>`).
- [ ] Play once with the Workshop copy, then co-op once with a friend subscribed.
- [ ] Set visibility to **Public** and write the change note.
- [ ] Put the Workshop link in the launcher README and the download page.

## 6. Ship the launcher

- [ ] Commit and push to `main`; the **Checks** workflow on GitHub must pass (it parses every
      script with Windows PowerShell 5.1, compiles the C#, checks the page's JavaScript, asks the
      Steam Web API about a mod and starts the app).
- [ ] Pushing a changed `VERSION` to `main` starts the **Release** workflow (or run it by hand
      from the Actions tab). It runs the checks again, builds `DayZSolo-Setup-1.2.0.exe`
      (Inno Setup) and `DayZSolo-1.2.0.zip` (`tools\make_release.ps1`), writes `SHA256SUMS.txt`,
      creates the `v1.2.0` tag and publishes the release with the CHANGELOG notes. A version
      that is already published is skipped. Installed copies offer the update within a few hours.
- [ ] Install the new Setup over the previous version: settings and world are kept, the app
      opens again, and Tools > Updates says it is the newest version.
- [ ] From the previous installed version, **Update now** installs it and reopens the app.
- [ ] `tools\make_release.ps1` still works by hand: it leaves out `signing\`, the app token,
      session files, the co-op password, logs, caches and your Trader setup, and refuses to zip
      a `.biprivatekey`.
- [ ] The zip carries the **same signed** `dayzsolo-mod\@DayZSolo` you uploaded, so friends who
      aren't subscribed still match the host's signatures.
- [ ] Unzip it into an empty folder on a clean PC (or a fresh Windows user) and press Play.
- [ ] The zip has `config\defaults\` but no `config\launcher.json` or `config\SoloSurvivor.json`.
      Unzip it over an older install: the old settings are still there and new options appear.
      New settings keys go into `config\defaults\` (the app and launcher add them to existing files).
- [ ] The Workshop page links to https://github.com/masterxxstabs/dayz-solo/releases/latest.

## Never

- Never upload `signing\` or a `.biprivatekey`.
- Never bundle other people's mods in the zip or the Workshop item (Expansion, Trader, CF, ...).
  Link to them instead.
- Never upload anything from `config\` except the two default settings files.
