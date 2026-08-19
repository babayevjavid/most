Archived 2026-08-13 for the Heroes Assemble: Reborn roster/visuals revamp.

- CharacterSelectUI.luau — old bottom-left hero picker
- CharacterRegistry.luau — old MCU roster (Wanda, Carol, Loki, Dagger, Marvel Girl, Iceman) + ability defs

Archived 2026-08-15 — Beam Clash removed from live play (BeamChar / clash parts no longer in Workspace).

- BeamClashService.luau — full server clash logic
- BeamClashClient.luau — clash prompt UI

Live `src/server/BeamClashService.luau` and `src/client/BeamClashClient.luau` are no-op stubs so existing requires keep working. Animation preload is unchanged.

Archived 2026-08-15 — camera-locked ability screen particles (JeanUI / InvisWomanUI) paused.

- ScreenFxClient.luau — clone UIEffects onto the camera and fade emitters with abilities

Live `src/client/ScreenFxClient.luau` is a no-op stub. Jean / Invisible Woman still call it; restore the archive file to turn it back on.
