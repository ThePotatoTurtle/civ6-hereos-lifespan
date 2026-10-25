# Hero Lifespans

This repository currently contains a development spike kit for Civilization VI. It checks whether a UI context can read every hero's actual remaining lifespan in Heroes & Legends. The finished Heroes screen extension has not been built.

Requires Gathering Storm and the Babylon Pack, with Heroes & Legends enabled. The probes read game state and write results to Lua.log. Separate experimental developer buttons change a test scenario through synced gameplay requests. Use the kit only in a new test game. It declares that it does not affect saved games; adding and removing it from a save still needs an in-game test. Multiplayer behavior has not been tested.

Run the local checks with Python 3.11 and `lupa` with Lua 5.1 support:

```powershell
python tools/check_all.py
python tests/offline/run_tests.py
powershell -NoProfile -File tests/offline/check_installer.ps1
```

The installer requires an explicit existing Mods folder and refuses to run while Civilization VI is open:

```powershell
.\tools\install.ps1 -DevOnly -TargetModsPath 'C:\path\to\Civilization VI\Mods'
```

Start a new game with the development kit enabled. Open its panel with Ctrl+Shift+D and click **Run All Spikes**. After exiting the game to the desktop, summarize the completed log:

```powershell
python tools/summarize_log.py 'C:\path\to\Lua.log'
```

`UNVERIFIED` means an in-game check is still needed. Offline tests check the probe's behavior with a fake engine; they cannot prove that a game API works in a live UI context. The production mod remains blocked until the lifespan spike passes in the game.
