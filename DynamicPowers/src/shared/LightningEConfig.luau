return {
	MaxRange = 200,
	-- Travel time = distance / BeamSpeedStudsPerSec, clamped (near = fast, far = slow).
	BeamSpeedStudsPerSec = 400,
	BeamTravelTimeMin = 0.12,
	BeamTravelTimeMax = 1.05,
	-- End-of-beam hit zone (no Explosion instance — scripted damage + knockback).
	HitRadius = 10,
	HitDamage = 22,
	KnockbackVelocity = 68,
	-- Hand VFX: start fading particles at 0.5s; destroy clones 3s after that.
	HandParticleFadeStart = 0.5,
	HandParticleFadeDuration = 0.45,
	HandCloneDestroyAfterFade = 3,
	-- End beam VFX: start fading soon + short fade; keep holder longer before destroy.
	EndFxParticleRun = 0.32,
	EndFxFadeDuration = 0.28,
	EndFxDestroyAfter = 5.5,
	AbilityCooldown = 10,
	-- Local caster: turn toward aim over this time (client).
	AimRotateDuration = 0.32,
	-- FOV punch (local camera).
	FovAdd = 9,
	FovInDuration = 0.08,
	FovOutDuration = 0.42,
	FovOutDelay = 0.06,
	-- Everyone in this radius of impact gets camera shake (client).
	CameraShakeRadius = 52,
	CameraShakeDuration = 0.5,
	CameraShakeMagnitude = 1.35,
}
