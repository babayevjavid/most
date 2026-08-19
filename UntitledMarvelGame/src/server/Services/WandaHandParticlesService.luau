--!strict
--[[
	Clone Assets.WandaMaximoff.HandParticles onto both hands and toggle while abilities are active.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))
local PlayerStateService = require(script.Parent.PlayerStateService)

local C = AbilityConstants

local ensuredChars: { [Model]: boolean } = {}
local refCountByChar: { [Model]: number } = {}
local savedRates: { [ParticleEmitter]: number } = {}

local WandaHandParticlesService = {}

local function isWandaPlayer(plr: Player): boolean
	return PlayerStateService.get(plr).HeroId == "Wanda"
end

local function isWandaCharacter(char: Model): boolean
	local plr = Players:GetPlayerFromCharacter(char)
	return plr ~= nil and isWandaPlayer(plr)
end

local function getTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local wanda = assets and assets:FindFirstChild("WandaMaximoff")
	return wanda and wanda:FindFirstChild("HandParticles")
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

local function getHandEffectEmitters(char: Model): { ParticleEmitter }
	local emitters: { ParticleEmitter } = {}
	local seen: { [ParticleEmitter]: boolean } = {}
	for _, hand in findBothHands(char) do
		for _, desc in hand:GetDescendants() do
			if desc:IsA("ParticleEmitter") and not seen[desc] then
				seen[desc] = true
				table.insert(emitters, desc)
			end
		end
	end
	return emitters
end

local function setHandParticlesEnabled(char: Model, enabled: boolean, smooth: boolean)
	local emitters = getHandEffectEmitters(char)
	if #emitters == 0 then
		return
	end

	for _, hand in findBothHands(char) do
		for _, desc in hand:GetDescendants() do
			if desc:IsA("Beam") then
				desc.Enabled = enabled
			end
		end
	end

	for _, em in emitters do
		if not savedRates[em] and em.Rate > 0 then
			savedRates[em] = em.Rate
		end
		local targetRate = savedRates[em] or 20
		if enabled then
			em.Enabled = true
			if smooth then
				em.Rate = 0
				local start = os.clock()
				local conn: RBXScriptConnection
				conn = RunService.Heartbeat:Connect(function()
					if not em.Parent then
						conn:Disconnect()
						return
					end
					local t = math.min(1, (os.clock() - start) / C.WANDA_HAND_EFFECT_FADE_TIME)
					em.Rate = t * targetRate
					if t >= 1 then
						conn:Disconnect()
					end
				end)
			else
				em.Rate = targetRate
			end
		elseif smooth then
			local startRate = em.Rate
			local start = os.clock()
			local conn: RBXScriptConnection
			conn = RunService.Heartbeat:Connect(function()
				if not em.Parent then
					conn:Disconnect()
					return
				end
				local t = math.min(1, (os.clock() - start) / C.WANDA_HAND_EFFECT_FADE_TIME)
				em.Rate = startRate * (1 - t)
				if t >= 1 then
					em.Enabled = false
					em.Rate = targetRate
					conn:Disconnect()
				end
			end)
		else
			em.Enabled = false
			em.Rate = targetRate
		end
	end
end

local function shouldKeepHandParticles(char: Model): boolean
	return char:GetAttribute("IsChaosBeamActive") == true
		or char:GetAttribute("IsTelekinesisActive") == true
		or char:GetAttribute("IsShieldActive") == true
		or char:GetAttribute("NewFlightActive") == true
end

function WandaHandParticlesService.ensure(char: Model)
	if not isWandaCharacter(char) then
		return
	end
	if ensuredChars[char] then
		return
	end

	local template = getTemplate()
	if not template then
		warn("[WandaHandParticlesService] Missing Assets.WandaMaximoff.HandParticles")
		return
	end

	for _, hand in findBothHands(char) do
		local keepOne = false
		for _, child in hand:GetChildren() do
			if child.Name == "HandParticles" then
				if keepOne then
					child:Destroy()
				else
					keepOne = true
				end
			end
		end
		if not hand:FindFirstChild("HandParticles") then
			local clone = template:Clone()
			clone.Name = "HandParticles"
			clone.Parent = hand
		end
	end

	ensuredChars[char] = true
	setHandParticlesEnabled(char, false, false)
end

function WandaHandParticlesService.getHandAttachment(handPart: BasePart): Attachment?
	local inst = handPart:FindFirstChild("HandParticles")
	if not inst then
		return nil
	end
	if inst:IsA("Attachment") then
		return inst
	end
	local att = inst:FindFirstChildWhichIsA("Attachment", true)
	if att then
		return att
	end
	return nil
end

function WandaHandParticlesService.enable(char: Model)
	if not isWandaCharacter(char) then
		return
	end
	WandaHandParticlesService.ensure(char)
	refCountByChar[char] = (refCountByChar[char] or 0) + 1
	if refCountByChar[char] == 1 then
		setHandParticlesEnabled(char, true, true)
	end
end

function WandaHandParticlesService.disable(char: Model)
	if not isWandaCharacter(char) then
		return
	end
	local count = refCountByChar[char]
	if not count or count <= 0 then
		return
	end
	refCountByChar[char] = count - 1
	if refCountByChar[char] == 0 then
		refCountByChar[char] = nil
		if shouldKeepHandParticles(char) then
			return
		end
		setHandParticlesEnabled(char, false, true)
	end
end

function WandaHandParticlesService.emit(char: Model, count: number?)
	if not isWandaCharacter(char) then
		return
	end
	WandaHandParticlesService.ensure(char)
	local n = count or C.WANDA_HAND_EMIT_ON_POWER_USE
	for _, em in getHandEffectEmitters(char) do
		pcall(function()
			em:Emit(n)
		end)
	end
end

function WandaHandParticlesService.onInstantAbility(char: Model)
	if not isWandaCharacter(char) then
		return
	end
	WandaHandParticlesService.enable(char)
	WandaHandParticlesService.emit(char)
	task.delay(C.WANDA_HAND_INSTANT_ABILITY_DURATION, function()
		if char.Parent then
			WandaHandParticlesService.disable(char)
		end
	end)
end

function WandaHandParticlesService.cleanupCharacter(char: Model)
	ensuredChars[char] = nil
	refCountByChar[char] = nil
	setHandParticlesEnabled(char, false, false)
end

function WandaHandParticlesService.cleanupPlayer(player: Player)
	local char = player.Character
	if char then
		WandaHandParticlesService.cleanupCharacter(char)
	end
end

return WandaHandParticlesService
