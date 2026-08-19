--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))
local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))
local PropHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PropHelper"))

local CombatService = require(script.Parent.CombatService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local WandaHandParticlesService = require(script.Parent.WandaHandParticlesService)

local C = AbilityConstants
local MAX_RANGE_SQ = C.TELEKINESIS_MAX_RANGE * C.TELEKINESIS_MAX_RANGE

type TargetState = {
	root: BasePart,
	model: Model?,
	humanoid: Humanoid?,
	currentVel: Vector3,
	holdAlign: AlignPosition?,
	holdAttach: Attachment?,
}

type TelekinesisState = {
	caster: Player,
	targetRoot: BasePart,
	targetModel: Model?,
	targetHumanoid: Humanoid?,
	heldTargets: { TargetState },
	holdDistance: number,
	targetHoldDistance: number,
	holdDirection: Vector3,
	cursorWorldPos: Vector3?,
	lastDrainTime: number,
	originalWalkSpeed: number?,
	originalJumpPower: number?,
	rotateAtt: Attachment?,
	rotateAlign: AlignOrientation?,
	throwPhase: ("pull" | "launched")?,
	throwPhaseStartTime: number?,
}

local TelekinesisService = {}
local tkByPlayer: { [Player]: TelekinesisState } = {}
local updateConn: RBXScriptConnection? = nil
local onStatUpdate: ((player: Player) -> ())? = nil
local onCooldown: ((player: Player, abilityId: string, duration: number) -> ())? = nil

local function clampWorldPosToCasterRange(pos: Vector3, casterPos: Vector3, maxRange: number): Vector3
	local delta = pos - casterPos
	if delta.Magnitude > maxRange then
		return casterPos + delta.Unit * maxRange
	end
	return pos
end

local function resolveTarget(hitPart: Instance?, casterRoot: BasePart): (BasePart?, Model?, Humanoid?)
	if not hitPart or not hitPart:IsA("BasePart") then
		return nil, nil, nil
	end
	if hitPart:IsDescendantOf(casterRoot.Parent) then
		return nil, nil, nil
	end

	local parent = hitPart.Parent
	if parent and parent:IsA("Model") then
		local model = parent :: Model
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health <= 0 then
				return nil, nil, nil
			end
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				return root, model, humanoid
			end
		elseif PropHelper.isProp(hitPart) then
			return hitPart, nil, nil
		end
	end

	if PropHelper.isProp(hitPart) then
		return hitPart, nil, nil
	end
	return nil, nil, nil
end

local function createHoldAlign(root: BasePart): (AlignPosition, Attachment)
	local att = Instance.new("Attachment")
	att.Name = "TelekinesisHoldAttachment"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "TelekinesisHoldAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxForce = 250000
	align.MaxVelocity = math.huge
	align.Responsiveness = 18
	align.ApplyAtCenterOfMass = true
	align.Position = root.Position
	align.Parent = root
	return align, att
end

local function destroyHoldAlign(target: TargetState)
	if target.holdAlign then
		target.holdAlign:Destroy()
		target.holdAlign = nil
	end
	if target.holdAttach then
		target.holdAttach:Destroy()
		target.holdAttach = nil
	end
end

local function ensureRotateAlign(s: TelekinesisState, casterRoot: BasePart)
	if s.rotateAlign and s.rotateAlign.Parent and s.rotateAtt and s.rotateAtt.Parent then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "TelekinesisRotateAttachment"
	att.Parent = casterRoot
	local align = Instance.new("AlignOrientation")
	align.Name = "TelekinesisRotateAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.AlignType = Enum.AlignType.AllAxes
	align.MaxTorque = math.huge
	align.Responsiveness = C.ROTATE_ALIGN_RESPONSIVENESS
	align.CFrame = casterRoot.CFrame
	align.Parent = casterRoot
	s.rotateAtt = att
	s.rotateAlign = align
end

local function updateCasterFacing(s: TelekinesisState, casterRoot: BasePart)
	if not s.targetRoot or not s.targetRoot.Parent then
		return
	end
	ensureRotateAlign(s, casterRoot)
	local align = s.rotateAlign
	if not align or not align.Parent then
		return
	end
	local flatToTarget = Vector3.new(
		s.targetRoot.Position.X - casterRoot.Position.X,
		0,
		s.targetRoot.Position.Z - casterRoot.Position.Z
	)
	if flatToTarget.Magnitude > 0.5 then
		flatToTarget = flatToTarget.Unit
		align.CFrame = CFrame.lookAt(casterRoot.Position, casterRoot.Position + flatToTarget, Vector3.yAxis)
	end
end

local function computeThrowDir(s: TelekinesisState, targetRoot: BasePart, casterRoot: BasePart?): Vector3
	local throwDir: Vector3? = nil
	if typeof(s.cursorWorldPos) == "Vector3" and targetRoot.Parent then
		local toCursor = s.cursorWorldPos - targetRoot.Position
		if toCursor.Magnitude > 0.15 then
			throwDir = toCursor.Unit
		end
	end
	if not throwDir and s.holdDirection.Magnitude > 0.01 then
		throwDir = s.holdDirection.Unit
	end
	if not throwDir and casterRoot then
		throwDir = casterRoot.CFrame.LookVector
	end
	if not throwDir then
		throwDir = Vector3.new(0, 0, -1)
	end
	if casterRoot then
		local away = targetRoot.Position - casterRoot.Position
		if away.Magnitude > 0.5 then
			local awayUnit = away.Unit
			if throwDir:Dot(awayUnit) < 0.35 then
				throwDir = (throwDir + awayUnit * 2.5).Unit
				if throwDir:Dot(awayUnit) < 0 then
					throwDir = awayUnit
				end
			end
		end
	end
	return throwDir
end

local function clearTargetRagdoll(model: Model?, humanoid: Humanoid?)
	if model then
		model:SetAttribute("TelekinesisHeld", nil)
		model:SetAttribute("Ragdolled", nil)
	end
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
	end
end

local function endTelekinesisFor(plr: Player, applyCooldown: boolean, skipRagdollClear: boolean)
	local s = tkByPlayer[plr]
	if not s then
		return
	end
	tkByPlayer[plr] = nil

	local heldTargets = s.heldTargets
	local char = s.caster.Character

	if s.rotateAlign and s.rotateAlign.Parent then
		s.rotateAlign:Destroy()
	end
	if s.rotateAtt and s.rotateAtt.Parent then
		s.rotateAtt:Destroy()
	end

	if char and char.Parent then
		char:SetAttribute("IsTelekinesisActive", nil)
		char:SetAttribute("TelekinesisHoldDistance", nil)
		WandaHandParticlesService.disable(char)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if s.originalWalkSpeed ~= nil then
				humanoid.WalkSpeed = s.originalWalkSpeed
			end
			if s.originalJumpPower ~= nil then
				humanoid.JumpPower = s.originalJumpPower
			end
		end
		if applyCooldown then
			PlayerStateService.setCooldown(plr, "Telekinesis", os.clock() + C.TELEKINESIS_COOLDOWN)
			if onCooldown then
				onCooldown(plr, "Telekinesis", C.TELEKINESIS_COOLDOWN)
			end
		end
	end

	if not skipRagdollClear then
		for _, target in heldTargets do
			clearTargetRagdoll(target.model, target.humanoid)
		end
	end

	for _, target in heldTargets do
		if target.root and target.root.Parent then
			destroyHoldAlign(target)
			if not target.humanoid then
				local wasAnchored = target.root:GetAttribute("TK_WasAnchored")
				if wasAnchored ~= nil then
					target.root.Anchored = wasAnchored
					target.root:SetAttribute("TK_WasAnchored", nil)
				end
				target.root:SetAttribute("TelekinesisHeld", nil)
				pcall(function()
					target.root:SetNetworkOwnershipAuto()
				end)
			end
		end
	end

	if onStatUpdate then
		onStatUpdate(plr)
	end
end

local function applyThrowAndLaunch(s: TelekinesisState)
	local char = s.caster.Character
	if not char or not char.Parent then
		endTelekinesisFor(s.caster, false, false)
		return
	end

	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local heroId = PlayerStateService.get(s.caster).HeroId
	local heldTargets = s.heldTargets
	local thrownTargets: { { model: Model?, humanoid: Humanoid? } } = {}

	for _, target in heldTargets do
		if target.humanoid and target.humanoid.Health > 0 then
			local dmg = CombatService.computeDamage(s.caster, heroId, C.TELEKINESIS_THROW_DAMAGE)
			target.humanoid:TakeDamage(dmg)
		end

		if target.root and target.root.Parent then
			local throwDir = computeThrowDir(s, target.root, casterRoot)
			local isHumanoid = target.humanoid ~= nil
			local baseSpeed = if isHumanoid then C.TELEKINESIS_HUMANOID_THROW_SPEED else C.TELEKINESIS_OBJECT_THROW_SPEED
			local vertical = if isHumanoid then C.TELEKINESIS_HUMANOID_THROW_VERTICAL else C.TELEKINESIS_OBJECT_THROW_VERTICAL
			local vel = throwDir * baseSpeed + Vector3.new(0, vertical, 0)

			destroyHoldAlign(target)
			if isHumanoid and target.model then
				for _, part in target.model:GetDescendants() do
					if part:IsA("BasePart") then
						part.AssemblyLinearVelocity = vel
					end
				end
				target.humanoid.PlatformStand = false
			else
				target.root.AssemblyLinearVelocity = vel
				local throwMass = target.root.AssemblyMass
				pcall(function()
					target.root:ApplyImpulse(throwDir * (throwMass * baseSpeed))
				end)
			end

			if target.model and target.humanoid then
				local touchedConn: RBXScriptConnection? = nil
				local didHit = false
				touchedConn = target.root.Touched:Connect(function(hitPart)
					if didHit then
						return
					end
					local hitModel = hitPart:FindFirstAncestorOfClass("Model")
					if not hitModel or hitModel == target.model then
						return
					end
					local hitHum = hitModel:FindFirstChildOfClass("Humanoid")
					if not hitHum or hitHum.Health <= 0 then
						return
					end
					didHit = true
					if touchedConn then
						touchedConn:Disconnect()
					end
					local impactDmg = CombatService.computeDamage(s.caster, heroId, C.TELEKINESIS_THROW_IMPACT_DAMAGE)
					hitHum:TakeDamage(impactDmg)
					local hitRoot = hitModel:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hitRoot then
						local pushDir = hitRoot.Position - target.root.Position
						if pushDir.Magnitude < 0.1 then
							pushDir = s.holdDirection
						end
						hitRoot:ApplyImpulse(pushDir.Unit * (hitRoot.AssemblyMass * C.TELEKINESIS_THROW_IMPACT_PUSH))
					end
					if hitModel:GetAttribute("IsShieldActive") ~= true then
						hitModel:SetAttribute("Ragdolled", true)
						task.delay(C.TELEKINESIS_THROW_IMPACT_RAGDOLL_SEC, function()
							if hitModel.Parent and hitModel:GetAttribute("Ragdolled") == true then
								hitModel:SetAttribute("Ragdolled", nil)
							end
						end)
					end
				end)
				task.delay(C.TELEKINESIS_THROW_HIT_WINDOW_SEC, function()
					if touchedConn then
						touchedConn:Disconnect()
					end
				end)
			end

			table.insert(thrownTargets, { model = target.model, humanoid = target.humanoid })
		end
	end

	s.throwPhase = "launched"
	local caster = s.caster
	task.defer(function()
		task.wait()
		if tkByPlayer[caster] then
			endTelekinesisFor(caster, true, true)
		end
		task.delay(C.TELEKINESIS_RAGDOLL_AFTER_THROW_SEC, function()
			for _, thrown in thrownTargets do
				clearTargetRagdoll(thrown.model, thrown.humanoid)
			end
		end)
	end)
end

local function canUseTelekinesis(plr: Player): boolean
	local state = PlayerStateService.get(plr)
	if not state.HeroId then
		return false
	end
	return HeroRegistry.heroOwnsAbility(state.HeroId, "Telekinesis")
end

local function tryStart(plr: Player, hitPart: Instance?, cursorAnchorPos: Vector3?): boolean
	if tkByPlayer[plr] then
		return false
	end
	if not canUseTelekinesis(plr) then
		return false
	end
	if PlayerStateService.isOnCooldown(plr, "Telekinesis") then
		return false
	end

	local char = plr.Character
	if not char or not char.Parent then
		return false
	end
	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not casterRoot or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local state = PlayerStateService.get(plr)
	if state.Energy < C.TELEKINESIS_ENERGY_DRAIN then
		return false
	end

	local root, targetModel, targetHumanoid = resolveTarget(hitPart, casterRoot)
	if not root or not root.Parent then
		return false
	end

	local hitPos = if hitPart and hitPart:IsA("BasePart") then hitPart.Position else root.Position
	if (hitPos - casterRoot.Position).Magnitude ^ 2 > MAX_RANGE_SQ then
		return false
	end

	local ShieldService = require(script.Parent.ShieldService)
	ShieldService.turnOff(plr)

	local initialHoldDist = C.TELEKINESIS_HOLD_DISTANCE
	local delta = root.Position - casterRoot.Position
	if delta.Magnitude > 0.05 then
		initialHoldDist = delta.Magnitude
	end
	initialHoldDist = math.clamp(initialHoldDist, C.TELEKINESIS_HOLD_DISTANCE_MIN, C.TELEKINESIS_HOLD_DISTANCE_MAX)

	local singularHoldWorld: Vector3? = nil
	if typeof(cursorAnchorPos) == "Vector3" then
		singularHoldWorld = clampWorldPosToCasterRange(cursorAnchorPos, casterRoot.Position, C.TELEKINESIS_MAX_RANGE)
	end

	local heldTargets: { TargetState } = {
		{
			root = root,
			model = targetModel,
			humanoid = targetHumanoid,
			currentVel = Vector3.zero,
		},
	}

	local s: TelekinesisState = {
		caster = plr,
		targetRoot = root,
		targetModel = targetModel,
		targetHumanoid = targetHumanoid,
		heldTargets = heldTargets,
		holdDistance = initialHoldDist,
		targetHoldDistance = initialHoldDist,
		holdDirection = delta.Magnitude > 0.05 and delta.Unit or casterRoot.CFrame.LookVector,
		cursorWorldPos = singularHoldWorld or cursorAnchorPos,
		lastDrainTime = os.clock(),
		originalWalkSpeed = humanoid.WalkSpeed,
		originalJumpPower = humanoid.JumpPower,
		rotateAtt = nil,
		rotateAlign = nil,
		throwPhase = nil,
		throwPhaseStartTime = nil,
	}
	tkByPlayer[plr] = s

	char:SetAttribute("IsTelekinesisActive", true)
	char:SetAttribute("TelekinesisHoldDistance", initialHoldDist)
	humanoid.WalkSpeed = C.TELEKINESIS_CASTER_WALK_SPEED
	humanoid.JumpPower = 0

	ensureRotateAlign(s, casterRoot)
	updateCasterFacing(s, casterRoot)

	WandaHandParticlesService.enable(char)
	WandaHandParticlesService.emit(char)

	for _, target in heldTargets do
		if target.model and target.humanoid then
			if target.model:GetAttribute("IsShieldActive") ~= true then
				target.model:SetAttribute("Ragdolled", true)
				target.model:SetAttribute("TelekinesisHeld", true)
				target.humanoid.PlatformStand = false
			end
		end
		if target.root and target.root.Parent then
			if target.humanoid then
				local align, att = createHoldAlign(target.root)
				target.holdAlign = align
				target.holdAttach = att
				target.root.AssemblyLinearVelocity = Vector3.zero
				target.root.AssemblyAngularVelocity = Vector3.zero
			else
				pcall(function()
					target.root:SetNetworkOwner(plr)
				end)
				target.root:SetAttribute("TK_WasAnchored", target.root.Anchored)
				target.root.Anchored = false
				target.root:SetAttribute("TelekinesisHeld", true)
			end
		end
	end

	humanoid.Died:Once(function()
		endTelekinesisFor(plr, false, false)
	end)
	for _, target in heldTargets do
		if target.humanoid then
			target.humanoid.Died:Once(function()
				endTelekinesisFor(plr, false, false)
			end)
		end
	end

	return true
end

local function updateDirection(
	plr: Player,
	lookX: number,
	lookY: number,
	lookZ: number,
	cursorAnchorPos: Vector3?,
	holdDistanceTarget: number?
)
	local s = tkByPlayer[plr]
	if not s then
		return
	end
	local dir = Vector3.new(lookX, lookY, lookZ)
	if dir.Magnitude < 0.01 then
		return
	end
	s.holdDirection = dir.Unit
	if typeof(cursorAnchorPos) == "Vector3" then
		s.cursorWorldPos = cursorAnchorPos
	end
	if typeof(holdDistanceTarget) == "number" then
		s.targetHoldDistance = math.clamp(holdDistanceTarget, C.TELEKINESIS_HOLD_DISTANCE_MIN, C.TELEKINESIS_HOLD_DISTANCE_MAX)
		local char = s.caster.Character
		if char then
			char:SetAttribute("TelekinesisHoldDistance", s.targetHoldDistance)
		end
	end
end

local function doThrow(plr: Player): boolean
	local s = tkByPlayer[plr]
	if not s then
		return false
	end
	if s.throwPhase == "pull" then
		return true
	end
	if not PlayerStateService.spendEnergy(plr, C.TELEKINESIS_THROW_COST) then
		return false
	end
	s.throwPhase = "pull"
	s.throwPhaseStartTime = os.clock()
	if onStatUpdate then
		onStatUpdate(plr)
	end
	return true
end

local function update(dt: number, now: number)
	for plr, s in tkByPlayer do
		local char = s.caster.Character
		if not char or not char.Parent then
			endTelekinesisFor(plr, false, false)
			continue
		end
		if char:GetAttribute("IsShieldActive") == true then
			endTelekinesisFor(plr, false, false)
			continue
		end

		local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not casterRoot or not s.targetRoot or not s.targetRoot.Parent then
			endTelekinesisFor(plr, false, false)
			continue
		end

		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = C.TELEKINESIS_CASTER_WALK_SPEED
			humanoid.JumpPower = 0
		end

		if s.throwPhase == "launched" then
			continue
		end

		if s.throwPhase == "pull" and typeof(s.throwPhaseStartTime) == "number" then
			if now - s.throwPhaseStartTime >= C.TELEKINESIS_THROW_PULL_DURATION then
				applyThrowAndLaunch(s)
				continue
			end
		else
			if now - s.lastDrainTime >= C.TELEKINESIS_ENERGY_INTERVAL then
				s.lastDrainTime = now
				local state = PlayerStateService.get(plr)
				state.Energy = math.max(0, state.Energy - C.TELEKINESIS_ENERGY_DRAIN)
				PlayerStateService.markResourceUsed(plr)
				if state.Energy <= 0 then
					endTelekinesisFor(plr, false, false)
					if onStatUpdate then
						onStatUpdate(plr)
					end
					continue
				end
				if onStatUpdate then
					onStatUpdate(plr)
				end
			end
		end

		updateCasterFacing(s, casterRoot)

		local holdDist = C.TELEKINESIS_HOLD_DISTANCE
		if s.throwPhase == "pull" then
			holdDist = C.TELEKINESIS_THROW_PULL_DISTANCE
		else
			local alpha = math.min(1, dt * C.TELEKINESIS_HOLD_DISTANCE_LERP_SPEED)
			s.holdDistance = s.holdDistance + (s.targetHoldDistance - s.holdDistance) * alpha
			holdDist = s.holdDistance
		end

		local holdAnchor = casterRoot.Position + s.holdDirection * holdDist
		holdAnchor = clampWorldPosToCasterRange(holdAnchor, casterRoot.Position, C.TELEKINESIS_MAX_RANGE)

		for _, target in s.heldTargets do
			if not (target.root and target.root.Parent) then
				continue
			end
			if not target.humanoid then
				target.root.Anchored = false
			end

			local desiredPos = holdAnchor
			if target.holdAlign then
				target.holdAlign.Position = desiredPos
				target.root.AssemblyAngularVelocity = Vector3.zero
			else
				local toDesired = desiredPos - target.root.Position
				local dist = toDesired.Magnitude
				local desiredVel = Vector3.zero
				if dist > 0.35 then
					local speed = math.min(C.TELEKINESIS_HOLD_SPEED, dist * 5)
					desiredVel = toDesired.Unit * speed
				end
				desiredVel += Vector3.new(0, workspace.Gravity * dt, 0)
				local diff = desiredVel - target.currentVel
				local maxStep = dt * C.TELEKINESIS_HOLD_ACCEL
				local step = if diff.Magnitude <= maxStep then diff else diff.Unit * maxStep
				target.currentVel = target.currentVel + step
				target.root.AssemblyLinearVelocity = target.currentVel
			end
		end
	end
end

function TelekinesisService.setup(
	telekinesisRequest: RemoteEvent,
	telekinesisUpdate: RemoteEvent,
	telekinesisThrow: RemoteEvent,
	telekinesisEnd: RemoteEvent,
	statUpdateCallback: (player: Player) -> (),
	cooldownCallback: (player: Player, abilityId: string, duration: number) -> ()
)
	onStatUpdate = statUpdateCallback
	onCooldown = cooldownCallback

	telekinesisRequest.OnServerEvent:Connect(function(plr: Player, hitPart: Instance?, cursorX: number?, cursorY: number?, cursorZ: number?)
		local cursorPos: Vector3? = nil
		if typeof(cursorX) == "number" and typeof(cursorY) == "number" and typeof(cursorZ) == "number" then
			cursorPos = Vector3.new(cursorX, cursorY, cursorZ)
		end
		tryStart(plr, hitPart, cursorPos)
	end)

	telekinesisUpdate.OnServerEvent:Connect(function(plr: Player, lookX: number, lookY: number, lookZ: number, cursorX: number?, cursorY: number?, cursorZ: number?, holdDist: number?)
		local cursorPos: Vector3? = nil
		if typeof(cursorX) == "number" and typeof(cursorY) == "number" and typeof(cursorZ) == "number" then
			cursorPos = Vector3.new(cursorX, cursorY, cursorZ)
		end
		updateDirection(plr, lookX, lookY, lookZ, cursorPos, holdDist)
	end)

	telekinesisThrow.OnServerEvent:Connect(function(plr: Player)
		doThrow(plr)
	end)

	telekinesisEnd.OnServerEvent:Connect(function(plr: Player)
		local s = tkByPlayer[plr]
		if not s then
			return
		end
		if s.throwPhase == "pull" then
			return
		end
		endTelekinesisFor(plr, true, false)
	end)
end

function TelekinesisService.startUpdateLoop()
	if updateConn then
		return
	end
	updateConn = RunService.Heartbeat:Connect(function(dt)
		update(dt, os.clock())
	end)
end

function TelekinesisService.cleanupPlayer(player: Player)
	endTelekinesisFor(player, false, false)
end

function TelekinesisService.isActive(player: Player): boolean
	return tkByPlayer[player] ~= nil
end

return TelekinesisService
