# UntitledMarvelGame

Marvel powers testing place (Rojo + Luau). Sync scripts with Rojo; map and assets live in Roblox Studio.

## Getting started

```bash
rojo serve
```

Connect from Roblox Studio, then Play.

## Studio setup (required)

These are **not** synced by Rojo — set them up in your place file:

### Map
- Build your testing arena in `Workspace` (Rojo does not add a Baseplate).
- Add `SpawnLocation` parts and/or a `Workspace.SpawnPoints` folder with spawn parts.

### Thor Mjolnir
- Path: `ReplicatedStorage.Assets.Thor.Mjolnir`
- Mesh-only is fine; the server creates an invisible `Handle` and welds the mesh at runtime.

### Pushable props
- Each prop `Model` needs a child **`BoolValue` named `Prop`**.
- Unanchored parts work best for push/telekinesis tests.

### Optional
- NPC humanoids with `Humanoid` for Telekinesis / Force Push testing.

## Controls (PC)

| Input | Action |
|-------|--------|
| Character buttons (bottom-right) | Pick hero |
| LMB | Basic attack (placeholder) |
| 1–5 | Abilities **Q E R Z X** |
| C | Movement ability |
| Shift (hold) | Sprint (uses stamina) |
| F | Parry (stub, future) |

Ability bar buttons are display-only on PC; use keyboard binds.

## Heroes (placeholder kits)

- **Wanda** (IW/Endgame): Telekinesis, Chaos Shield, Force Push, Chaos Beam, Overwhelming Force. Passive **Undone Grief**: +15% damage below 40% HP.
- **Thor** (Mjolnir only): Hammer throw, lightning, thunder clap, storm, god blast.
- **Captain Marvel**: Photon, absorption, cosmic punch, binary burst, barrier, binary form.
- **Loki**: Daggers, mirror image, mind scepter, swap, army of illusions.

## Project layout

```
src/shared/     Config, heroes, abilities, PropHelper
src/server/     Services, MjolnirFactory
src/client/     UI, input, controllers
```

## Respawn

On death, hero selection is cleared and the bottom-right character picker appears again.
