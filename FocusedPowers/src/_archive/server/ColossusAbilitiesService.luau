--!strict
--[[
	Colossus abilities: Power Punch, Bulwark, Seismic Slam.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCombatHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local BulwarkConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BulwarkConstants"))
local InteractableHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractableHelper"))
local PowerPunchConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PowerPunchConstants"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))
local SeismicSlamConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeismicSlamConstants"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))

local ColossusAbilitiesService = {}

type BulwarkState = {
	originalSpeed: number,
	originalJumpPower: number,
	originalJumpHeight: number?,
	originalJumpEnabled: boolean,
	originalAutoRotate: boolean,
	lookDir: Vector3,
	hitOnce: { [BasePart]: boolean },
}

local bulwarkState: { [Player]: BulwarkState } = {}

local function isColossus(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "Colossus"
end

local function isSteel(char: Model): boolean
	return char:GetAttribute("IsSteelFormActive") == true
end

local function getLookFlat(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function normalizeFlatLook(x: number, y: number, z: number, fallback: Vector3): Vector3
	local flat = Vector3.new(x, 0, z)
	if flat.Magnitude < 0.01 then
		return fallback
	end
	return flat.Unit
end

local function damageAndPushTarget(
	caster: Model,
	targetModel: Model,
	targetHum: Humanoid?,
	direction: Vector3,
	damage: number,
	pushSpeed: number,
	pushUp: number
)
	if targetHum and targetHum.Health > 0 then
		targetHum:TakeDamage(damage)
		PushHelper.applyToModel(targetModel, direction, {
			speed = pushSpeed,
			upBoost = pushUp,
		})
	elseif InteractableHelper.modelIsInteractableProp(targetModel) then
		InteractableHelper.applyDamage(targetModel, damage)
		local part = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
		if part then
			PushHelper.applyToPart(part, direction, {
				speed = pushSpeed,
				upBoost = pushUp,
			})
		end
	end
end

local function hitTargetsInRadius(
	plr: Player,
	char: Model,
	origin: Vector3,
	radius: number,
	direction: Vector3,
	damage: number,
	pushSpeed: number,
	pushUp: number,
	hitOnce: { [BasePart]: boolean }
)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char }

	for _, part in workspace:GetPartBoundsInRadius(origin, radius, overlap) do
		if hitOnce[part] then
			continue
		end
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or model == char then
			if InteractableHelper.hasInteractableMark(part) then
				hitOnce[part] = true
				InteractableHelper.applyDamage(part, damage)
				PushHelper.applyToPart(part, direction, { speed = pushSpeed, upBoost = pushUp })
			end
			continue
		end

		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local key = root or part
		if hitOnce[key] then
			continue
		end

		if hum and hum.Health > 0 then
			local targetPlr = Players:GetPlayerFromCharacter(model)
			if targetPlr == plr then
				continue
			end
			hitOnce[key] = true
			local pushDir = if root then (root.Position - origin) else direction
			damageAndPushTarget(char, model, hum, pushDir, damage, pushSpeed, pushUp)
		elseif InteractableHelper.modelIsInteractableProp(model) then
			hitOnce[key] = true
			local pushDir = direction
			damageAndPushTarget(char, model, nil, pushDir, damage, pushSpeed, pushUp)
		end
	end
end

local BULWARK_ROTATE_SPEED = 14

local function isGrounded(root: BasePart, char: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(root.Position + Vector3.new(0, 2, 0), Vector3.new(0, -6, 0), params)
	return hit ~= nil
end

local function snapBulwarkToGround(root: BasePart, hum: Humanoid, char: Model): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -24, 0), params)
	if not hit then
		return 0
	end
	local targetY = hit.Position.Y + hum.HipHeight
	local deltaY = targetY - root.Position.Y
	if math.abs(deltaY) > 0.05 then
		root.CFrame = CFrame.new(root.Position.X, targetY, root.Position.Z) * root.CFrame.Rotation
	end
	if deltaY < -0.5 then
		return -18
	elseif deltaY > 0.5 then
		return 12
	end
	return 0
end

local function normalizeLook(x: number, y: number, z: number, fallback: Vector3): Vector3
	local v = Vector3.new(x, y, z)
	if v.Magnitude < 0.01 then
		return fallback
	end
	return v.Unit
end

local function powerPunch(plr: Player, char: Model, _lookX: number, _lookY: number, _lookZ: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	-- Placeholder for future custom punch animation.
	char:SetAttribute("IsColossusLunging", true)
	local mult = if isSteel(char) then PowerPunchConstants.STEEL_MULT else 1
	local damage = PowerPunchConstants.BASE_DAMAGE * mult
	local pushSpeed = PowerPunchConstants.PUSH_SPEED * mult
	local hitOnce: { [Model]: boolean } = {}
	local duration = 0.22
	local started = tick()

	while tick() - started <= duration do
		for _, handName in { "RightHand", "Right Arm", "RightLowerArm", "LeftHand", "Left Arm", "LeftLowerArm" } do
			local hand = char:FindFirstChild(handName) :: BasePart?
			if hand and hand:IsA("BasePart") then
				local overlap = OverlapParams.new()
				overlap.FilterType = Enum.RaycastFilterType.Exclude
				overlap.FilterDescendantsInstances = { char }
				for _, part in workspace:GetPartBoundsInRadius(hand.Position, 2.2, overlap) do
					local model = part:FindFirstAncestorOfClass("Model")
					if model and not hitOnce[model] then
						local targetHum = model:FindFirstChildOfClass("Humanoid")
						local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
						local targetPlayer = Players:GetPlayerFromCharacter(model)
						if targetHum and targetHum.Health > 0 and targetPlayer ~= plr then
							hitOnce[model] = true
							targetHum:TakeDamage(damage)
							local dir = if targetRoot then (targetRoot.Position - hand.Position).Unit else hand.CFrame.LookVector
							PushHelper.applyToModel(model, dir, {
								speed = pushSpeed,
								upBoost = PowerPunchConstants.PUSH_UP,
							})
						elseif InteractableHelper.modelIsInteractableProp(model) then
							hitOnce[model] = true
							InteractableHelper.applyDamage(model, damage)
							PushHelper.applyToModel(model, hand.CFrame.LookVector, {
								speed = pushSpeed,
								upBoost = PowerPunchConstants.PUSH_UP,
							})
						end
					elseif InteractableHelper.hasInteractableMark(part) then
						InteractableHelper.applyDamage(part, damage)
						PushHelper.applyToPart(part, hand.CFrame.LookVector, {
							speed = pushSpeed,
							upBoost = PowerPunchConstants.PUSH_UP,
						})
					end
				end
			end
		end
		task.wait(0.03)
	end
	char:SetAttribute("IsColossusLunging", nil)
end

local function setBulwark(plr: Player, char: Model, active: boolean, lookX: number?, lookY: number?, lookZ: number?)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	if active then
		if char:GetAttribute("IsBulwarkActive") == true then
			local state = bulwarkState[plr]
			if state and lookX and lookY and lookZ then
				state.lookDir = normalizeLook(lookX, lookY, lookZ, state.lookDir)
			end
			return
		end
		local lookDir = normalizeLook(lookX or 0, lookY or 0, lookZ or 0, root.CFrame.LookVector)
		bulwarkState[plr] = {
			originalSpeed = hum.WalkSpeed,
			originalJumpPower = hum.JumpPower,
			originalJumpHeight = hum.JumpHeight,
			originalJumpEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping),
			originalAutoRotate = hum.AutoRotate,
			lookDir = lookDir,
			hitOnce = {},
		}
		char:SetAttribute("IsBulwarkActive", true)
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		if hum.JumpHeight then
			hum.JumpHeight = 0
		end
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		hum.AutoRotate = false
		hum.PlatformStand = false
	else
		char:SetAttribute("IsBulwarkActive", nil)
		local state = bulwarkState[plr]
		if state then
			hum.WalkSpeed = state.originalSpeed
			hum.PlatformStand = false
			hum.JumpPower = state.originalJumpPower
			if state.originalJumpHeight then
				hum.JumpHeight = state.originalJumpHeight
			end
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.originalJumpEnabled)
			hum.AutoRotate = state.originalAutoRotate
			root.AssemblyLinearVelocity = Vector3.zero
		end
		bulwarkState[plr] = nil
	end
end

local function groundSlam(plr: Player, char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end

	local mult = if isSteel(char) then SeismicSlamConstants.STEEL_MULT else 1
	local hopPos = root.Position + Vector3.new(0, SeismicSlamConstants.HOP_HEIGHT, 0)

	char:SetAttribute("IsColossusLunging", true)
	SmoothMotionHelper.runSmoothTravel(root, root.Position, hopPos, SeismicSlamConstants.SLAM_DURATION * 0.45, getLookFlat(root))
	SmoothMotionHelper.runSmoothTravel(root, hopPos, Vector3.new(root.Position.X, root.Position.Y, root.Position.Z), SeismicSlamConstants.SLAM_DURATION * 0.55, getLookFlat(root))
	char:SetAttribute("IsColossusLunging", nil)

	local radius = if isSteel(char) then SeismicSlamConstants.MAX_RADIUS else SeismicSlamConstants.MIN_RADIUS
	local damage = SeismicSlamConstants.BASE_DAMAGE * mult
	local origin = root.Position

	AbilityVfxHelper.spawnGroundRing(origin, Color3.fromRGB(190, 200, 220), 2, radius, 0.4)

	AbilityCombatHelper.hitInRadius(origin, radius, char, {
		damage = damage,
		pushSpeed = 20 * mult,
		pushUp = SeismicSlamConstants.PUSH_UP * mult,
		excludePlayer = plr,
	})
end

function ColossusAbilitiesService.update(dt: number)
	for plr, state in bulwarkState do
		local char = plr.Character
		if not char or char:GetAttribute("IsBulwarkActive") ~= true then
			bulwarkState[plr] = nil
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then
			bulwarkState[plr] = nil
			continue
		end

		local lookDir = state.lookDir
		if lookDir.Magnitude < 0.01 then
			lookDir = getLookFlat(root)
		end
		lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
		if lookDir.Magnitude < 0.01 then
			lookDir = getLookFlat(root)
		else
			lookDir = lookDir.Unit
		end

		local mult = if isSteel(char) then BulwarkConstants.STEEL_MULT else 1
		local damage = BulwarkConstants.BASE_DAMAGE * mult
		local pushSpeed = BulwarkConstants.PUSH_SPEED * mult
		local pushUp = BulwarkConstants.PUSH_UP

		local yVel = snapBulwarkToGround(root, hum, char)
		root.AssemblyLinearVelocity = Vector3.new(
			lookDir.X * BulwarkConstants.CHARGE_SPEED,
			yVel,
			lookDir.Z * BulwarkConstants.CHARGE_SPEED
		)

		local targetCF = CFrame.lookAt(root.Position, root.Position + lookDir)
		local rotAlpha = math.min(1, dt * BULWARK_ROTATE_SPEED)
		root.CFrame = root.CFrame:Lerp(targetCF, rotAlpha)

		hitTargetsInRadius(plr, char, root.Position, BulwarkConstants.HIT_RADIUS, lookDir, damage, pushSpeed, pushUp, state.hitOnce)
	end
end

function ColossusAbilitiesService.setup(punchRemote: RemoteEvent, bulwarkRemote: RemoteEvent, slamRemote: RemoteEvent)
	punchRemote.OnServerEvent:Connect(function(plr: Player, lookX: unknown, lookY: unknown, lookZ: unknown)
		if not isColossus(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, PowerPunchConstants.ABILITY_ID) then
			return
		end
		if typeof(lookX) ~= "number" or typeof(lookY) ~= "number" or typeof(lookZ) ~= "number" then
			return
		end
		AbilityCooldownHelper.apply(char, PowerPunchConstants.ABILITY_ID, PowerPunchConstants.COOLDOWN_SEC)
		task.spawn(function()
			powerPunch(plr, char, lookX, lookY, lookZ)
		end)
	end)

	bulwarkRemote.OnServerEvent:Connect(function(plr: Player, active: unknown, lookX: unknown, lookY: unknown, lookZ: unknown)
		if not isColossus(plr) or typeof(active) ~= "boolean" then
			return
		end
		local char = plr.Character
		if not char then
			return
		end
		local lx = if typeof(lookX) == "number" then lookX else nil
		local ly = if typeof(lookY) == "number" then lookY else nil
		local lz = if typeof(lookZ) == "number" then lookZ else nil
		if active then
			if char:GetAttribute("IsBulwarkActive") ~= true and AbilityCooldownHelper.isOnCooldown(char, BulwarkConstants.ABILITY_ID) then
				return
			end
			setBulwark(plr, char, true, lx, ly, lz)
		else
			setBulwark(plr, char, false)
			AbilityCooldownHelper.apply(char, BulwarkConstants.ABILITY_ID, BulwarkConstants.COOLDOWN_SEC)
		end
	end)

	slamRemote.OnServerEvent:Connect(function(plr: Player)
		if not isColossus(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, SeismicSlamConstants.ABILITY_ID) then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not root then
			return
		end
		if not isGrounded(root, char) then
			return
		end
		AbilityCooldownHelper.apply(char, SeismicSlamConstants.ABILITY_ID, SeismicSlamConstants.COOLDOWN_SEC)
		task.spawn(function()
			groundSlam(plr, char)
		end)
	end)
end

function ColossusAbilitiesService.onPlayerRemoving(plr: Player)
	bulwarkState[plr] = nil
end

return ColossusAbilitiesService
