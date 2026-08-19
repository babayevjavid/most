# Ability bar (by element)

Hotkeys on the HUD are **`1` `2` `3` `4`** (same for every element).

| Element | Slot 1 | Slot 2 | Slot 3 | Slot 4 |
|--------|--------|--------|--------|--------|
| **Water** | Brine Surge | Rimebolt | Glacier Path | Tidemend |
| **Earth** | Spike Chain | Shardspire | Catapult Root | Faultbreaker |
| **Fire** | Inferno Lash | Dragon's Inhale | Afterburn Drive | Cinder Sigil |
| **Air** | Galefang | Shearline | Nimbus Drift | Skybreak Column |

These names are defined in `src/shared/BendingUI.luau` → `ABILITIES_BY_ELEMENT`.

---

# Subbendings (same four abilities today)

Subbending is chosen in the second picker step and stored as the character attribute **`BendingSub`** (display label).  
**Gameplay/UI does not swap the bottom bar per subbending yet** — every substyle of an element still uses that element’s four abilities above. You can add server logic (e.g. damage modifiers, passives, or a second ability table keyed by `BendingSub`) later.

## Water

| Subbending |
|------------|
| Plantbending |
| Bloodbending |
| Healing |
| Spiritbending |

## Earth

| Subbending |
|------------|
| Lava |
| Metal |
| Sand |
| Crystal |
| Seismic Sense |

## Fire

| Subbending |
|------------|
| Combustion |
| Lightning |
| Flame Divination |

## Air

| Subbending |
|------------|
| Flight |
| Sound |
| Projection |

---

## Optional design direction (not implemented)

Use **`BendingElement` + `BendingSub`** together to pick rows from a future `ABILITIES_BY_SUB` table, or attach **passives** only (e.g. Lightning → Afterburn Drive travels farther).
