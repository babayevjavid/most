--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local PhotonFlightService = require(script.Parent.PhotonFlightService)
local PhotonParticleHelper = require(script.Parent.PhotonParticleHelper)
local RagdollService = require(script.Parent.RagdollService)
local BeamClashService = require(script.Parent.BeamClashService)

local CaptainMarvelService = {}

type BeamState = {
	character: Model,
	tipHost: BasePart,
	startAtt: Attachment,
	endAtt: Attachment,
	beam: Beam?,
	aimPoint: Vector3,
	smoothedTip: Vector3,
	lastHit: number,
}

local beamByPlayer: { [Player]: BeamState } = {}

local BINARY_PARTICLE_NAME = "CM_BinaryParticle"

local function clearBinaryParticles(character: Model)
	for _, desc in character:GetDescendants() do
		if desc.Name == BINARY_PARTICLE_NAME then
			desc:Destroy()
		end
	end
end

local function attachBinaryParticles(character: Model)
	clearBinaryParticles(character)
	local template = VfxHelper.getCaptainMarvelAsset("EnergyAbsorptionParticle")
	if not template then
		warn("[CaptainMarvel] Missing EnergyAbsorptionParticle under Assets.CaptainMarvel")
		return
	end
	local attSource: Instance = template
	if not template:IsA("Attachment") then
		local nested = template:FindFirstChildWhichIsA("Attachment", true)
		if nested then
			attSource = nested
		end
	end

	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and not desc:FindFirstAncestorOfClass("Accessory") then
			local clone = attSource:Clone()
			clone.Name = BINARY_PARTICLE_NAME
			if clone:IsA("Attachment") then
				clone.Position = Vector3.zero
			end
			clone.Parent = desc
			VfxHelper.setParticlesEnabled(clone, true)
			VfxHelper.emitAllParticles(clone, 6)
		end
	end
end

local binaryTokenByPlayer: { [Player]: number } = {}

local function stopBinaryForm(player: Player, applyCooldown: boolean?)
	local character = player.Character
	if not character then
		return
	end
	if character:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) ~= true then
		return
	end
	binaryTokenByPlayer[player] = (binaryTokenByPlayer[player] or 0) + 1
	character:SetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.BINARY_UNTIL_ATTRIBUTE, nil)
	AbilityCooldownHelper.setActive(character, "binary_form", false)
	clearBinaryParticles(character)
	PhotonParticleHelper.endUse(character)
	if applyCooldown then
		AbilityCooldownHelper.applyAfterUse(character, "binary_form", GameConstants.BINARY_COOLDOWN)
	end
end

local function startBinaryForm(player: Player)
	local character = player.Character
	if not character then
		return
	end
	if character:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true then
		stopBinaryForm(player, true)
		return
	end
	local entry = CharacterRegistry.getAbilityById("captain_marvel", "binary_form")
	if not entry then
		return
	end
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, "binary_form") then
		return
	end
	if AbilityCooldownHelper.isActive(character, "binary_form") then
		return
	end

	AbilityCooldownHelper.setActive(character, "binary_form", true)
	character:SetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE, true)
	local untilTime = AbilityCooldownHelper.getNow() + GameConstants.BINARY_DURATION
	character:SetAttribute(GameConstants.BINARY_UNTIL_ATTRIBUTE, untilTime)
	PhotonParticleHelper.beginUse(character)
	attachBinaryParticles(character)
	CharacterService.markAbilityUse(character)

	local token = (binaryTokenByPlayer[player] or 0) + 1
	binaryTokenByPlayer[player] = token
	task.delay(GameConstants.BINARY_DURATION, function()
		if binaryTokenByPlayer[player] ~= token then
			return
		end
		if player.Character and player.Character:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true then
			stopBinaryForm(player, true)
		end
	end)
end

local function energyDrainMult(character: Model): number
	if character:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true then
		return GameConstants.BINARY_ENERGY_MULT
	end
	return 1
end

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
end

local function canUse(character: Model, abilityId: string, energyCost: number): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return false
	end
	if CombatHelper.arePowersDisabled(character) then
		return false
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isActive(character, abilityId) then
		return false
	end
	-- One ability at a time (photon flight excluded)
	for _, ab in CharacterRegistry.getAbilities("captain_marvel") do
		if ab.passive or ab.id == abilityId or ab.id == "photon_flight" then
			continue
		end
		if AbilityCooldownHelper.isActive(character, ab.id) then
			return false
		end
	end
	if not CharacterService.spendEnergy(character, energyCost) then
		return false
	end
	return true
end

local function getRightHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

local function getOrigin(character: Model): Vector3
	local hand = getRightHand(character)
	if hand then
		return hand.Position
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position + Vector3.new(0, 1.5, 0) else Vector3.zero
end

local function cloneMarvelAttachment(assetName: string): Attachment?
	local template = VfxHelper.getCaptainMarvelAsset(assetName)
	if not template then
		return nil
	end
	local source: Instance = template
	if not template:IsA("Attachment") then
		local nested = template:FindFirstChildWhichIsA("Attachment", true)
		if not nested then
			return nil
		end
		source = nested
	end
	local clone = source:Clone()
	if not clone:IsA("Attachment") then
		clone:Destroy()
		return nil
	end
	-- Keep beam endpoints at the hand / tip, not the asset's authored offset
	clone.Position = Vector3.zero
	clone.Orientation = Vector3.zero
	return clone
end

local function wireBeam(startAtt: Attachment, endAtt: Attachment): Beam?
	local beam = startAtt:FindFirstChildWhichIsA("Beam", true) or endAtt:FindFirstChildWhichIsA("Beam", true)
	if not beam then
		beam = Instance.new("Beam")
		beam.Name = "PhotonBeam"
		beam.Width0 = 1.1
		beam.Width1 = 0.85
		beam.FaceCamera = true
		beam.LightEmission = 0.85
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(VfxHelper.photonColor())
		beam.Parent = startAtt
	end
	beam.Attachment0 = startAtt
	beam.Attachment1 = endAtt
	beam.Enabled = true
	return beam
end

local function setMode(player: Player, abilityId: string, mode: string)
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return
	end
	if abilityId == "photon_flight" and (mode == "Normal" or mode == "Accelerated") then
		character:SetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE, mode)
	end
end

local diveTokenByPlayer: { [Player]: number } = {}

local function applyPhotonDiveImpact(character: Model, origin: Vector3)
	VfxHelper.spawnPhotonGroundSlam(origin, GameConstants.PHOTON_DIVE_RADIUS)
	local near = CombatHelper.overlapCharacters(origin, GameConstants.PHOTON_DIVE_RADIUS, character)
	for _, victim in near do
		CombatHelper.dealDamage(character, victim, GameConstants.PHOTON_DIVE_DAMAGE, origin, "explosion")
		RagdollService.applyTimed(victim, GameConstants.PHOTON_DIVE_RAGDOLL)
		local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
		if vRoot then
			local push = vRoot.Position - origin
			if push.Magnitude > 0.05 then
				PushHelper.applyToCharacter(victim, push.Unit, {
					speed = GameConstants.PHOTON_DIVE_PUSH_SPEED,
					upBoost = GameConstants.PHOTON_DIVE_PUSH_UP,
				})
			end
		end
	end
end

local function castPhotonDive(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	if not PhotonFlightService.isFlying(player) then
		return
	end
	local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_dive")
	if not entry or not canUse(character, entry.id, GameConstants.PHOTON_DIVE_ENERGY) then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local probe = aimPoint or (root.Position + root.CFrame.LookVector * 40)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local cast = Workspace:Raycast(probe + Vector3.new(0, 8, 0), Vector3.new(0, -120, 0), params)
	if not cast then
		cast = Workspace:Raycast(root.Position, Vector3.new(0, -200, 0), params)
	end
	if not cast then
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) == "number" then
			character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, energy + GameConstants.PHOTON_DIVE_ENERGY)
		end
		return
	end

	local flat = Vector3.new(cast.Position.X - root.Position.X, 0, cast.Position.Z - root.Position.Z)
	if flat.Magnitude > GameConstants.PHOTON_DIVE_MAX_RANGE then
		flat = flat.Unit * GameConstants.PHOTON_DIVE_MAX_RANGE
		local reclamped = Workspace:Raycast(
			Vector3.new(root.Position.X + flat.X, root.Position.Y + 8, root.Position.Z + flat.Z),
			Vector3.new(0, -120, 0),
			params
		)
		if reclamped then
			cast = reclamped
		end
	end

	local groundPos = cast.Position
	-- Dive toward a point slightly above ground so we don't clip; impact uses groundPos
	local diveTarget = groundPos + Vector3.new(0, 3.2, 0)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	PhotonParticleHelper.beginUse(character)
	PhotonFlightService.setDiveTarget(player, diveTarget)

	local token = (diveTokenByPlayer[player] or 0) + 1
	diveTokenByPlayer[player] = token

	task.spawn(function()
		local t0 = os.clock()
		local landed = false
		local impactGround = groundPos
		while diveTokenByPlayer[player] == token and PhotonFlightService.isFlying(player) and (os.clock() - t0) < 2.8 do
			local pos = PhotonFlightService.getPosition(player)
			if not pos then
				break
			end
			if (pos - diveTarget).Magnitude <= GameConstants.PHOTON_DIVE_LAND_DIST then
				landed = true
				break
			end
			local groundHit = Workspace:Raycast(pos, Vector3.new(0, -8, 0), params)
			if groundHit then
				local nearTarget = (Vector3.new(groundHit.Position.X, 0, groundHit.Position.Z)
					- Vector3.new(groundPos.X, 0, groundPos.Z)).Magnitude < GameConstants.PHOTON_DIVE_RADIUS
				if nearTarget or pos.Y - groundHit.Position.Y < 4.5 then
					impactGround = groundHit.Position
					landed = true
					break
				end
			end
			task.wait()
		end

		PhotonFlightService.clearDive(player)

		if character.Parent then
			character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		end

		if landed and character.Parent and player.Character == character then
			-- Stop flight on impact, then slam at ground level
			if PhotonFlightService.isFlying(player) then
				PhotonFlightService.endFlight(player, true)
			end
			local liveRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if liveRoot then
				local g = Workspace:Raycast(liveRoot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
				if g then
					impactGround = g.Position
				end
				local look = liveRoot.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				if flatLook.Magnitude < 0.05 then
					flatLook = Vector3.new(0, 0, -1)
				else
					flatLook = flatLook.Unit
				end
				liveRoot.CFrame = CFrame.lookAt(impactGround + Vector3.new(0, 3, 0), impactGround + Vector3.new(0, 3, 0) + flatLook)
				liveRoot.AssemblyLinearVelocity = Vector3.zero
				liveRoot.AssemblyAngularVelocity = Vector3.zero
			end
			applyPhotonDiveImpact(character, impactGround)
		end

		if character.Parent then
			PhotonParticleHelper.endUse(character)
			finishAbility(character, entry.id, GameConstants.PHOTON_DIVE_COOLDOWN)
			CharacterService.markAbilityUse(character)
		end
		if diveTokenByPlayer[player] == token then
			diveTokenByPlayer[player] = nil
		end
	end)
end

local function firePhotonBlast(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_blast")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local origin = getOrigin(character)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	local homeDir = dir
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			homeDir = toAim.Unit
		end
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	PhotonParticleHelper.beginUse(character)
	VfxHelper.castHandFlash(origin, VfxHelper.photonColor())

	-- Slight delay so blast syncs with cast motion
	task.delay(0.1, function()
		if not character.Parent or player.Character ~= character then
			AbilityCooldownHelper.setActive(character, entry.id, false)
			PhotonParticleHelper.endUse(character)
			return
		end
		local fireOrigin = getOrigin(character)
		ProjectileHelper.spawn(fireOrigin, homeDir, {
			speed = GameConstants.PHOTON_BLAST_SPEED,
			damage = GameConstants.PHOTON_BLAST_DAMAGE,
			radius = GameConstants.PHOTON_BLAST_HIT_RADIUS,
			maxDistance = GameConstants.PHOTON_BLAST_RANGE,
			owner = character,
			color = VfxHelper.photonColor(),
			homeDir = homeDir,
			homePoint = aimPoint or (fireOrigin + homeDir * math.min(60, GameConstants.PHOTON_BLAST_RANGE * 0.7)),
			homeAfter = 0,
			seekUntilClose = true,
			seekCloseDistance = 2.2,
			boltFolder = "CaptainMarvel",
			boltAsset = "PhotonBlast",
			impactFx = "photon_blast",
		})
		CombatHelper.spendAbsorbCharge(character, GameConstants.CM_ABSORB_SPEND_BLAST)
		VfxHelper.spawnBeamLine(fireOrigin, fireOrigin + homeDir * 8, VfxHelper.photonSoft(), 0.35, 0.16)
		finishAbility(character, entry.id, entry.cooldown)
		task.delay(0.4, function()
			if character.Parent then
				PhotonParticleHelper.endUse(character)
			end
		end)
	end)
end

local function firePhotonExplosion(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_explosion")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local origin = getOrigin(character)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	local homeDir = dir
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			homeDir = toAim.Unit
		end
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	PhotonParticleHelper.beginUse(character)
	VfxHelper.castHandFlash(origin, VfxHelper.photonColor())

	-- Projectile uses PhotonBlast for now; ExplosionAttachment plays at impact
	ProjectileHelper.spawn(origin, homeDir, {
		speed = GameConstants.PHOTON_BLAST_SPEED,
		damage = GameConstants.PHOTON_EXPLOSION_DAMAGE,
		radius = GameConstants.PHOTON_BLAST_HIT_RADIUS,
		maxDistance = GameConstants.PHOTON_BLAST_RANGE,
		owner = character,
		color = VfxHelper.photonColor(),
		homeDir = homeDir,
		homePoint = aimPoint or (origin + homeDir * math.min(60, GameConstants.PHOTON_BLAST_RANGE * 0.7)),
		homeAfter = 0,
		seekUntilClose = true,
		seekCloseDistance = 2.2,
		boltFolder = "CaptainMarvel",
		boltAsset = "PhotonBlast",
		impactAoeRadius = GameConstants.PHOTON_EXPLOSION_RADIUS,
		impactAoeDamage = GameConstants.PHOTON_EXPLOSION_DAMAGE,
		impactFx = "photon_explosion",
		ragdollOnHit = GameConstants.PHOTON_EXPLOSION_RAGDOLL,
		pushOnHit = true,
		pushSpeed = GameConstants.PHOTON_EXPLOSION_PUSH_SPEED,
		pushUp = GameConstants.PHOTON_EXPLOSION_PUSH_UP,
	})
	CombatHelper.spendAbsorbCharge(character, GameConstants.CM_ABSORB_SPEND_EXPLOSION)
	VfxHelper.spawnBeamLine(origin, origin + homeDir * 8, VfxHelper.photonSoft(), 0.4, 0.2)
	finishAbility(character, entry.id, entry.cooldown)
	task.delay(0.45, function()
		if character.Parent then
			PhotonParticleHelper.endUse(character)
		end
	end)
end

local function fadeOutBeamFx(startAtt: Attachment, endAtt: Attachment, tipHost: BasePart, beam: Beam?)
	VfxHelper.setParticlesEnabled(startAtt, false)
	VfxHelper.setParticlesEnabled(endAtt, false)
	if beam then
		beam.Enabled = false
	end
	task.delay(BEAM_FX_FADE, function()
		if startAtt.Parent then
			startAtt:Destroy()
		end
		if tipHost.Parent then
			tipHost:Destroy()
		end
	end)
end

local function stopPhotonBeam(player: Player, applyCooldown: boolean?)
	local state = beamByPlayer[player]
	if not state then
		return
	end
	if state.character:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true
		or BeamClashService.shouldKeepBeamAlive(state.character)
	then
		return
	end
	beamByPlayer[player] = nil
	fadeOutBeamFx(state.startAtt, state.endAtt, state.tipHost, state.beam)
	local char = state.character
	if char.Parent then
		AbilityCooldownHelper.setActive(char, "photon_beam", false)
		PhotonParticleHelper.endUse(char, "Right")
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_beam")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end
end

function CaptainMarvelService.forceStopBeam(player: Player, applyCooldown: boolean?)
	local state = beamByPlayer[player]
	if not state then
		return
	end
	beamByPlayer[player] = nil
	fadeOutBeamFx(state.startAtt, state.endAtt, state.tipHost, state.beam)
	local char = state.character
	if char.Parent then
		AbilityCooldownHelper.setActive(char, "photon_beam", false)
		PhotonParticleHelper.endUse(char, "Right")
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_beam")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end
end

local function startPhotonBeam(player: Player, aimPoint: Vector3)
	local character = player.Character
	if not character or beamByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_beam")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local hand = getRightHand(character)
	if not hand then
		return
	end

	local startAtt = cloneMarvelAttachment("BeamStartAttachment")
	local endAtt = cloneMarvelAttachment("BeamEndAttachment")
	if not startAtt or not endAtt then
		warn("[CaptainMarvel] Missing BeamStartAttachment / BeamEndAttachment under Assets.CaptainMarvel")
		-- refund energy spent by canUse
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) == "number" then
			character:SetAttribute(
				GameConstants.ENERGY_ATTRIBUTE,
				math.min(
					(character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE) :: number?) or 100,
					energy + entry.energyCost
				)
			)
		end
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	PhotonParticleHelper.beginUse(character, "Right")

	startAtt.Name = "CM_BeamStartAttachment"
	startAtt.Parent = hand

	local tipHost = Instance.new("Part")
	tipHost.Name = "PhotonBeamTipHost"
	tipHost.Size = Vector3.new(0.2, 0.2, 0.2)
	tipHost.Transparency = 1
	tipHost.Anchored = true
	tipHost.CanCollide = false
	tipHost.CanQuery = false
	tipHost.CanTouch = false
	tipHost.CFrame = CFrame.lookAt(aimPoint, getOrigin(character))
	tipHost.Parent = Workspace

	endAtt.Name = "CM_BeamEndAttachment"
	endAtt.Parent = tipHost

	local beam = wireBeam(startAtt, endAtt)

	VfxHelper.setParticlesEnabled(startAtt, true)
	VfxHelper.setParticlesEnabled(endAtt, true)
	VfxHelper.emitAllParticles(startAtt, 10)
	VfxHelper.emitAllParticles(endAtt, 10)

	beamByPlayer[player] = {
		character = character,
		tipHost = tipHost,
		startAtt = startAtt,
		endAtt = endAtt,
		beam = beam,
		aimPoint = aimPoint,
		smoothedTip = aimPoint,
		lastHit = 0,
	}
end

function CaptainMarvelService.update(dt: number)
	local now = AbilityCooldownHelper.getNow()
	local dtClamped = math.clamp(dt, 0.001, 0.1)

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and char:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "captain_marvel" then
			CombatHelper.decayAbsorbCharge(char, dtClamped)
			local untilTime = char:GetAttribute(GameConstants.BINARY_UNTIL_ATTRIBUTE)
			if
				char:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true
				and type(untilTime) == "number"
				and now >= untilTime
			then
				stopBinaryForm(player, true)
			end
		end
	end

	for player, state in beamByPlayer do
		local char = state.character
		if not char.Parent or player.Character ~= char then
			stopPhotonBeam(player, true)
			continue
		end

		local energy = char:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopPhotonBeam(player, true)
			continue
		end
		char:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.PHOTON_BEAM_ENERGY_PER_SEC * energyDrainMult(char) * dtClamped)
		)
		CharacterService.markAbilityUse(char)
		do
			local charge = char:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
			if type(charge) == "number" and charge > 0 then
				char:SetAttribute(
					GameConstants.ABSORB_CHARGE_ATTRIBUTE,
					math.max(0, charge - GameConstants.CM_ABSORB_SPEND_BEAM_PER_SEC * dtClamped)
				)
			end
		end

		local origin = if state.startAtt.Parent then state.startAtt.WorldPosition else getOrigin(char)
		local toAim = state.aimPoint - origin
		local dir = if toAim.Magnitude > 0.05 then toAim.Unit else char:GetPivot().LookVector
		local maxDist = GameConstants.PHOTON_BEAM_RANGE

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, state.tipHost }
		local hit = Workspace:Raycast(origin, dir * maxDist, params)
		local desiredTip = if hit then hit.Position else origin + dir * maxDist

		local tipLerp = 1 - (1 - 0.22) ^ (dtClamped * 60)
		state.smoothedTip = state.smoothedTip:Lerp(desiredTip, tipLerp)
		local tipPos = state.smoothedTip

		local forcedTip = BeamClashService.getForcedBeamTip(char)
		if forcedTip then
			tipPos = forcedTip
			state.smoothedTip = forcedTip
		end

		-- Face tip back toward the hand so end attachment / particles align with the beam
		if (origin - tipPos).Magnitude > 0.05 then
			state.tipHost.CFrame = CFrame.lookAt(tipPos, origin)
		else
			state.tipHost.CFrame = CFrame.new(tipPos)
		end
		if state.beam and not state.beam.Enabled then
			state.beam.Enabled = true
		end
		if state.beam then
			state.beam.Attachment0 = state.startAtt
			state.beam.Attachment1 = state.endAtt
		end

		if now - state.lastHit >= 0.12 then
			state.lastHit = now
			if char:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true or forcedTip then
				-- skip tip damage while clashing
			else
				local half = GameConstants.PHOTON_BEAM_HIT_SIZE
				local overlap = OverlapParams.new()
				overlap.FilterType = Enum.RaycastFilterType.Exclude
				overlap.FilterDescendantsInstances = { char, state.tipHost }
				local tipCf = if (origin - tipPos).Magnitude > 0.05
					then CFrame.lookAt(tipPos, origin)
					else CFrame.new(tipPos)
				local box = Workspace:GetPartBoundsInBox(tipCf, Vector3.new(half, half, half), overlap)
				local seen: { [Model]: boolean } = {}
				for _, part in box do
					local victim = CombatHelper.getCharacterFromPart(part)
					if victim and victim ~= char and not seen[victim] then
						seen[victim] = true
						CombatHelper.dealDamage(char, victim, GameConstants.PHOTON_BEAM_DAMAGE_PER_SEC * 0.12, nil, "beam")
					end
				end
			end
		end
	end
end

function CaptainMarvelService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return
	end

	local action = payload.action
	if type(action) ~= "string" then
		return
	end

	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else Vector3.new(0, 0, -1)
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil

	if action == "SetMode" then
		if type(payload.abilityId) == "string" and type(payload.mode) == "string" then
			setMode(player, payload.abilityId, payload.mode)
		end
		return
	end

	if action == "Q" then
		firePhotonBlast(player, direction, aimPoint)
	elseif action == "E_down" or action == "E" then
		firePhotonExplosion(player, direction, aimPoint)
	elseif action == "F" then
		PhotonFlightService.toggleFlight(player)
	elseif action == "C" then
		castPhotonDive(player, aimPoint)
	elseif action == "X" then
		startBinaryForm(player)
	elseif action == "T_down" then
		startPhotonBeam(
			player,
			aimPoint or (character:GetPivot().Position + direction * 40)
		)
	elseif action == "T_up" then
		stopPhotonBeam(player, true)
	elseif action == "T_aim" then
		local state = beamByPlayer[player]
		if state and aimPoint then
			state.aimPoint = aimPoint
		end
	end
end

function CaptainMarvelService.cancelAll(player: Player)
	CaptainMarvelService.forceStopBeam(player, false)
	stopBinaryForm(player, false)
	diveTokenByPlayer[player] = nil
	PhotonFlightService.clearDive(player)
	PhotonFlightService.endFlight(player, false)
	local char = player.Character
	if char then
		char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(char, "photon_dive", false)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			RagdollService.apply(char)
		end
	end
end

function CaptainMarvelService.getActiveBeamSegments(): {
	{
		id: string,
		kind: "player",
		player: Player,
		character: Model,
		origin: Vector3,
		tip: Vector3,
		label: string,
	}
}
	local list = {}
	for player, state in beamByPlayer do
		local char = state.character
		if char.Parent and player.Character == char then
			local origin = if state.startAtt.Parent then state.startAtt.WorldPosition else char:GetPivot().Position
			local tip = state.tipHost.Position
			table.insert(list, {
				id = "photon:" .. tostring(player.UserId),
				kind = "player" :: "player",
				player = player,
				character = char,
				origin = origin,
				tip = tip,
				label = player.DisplayName,
			})
		end
	end
	return list
end

function CaptainMarvelService.init()
	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		CaptainMarvelService.handleAction(player, payload)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			CaptainMarvelService.cancelAll(player)
		end)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					CaptainMarvelService.cancelAll(player)
				end)
			end
		end)
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					CaptainMarvelService.cancelAll(player)
				end)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	Players.PlayerRemoving:Connect(function(player)
		CaptainMarvelService.cancelAll(player)
	end)
end

return CaptainMarvelService
