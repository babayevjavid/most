local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	error("[BelthazorAbilities] Shared missing.")
end

local configModule = shared:WaitForChild("CharacterConfig", 10)
local ok, CharacterConfig = pcall(require, configModule)
if not ok or type(CharacterConfig) ~= "table" then
	error("[BelthazorAbilities] CharacterConfig required.")
end

local ghMod = shared:WaitForChild("GameHealth", 10)
local ghOk, GameHealth = pcall(require, ghMod)
if not ghOk or type(GameHealth) ~= "table" then
	error("[BelthazorAbilities] GameHealth required.")
end

local TAG = CharacterConfig.BelthazorTagName or "Belthazor"

local AGGRO = (CharacterConfig :: any).BelthazorAggroRangeStuds
local THINK = (CharacterConfig :: any).BelthazorThinkIntervalSeconds
local FB_CD = (CharacterConfig :: any).BelthazorFireballCooldown
local FB_DMG = (CharacterConfig :: any).BelthazorFireballDamage
local FB_SPEED = (CharacterConfig :: any).BelthazorFireballSpeed
local FB_SIZE = (CharacterConfig :: any).BelthazorFireballSizeStuds
local FB_LIFE = (CharacterConfig :: any).BelthazorFireballLifetime
local EB_CD = (CharacterConfig :: any).BelthazorEnergyBallCooldown
local EB_DMG = (CharacterConfig :: any).BelthazorEnergyBallDamage
local EB_SPEED = (CharacterConfig :: any).BelthazorEnergyBallSpeed
local EB_SIZE = (CharacterConfig :: any).BelthazorEnergyBallSizeStuds
local EB_LIFE = (CharacterConfig :: any).BelthazorEnergyBallLifetime
local SH_CD = (CharacterConfig :: any).BelthazorShimmerCooldown
local SH_MAX = (CharacterConfig :: any).BelthazorShimmerMaxRangeStuds
local SH_MIN = (CharacterConfig :: any).BelthazorShimmerMinRangeStuds
local SH_OFF = (CharacterConfig :: any).BelthazorShimmerOffsetStuds

if type(AGGRO) ~= "number" then
	AGGRO = 140
end
if type(THINK) ~= "number" then
	THINK = 0.35
end
if type(FB_CD) ~= "number" then
	FB_CD = 2
end
if type(FB_DMG) ~= "number" then
	FB_DMG = 24
end
if type(FB_SPEED) ~= "number" then
	FB_SPEED = 100
end
if type(FB_SIZE) ~= "number" then
	FB_SIZE = 3
end
if type(FB_LIFE) ~= "number" then
	FB_LIFE = 5
end
if type(EB_CD) ~= "number" then
	EB_CD = 5
end
if type(EB_DMG) ~= "number" then
	EB_DMG = 46
end
if type(EB_SPEED) ~= "number" then
	EB_SPEED = 92
end
if type(EB_SIZE) ~= "number" then
	EB_SIZE = 3.5
end
if type(EB_LIFE) ~= "number" then
	EB_LIFE = 5
end
if type(SH_CD) ~= "number" then
	SH_CD = 7
end
if type(SH_MAX) ~= "number" then
	SH_MAX = 78
end
if type(SH_MIN) ~= "number" then
	SH_MIN = 10
end
if type(SH_OFF) ~= "number" then
	SH_OFF = 12
end

type CooldownState = {
	lastFireball: number,
	lastEnergy: number,
	lastShimmer: number,
}

local cooldownByModel: { [Model]: CooldownState } = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function getCooldownState(model: Model): CooldownState
	local s = cooldownByModel[model]
	if not s then
		s = { lastFireball = 0, lastEnergy = 0, lastShimmer = 0 }
		cooldownByModel[model] = s
	end
	return s
end

local function clearModelState(model: Model)
	cooldownByModel[model] = nil
end

local function isBelthazorActive(model: Model): boolean
	if model:GetAttribute("Vanquished") == true then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	return true
end

local function getRightHand(model: Model): BasePart?
	local r = model:FindFirstChild("RightHand")
	if r and r:IsA("BasePart") then
		return r
	end
	r = model:FindFirstChild("Right Arm")
	if r and r:IsA("BasePart") then
		return r
	end
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Nearest living witch (chosen character) within aggro; aim point = their root (world target analogous to mouse hit).
local function getNearestAggroTarget(fromPosition: Vector3): (Player?, Vector3?, number)
	local bestPlr: Player? = nil
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	for _, plr in Players:GetPlayers() do
		local chosen = plr:GetAttribute("ChosenCharacter")
		if type(chosen) ~= "string" or chosen == "" then
			continue
		end
		local ch = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not hrp then
			continue
		end
		local dist = (hrp.Position - fromPosition).Magnitude
		if dist <= AGGRO and dist < bestDist then
			bestDist = dist
			bestPlr = plr
			bestPos = hrp.Position
		end
	end
	return bestPlr, bestPos, if bestPos then bestDist else math.huge
end

local function getGroundPosition(xz: Vector3, ignore: { Instance }): Vector3?
	groundParams.FilterDescendantsInstances = ignore
	local origin = Vector3.new(xz.X, xz.Y + 80, xz.Z)
	local res = Workspace:Raycast(origin, Vector3.new(0, -220, 0), groundParams)
	if not res then
		return nil
	end
	return res.Position
end

local function buildProjectile(
	origin: CFrame,
	size: number,
	color: Color3,
	projectileName: string
): BasePart
	local ball = Instance.new("Part")
	ball.Name = projectileName
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.CanCollide = false
	ball.CanQuery = true
	ball.Anchored = false
	ball.CFrame = origin
	ball:SetAttribute("IsProjectile", true)

	local interactableTag = Instance.new("BoolValue")
	interactableTag.Name = "Interactable"
	interactableTag.Value = true
	interactableTag.Parent = ball

	local attachment = Instance.new("Attachment")
	attachment.Name = "ProjectileAttachment"
	attachment.Parent = ball

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "ProjectileLinearVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.Enabled = true
	velocity.Parent = ball

	return ball
end

local function launchFromHand(
	casterModel: Model,
	hand: BasePart,
	aimWorld: Vector3,
	opts: { speed: number, damage: number, size: number, lifetime: number, color: Color3, name: string, push: number }
)
	local offset = aimWorld - hand.Position
	local dir = if offset.Magnitude > 0.15 then offset.Unit else hand.CFrame.LookVector
	local spawnPos = hand.Position + dir * (math.max(hand.Size.Magnitude * 0.35, 1.2) + opts.size * 0.35)
	local ball = buildProjectile(CFrame.new(spawnPos), opts.size, opts.color, opts.name)
	ball.Parent = Workspace

	local lv = ball:FindFirstChild("ProjectileLinearVelocity")
	if lv and lv:IsA("LinearVelocity") then
		lv.VectorVelocity = dir * opts.speed
	end

	local touched = false
	ball.Touched:Connect(function(hit: BasePart)
		if touched or not ball.Parent then
			return
		end
		if hit:IsDescendantOf(casterModel) then
			return
		end
		local victimModel = hit:FindFirstAncestorOfClass("Model")
		if not victimModel then
			return
		end
		local hum = victimModel:FindFirstChildOfClass("Humanoid")
		local root = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not root then
			return
		end
		if CollectionService:HasTag(victimModel, TAG) then
			return
		end
		if victimModel:GetAttribute("EmpathicDeflectionActive") == true then
			-- Deflected: avoid dealing damage/ragdoll to the empathic deflector.
			touched = true
			local away = ball.Position - root.Position
			local deflectDir = if away.Magnitude > 0.01 then away.Unit else dir
			local lv = ball:FindFirstChild("ProjectileLinearVelocity")
			if lv and lv:IsA("LinearVelocity") then
				lv.VectorVelocity = deflectDir * opts.speed
			end
			ball:Destroy()
			return
		end
		touched = true
		GameHealth.applyDamage(hum, opts.damage)
		local away = root.Position - ball.Position
		local pushDir = if away.Magnitude > 0.01 then away.Unit else dir
		root.AssemblyLinearVelocity = pushDir * opts.push + Vector3.new(0, 20, 0)
		victimModel:SetAttribute("Ragdolled", true)
		task.delay(2.4, function()
			if victimModel.Parent and hum.Health > 0 and victimModel:GetAttribute("Ragdolled") == true then
				victimModel:SetAttribute("Ragdolled", false)
			end
		end)
		ball:Destroy()
	end)

	Debris:AddItem(ball, opts.lifetime)
end

local function tryShimmerTeleport(casterModel: Model, casterHrp: BasePart, hum: Humanoid, aimWorld: Vector3): boolean
	local flatFrom = Vector3.new(casterHrp.Position.X, 0, casterHrp.Position.Z)
	local flatTo = Vector3.new(aimWorld.X, 0, aimWorld.Z)
	local delta = flatTo - flatFrom
	local dist = delta.Magnitude
	if dist < SH_MIN or dist > SH_MAX then
		return false
	end
	local dir = if dist > 0.05 then delta.Unit else casterHrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.05 then
		dir = Vector3.new(0, 0, -1)
	end
	local destFlat = flatTo - dir * SH_OFF
	local ground = getGroundPosition(Vector3.new(destFlat.X, aimWorld.Y, destFlat.Z), { casterModel })
	if not ground then
		return false
	end
	local hip = hum.HipHeight
	local halfY = casterHrp.Size.Y * 0.5
	local y = ground.Y + hip + halfY + 0.12
	local newPos = Vector3.new(destFlat.X, y, destFlat.Z)
	casterHrp.AssemblyLinearVelocity = Vector3.zero
	casterHrp.AssemblyAngularVelocity = Vector3.zero
	local lookAt = Vector3.new(aimWorld.X, newPos.Y, aimWorld.Z)
	casterHrp.CFrame = CFrame.new(newPos, lookAt)
	return true
end

local function thinkBelthazor(model: Model)
	-- Playable Belthazor uses PowerCast powers; only untagged NPC rigs use this AI.
	if Players:GetPlayerFromCharacter(model) ~= nil then
		return
	end
	if not isBelthazorActive(model) then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hand = getRightHand(model)
	if not hum or not hrp or not hand then
		return
	end

	local _, aimPos = getNearestAggroTarget(hrp.Position)
	if not aimPos then
		return
	end

	local now = os.clock()
	local cd = getCooldownState(model)

	-- Shimmer: blink to grounded point near “mouse” (target), in valid band.
	if now - cd.lastShimmer >= SH_CD then
		if tryShimmerTeleport(model, hrp, hum, aimPos) then
			cd.lastShimmer = now
			return
		end
	end

	-- Energy ball: heavier hit, longer cooldown.
	if now - cd.lastEnergy >= EB_CD then
		cd.lastEnergy = now
		launchFromHand(model, hand, aimPos, {
			speed = EB_SPEED,
			damage = EB_DMG,
			size = EB_SIZE,
			lifetime = EB_LIFE,
			color = Color3.fromRGB(120, 220, 255),
			name = "BelthazorEnergyBall",
			push = 105,
		})
		return
	end

	-- Fireball: frequent poke.
	if now - cd.lastFireball >= FB_CD then
		cd.lastFireball = now
		launchFromHand(model, hand, aimPos, {
			speed = FB_SPEED,
			damage = FB_DMG,
			size = FB_SIZE,
			lifetime = FB_LIFE,
			color = Color3.fromRGB(255, 110, 28),
			name = "BelthazorFireball",
			push = 92,
		})
	end
end

local function bindModelCleanup(model: Model)
	model.Destroying:Connect(function()
		clearModelState(model)
	end)
end

for _, inst in CollectionService:GetTagged(TAG) do
	if inst:IsA("Model") then
		bindModelCleanup(inst)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	if inst:IsA("Model") then
		bindModelCleanup(inst)
	end
end)

task.spawn(function()
	while true do
		for _, inst in CollectionService:GetTagged(TAG) do
			if inst:IsA("Model") then
				thinkBelthazor(inst)
			end
		end
		task.wait(THINK)
	end
end)