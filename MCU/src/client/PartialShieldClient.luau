--!strict
-- Instant local PartialShield VFX: unreliable remote + client-side bolt proximity predict.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local PartialShieldClient = {}

local HIT_RADIUS = 9
local predicted: { [Instance]: boolean } = {}
local lastBurstAt: { [Model]: number } = {}

local function spawnLocalBurst(character: Model, hitFrom: Vector3?)
	-- Jean / Invisible Woman use persistent forcefields — never Wanda partial shells
	if
		character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "jean_grey"
		or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
	then
		return
	end

	local now = os.clock()
	local last = lastBurstAt[character]
	if last and (now - last) < 0.05 then
		return
	end
	lastBurstAt[character] = now

	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	local shell = VfxHelper.spawnPartialShieldShell(root, hitFrom, 10)
	if not shell then
		return
	end

	task.delay(GameConstants.SHIELD_PARTIAL_EMIT_TIME, function()
		if not shell.Parent then
			return
		end
		VfxHelper.setParticlesEnabled(shell, false)
		task.delay(GameConstants.SHIELD_PARTIAL_DELETE_DELAY, function()
			if shell.Parent then
				shell:Destroy()
			end
		end)
	end)
end

local function getBoltPosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		return if pp then pp.Position else nil
	end
	return nil
end

local function predictHits(character: Model)
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) ~= true then
		return
	end
	if
		character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "jean_grey"
		or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
	then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, child in Workspace:GetChildren() do
		if child.Name ~= "HexProjectile" then
			continue
		end
		if predicted[child] then
			continue
		end
		local pos = getBoltPosition(child)
		if not pos then
			continue
		end
		if (pos - root.Position).Magnitude > HIT_RADIUS then
			continue
		end
		predicted[child] = true
		spawnLocalBurst(character, pos)
		child.Destroying:Once(function()
			predicted[child] = nil
		end)
	end
end

function PartialShieldClient.init(player: Player)
	local hitEvent = Remotes.getUnreliableEvent("ShieldPartialHit")
	hitEvent.OnClientEvent:Connect(function(character: any, hitFrom: any)
		if typeof(character) ~= "Instance" or not character:IsA("Model") then
			return
		end
		spawnLocalBurst(character, if typeof(hitFrom) == "Vector3" then hitFrom else nil)
	end)

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		if character then
			predictHits(character)
		end
	end)
end

return PartialShieldClient
