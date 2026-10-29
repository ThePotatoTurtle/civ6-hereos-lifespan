# Show Hero Lifespans

Show Hero Lifespans extends the Civilization VI Heroes screen with the actual remaining lifespan of claimed heroes. Your active heroes appear first, followed by other active heroes ordered by turns remaining, then unclaimed and fallen heroes. Heroes with five or fewer turns remaining are shown in red. An unmet owner is displayed as **Unknown civ**.

Unclaimed heroes show their base lifespan. Fallen heroes are labeled **Fallen**; their death turn is unavailable. The original recall action remains available, with recall eligibility shown only for your own heroes. The game's existing filter for undiscovered, unclaimed heroes is unchanged.

Requires Gathering Storm, the Babylon Pack, and Heroes & Legends mode. The production mod is UI-only. Its layout, multiplayer behavior, and adding or removing it from a saved game still need live validation.

## Install

Close Civilization VI and specify an existing Mods folder. The default installs both the production mod and the optional spike tools:

```powershell
.\tools\install.ps1 -TargetModsPath 'C:\path\to\Civilization VI\Mods'
```

To install only the spike tools, add `-DevOnly`.

## Optional spike tools

In a disposable hotseat game with three humans and one AI, have each human recruit a hero through normal play. Open **Hero Lifespan Spikes** with Ctrl+Shift+D. Use **Run All Spikes** and **Visibility Check** for observations, then **Meet Humans 1 & 2** and **Meet All + Relationships** for staged diplomacy checks. The tools do not spawn heroes; the diplomacy actions change the test game.

After exiting to the desktop, summarize the completed log with `python tools/summarize_log.py 'C:\path\to\Lua.log'`. `UNVERIFIED` means an in-game check is still needed.

## Local checks

Use Python 3.11 and `lupa` with Lua 5.1 support:

```powershell
python tools/check_all.py
python tests/offline/run_tests.py
powershell -NoProfile -File tests/offline/check_installer.ps1
```

Offline tests cannot establish live engine, layout, save, or multiplayer behavior.
