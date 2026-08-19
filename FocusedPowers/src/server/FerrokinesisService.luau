--!strict
--[[ Ferrokinesis: hold Metal-tagged targets at mouse aim distance; LMB throw. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityCooldownHelper = require(Shared:WaitForChild("AbilityCooldownHelper"))
local MetallicHelper = require(Shared:WaitForChild("MetallicHelper"))
local PolarisConstants = require(Shared:WaitForChild("PolarisConstants"))
local PushHelper = require(Shared:WaitForChild("PushHelper"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local ResourceService = require(script.Parent:WaitForChild("ResourceService"))

local C = PolarisConstants.Ferrokinesis
local ABILITY_ID = C.ABILITY_ID
local MAX_RANGE_SQ = C.RAYCAST_MAX_DIST * C.RAYCAST_MAX_DIST

type AmbientEntry = {
	root: BasePart,
	model: Model?,
	humanoid: Humanoid?,
	currentVel: Vector3,
	hoverSlot: number,
}

type FerroState = {
	mode: "single" | "ambient",
	caster: Player,
	targetRoot: BasePart?,
	targetModel: Model?,
	targetHumanoid: Humanoid?,
	ambientEntries: { AmbientEntry }?,
	holdDirection: Vector3,
	targetHoldDistance: number,
	holdDistance: number,
	currentVel: Vector3,
	grabTime: number,
	grabDistance: number,
	grabWorldPosition: Vector3,
	throwPhase: "pull"?,
	throwPhaseStartTime: number?,
	throwLaunchDirection: Vector3?,
	throwTargetWorld: Vector3?,
	originalWalkSpeed: number?,
	originalJumpPower: number?,
	originalJumpHeight: number?,
	originalJumpingEnabled: boolean?,
	originalAutoJumpEnabled: boolean?,
}

local ferroByPlayer: { [Player]: FerroState } = {}

type ThrownMonitor = {
	root: BasePart,
	caster: Player,
	casterChar: Model,
	throwDir: Vector3,
	hitTargets: { [Model]: boolean },
	startTime: number,
	touchConn: RBXScriptConnection?,
}

local thrownMonitors: { ThrownMonitor } = {}

local function holdAimDirection(holdDir: Vector3, fallback: Vector3): Vector3
	if holdDir.Magnitude > 0.01 then
		return holdDir.Unit
	end
	if fallback.Magnitude > 0.01 then
		return fallback.Unit
	end
	return Vector3.new(0, 0, -1)
end

local function clampWorldPosToCasterRange(pos: Vector3, casterPos: Vector3, maxDist: number): Vector3
	local offset = pos - casterPos
	if offset.Magnitude > maxDist then
		return casterPos + offset.Unit * maxDist
	end
	return pos
end

local function monitorThrownTarget(root: BasePart, caster: Player, casterChar: Model, throwDir: Vector3)
	local primaryModel = root:FindFirstAncestorOfClass("Model")
	local hitTargets: { [Model]: boolean } = {}
	if primaryModel then
		hitTargets[primaryModel] = true
	end

	local monitor: ThrownMonitor = {
		root = root,
		caster = caster,
		casterChar = casterChar,
		throwDir = throwDir,
		hitTargets = hitTargets,
		startTime = tick(),
		touchConn = nil,
	}

	monitor.touchConn = root.Touched:Connect(function(hit)
		if not hit or not hit.Parent or not root.Parent then
			return
		end
		if hit:IsDescendantOf(casterChar) then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and hitTargets[model] then
			return
		end
		if model then
			hitTargets[model] = true
		end

		local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
		local pushDir = if throwDir.Magnitude > 0.01 then throwDir.Unit else root.AssemblyLinearVelocity.Unit
		if hum and hum.Health > 0 then
			hum:TakeDamage(C.THROW_DAMAGE * C.THROW_CHAIN_DAMAGE_MULT)
			PushHelper.applyFromHit(hit, pushDir, {
				speed = C.THROW_SPEED * 0.55,
				upBoost = C.THROW_UP_BOOST * 0.5,
			}, casterChar)
		elseif MetallicHelper.isFerrokinesisTarget(hit, casterChar) then
			PushHelper.applyFromHit(hit, pushDir, {
				speed = C.THROW_SPEED * 0.45,
				upBoost = 0,
			}, casterChar)
		end
	end)

	table.insert(thrownMonitors, monitor)
end

local function cleanupThrownMonitors(now: number)
	for i = #thrownMonitors, 1, -1 do
		local monitor = thrownMonitors[i]
		local expired = now - monitor.startTime >= 3
		local stopped = not monitor.root.Parent or monitor.root.AssemblyLinearVelocity.Magnitude < 2
		if expired or stopped then
			if monitor.touchConn then
				monitor.touchConn:Disconnect()
			end
			table.remove(thrownMonitors, i)
		end
	end
end

local function isPolaris(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "Polaris"
end

local function resolveTarget(hitPart: Instance?, casterChar: Model, casterRoot: BasePart)
	if not hitPart or not hitPart:IsA("BasePart") then
		return nil
	end
	if hitPart:IsDescendantOf(casterChar) then
		return nil
	end
	if not MetallicHelper.isFerrokinesisTarget(hitPart, casterChar) then
		return nil
	end
	local model = hitPart:FindFirstAncestorOfClass("Model")
	if model and model ~= casterChar then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				return root, model, humanoid
			end
		end
		return MetallicHelper.getMetallicRoot(hitPart), model, nil
	end
	return MetallicHelper.getMetallicRoot(hitPart), nil, nil
end

local function unanchorMetalAssembly(root: BasePart, model: Model?)
	if model then
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") and desc.Anchored then
				desc:SetAttribute("FK_WasAnchored", true)
				desc.Anchored = false
			end
		end
	elseif root.Anchored then
		root:SetAttribute("FK_WasAnchored", true)
		root.Anchored = false
	end
end

local function restoreMetalAssemblyAnchors(root: BasePart, model: Model?, skipPropAnchor: boolean?)
	if skipPropAnchor then
		return
	end
	local function restorePart(part: BasePart)
		local wasAnchored = part:GetAttribute("FK_WasAnchored")
		if wasAnchored == true then
			part.Anchored = true
			part:SetAttribute("FK_WasAnchored", nil)
		end
	end
	if model then
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				restorePart(desc)
			end
		end
	else
		restorePart(root)
	end
end

local function setupSingleHeld(root: BasePart, model: Model?, humanoid: Humanoid?)
	if model and humanoid then
		model:SetAttribute("Ragdolled", true)
		model:SetAttribute("FerrokinesisHeld", true)
		humanoid.PlatformStand = true
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	elseif root then
		unanchorMetalAssembly(root, model)
		root:SetAttribute("FerrokinesisHeld", true)
	end
end

local function clearSingleHeld(root: BasePart?, model: Model?, humanoid: Humanoid?, skipPropAnchor: boolean?)
	if model then
		model:SetAttribute("FerrokinesisHeld", nil)
		if model:GetAttribute("Ragdolled") == true then
			model:SetAttribute("Ragdolled", nil)
		end
	end
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
	end
	if root and root.Parent and not humanoid then
		root:SetAttribute("FerrokinesisHeld", nil)
		restoreMetalAssemblyAnchors(root, model, skipPropAnchor)
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
end

local function setupHeldTarget(target: FerroState)
	if target.mode == "ambient" and target.ambientEntries then
		for _, entry in target.ambientEntries do
			setupSingleHeld(entry.root, entry.model, entry.humanoid)
		end
		return
	end
	if target.targetRoot then
		setupSingleHeld(target.targetRoot, target.targetModel, target.targetHumanoid)
	end
end

local function clearHeldTarget(target: FerroState, skipPropAnchor: boolean?)
	if target.mode == "ambient" and target.ambientEntries then
		for _, entry in target.ambientEntries do
			clearSingleHeld(entry.root, entry.model, entry.humanoid, skipPropAnchor)
		end
		return
	end
	clearSingleHeld(target.targetRoot, target.targetModel, target.targetHumanoid, skipPropAnchor)
end

local function endFerrokinesis(plr: Player, applyCooldown: boolean, fromThrow: boolean?)
	local s = ferroByPlayer[plr]
	ferroByPlayer[plr] = nil
	if not s then
		return
	end

	local char = s.caster.Character
	if char and char.Parent then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if s.originalWalkSpeed ~= nil then
				humanoid.WalkSpeed = s.originalWalkSpeed
			end
			if s.originalJumpPower ~= nil then
				humanoid.JumpPower = s.originalJumpPower
			end
			if s.originalJumpHeight ~= nil then
				humanoid.JumpHeight = s.originalJumpHeight
			end
			if s.originalJumpingEnabled ~= nil then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, s.originalJumpingEnabled)
			end
			if s.originalAutoJumpEnabled ~= nil then
				humanoid.AutoJumpEnabled = s.originalAutoJumpEnabled
			end
		end
		char:SetAttribute("IsFerrokinesisActive", nil)
		char:SetAttribute("FerrokinesisHoldDistance", nil)
		char:SetAttribute("FerrokinesisAmbientMode", nil)
		char:SetAttribute("FerrokinesisAmbientCount", nil)
		local heldRef = char:FindFirstChild("FerrokinesisHeldRoot")
		if heldRef and heldRef:IsA("ObjectValue") then
			heldRef.Value = nil
		end
		if applyCooldown then
			AbilityCooldownHelper.apply(char, ABILITY_ID, C.COOLDOWN_SEC)
		end
	end

	clearHeldTarget(s, fromThrow == true)
	ProgressionService.clearHoldTimer(plr)
	if applyCooldown and not fromThrow then
		ProgressionService.grantAbilityXp(plr, ABILITY_ID, "release")
	end
end

local function throwSingleRoot(
	root: BasePart,
	model: Model?,
	humanoid: Humanoid?,
	throwDir: Vector3,
	caster: Player,
	casterChar: Model
)
	local vel = throwDir * C.THROW_SPEED + Vector3.new(0, C.THROW_UP_BOOST, 0)
	root.AssemblyLinearVelocity = vel
	pcall(function()
		root:ApplyImpulse(throwDir * (root.AssemblyMass * C.THROW_SPEED * C.THROW_IMPULSE_MULT))
	end)

	if humanoid then
		humanoid.PlatformStand = false
		if humanoid.Health > 0 then
			humanoid:TakeDamage(C.THROW_DAMAGE)
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
		if model then
			model:SetAttribute("Ragdolled", true)
			task.delay(3, function()
				if model and model.Parent then
					model:SetAttribute("Ragdolled", nil)
				end
			end)
		end
	end

	monitorThrownTarget(root, caster, casterChar, throwDir)
end

local function applyThrow(s: FerroState)
	local char = s.caster.Character
	if not char or not char.Parent then
		endFerrokinesis(s.caster, false, true)
		return
	end

	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local throwTarget = s.throwTargetWorld
	local throwDir = if s.throwLaunchDirection and s.throwLaunchDirection.Magnitude > 0.01
		then s.throwLaunchDirection.Unit
		elseif throwTarget and casterRoot
		then (throwTarget - casterRoot.Position).Unit
		elseif s.holdDirection.Magnitude > 0.01
		then s.holdDirection.Unit
		else (casterRoot and casterRoot.CFrame.LookVector or Vector3.new(0, 0, -1))

	if s.mode == "ambient" and s.ambientEntries then
		for _, entry in s.ambientEntries do
			if entry.root.Parent then
				local entryDir = if throwTarget
					then (throwTarget - entry.root.Position).Unit
					else throwDir
				if entryDir.Magnitude < 0.01 then
					entryDir = throwDir
				end
				throwSingleRoot(entry.root, entry.model, entry.humanoid, entryDir, s.caster, char)
				clearSingleHeld(entry.root, entry.model, entry.humanoid, true)
			end
		end
	else
		if not s.targetRoot or not s.targetRoot.Parent then
			endFerrokinesis(s.caster, false, true)
			return
		end
		throwSingleRoot(s.targetRoot, s.targetModel, s.targetHumanoid, throwDir, s.caster, char)
	end

	local config = ResourceService.getConfig("Polaris")
	if config then
		ResourceService.trySpend(char, config.instant.FerrokinesisThrow or 5)
	end
	ProgressionService.grantAbilityXp(s.caster, ABILITY_ID, "throw")
	endFerrokinesis(s.caster, true, true)
end

local function beginFerrokinesis(
	plr: Player,
	char: Model,
	casterRoot: BasePart,
	humanoid: Humanoid,
	s: FerroState
)
	ferroByPlayer[plr] = s
	char:SetAttribute("IsFerrokinesisActive", true)
	if s.mode == "ambient" then
		char:SetAttribute("FerrokinesisAmbientMode", true)
		char:SetAttribute("FerrokinesisAmbientCount", if s.ambientEntries then #s.ambientEntries else 0)
	else
		char:SetAttribute("FerrokinesisHoldDistance", s.targetHoldDistance)
	end

	local heldRef = char:FindFirstChild("FerrokinesisHeldRoot")
	if not heldRef then
		heldRef = Instance.new("ObjectValue")
		heldRef.Name = "FerrokinesisHeldRoot"
		heldRef.Parent = char
	end
	if s.mode == "single" and s.targetRoot then
		(heldRef :: ObjectValue).Value = s.targetRoot
	else
		(heldRef :: ObjectValue).Value = nil
	end

	if char:GetAttribute("IsMagneticFlying") ~= true then
		humanoid.WalkSpeed = 4
		humanoid.JumpPower = 0
		if humanoid.JumpHeight then
			humanoid.JumpHeight = 0
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.AutoJumpEnabled = false
	end

	setupHeldTarget(s)
	if s.mode == "single" and s.targetHumanoid then
		s.targetHumanoid.Died:Once(function()
			endFerrokinesis(plr, false, false)
		end)
	end
	humanoid.Died:Once(function()
		endFerrokinesis(plr, false, false)
	end)
	ProgressionService.grantAbilityXp(plr, ABILITY_ID, "start")
end

local function tryStartAmbient(plr: Player, char: Model, casterRoot: BasePart, humanoid: Humanoid, roots: { BasePart }): boolean
	local entries: { AmbientEntry } = {}
	for i, root in roots do
		if not root.Parent then
			continue
		end
		local model = root:FindFirstAncestorOfClass("Model")
		local targetHumanoid = if model and model ~= char then model:FindFirstChildOfClass("Humanoid") else nil
		table.insert(entries, {
			root = root,
			model = if targetHumanoid and targetHumanoid.Health > 0 then model else (model ~= char and model or nil),
			humanoid = if targetHumanoid and targetHumanoid.Health > 0 then targetHumanoid else nil,
			currentVel = Vector3.zero,
			hoverSlot = math.min(i, #C.AMBIENT_HOVER_OFFSETS),
		})
	end
	if #entries == 0 then
		return false
	end

	local s: FerroState = {
		mode = "ambient",
		caster = plr,
		targetRoot = nil,
		targetModel = nil,
		targetHumanoid = nil,
		ambientEntries = entries,
		holdDirection = casterRoot.CFrame.LookVector,
		targetHoldDistance = C.HOLD_DISTANCE_MAX * 0.5,
		holdDistance = C.HOLD_DISTANCE_MAX * 0.5,
		currentVel = Vector3.zero,
		grabTime = tick(),
		grabDistance = C.HOLD_DISTANCE_MAX * 0.5,
		grabWorldPosition = casterRoot.Position,
		originalWalkSpeed = humanoid.WalkSpeed,
		originalJumpPower = humanoid.JumpPower,
		originalJumpHeight = humanoid.JumpHeight,
		originalJumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		originalAutoJumpEnabled = humanoid.AutoJumpEnabled,
	}
	beginFerrokinesis(plr, char, casterRoot, humanoid, s)
	return true
end

local function tryStart(plr: Player, hitPart: Instance?): boolean
	if ferroByPlayer[plr] or not isPolaris(plr) then
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
	if char:GetAttribute("Ragdolled") == true then
		return false
	end
	if char:GetAttribute("IsOrbitalStrikesActive") == true or char:GetAttribute("IsMetalLanceActive") == true then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(char, ABILITY_ID) then
		return false
	end
	if not ResourceService.hasMinimum(char, "Polaris", ABILITY_ID) then
		return false
	end

	local root, targetModel, targetHumanoid = resolveTarget(hitPart, char, casterRoot)
	if not root or not root.Parent then
		local ambientRoots = MetallicHelper.findAmbientPropRoots(
			casterRoot.Position,
			char,
			C.AMBIENT_SCAN_RANGE,
			C.AMBIENT_MAX_ITEMS,
			nil
		)
		if #ambientRoots == 0 then
			return false
		end
		return tryStartAmbient(plr, char, casterRoot, humanoid, ambientRoots)
	end
	local hitPos = (hitPart and hitPart:IsA("BasePart")) and hitPart.Position or root.Position
	if (hitPos - casterRoot.Position).Magnitude ^ 2 > MAX_RANGE_SQ then
		return false
	end

	local delta = root.Position - casterRoot.Position
	local holdDist = math.clamp(
		if delta.Magnitude > 0.05 then delta.Magnitude else C.HOLD_DISTANCE_MAX * 0.5,
		C.HOLD_DISTANCE_MIN,
		C.HOLD_DISTANCE_MAX
	)

	local s: FerroState = {
		mode = "single",
		caster = plr,
		targetRoot = root,
		targetModel = targetHumanoid and targetModel or nil,
		targetHumanoid = targetHumanoid,
		ambientEntries = nil,
		holdDirection = casterRoot.CFrame.LookVector,
		targetHoldDistance = holdDist,
		holdDistance = holdDist,
		currentVel = Vector3.zero,
		grabTime = tick(),
		grabDistance = holdDist,
		grabWorldPosition = root.Position,
		originalWalkSpeed = humanoid.WalkSpeed,
		originalJumpPower = humanoid.JumpPower,
		originalJumpHeight = humanoid.JumpHeight,
		originalJumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		originalAutoJumpEnabled = humanoid.AutoJumpEnabled,
	}

	beginFerrokinesis(plr, char, casterRoot, humanoid, s)
	return true
end

local function updateDirection(plr: Player, lookX: number, lookY: number, lookZ: number, holdDistanceTarget: number?)
	local s = ferroByPlayer[plr]
	if not s then
		return
	end
	local dir = Vector3.new(lookX, lookY, lookZ)
	if dir.Magnitude > 0.01 then
		s.holdDirection = dir.Unit
	end
	if typeof(holdDistanceTarget) == "number" then
		local clamped = math.clamp(holdDistanceTarget, C.HOLD_DISTANCE_MIN, C.HOLD_DISTANCE_MAX)
		if (tick() - s.grabTime) >= C.GRAB_DISTANCE_LOCK_SEC then
			s.targetHoldDistance = clamped
		elseif math.abs(clamped - s.grabDistance) > 0.5 then
			s.targetHoldDistance = clamped
			s.grabDistance = clamped
		end
		local char = s.caster.Character
		if char then
			char:SetAttribute("FerrokinesisHoldDistance", s.targetHoldDistance)
		end
	end
end

local FerrokinesisService = {}

function FerrokinesisService.setup(
	request: RemoteEvent,
	updateRemote: RemoteEvent,
	throwRemote: RemoteEvent,
	endRemote: RemoteEvent
)
	request.OnServerEvent:Connect(function(plr: Player, hitPart: Instance?)
		if ferroByPlayer[plr] then
			return
		end
		tryStart(plr, hitPart)
	end)

	updateRemote.OnServerEvent:Connect(function(plr: Player, lookX: number, lookY: number, lookZ: number, holdDist: number?)
		updateDirection(plr, lookX, lookY, lookZ, holdDist)
	end)

	throwRemote.OnServerEvent:Connect(function(plr: Player, targetX: number?, targetY: number?, targetZ: number?)
		local s = ferroByPlayer[plr]
		if not s or s.throwPhase == "pull" then
			return
		end
		local char = s.caster.Character
		local casterRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if typeof(targetX) == "number" and typeof(targetY) == "number" and typeof(targetZ) == "number" then
			s.throwTargetWorld = Vector3.new(targetX, targetY, targetZ)
			s.throwLaunchDirection = if casterRoot
				then (s.throwTargetWorld - casterRoot.Position).Unit
				else s.holdDirection
		else
			s.throwLaunchDirection = if s.holdDirection.Magnitude > 0.01
				then s.holdDirection.Unit
				else (casterRoot and casterRoot.CFrame.LookVector or Vector3.new(0, 0, -1))
		end
		s.throwPhase = "pull"
		s.throwPhaseStartTime = tick()
	end)

	endRemote.OnServerEvent:Connect(function(plr: Player)
		local s = ferroByPlayer[plr]
		if not s or s.throwPhase == "pull" then
			return
		end
		endFerrokinesis(plr, true, false)
	end)
end

function FerrokinesisService.update(dt: number, now: number)
	cleanupThrownMonitors(now)

	for plr, s in ferroByPlayer do
		local char = s.caster.Character
		if not char or not char.Parent then
			endFerrokinesis(plr, true, false)
			continue
		end
		if char:GetAttribute("Ragdolled") == true then
			endFerrokinesis(plr, false, false)
			continue
		end

		local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not casterRoot then
			endFerrokinesis(plr, false, false)
			continue
		end

		if s.mode == "ambient" then
			if not s.ambientEntries or #s.ambientEntries == 0 then
				endFerrokinesis(plr, true, false)
				continue
			end
			for i = #s.ambientEntries, 1, -1 do
				local entry = s.ambientEntries[i]
				if not entry.root.Parent then
					clearSingleHeld(entry.root, entry.model, entry.humanoid, false)
					table.remove(s.ambientEntries, i)
				end
			end
			if #s.ambientEntries == 0 then
				endFerrokinesis(plr, true, false)
				continue
			end
			char:SetAttribute("FerrokinesisAmbientCount", #s.ambientEntries)
		else
			if not s.targetRoot or not s.targetRoot.Parent then
				endFerrokinesis(plr, true, false)
				continue
			end
			if not MetallicHelper.isFerrokinesisTarget(s.targetRoot, char) then
				endFerrokinesis(plr, true, false)
				continue
			end
		end

		if s.throwPhase == "pull" and s.throwPhaseStartTime then
			if now - s.throwPhaseStartTime >= C.THROW_PULL_DURATION then
				applyThrow(s)
				continue
			end
		else
			ProgressionService.tickAbilityHold(plr, ABILITY_ID, dt)
		end

		if humanoid and char:GetAttribute("IsMagneticFlying") ~= true then
			humanoid.WalkSpeed = 4
			humanoid.JumpPower = 0
		end

		local isFlying = char:GetAttribute("IsMagneticFlying") == true
		local holdSpeed = if isFlying then C.FLIGHT_HOLD_SPEED else C.HOLD_SPEED
		local holdAccel = if isFlying then C.FLIGHT_HOLD_ACCEL else C.HOLD_ACCEL

		if s.mode == "ambient" and s.ambientEntries then
			local casterCF = casterRoot.CFrame
			local pullAnchor = casterRoot.Position
			if s.throwPhase == "pull" then
				pullAnchor = casterRoot.Position + casterRoot.CFrame.LookVector * C.THROW_PULL_DISTANCE
			end
			for _, entry in s.ambientEntries do
				if not entry.root.Parent then
					continue
				end
				if entry.humanoid and entry.humanoid.Parent then
					entry.humanoid.PlatformStand = true
				else
					entry.root.Anchored = false
				end
				local offset = C.AMBIENT_HOVER_OFFSETS[entry.hoverSlot] or C.AMBIENT_HOVER_OFFSETS[1]
				local holdAnchor = if s.throwPhase == "pull"
					then pullAnchor
					else casterCF:PointToWorldSpace(offset)
				local toDesired = holdAnchor - entry.root.Position
				local dist = toDesired.Magnitude
				local desiredVel = Vector3.zero
				if dist > 0.35 then
					local speedMult = if s.throwPhase == "pull" then 1.35 else 1
					desiredVel = toDesired.Unit * math.min(holdSpeed * speedMult, dist * 5)
				end
				if not isFlying and s.throwPhase ~= "pull" then
					desiredVel += Vector3.new(0, workspace.Gravity * dt, 0)
				end
				local diff = desiredVel - entry.currentVel
				local maxStep = dt * holdAccel
				local step = if diff.Magnitude <= maxStep then diff else diff.Unit * maxStep
				entry.currentVel = entry.currentVel + step
				entry.root.AssemblyLinearVelocity = entry.currentVel
			end
			continue
		end

		local holdDist = s.holdDistance
		if s.throwPhase == "pull" then
			holdDist = C.THROW_PULL_DISTANCE
		elseif s.throwPhase ~= "pull" then
			local targetDist = if (now - s.grabTime) < C.GRAB_DISTANCE_LOCK_SEC then s.grabDistance else s.targetHoldDistance
			local alpha = math.min(1, dt * C.HOLD_DISTANCE_LERP_SPEED)
			s.holdDistance = s.holdDistance + (targetDist - s.holdDistance) * alpha
			holdDist = s.holdDistance
		end

		if s.targetHumanoid and s.targetHumanoid.Parent then
			s.targetHumanoid.PlatformStand = true
		elseif s.targetRoot then
			s.targetRoot.Anchored = false
		end

		local singleRoot = s.targetRoot :: BasePart
		local aimDir = holdAimDirection(s.holdDirection, casterRoot.CFrame.LookVector)
		local holdAnchor = casterRoot.Position + aimDir * holdDist
		holdAnchor = clampWorldPosToCasterRange(holdAnchor, casterRoot.Position, C.RAYCAST_MAX_DIST)

		local toDesired = holdAnchor - singleRoot.Position
		local dist = toDesired.Magnitude
		local desiredVel = Vector3.zero
		if dist > 0.35 then
			local speedMult = if s.throwPhase == "pull" then 1.35 else 1
			desiredVel = toDesired.Unit * math.min(holdSpeed * speedMult, dist * 5)
		end
		if not isFlying and s.throwPhase ~= "pull" then
			desiredVel += Vector3.new(0, workspace.Gravity * dt, 0)
		end

		local diff = desiredVel - s.currentVel
		local maxStep = dt * holdAccel
		local step = if diff.Magnitude <= maxStep then diff else diff.Unit * maxStep
		s.currentVel = s.currentVel + step
		singleRoot.AssemblyLinearVelocity = s.currentVel
	end
end

function FerrokinesisService.forceEnd(plr: Player)
	if ferroByPlayer[plr] then
		endFerrokinesis(plr, false, false)
	end
end

function FerrokinesisService.forceEndHoldingTarget(targetModel: Model)
	for plr, s in ferroByPlayer do
		if s.targetModel == targetModel then
			endFerrokinesis(plr, true, false)
		elseif s.mode == "ambient" and s.ambientEntries then
			for _, entry in s.ambientEntries do
				if entry.model == targetModel then
					endFerrokinesis(plr, true, false)
					break
				end
			end
		end
	end
end

function FerrokinesisService.onPlayerRemoving(plr: Player)
	FerrokinesisService.forceEnd(plr)
end

return FerrokinesisService
