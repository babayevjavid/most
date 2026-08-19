--!strict
--[[
	Clones ReplicatedStorage.Assets.ScarletWitch.HandParticle onto both hands once.
	beginUse/endUse enable/disable only (no Emit, no extra clones).
	A stack keeps overlapping abilities from stacking VFX; ending one restores the previous.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local HandParticleHelper = {}

export type HandSide = "Both" | "Right" | "Left"

local ATTACHMENT_NAME = "HandParticle"
local FADE_TIME = 0.35

local ensured: { [Model]: boolean } = {}
local useStack: { [Model]: { HandSide } } = {}
local flyingHands: { [Model]: boolean } = {}
local handOn: { [Model]: { Left: boolean, Right: boolean } } = {}
local savedRates: { [ParticleEmitter]: number } = {}
local fadeConns: { [ParticleEmitter]: RBXScriptConnection } = {}

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

local function getTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local classic = assets and assets:FindFirstChild("ScarletWitchClassic")
	local classicFx = classic and classic:FindFirstChild("HandVFXBasepart")
	if classicFx then
		if classicFx:IsA("Attachment") or classicFx:IsA("BasePart") then
			return classicFx
		end
		local nested = classicFx:FindFirstChildWhichIsA("Attachment", true)
			or classicFx:FindFirstChildWhichIsA("BasePart", true)
		if nested then
			return nested
		end
		return classicFx
	end
	local folder = assets and assets:FindFirstChild("ScarletWitch")
	local template = folder and folder:FindFirstChild("HandParticle")
	if not template then
		return nil
	end
	if template:IsA("Attachment") then
		return template
	end
	local nested = template:FindFirstChildWhichIsA("Attachment", true)
	return nested or template
end

local function stopFade(em: ParticleEmitter)
	local conn = fadeConns[em]
	if conn then
		conn:Disconnect()
		fadeConns[em] = nil
	end
end

local function forEachFxOnHand(character: Model, handName: string, fn: (Instance) -> ())
	local hand = character:FindFirstChild(handName)
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local fx = hand:FindFirstChild(ATTACHMENT_NAME)
	if not fx then
		return
	end
	fn(fx)
	for _, desc in fx:GetDescendants() do
		fn(desc)
	end
end

local function collectEmittersOnHand(character: Model, handName: string): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	forEachFxOnHand(character, handName, function(inst)
		if inst:IsA("ParticleEmitter") then
			table.insert(list, inst)
		end
	end)
	return list
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
		elseif desc:IsA("Sound") then
			desc:Stop()
			desc.Playing = false
		end
	end
	if root:IsA("ParticleEmitter") then
		rememberRate(root)
		root.Enabled = false
	elseif root:IsA("Trail") or root:IsA("Beam") then
		(root :: any).Enabled = false
	elseif root:IsA("Sound") then
		root:Stop()
		root.Playing = false
	end
end

local function setHandFxEnabled(character: Model, handName: string, enabled: boolean, smooth: boolean)
	local emitters = collectEmittersOnHand(character, handName)
	for _, em in emitters do
		rememberRate(em)
		stopFade(em)
		local targetRate = savedRates[em] or 20
		if enabled then
			em.Enabled = true
			em.Rate = targetRate
		else
			if smooth then
				local startRate = em.Rate
				local start = os.clock()
				fadeConns[em] = RunService.Heartbeat:Connect(function()
					if not em.Parent then
						stopFade(em)
						return
					end
					local t = math.min(1, (os.clock() - start) / FADE_TIME)
					em.Rate = startRate * (1 - t)
					if t >= 1 then
						em.Enabled = false
						em.Rate = targetRate
						stopFade(em)
					end
				end)
			else
				em.Enabled = false
				em.Rate = targetRate
			end
		end
	end
	forEachFxOnHand(character, handName, function(inst)
		if inst:IsA("Beam") then
			inst.Enabled = enabled
		elseif inst:IsA("Trail") then
			-- Trails only while flying — handled by setFlightTrails
		end
	end)
end

local function setAllTrails(character: Model, enabled: boolean)
	for _, handName in getHandNames(character) do
		forEachFxOnHand(character, handName, function(inst)
			if inst:IsA("Trail") then
				inst.Enabled = enabled
			end
		end)
	end
end

local function desiredHands(character: Model): (boolean, boolean)
	local stack = useStack[character]
	if stack and #stack > 0 then
		local side = stack[#stack]
		if side == "Both" then
			return true, true
		elseif side == "Right" then
			return false, true
		end
		return true, false
	end
	if flyingHands[character] then
		return true, true
	end
	return false, false
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
		setHandFxEnabled(character, getLeftHandName(character), wantLeft, smoothOff and not wantLeft)
		state.Left = wantLeft
	end
	if wantRight ~= state.Right then
		setHandFxEnabled(character, getRightHandName(character), wantRight, smoothOff and not wantRight)
		state.Right = wantRight
	end
end

--[[ Enable hand trails only during hex flight; disable otherwise. ]]
function HandParticleHelper.setFlightTrails(character: Model, flying: boolean)
	if not character.Parent then
		return
	end
	HandParticleHelper.ensure(character)
	flyingHands[character] = flying == true
	setAllTrails(character, flying == true)
	refreshHands(character, not flying)
end

local function anyActive(character: Model): boolean
	local stack = useStack[character]
	return flyingHands[character] == true or (stack ~= nil and #stack > 0)
end

function HandParticleHelper.ensure(character: Model)
	if not character.Parent then
		return
	end
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
		return
	end
	if ensured[character] then
		for _, handName in getHandNames(character) do
			local hand = character:FindFirstChild(handName)
			if hand then
				local keep = false
				for _, ch in hand:GetChildren() do
					if ch.Name == ATTACHMENT_NAME then
						if keep then
							ch:Destroy()
						else
							keep = true
						end
					end
				end
			end
		end
		if not anyActive(character) then
			for _, handName in getHandNames(character) do
				for _, em in collectEmittersOnHand(character, handName) do
					if em.Enabled then
						em.Enabled = false
					end
				end
				forEachFxOnHand(character, handName, function(inst)
					if inst:IsA("Beam") then
						inst.Enabled = false
					elseif inst:IsA("Trail") then
						-- keep trail state tied to flight only
						local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
						inst.Enabled = flying
					end
				end)
			end
		end
		return
	end

	local template = getTemplate()
	if not template then
		return
	end

	for _, handName in getHandNames(character) do
		local hand = character:FindFirstChild(handName)
		if hand and hand:IsA("BasePart") then
			local keep = false
			for _, ch in hand:GetChildren() do
				if ch.Name == ATTACHMENT_NAME then
					if keep then
						ch:Destroy()
					else
						keep = true
					end
				end
			end
			if not hand:FindFirstChild(ATTACHMENT_NAME) then
				local clone = template:Clone()
				clone.Name = ATTACHMENT_NAME
				if clone:IsA("Attachment") then
					clone.Parent = hand
				elseif clone:IsA("BasePart") then
					clone.Anchored = false
					clone.CanCollide = false
					clone.CanQuery = false
					clone.CanTouch = false
					clone.Massless = true
					clone.CFrame = hand.CFrame
					clone.Parent = hand
					local weld = Instance.new("Weld")
					weld.Name = "HandVfxWeld"
					weld.Part0 = hand
					weld.Part1 = clone
					weld.C0 = CFrame.identity
					weld.Parent = clone
				else
					clone.Parent = hand
				end
				disableAllFx(clone)
			else
				local existing = hand:FindFirstChild(ATTACHMENT_NAME)
				if existing then
					disableAllFx(existing)
				end
			end
		end
	end

	ensured[character] = true
	handOn[character] = { Left = false, Right = false }
	character.Destroying:Once(function()
		ensured[character] = nil
		useStack[character] = nil
		flyingHands[character] = nil
		handOn[character] = nil
	end)
end

--[[ Ability started. side defaults to Both; use "Right" for hex beam. ]]
function HandParticleHelper.beginUse(character: Model, side: HandSide?)
	if not character or not character.Parent then
		return
	end
	HandParticleHelper.ensure(character)
	local stack = useStack[character]
	if not stack then
		stack = {}
		useStack[character] = stack
	end
	table.insert(stack, side or "Both")
	refreshHands(character, false)
end

--[[ Ability ended. Pass the same side used in beginUse. ]]
function HandParticleHelper.endUse(character: Model, side: HandSide?)
	if not character or not character.Parent then
		return
	end
	local stack = useStack[character]
	if not stack then
		refreshHands(character, true)
		return
	end
	local useSide: HandSide = side or "Both"
	for i = #stack, 1, -1 do
		if stack[i] == useSide then
			table.remove(stack, i)
			break
		end
	end
	if #stack == 0 then
		useStack[character] = nil
	end
	refreshHands(character, true)
end

function HandParticleHelper.pulse(character: Model, holdSeconds: number?, side: HandSide?)
	HandParticleHelper.beginUse(character, side)
	local hold = holdSeconds or 0.45
	task.delay(hold, function()
		if character.Parent then
			HandParticleHelper.endUse(character, side)
		end
	end)
end

function HandParticleHelper.clear(character: Model)
	useStack[character] = nil
	flyingHands[character] = nil
	ensured[character] = nil
	handOn[character] = nil
	for _, handName in getHandNames(character) do
		for _, em in collectEmittersOnHand(character, handName) do
			stopFade(em)
			em.Enabled = false
		end
		forEachFxOnHand(character, handName, function(inst)
			if inst:IsA("Beam") then
				inst.Enabled = false
			elseif inst:IsA("Trail") then
				inst.Enabled = false
			end
		end)
	end
end

return HandParticleHelper
