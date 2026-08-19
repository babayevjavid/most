--!strict
--[[
	Captain Marvel VFX:
	- HandParticleAttachment → both hands (powers)
	- TrailAttachment → HumanoidRootPart (flight trails)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local PhotonParticleHelper = {}

export type HandSide = "Both" | "Right" | "Left"

local HAND_NAME = "CM_HandParticle"
local TRAIL_NAME = "CM_TrailAttachment"
local EMIT_ON_USE = 7
local FADE_TIME = 0.35

local ensured: { [Model]: boolean } = {}
local bothCount: { [Model]: number } = {}
local rightCount: { [Model]: number } = {}
local leftCount: { [Model]: number } = {}
local handOn: { [Model]: { Left: boolean, Right: boolean } } = {}
local savedRates: { [ParticleEmitter]: number } = {}
local fadeConns: { [ParticleEmitter]: RBXScriptConnection } = {}

local function getAssetsFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("CaptainMarvel")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function resolveAttachmentTemplate(name: string): Instance?
	local folder = getAssetsFolder()
	if not folder then
		return nil
	end
	local template = folder:FindFirstChild(name)
	if not template then
		return nil
	end
	if template:IsA("Attachment") then
		return template
	end
	local nested = template:FindFirstChildWhichIsA("Attachment", true)
	return nested or template
end

local function getRightHandName(character: Model): string
	if character:FindFirstChild("RightHand") then
		return "RightHand"
	end
	return "Right Arm"
end

local function getLeftHandName(character: Model): string
	if character:FindFirstChild("LeftHand") then
		return "LeftHand"
	end
	return "Left Arm"
end

local function getHandNames(character: Model): { string }
	return { getLeftHandName(character), getRightHandName(character) }
end

local function getTrailParent(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return nil
end

local function stopFade(em: ParticleEmitter)
	local conn = fadeConns[em]
	if conn then
		conn:Disconnect()
		fadeConns[em] = nil
	end
end

local function rememberRate(em: ParticleEmitter)
	if savedRates[em] == nil and em.Rate > 0 then
		savedRates[em] = em.Rate
	elseif savedRates[em] == nil then
		savedRates[em] = 20
	end
end

local function disableAllFx(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			rememberRate(desc)
			desc.Enabled = false
		elseif desc:IsA("Trail") or desc:IsA("Beam") then
			(desc :: any).Enabled = false
		end
	end
	if root:IsA("ParticleEmitter") then
		rememberRate(root)
		root.Enabled = false
	elseif root:IsA("Trail") or root:IsA("Beam") then
		(root :: any).Enabled = false
	end
end

local function forEachFx(root: Instance, fn: (Instance) -> ())
	fn(root)
	for _, desc in root:GetDescendants() do
		fn(desc)
	end
end

local function collectEmitters(root: Instance): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	forEachFx(root, function(inst)
		if inst:IsA("ParticleEmitter") then
			table.insert(list, inst)
		end
	end)
	return list
end

local function setFxEnabled(root: Instance, enabled: boolean, smooth: boolean, doEmit: boolean)
	local emitters = collectEmitters(root)
	for _, em in emitters do
		stopFade(em)
		rememberRate(em)
		if enabled then
			em.Rate = savedRates[em] or 20
			em.Enabled = true
			if doEmit then
				em:Emit(EMIT_ON_USE)
			end
		elseif smooth then
			local startRate = em.Rate
			local t0 = os.clock()
			fadeConns[em] = RunService.Heartbeat:Connect(function()
				local alpha = math.clamp((os.clock() - t0) / FADE_TIME, 0, 1)
				em.Rate = startRate * (1 - alpha)
				if alpha >= 1 then
					stopFade(em)
					em.Enabled = false
					em.Rate = savedRates[em] or 20
				end
			end)
		else
			em.Enabled = false
		end
	end

	forEachFx(root, function(inst)
		if inst:IsA("Trail") or inst:IsA("Beam") then
			(inst :: any).Enabled = enabled
		end
	end)
end

local function forEachHandAtt(character: Model, handName: string, fn: (Instance) -> ())
	local hand = character:FindFirstChild(handName)
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local att = hand:FindFirstChild(HAND_NAME)
	if not att then
		return
	end
	fn(att)
end

local function desiredHands(character: Model): (boolean, boolean)
	if (bothCount[character] or 0) > 0 then
		return true, true
	end
	return (leftCount[character] or 0) > 0, (rightCount[character] or 0) > 0
end

local function refreshHands(character: Model, smoothOff: boolean)
	if not character.Parent then
		return
	end
	local wantLeft, wantRight = desiredHands(character)
	local state = handOn[character]
	if not state then
		state = { Left = false, Right = false }
		handOn[character] = state
	end

	if wantLeft ~= state.Left then
		forEachHandAtt(character, getLeftHandName(character), function(att)
			setFxEnabled(att, wantLeft, smoothOff and not wantLeft, wantLeft)
		end)
		state.Left = wantLeft
	end
	if wantRight ~= state.Right then
		forEachHandAtt(character, getRightHandName(character), function(att)
			setFxEnabled(att, wantRight, smoothOff and not wantRight, wantRight)
		end)
		state.Right = wantRight
	end
end

local function anyActive(character: Model): boolean
	return (bothCount[character] or 0) > 0
		or (rightCount[character] or 0) > 0
		or (leftCount[character] or 0) > 0
end

function PhotonParticleHelper.ensure(character: Model)
	if not character.Parent then
		return
	end
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return
	end
	if ensured[character] then
		if not anyActive(character) then
			for _, handName in getHandNames(character) do
				forEachHandAtt(character, handName, function(att)
					for _, em in collectEmitters(att) do
						if em.Enabled then
							em.Enabled = false
						end
					end
					forEachFx(att, function(inst)
						if inst:IsA("Beam") or inst:IsA("Trail") then
							inst.Enabled = false
						end
					end)
				end)
			end
			local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			local trailParent = getTrailParent(character)
			local trail = trailParent and trailParent:FindFirstChild(TRAIL_NAME)
			if trail then
				forEachFx(trail, function(inst)
					if inst:IsA("Trail") or inst:IsA("Beam") then
						inst.Enabled = flying
					elseif inst:IsA("ParticleEmitter") and not flying then
						inst.Enabled = false
					end
				end)
			end
		end
		return
	end

	local handTemplate = resolveAttachmentTemplate("HandParticleAttachment")
	if handTemplate then
		for _, handName in getHandNames(character) do
			local hand = character:FindFirstChild(handName)
			if hand and hand:IsA("BasePart") then
				local existing = hand:FindFirstChild(HAND_NAME)
				if not existing then
					local clone = handTemplate:Clone()
					clone.Name = HAND_NAME
					clone.Parent = hand
					disableAllFx(clone)
				else
					disableAllFx(existing)
				end
			end
		end
	end

	local trailTemplate = resolveAttachmentTemplate("TrailAttachment")
	local trailParent = getTrailParent(character)
	if trailTemplate and trailParent then
		local existing = trailParent:FindFirstChild(TRAIL_NAME)
		if not existing then
			local clone = trailTemplate:Clone()
			clone.Name = TRAIL_NAME
			clone.Parent = trailParent
			disableAllFx(clone)
		else
			disableAllFx(existing)
		end
	end

	ensured[character] = true
	handOn[character] = { Left = false, Right = false }
	character.Destroying:Once(function()
		ensured[character] = nil
		bothCount[character] = nil
		rightCount[character] = nil
		leftCount[character] = nil
		handOn[character] = nil
	end)
end

function PhotonParticleHelper.setFlightTrails(character: Model, flying: boolean)
	if not character.Parent then
		return
	end
	PhotonParticleHelper.ensure(character)
	local trailParent = getTrailParent(character)
	local trail = trailParent and trailParent:FindFirstChild(TRAIL_NAME)
	if not trail then
		return
	end
	local on = flying == true
	forEachFx(trail, function(inst)
		if inst:IsA("Trail") or inst:IsA("Beam") then
			inst.Enabled = on
		elseif inst:IsA("ParticleEmitter") then
			rememberRate(inst)
			inst.Enabled = on
			if on then
				inst.Rate = savedRates[inst] or 20
			end
		end
	end)
end

function PhotonParticleHelper.beginUse(character: Model, side: HandSide?)
	if not character.Parent then
		return
	end
	PhotonParticleHelper.ensure(character)

	local useSide: HandSide = side or "Both"
	if useSide == "Both" then
		bothCount[character] = (bothCount[character] or 0) + 1
	elseif useSide == "Right" then
		rightCount[character] = (rightCount[character] or 0) + 1
	else
		leftCount[character] = (leftCount[character] or 0) + 1
	end
	refreshHands(character, false)
end

function PhotonParticleHelper.endUse(character: Model, side: HandSide?)
	if not character.Parent then
		return
	end
	local useSide: HandSide = side or "Both"
	if useSide == "Both" then
		local n = bothCount[character]
		if type(n) ~= "number" or n <= 0 then
			return
		end
		n -= 1
		bothCount[character] = if n > 0 then n else nil
	elseif useSide == "Right" then
		local n = rightCount[character]
		if type(n) ~= "number" or n <= 0 then
			return
		end
		n -= 1
		rightCount[character] = if n > 0 then n else nil
	else
		local n = leftCount[character]
		if type(n) ~= "number" or n <= 0 then
			return
		end
		n -= 1
		leftCount[character] = if n > 0 then n else nil
	end
	refreshHands(character, true)
end

function PhotonParticleHelper.clear(character: Model)
	bothCount[character] = nil
	rightCount[character] = nil
	leftCount[character] = nil
	ensured[character] = nil
	handOn[character] = nil
	for _, handName in getHandNames(character) do
		forEachHandAtt(character, handName, function(att)
			for _, em in collectEmitters(att) do
				stopFade(em)
				em.Enabled = false
			end
			disableAllFx(att)
		end)
	end
	local trailParent = getTrailParent(character)
	local trail = trailParent and trailParent:FindFirstChild(TRAIL_NAME)
	if trail then
		disableAllFx(trail)
	end
end

return PhotonParticleHelper
