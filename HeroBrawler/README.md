# HeroBrawler

Marvel-inspired PvP hero battler (Rojo + Luau). First hero: **Monet St. Croix** with Monet/Penance dual form.

## Connect Rojo to Roblox Studio (you do this — not the AI)

The AI edits files on your PC. **Rojo** copies those files into Studio. You connect Studio yourself.

### One-time setup

1. **Install Aftman** (tool manager): https://github.com/LPGhatguy/aftman#installation  
2. **Install Roblox Studio** and the **Rojo plugin**: https://rojo.space/docs/v7/getting-started/installation/  
3. Open a terminal in this folder (`HeroBrawler`) and run:

```powershell
aftman install
```

That installs Rojo 7.7.0 locally for this project.

### Every time you work on the game

1. Open **PowerShell** or **Command Prompt** in this folder:

```
C:\Users\HP\OneDrive\Рабочий стол\RobloxCursor\HeroBrawler
```

2. Start the Rojo server (use one of these — **not** `aftman\bin\rojo.exe`):

```powershell
rojo serve
```

If that says "not recognized", use the full path:

```powershell
C:\Users\HP\.aftman\bin\rojo.exe serve
```

Leave this window open. You should see: `Rojo server listening on port 34872`.

3. Open **Roblox Studio** → **New** → **Baseplate** (or open an existing place).

4. In Studio, open the **Rojo** plugin tab → click **Connect**.

5. Press **Play** to test. When you die/respawn, pick **Monet St. Croix** from the bottom-left list.

### If Connect fails

- Make sure `rojo serve` is still running in the terminal.
- Try disconnect/reconnect in the Rojo plugin.
- Allow Windows Firewall for the Rojo port if prompted.

## Controls (Monet St. Croix)

| Key | Monet form | Penance form |
|-----|------------|--------------|
| **Q** | Telekinetic Lunge (force toward cursor) | Claw Frenzy Dash |
| **F** | Psychic Push (hold builds momentum → wave toward cursor) | Diamond Curl (hold, roll with WASD, release = burst) |
| **R** | Mind Probe | Razor Lacerate |
| **T** | Astral Dominion (ultimate) | Anguish Unleashed (ultimate) |
| **E** | Form swap (cancels ultimate if active, starts ult cooldown) | same |

- Cooldowns start **after** the ability finishes.
- Penance form HP: **350**. Monet form HP: **280**.

## What you still do manually in Studio

- **Particles / VFX** — placeholders are small neon cubes for now.
- **Animations** — add later per ability.
- **Map design** — baseplate + spawn are synced from Rojo; build arenas in Studio.
- **More heroes** — add entries in `src/shared/CharacterRegistry.luau`.

## Project layout

```
src/
  shared/     Config, helpers, remotes
  server/     Combat, Monet abilities, character select
  client/     HUD, character picker, input
```

## Sync direction

- **Code** (`.luau`) → edit in Cursor, syncs **into** Studio via Rojo.
- **Map/parts** you place in Studio → stay in the `.rbxl` place file unless you add them to `default.project.json`.

Save your place in Studio as something like `HeroBrawler.rbxl` so you don't lose map work.
