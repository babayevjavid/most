--!strict

--[[

	Wanda Chaos Beam — ported from NewMarvel Blue Marvel antimatter beam + Human Torch hold beam.

	Workspace EndBeam follower, dual-hand VFX, server raycast/extend/damage, flat yaw while grounded.

]]



local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")



local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))

local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))



local CombatService = require(script.Parent.CombatService)

local PlayerStateService = require(script.Parent.PlayerStateService)

local ShieldService = require(script.Parent.ShieldService)

local SprintService = require(script.Parent.SprintService)

local TelekinesisService = require(script.Parent.TelekinesisService)
local WandaHandParticlesService = require(script.Parent.WandaHandParticlesService)



local C = AbilityConstants



type BeamState = {

	active: boolean,

	handStartAtts: { Attachment },

	beams: { Beam },

	beamEndAtt: Attachment?,

	beamEndFollowerPart: BasePart?,

	beamEndAttLocalCFrame: CFrame?,

	animTrack: AnimationTrack?,

	jumpRestore: {

		jumpPower: number,

		jumpHeight: number?,

		autoJumpEnabled: boolean,

		jumpingEnabled: boolean,

	}?,

	beamAlign: AlignOrientation?,

	beamAttach: Attachment?,

	targetEndPos: Vector3?,

	startPos: Vector3?,

	channelStartTime: number?,

	lastDamageTime: number,

	heartbeatConn: RBXScriptConnection?,

	retractConn: RBXScriptConnection?,

}



local BeamService = {}



local stateByPlayer: { [Player]: BeamState } = {}

local onStatUpdate: ((player: Player) -> ())? = nil

local onCooldown: ((player: Player, abilityId: string, duration: number) -> ())? = nil



local function getState(plr: Player): BeamState

	if not stateByPlayer[plr] then

		stateByPlayer[plr] = {

			active = false,

			handStartAtts = {},

			beams = {},

			beamEndAtt = nil,

			beamEndFollowerPart = nil,

			beamEndAttLocalCFrame = nil,

			animTrack = nil,

			jumpRestore = nil,

			beamAlign = nil,

			beamAttach = nil,

			targetEndPos = nil,

			startPos = nil,

			channelStartTime = nil,

			lastDamageTime = 0,

			heartbeatConn = nil,

			retractConn = nil,

		}

	end

	return stateByPlayer[plr]

end



local function canUseBeam(plr: Player): boolean

	local state = PlayerStateService.get(plr)

	if not state.HeroId then

		return false

	end

	return HeroRegistry.heroOwnsAbility(state.HeroId, "ChaosBeam")

end



local function findBothHands(char: Model): { BasePart }

	local hands: { BasePart } = {}

	local right = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")

	local left = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")

	if right and right:IsA("BasePart") then

		table.insert(hands, right)

	end

	if left and left:IsA("BasePart") and left ~= right then

		table.insert(hands, left)

	end

	return hands

end



local function getHandsMedianPos(char: Model): Vector3?

	local hands = findBothHands(char)

	if #hands == 0 then

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

		return root and root.Position or nil

	end

	local sum = Vector3.zero

	for _, hand in hands do

		sum += hand.Position

	end

	return sum / #hands

end



local function getWandaAssets(): (Instance?, Instance?)

	local assets = ReplicatedStorage:FindFirstChild("Assets")

	if not assets then

		return nil, nil

	end

	local wanda = assets:FindFirstChild("WandaMaximoff")

	if not wanda then

		return nil, nil

	end

	return wanda:FindFirstChild("HandParticles"), wanda:FindFirstChild("EndBeam")

end



local function resolveHandAttachment(inst: Instance, handPart: BasePart): Attachment

	if inst:IsA("Attachment") then

		inst.Parent = handPart

		return inst

	end

	local existing = inst:FindFirstChildWhichIsA("Attachment", true)

	if existing then

		existing.Parent = handPart

		return existing

	end

	local att = Instance.new("Attachment")

	att.Name = "HandParticles"

	att.Parent = handPart

	return att

end



local function getRaycastParams(char: Model): RaycastParams

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = { char }

	params.IgnoreWater = true

	return params

end



local function getOverlapParams(char: Model): OverlapParams

	local params = OverlapParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = { char }

	return params

end



local function wireBeams(handRoot: Instance, handAtt: Attachment, endAtt: Attachment): { Beam }

	local beams: { Beam } = {}

	local function tryWire(beam: Beam)

		beam.Attachment0 = handAtt

		beam.Attachment1 = endAtt

		beam.Enabled = true

		table.insert(beams, beam)

	end

	for _, desc in handRoot:GetDescendants() do

		if desc:IsA("Beam") then

			tryWire(desc)

		end

	end

	for _, child in handRoot:GetChildren() do

		if child:IsA("Beam") then

			tryWire(child)

		end

	end

	return beams

end



local function createEndFollower(endTpl: Instance, initialPos: Vector3): (BasePart, Attachment, CFrame)

	local follower = Instance.new("Part")

	follower.Name = "ChaosBeamEndFollowerPart"

	follower.Size = Vector3.new(0.2, 0.2, 0.2)

	follower.Anchored = true

	follower.CanCollide = false

	follower.CanTouch = false

	follower.CanQuery = false

	follower.Transparency = 1

	follower.Parent = workspace



	local endAtt: Attachment

	local localCf: CFrame

	if endTpl:IsA("Attachment") then

		endAtt = endTpl:Clone() :: Attachment

		endAtt.Name = "EndBeam"

		endAtt.Parent = follower

		localCf = endAtt.CFrame

	elseif endTpl:IsA("BasePart") then

		local clone = endTpl:Clone() :: BasePart

		clone.Anchored = false

		clone.CanCollide = false

		clone.CanTouch = false

		clone.CanQuery = false

		clone.Parent = follower

		local found = clone:FindFirstChildWhichIsA("Attachment")

		if found then

			endAtt = found

			localCf = endAtt.CFrame

		else

			endAtt = Instance.new("Attachment")

			endAtt.Name = "EndBeam"

			endAtt.Parent = follower

			localCf = endAtt.CFrame

		end

	else

		local clone = endTpl:Clone()

		clone.Parent = follower

		local found = clone:FindFirstChildWhichIsA("Attachment", true)

		if found then

			endAtt = found

			endAtt.Parent = follower

			localCf = endAtt.CFrame

		else

			endAtt = Instance.new("Attachment")

			endAtt.Name = "EndBeam"

			endAtt.Parent = follower

			localCf = endAtt.CFrame

		end

	end



	follower.CFrame = CFrame.new(initialPos) * localCf:Inverse()

	return follower, endAtt, localCf

end



local function moveFollowerToWorldPos(st: BeamState, worldPos: Vector3)

	if not st.beamEndFollowerPart or not st.beamEndAttLocalCFrame then

		return

	end

	st.beamEndFollowerPart.CFrame = CFrame.new(worldPos) * st.beamEndAttLocalCFrame:Inverse()

end



local function updateBeamFacing(char: Model, root: BasePart, tipPos: Vector3, st: BeamState)

	local flat = Vector3.new(tipPos.X - root.Position.X, 0, tipPos.Z - root.Position.Z)

	if flat.Magnitude < 0.01 then

		return

	end

	local unit = flat.Unit

	char:SetAttribute("ChaosBeamLookX", unit.X)

	char:SetAttribute("ChaosBeamLookZ", unit.Z)



	if char:GetAttribute("NewFlightActive") == true then

		return

	end

	if not st.beamAlign or not st.beamAlign.Parent then

		return

	end

	st.beamAlign.CFrame = CFrame.lookAt(Vector3.zero, unit, Vector3.yAxis)

end



local function computeEndPos(

	char: Model,

	root: BasePart,

	startPos: Vector3,

	targetPos: Vector3,

	channelStartTime: number?

): Vector3

	local toTarget = targetPos - startPos

	local dist = toTarget.Magnitude

	local clampedDist = math.min(dist, C.CHAOS_BEAM_RANGE)

	local endPos: Vector3

	if dist > 0.0001 then

		local rayDir = toTarget.Unit * clampedDist

		local hit = workspace:Raycast(startPos, rayDir, getRaycastParams(char))

		endPos = if hit then hit.Position else (startPos + rayDir)

	else

		endPos = startPos

	end



	local fromRoot = endPos - root.Position

	if fromRoot.Magnitude > C.CHAOS_BEAM_RANGE then

		endPos = root.Position + fromRoot.Unit * C.CHAOS_BEAM_RANGE

	end



	local elapsed = if channelStartTime then (os.clock() - channelStartTime) else 0

	local extendSpeed = C.CHAOS_BEAM_RANGE / math.max(0.0001, C.CHAOS_BEAM_MAX_EXTEND_TIME)

	local maxReach = math.min(C.CHAOS_BEAM_RANGE, extendSpeed * math.min(elapsed, C.CHAOS_BEAM_MAX_EXTEND_TIME))

	local fromStart = endPos - startPos

	local idealLen = fromStart.Magnitude

	if idealLen > 0.05 then

		local allowedLen = math.min(idealLen, math.max(maxReach, 1))

		endPos = startPos + fromStart.Unit * allowedLen

	end



	local fromRootFinal = endPos - root.Position

	if fromRootFinal.Magnitude > C.CHAOS_BEAM_RANGE then

		endPos = root.Position + fromRootFinal.Unit * C.CHAOS_BEAM_RANGE

	end



	return endPos

end



local function destroyBeamInstances(st: BeamState)

	for _, beam in st.beams do

		beam.Enabled = false

	end

	st.beams = {}



	st.handStartAtts = {}



	if st.beamEndAtt and st.beamEndAtt.Parent then

		st.beamEndAtt:Destroy()

	end

	st.beamEndAtt = nil



	if st.beamEndFollowerPart and st.beamEndFollowerPart.Parent then

		st.beamEndFollowerPart:Destroy()

	end

	st.beamEndFollowerPart = nil

	st.beamEndAttLocalCFrame = nil

end



local function destroyBeamFacing(st: BeamState)

	if st.beamAlign and st.beamAlign.Parent then

		st.beamAlign:Destroy()

	end

	if st.beamAttach and st.beamAttach.Parent then

		st.beamAttach:Destroy()

	end

	st.beamAlign = nil

	st.beamAttach = nil

end



local function damageAtBeamEnd(plr: Player, char: Model, tipPos: Vector3)

	local heroId = PlayerStateService.get(plr).HeroId

	local overlap = getOverlapParams(char)

	local parts = workspace:GetPartBoundsInBox(CFrame.new(tipPos), C.CHAOS_BEAM_DAMAGE_BOX, overlap)

	local hitModels: { [Model]: boolean } = {}



	for _, part in parts do

		local model = part:FindFirstAncestorOfClass("Model")

		if not model or model == char or hitModels[model] then

			continue

		end

		hitModels[model] = true

		local humanoid = model:FindFirstChildOfClass("Humanoid")

		if humanoid and humanoid.Health > 0 then

			local damage = CombatService.computeDamage(plr, heroId, C.CHAOS_BEAM_DAMAGE)

			humanoid:TakeDamage(damage)

		end

	end

end



local function finishStop(plr: Player, applyCooldown: boolean)

	local st = getState(plr)

	if not st.active and #st.handStartAtts == 0 then

		return

	end



	st.active = false

	st.targetEndPos = nil

	st.startPos = nil

	st.channelStartTime = nil



	if st.heartbeatConn then

		st.heartbeatConn:Disconnect()

		st.heartbeatConn = nil

	end

	if st.retractConn then

		st.retractConn:Disconnect()

		st.retractConn = nil

	end



	if st.animTrack then

		pcall(function()

			st.animTrack:Stop()

		end)

		st.animTrack = nil

	end



	destroyBeamInstances(st)

	destroyBeamFacing(st)



	local char = plr.Character

	if char then

		WandaHandParticlesService.disable(char)

		char:SetAttribute("IsChaosBeamActive", nil)

		char:SetAttribute("ChaosBeamLookX", nil)

		char:SetAttribute("ChaosBeamLookZ", nil)

		local humanoid = char:FindFirstChildOfClass("Humanoid")

		if humanoid and st.jumpRestore then

			humanoid.JumpPower = st.jumpRestore.jumpPower

			if st.jumpRestore.jumpHeight ~= nil then

				humanoid.JumpHeight = st.jumpRestore.jumpHeight

			end

			humanoid.AutoJumpEnabled = st.jumpRestore.autoJumpEnabled

			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, st.jumpRestore.jumpingEnabled)

		end

	end

	st.jumpRestore = nil



	if applyCooldown then

		PlayerStateService.setCooldown(plr, "ChaosBeam", os.clock() + C.CHAOS_BEAM_COOLDOWN)

		if onCooldown then

			onCooldown(plr, "ChaosBeam", C.CHAOS_BEAM_COOLDOWN)

		end

	end



	if onStatUpdate then

		onStatUpdate(plr)

	end

end



local function stopBeam(plr: Player, applyCooldown: boolean)

	local st = getState(plr)

	if not st.active then

		finishStop(plr, applyCooldown)

		return

	end



	st.active = false

	if st.heartbeatConn then

		st.heartbeatConn:Disconnect()

		st.heartbeatConn = nil

	end



	local startAtt = st.handStartAtts[1]

	local follower = st.beamEndFollowerPart

	local endAtt = st.beamEndAtt

	local localCf = st.beamEndAttLocalCFrame



	if not startAtt or not startAtt.Parent or not follower or not follower.Parent or not endAtt or not localCf then

		finishStop(plr, applyCooldown)

		return

	end



	if st.retractConn then

		st.retractConn:Disconnect()

	end



	local retractAcc = 0

	st.retractConn = RunService.Heartbeat:Connect(function(dt: number)

		retractAcc += dt

		if not startAtt.Parent or not follower.Parent or not endAtt.Parent then

			if st.retractConn then

				st.retractConn:Disconnect()

				st.retractConn = nil

			end

			finishStop(plr, applyCooldown)

			return

		end



		local startP = startAtt.WorldPosition

		local endP = endAtt.WorldPosition

		local offset = startP - endP

		local dist = offset.Magnitude

		if dist < 0.35 or retractAcc > 2.5 then

			follower.CFrame = CFrame.new(startP) * localCf:Inverse()

			if st.retractConn then

				st.retractConn:Disconnect()

				st.retractConn = nil

			end

			finishStop(plr, applyCooldown)

			return

		end



		local move = math.min(dist, dist * math.clamp(dt * 10, 0.08, 1))

		local newEnd = endP + offset.Unit * move

		follower.CFrame = CFrame.new(newEnd) * localCf:Inverse()

	end)

end



local function applyLookUpdate(plr: Player, targetPos: Vector3)

	local st = getState(plr)

	if not st.active or not st.beamEndFollowerPart or not st.beamEndAttLocalCFrame then

		return

	end



	local char = plr.Character

	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not char or not root then

		return

	end



	local startPos = getHandsMedianPos(char)

	if not startPos then

		return

	end

	st.startPos = startPos



	local endPos = computeEndPos(char, root, startPos, targetPos, st.channelStartTime)

	st.targetEndPos = endPos

	moveFollowerToWorldPos(st, endPos)

	updateBeamFacing(char, root, endPos, st)

end



local function startBeamHeartbeat(plr: Player)

	local st = getState(plr)

	if st.heartbeatConn then

		st.heartbeatConn:Disconnect()

	end



	st.heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)

		if not st.active then

			return

		end



		local char = plr.Character

		if not char or not char.Parent then

			stopBeam(plr, false)

			return

		end



		local humanoid = char:FindFirstChildOfClass("Humanoid")

		if humanoid and humanoid.Health <= 0 then

			stopBeam(plr, false)

			return

		end



		local playerState = PlayerStateService.get(plr)

		playerState.Energy = math.max(0, playerState.Energy - C.CHAOS_BEAM_ENERGY_PER_SEC * dt)

		PlayerStateService.markResourceUsed(plr)

		if playerState.Energy <= 0 then

			stopBeam(plr, true)

			return

		end



		local tipPos = st.targetEndPos

		if tipPos then

			local now = os.clock()

			if now - st.lastDamageTime >= C.CHAOS_BEAM_DAMAGE_INTERVAL then

				st.lastDamageTime = now

				damageAtBeamEnd(plr, char, tipPos)

			end

		end



		if onStatUpdate then

			onStatUpdate(plr)

		end

	end)

end



local function playBeamAnimation(char: Model): AnimationTrack?

	local humanoid = char:FindFirstChildOfClass("Humanoid")

	if not humanoid then

		return nil

	end

	local animator = humanoid:FindFirstChildOfClass("Animator")

	if not animator then

		animator = Instance.new("Animator")

		animator.Parent = humanoid

	end

	local anim = Instance.new("Animation")

	anim.AnimationId = C.CHAOS_BEAM_ANIMATION_ID

	local track = humanoid:LoadAnimation(anim)

	track.Looped = true

	track:Play()

	return track

end



local function turnOn(plr: Player): boolean

	if not canUseBeam(plr) then

		return false

	end

	if PlayerStateService.isOnCooldown(plr, "ChaosBeam") then

		return false

	end



	local char = plr.Character

	if not char or not char.Parent then

		return false

	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not root or humanoid.Health <= 0 then

		return false

	end



	local playerState = PlayerStateService.get(plr)

	if playerState.Energy <= 0 then

		return false

	end



	local st = getState(plr)

	if st.active then

		return true

	end



	TelekinesisService.cleanupPlayer(plr)

	ShieldService.turnOff(plr)

	SprintService.forceStopSprint(plr)



	local _, endTpl = getWandaAssets()

	if not endTpl then

		warn("[BeamService] Missing Assets.WandaMaximoff.EndBeam")

		return false

	end



	local hands = findBothHands(char)

	if #hands == 0 then

		return false

	end



	WandaHandParticlesService.ensure(char)

	WandaHandParticlesService.enable(char)

	WandaHandParticlesService.emit(char)



	local startPos = getHandsMedianPos(char) or root.Position

	local lookDir = root.CFrame.LookVector

	local initialEnd = computeEndPos(char, root, startPos, startPos + lookDir * C.CHAOS_BEAM_RANGE, os.clock())



	local follower, endAtt, localCf = createEndFollower(endTpl, initialEnd)

	follower.CFrame = CFrame.new(initialEnd) * localCf:Inverse()



	local handStartAtts: { Attachment } = {}

	local allBeams: { Beam } = {}



	for _, handPart in hands do

		local handAtt = WandaHandParticlesService.getHandAttachment(handPart)

		if not handAtt then

			continue

		end

		table.insert(handStartAtts, handAtt)

		local handRoot = handPart:FindFirstChild("HandParticles") or handPart

		for _, beam in wireBeams(handRoot, handAtt, endAtt) do

			table.insert(allBeams, beam)

		end

	end



	if #handStartAtts == 0 then

		WandaHandParticlesService.disable(char)

		follower:Destroy()

		return false

	end



	st.active = true

	st.handStartAtts = handStartAtts

	st.beams = allBeams

	st.beamEndAtt = endAtt

	st.beamEndFollowerPart = follower

	st.beamEndAttLocalCFrame = localCf

	st.startPos = startPos

	st.targetEndPos = initialEnd

	st.channelStartTime = os.clock()

	st.lastDamageTime = 0

	st.animTrack = playBeamAnimation(char)



	st.jumpRestore = {

		jumpPower = humanoid.JumpPower,

		jumpHeight = humanoid.JumpHeight,

		autoJumpEnabled = humanoid.AutoJumpEnabled,

		jumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),

	}

	humanoid.JumpPower = 0

	humanoid.JumpHeight = 0

	humanoid.AutoJumpEnabled = false

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)



	if char:GetAttribute("NewFlightActive") ~= true then

		local att = Instance.new("Attachment")

		att.Name = "ChaosBeamRotateAttachment"

		att.Parent = root

		local align = Instance.new("AlignOrientation")

		align.Name = "ChaosBeamRotateAlign"

		align.Mode = Enum.OrientationAlignmentMode.OneAttachment

		align.Attachment0 = att

		align.RigidityEnabled = false

		align.MaxTorque = math.huge

		align.Responsiveness = C.ROTATE_ALIGN_RESPONSIVENESS

		align.Parent = root

		st.beamAttach = att

		st.beamAlign = align

	end



	char:SetAttribute("IsChaosBeamActive", true)

	updateBeamFacing(char, root, initialEnd, st)



	humanoid.Died:Once(function()

		stopBeam(plr, false)

	end)



	startBeamHeartbeat(plr)

	return true

end



function BeamService.setup(

	chaosBeamSetActive: RemoteEvent,

	chaosBeamLookUpdate: RemoteEvent,

	statUpdateCallback: (player: Player) -> (),

	cooldownCallback: (player: Player, abilityId: string, duration: number) -> ()

)

	onStatUpdate = statUpdateCallback

	onCooldown = cooldownCallback



	chaosBeamSetActive.OnServerEvent:Connect(function(plr: Player, holding: boolean)

		if typeof(holding) ~= "boolean" then

			return

		end

		if holding then

			turnOn(plr)

		elseif getState(plr).active then

			stopBeam(plr, true)

		end

	end)



	chaosBeamLookUpdate.OnServerEvent:Connect(function(plr: Player, targetX: number, targetY: number, targetZ: number)

		if typeof(targetX) ~= "number" or typeof(targetY) ~= "number" or typeof(targetZ) ~= "number" then

			return

		end

		applyLookUpdate(plr, Vector3.new(targetX, targetY, targetZ))

	end)

end



function BeamService.cleanupPlayer(player: Player)

	stopBeam(player, false)

	stateByPlayer[player] = nil

end



return BeamService

