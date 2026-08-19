# ASMR Satisfaction Game

A cozy Roblox ASMR satisfaction experience built with [Rojo](https://github.com/rojo-rbx/rojo). **Just walk around** — sounds and effects trigger automatically when you enter stations. No clicking needed.

## Features

- **Walk-in ASMR** — Proximity zones auto-trigger sounds as you stroll through stations
- **Visual decor** — Rainbow paths, floating orbs, aurora pillars, cherry blossom tree, crystal fountain, fairy lights, fireflies, zen garden, rotating halo
- **Balloon Pop** — Pop colorful balloons with particles; they respawn after a few seconds
- **Bubble Wrap** — Pop a full sheet of bubbles
- **Slime Squish** — Squish neon slime blobs
- **Soap Cutting** — Slice through layered soap bars
- **Fidget Cube** — Buttons, rollers, and switches on a 3D cube
- **Switch Panel** — Flip 8 satisfying toggles
- **Crinkle Paper** — Foil sheet and strips that crinkle on click
- **Sand Tray** — Pour and shift kinetic sand grains
- **Water Drops** — Plink droplets in a basin
- **Satisfaction counter** — Track your relaxing clicks
- **Volume control** — Cycle volume levels in the HUD

## Getting Started

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) if you haven't already.

2. Build the place file:

```bash
rojo build -o "ASMRGame.rbxlx"
```

3. Open `ASMRGame.rbxlx` in Roblox Studio.

4. Start live sync (recommended while developing):

```bash
rojo serve
```

5. In Studio: **Plugins → Rojo → Connect** (default port `34872`).

6. Press **Play** and explore the stations around spawn.

## Customizing Sounds

Edit `src/shared/SoundConfig.luau` and replace the `rbxassetid://` values with your own uploaded ASMR audio. The keyboard and pop sounds use common library IDs as placeholders.

## Project Structure

```
src/
  shared/     ActivityConfig, SoundConfig, Theme, Util
  server/     WorldService (builds stations), GameService, LightingService
  client/     ActivityController, SoundPlayer, UIController
```

## Station Map

Stations are arranged around spawn:

| Direction | Station        |
|-----------|----------------|
| North     | Soap Cutting   |
| NE        | Balloon Pop    |
| NW        | Keyboard ASMR  |
| East      | Switch Panel   |
| West      | Fidget Cube    |
| SE        | Slime Squish   |
| SW        | Bubble Wrap    |
| South     | Crinkle Paper  |
| Near      | Sand & Water   |
