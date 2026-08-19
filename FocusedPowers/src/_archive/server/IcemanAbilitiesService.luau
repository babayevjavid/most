--!strict
--[[ Iceman abilities server ]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AbilityCombatHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local IcemanConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IcemanConstants"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))

local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local SteerableBoltService = require(script.Parent:WaitForChild("SteerableBoltService"))

local CHAR_ID = "Iceman"
local C = IcemanConstants
local COLOR = C.COLOR

type SlideState = {
	originalSpeed: number,
	lookDir: Vector3,
	lastPadAt: number,
	linearVel: LinearVelocity,
	gravityCancel: VectorForce,
}

local function destroySlidePhysics(state: SlideState)
	if state.linearVel.Parent then
		state.linearVel:Destroy()
	end
	if state.gravityCancel.Parent then
		state.gravityCancel:Destroy()
	end
end

local slidePlayers: { [Player]: SlideState } = {}

local IcemanAbilitiesService = {}

local function isIceman(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function getRoot(char: Model): BasePart?
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function normalizeLook(x: number, y: number, z: number, fallback: Vector3): Vector3
	local v = Vector3.new(x, y, z)
	if v.Magnitude < 0.01 then
		return fallback
	end
	return v.Unit
end

local function spawnIcePad(position: Vector3, moveDir: Vector3)
	local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	local padPos = position + flat * C.IceSlide.PAD_OFFSET + Vector3.new(0, -2.8, 0)
	local pad = Instance.new("Part")
	pad.Name = "IceSlidePad"
	pad.Size = Vector3.new(C.IceSlide.PAD_WIDTH, C.IceSlide.PAD_THICKNESS, C.IceSlide.PAD_LENGTH)
	pad.Material = Enum.Material.Ice
	pad.Color = COLOR
	pad.Transparency = 0
	pad.Anchored = true
	pad.CanCollide = true
	pad.CFrame = CFrame.lookAt(padPos, padPos + flat) * CFrame.Angles(0, math.rad(90), 0)
	pad.Parent = workspace
	Debris:AddItem(pad, C.IceSlide.PAD_LIFETIME)
end

local function setIceSlide(plr: Player, active: boolean, lookX: number?, lookY: number?, lookZ: number?)
	local char = plr.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = getRoot(char)
	if not hum or not root then
		return
	end
	if active then
		if not ResourceService.hasMinimum(char, CHAR_ID, C.IceSlide.ABILITY_ID) then
			return
		end
		if char:GetAttribute("IsIceSliding") == true then
			local state = slidePlayers[plr]
			if state and lookX and lookY and lookZ then
				state.lookDir = normalizeLook(lookX, lookY, lookZ, state.lookDir)
			end
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, C.IceSlide.ABILITY_ID) then
			return
		end
		local lookDir = normalizeLook(lookX or 0, lookY or 0, lookZ or 0, root.CFrame.LookVector)
		slidePlayers[plr] = {
			originalSpeed = hum.WalkSpeed,
			lookDir = lookDir,
			lastPadAt = 0,
			linearVel = (nil :: any),
			gravityCancel = (nil :: any),
		}
		local state = slidePlayers[plr]
		char:SetAttribute("IsIceSliding", true)
		hum.WalkSpeed = 0
		hum.PlatformStand = true
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		local att = root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", root)
		local lv = Instance.new("LinearVelocity", root)
		lv.Name = "IceSlideLinearVel"
		lv.Attachment0 = att
		lv.MaxForce = math.huge
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VectorVelocity = Vector3.zero
		local vf = Instance.new("VectorForce", root)
		vf.Name = "IceSlideGravityCancel"
		vf.Attachment0 = att
		vf.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		state.linearVel = lv
		state.gravityCancel = vf
	else
		local saved = slidePlayers[plr]
		if saved then
			destroySlidePhysics(saved)
		end
		slidePlayers[plr] = nil
		char:SetAttribute("IsIceSliding", nil)
		hum.WalkSpeed = if saved then saved.originalSpeed else 16
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Running)
		AbilityCooldownHelper.apply(char, C.IceSlide.ABILITY_ID, C.IceSlide.COOLDOWN_SEC)
	end
end

local function frostBoltConfig()
	local cfg = C.FrostBolt
	return {
		abilityId = cfg.ABILITY_ID,
		boltName = "FrostBolt",
		size = cfg.SIZE,
		color = COLOR,
		speed = cfg.SPEED,
		maxRange = cfg.RANGE,
		lifetime = cfg.LIFETIME,
		damage = cfg.DAMAGE,
		pushSpeed = cfg.PUSH_SPEED,
		pushUp = cfg.PUSH_UP,
		curveStrength = cfg.CURVE_STRENGTH,
		impactRadius = 3,
		impactDuration = 0.25,
	}
end

local function onFrostBoltHit(_plr: Player, hit: BasePart, caster: Model, direction: Vector3)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model or model == caster then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:TakeDamage(C.FrostBolt.DAMAGE)
		model:SetAttribute("Frozen", true)
		task.delay(C.FrostBolt.FREEZE_DURATION, function()
			if model.Parent then
				model:SetAttribute("Frozen", nil)
			end
		end)
		AbilityCombatHelper.damageAndPush(model, hum, hit, direction, {
			damage = 0,
			pushSpeed = C.FrostBolt.PUSH_SPEED,
			pushUp = C.FrostBolt.PUSH_UP,
		})
	end
end

local function iceWall(plr: Player, char: Model)
	local root = getRoot(char)
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local targetPos = root.Position + flat * C.IceWall.DISTANCE
	local cfg = C.IceWall
	local finalCF = CFrame.new(targetPos, targetPos + flat)
	local startCF = finalCF * CFrame.new(0, -cfg.SIZE.Y * 0.55, 0)

	local wall = Instance.new("Part")
	wall.Name = "IceWall"
	wall.Size = cfg.SIZE
	wall.Material = Enum.Material.Ice
	wall.Color = COLOR
	wall.Transparency = 0
	wall.Anchored = true
	wall.CanCollide = true
	wall.CFrame = startCF
	wall.Parent = workspace

	TweenService:Create(
		wall,
		TweenInfo.new(cfg.RISE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = finalCF }
	):Play()
	Debris:AddItem(wall, cfg.LIFETIME)
end

local function absoluteZero(plr: Player, char: Model)
	local root = getRoot(char)
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	AbilityVfxHelper.spawnDirectionalBurst(root.Position, look, COLOR, C.AbsoluteZero.RANGE, 0.3)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(root.Position, look * C.AbsoluteZero.RANGE, params)
	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
		if hum and hum.Health > 0 and model then
			hum:TakeDamage(C.AbsoluteZero.DAMAGE)
			model:SetAttribute("Frozen", true)
			task.delay(C.AbsoluteZero.FREEZE_DURATION, function()
				if model.Parent then
					model:SetAttribute("Frozen", nil)
				end
			end)
		end
	end
	AbilityCombatHelper.hitInRadius(root.Position + look * (C.AbsoluteZero.RANGE * 0.5), 6, char, {
		damage = C.AbsoluteZero.DAMAGE * 0.5,
		pushSpeed = 20,
		pushUp = 4,
		excludePlayer = plr,
	})
end

local function blizzard(plr: Player, char: Model, alpha: number)
	local root = getRoot(char)
	if not root then
		return
	end
	local cfg = C.Blizzard
	local maxR = cfg.MIN_RADIUS + (cfg.MAX_RADIUS - cfg.MIN_RADIUS) * alpha
	local damage = cfg.MIN_DAMAGE + (cfg.MAX_DAMAGE - cfg.MIN_DAMAGE) * alpha
	AbilityVfxHelper.spawnExpandingSphere(root.Position, COLOR, 2, maxR, cfg.WAVE_DURATION)
	local hitOnce: { [Instance]: boolean } = {}
	local start = tick()
	while tick() - start < cfg.WAVE_DURATION do
		local a = SmoothMotionHelper.smoothstep((tick() - start) / cfg.WAVE_DURATION)
		local overlap = OverlapParams.new()
		overlap.FilterDescendantsInstances = { char }
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		for _, part in workspace:GetPartBoundsInRadius(root.Position, maxR * a, overlap) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model then
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and not hitOnce[model] then
					hitOnce[model] = true
					hum:TakeDamage(damage)
					model:SetAttribute("HexSlow", true)
					task.delay(2, function()
						if model.Parent then
							model:SetAttribute("HexSlow", nil)
						end
					end)
					AbilityCombatHelper.damageAndPush(model, hum, part, part.Position - root.Position, {
						damage = 0,
						pushSpeed = cfg.PUSH_SPEED,
						pushUp = cfg.PUSH_UP,
					})
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
end

function IcemanAbilitiesService.setup(
	slideRemote: RemoteEvent,
	frostBoltStart: RemoteEvent,
	frostBoltAim: RemoteEvent,
	frostBoltRelease: RemoteEvent,
	wallRemote: RemoteEvent,
	zeroRemote: RemoteEvent,
	blizzardRemote: RemoteEvent
)
	ResourceService.registerStopCallback("IsIceSliding", function(p)
		setIceSlide(p, false)
	end)

	slideRemote.OnServerEvent:Connect(function(plr, active: unknown, lookX: unknown, lookY: unknown, lookZ: unknown)
		if not isIceman(plr) or typeof(active) ~= "boolean" then
			return
		end
		local lx = if typeof(lookX) == "number" then lookX else nil
		local ly = if typeof(lookY) == "number" then lookY else nil
		local lz = if typeof(lookZ) == "number" then lookZ else nil
		setIceSlide(plr, active, lx, ly, lz)
	end)

	frostBoltStart.OnServerEvent:Connect(function(plr: Player, dirX: unknown, dirY: unknown, dirZ: unknown)
		if not isIceman(plr) or typeof(dirX) ~= "number" or typeof(dirY) ~= "number" or typeof(dirZ) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.FrostBolt.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 6) then
			return
		end
		local state = SteerableBoltService.handleStart(plr, C.FrostBolt.ABILITY_ID, dirX, dirY, dirZ, frostBoltConfig(), onFrostBoltHit)
		if state then
			AbilityCooldownHelper.apply(char, C.FrostBolt.ABILITY_ID, C.FrostBolt.COOLDOWN_SEC)
		end
	end)

	frostBoltAim.OnServerEvent:Connect(function(plr: Player, dirX: unknown, dirY: unknown, dirZ: unknown)
		if not isIceman(plr) or typeof(dirX) ~= "number" or typeof(dirY) ~= "number" or typeof(dirZ) ~= "number" then
			return
		end
		SteerableBoltService.handleAim(plr, C.FrostBolt.ABILITY_ID, dirX, dirY, dirZ)
	end)

	frostBoltRelease.OnServerEvent:Connect(function(plr: Player)
		if not isIceman(plr) then
			return
		end
		SteerableBoltService.handleRelease(plr, C.FrostBolt.ABILITY_ID)
	end)

	wallRemote.OnServerEvent:Connect(function(plr)
		if not isIceman(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.IceWall.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 14) then
			return
		end
		AbilityCooldownHelper.apply(char, C.IceWall.ABILITY_ID, C.IceWall.COOLDOWN_SEC)
		iceWall(plr, char)
	end)

	zeroRemote.OnServerEvent:Connect(function(plr)
		if not isIceman(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.AbsoluteZero.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 20) then
			return
		end
		AbilityCooldownHelper.apply(char, C.AbsoluteZero.ABILITY_ID, C.AbsoluteZero.COOLDOWN_SEC)
		absoluteZero(plr, char)
	end)

	blizzardRemote.OnServerEvent:Connect(function(plr, alpha: unknown)
		if not isIceman(plr) or typeof(alpha) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.Blizzard.ABILITY_ID) then
			return
		end
		local a = math.clamp(alpha, 0, 1)
		local cost = ResourceService.getScaledCost(CHAR_ID, C.Blizzard.ABILITY_ID, a) or 12
		if not ResourceService.trySpend(char, cost) then
			return
		end
		AbilityCooldownHelper.apply(char, C.Blizzard.ABILITY_ID, C.Blizzard.COOLDOWN_SEC)
		task.spawn(function()
			blizzard(plr, char, a)
		end)
	end)
end

function IcemanAbilitiesService.update(dt: number)
	local now = tick()
	for plr, state in slidePlayers do
		local char = plr.Character
		if not char or char:GetAttribute("IsIceSliding") ~= true then
			if state then
				destroySlidePhysics(state)
			end
			slidePlayers[plr] = nil
			continue
		end
		local root = getRoot(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then
			continue
		end

		local look = state.lookDir
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
		local vel = flat * C.IceSlide.MOVE_SPEED
		if hum.FloorMaterial == Enum.Material.Air then
			vel += Vector3.new(0, C.IceSlide.FLOAT_BIAS, 0)
		end
		if state.linearVel.Parent then
			state.linearVel.VectorVelocity = vel
		end
		if state.gravityCancel.Parent then
			state.gravityCancel.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
		end
		local targetCF = CFrame.lookAt(root.Position, root.Position + flat)
		root.CFrame = root.CFrame:Lerp(targetCF, C.IceSlide.ROTATE_LERP)

		if now - state.lastPadAt >= 0.12 then
			state.lastPadAt = now
			spawnIcePad(root.Position, flat)
		end
	end
end

function IcemanAbilitiesService.onPlayerRemoving(plr: Player)
	slidePlayers[plr] = nil
end

return IcemanAbilitiesService
