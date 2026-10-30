# Show Hero Lifespans

Show Hero Lifespans adds the exact remaining turns to living heroes on the Civilization VI Heroes screen. Your active heroes appear first, followed by other active heroes ordered by turns remaining, then unclaimed and deceased heroes. Heroes with five or fewer turns remaining are shown in red.

The game’s normal hero discovery and owner identity display remain in place. Unclaimed and deceased heroes show their regular base lifespan; the vanilla deceased label and recall action remain available.

Requires Gathering Storm, the Babylon Pack, and Heroes & Legends mode. The production mod is UI-only. A hotseat session and a disposable save add, reload, removal and add-back were observed with version 0.1.1. The next live check covers death and recall with 0.1.2.

## Install

Close Civilization VI and specify an existing Mods folder. The default installs both the production mod and optional spike tools:

```powershell
.\tools\install.ps1 -TargetModsPath 'C:\path\to\Civilization VI\Mods'
```

To install only the spike tools, add `-DevOnly`.

## Optional spike tools

Open **Hero Lifespan Spikes** with Ctrl+Shift+D in a disposable game. **Give Me 1000 Faith** adds faith for manual recall; **Run All Spikes** records diagnostic observations. After exiting to the desktop, summarize the completed log with `python tools/summarize_log.py 'C:\path\to\Lua.log'`. `UNVERIFIED` means an in-game check is still needed.

## Local checks

Use Python 3.11 and `lupa` with Lua 5.1 support:

```powershell
python tools/check_all.py
python tests/offline/run_tests.py
powershell -NoProfile -File tests/offline/check_installer.ps1
```

Offline tests cannot establish live engine or layout behavior.
