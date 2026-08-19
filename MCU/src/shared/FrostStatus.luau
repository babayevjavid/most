--!strict
--[[
	Iceman Chill / Freeze status.

	Chill (0-100) stacks from every ice hit and slows the victim. A full bar
	freezes them solid: locked in place, powers disabled, encased in a block.
	Thawing clears the stacks and grants a short immunity window.

	FrostStatus.update(dt) must be pumped once per frame (IcemanService does it).
	Visuals: Assets.IceMan.Ice shells welded to each body part, revealed feet→head.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local FrostStatus = {}

type ChillEntry = {
	chill: number,
	lastAddAt: number,
	baseWalk: number?,
	lastAppliedWalk: number?,
	shownChill: number?,
	baseJumpPower: number?,
	baseJumpHeight: number?,
	baseAutoRotate: boolean?,
	baseAnchored: boolean?,
	frozenUntil: number?,
	powerLockUntil: number?,
	immuneUntil: number,
	shells: { BasePart }?,
}

local byModel: { [Model]: ChillEntry } = {}

local function getRoot(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return model.PrimaryPart
end

local function isValidTarget(model: Model?): boolean
	if not model or not model.Parent then
		return false
	end
	local hum = CombatHelper.getHumanoid(model)
	if not hum or hum.Health <= 0 then
		return false
	end
	-- Illusions / astral copies are not real bodies
	if model:GetAttribute("LokiUltClone") == true or model:GetAttribute("LokiDecoy") == true then
		return false
	end
	if model:GetAttribute("FearVisual") == true or model.Name == "FearClone" then
		return false
	end
	if model:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return false
	end
	return true
end

--[[ Iceman shrugs off his own element (Sub-Zero Body passive). ]]
function FrostStatus.isImmune(model: Model): boolean
	if model:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "iceman" then
		return true
	end
	local entry = byModel[model]
	if entry and AbilityCooldownHelper.getNow() < entry.immuneUntil then
		return true
	end
	return false
end

function FrostStatus.getChill(model: Model): number
	local entry = byModel[model]
	if not entry then
		return 0
	end
	return entry.chill
end

function FrostStatus.isFrozen(model: Model): boolean
	return model:GetAttribute(GameConstants.ICE_FROZEN_ATTRIBUTE) == true
end

local function ensureEntry(model: Model): ChillEntry
	local entry = byModel[model]
	if entry then
		return entry
	end
	entry = {
		chill = 0,
		lastAddAt = AbilityCooldownHelper.getNow(),
		immuneUntil = 0,
	}
	byModel[model] = entry
	return entry
end

--[[
	Slow off whatever speed the rest of the game wants right now: if another
	system (sprint, Ice Slide, Purify) moved WalkSpeed since our last write,
	that becomes the new base instead of compounding the slow.
]]
local function applySlow(model: Model, entry: ChillEntry)
	local hum = CombatHelper.getHumanoid(model)
	if not hum then
		return
	end
	local applied = entry.lastAppliedWalk
	if entry.baseWalk == nil or applied == nil or math.abs(hum.WalkSpeed - applied) > 0.01 then
		entry.baseWalk = hum.WalkSpeed
	end
	local ratio = math.clamp(entry.chill / GameConstants.ICE_CHILL_MAX, 0, 1)
	local base = entry.baseWalk :: number
	hum.WalkSpeed = base * (1 - GameConstants.ICE_CHILL_SLOW_MAX * ratio)
	entry.lastAppliedWalk = hum.WalkSpeed
end

local function restoreSlow(model: Model, entry: ChillEntry)
	local hum = CombatHelper.getHumanoid(model)
	if hum and hum.Parent and entry.baseWalk ~= nil then
		hum.WalkSpeed = entry.baseWalk :: number
	end
	entry.baseWalk = nil
	entry.lastAppliedWalk = nil
end

--[[ Replicate Chill as a whole number so we're not writing an attribute every frame. ]]
local function publishChill(model: Model, entry: ChillEntry)
	local shown = if entry.chill > 0 then math.floor(entry.chill + 0.5) else 0
	if entry.shownChill == shown then
		return
	end
	entry.shownChill = shown
	model:SetAttribute(GameConstants.ICE_CHILL_ATTRIBUTE, if shown > 0 then shown else nil)
end

--[[ Direct children only — R15/R6 body MeshParts, not accessory Handles. ]]
local function getBodyParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			table.insert(parts, child)
		end
	end
	return parts
end

local function getIceTemplate(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("IceMan")
	local ice = folder and folder:FindFirstChild("Ice")
	if ice and ice:IsA("BasePart") then
		return ice
	end
	return nil
end

--[[
	One Ice shell per body part, welded on, revealed feet→head.
	Uses Assets.IceMan.Ice when present; falls back to a plain ice part.
]]
local function spawnFreezeShells(model: Model): { BasePart }
	local template = getIceTemplate()
	local parts = getBodyParts(model)
	if #parts == 0 then
		return {}
	end

	local minY = math.huge
	local maxY = -math.huge
	for _, part in parts do
		minY = math.min(minY, part.Position.Y)
		maxY = math.max(maxY, part.Position.Y)
	end
	local span = math.max(0.05, maxY - minY)
	local cascade = GameConstants.ICE_FREEZE_CASCADE

	local shells: { BasePart } = {}
	for _, part in parts do
		local shell: BasePart
		if template then
			shell = template:Clone()
		else
			local fallback = Instance.new("Part")
			fallback.Material = Enum.Material.Ice
			fallback.Color = GameConstants.ICE_COLOR
			shell = fallback
		end
		shell.Name = "IceFreezeShell"
		shell.Size = part.Size * GameConstants.ICE_FREEZE_SHELL_SCALE
		shell.CFrame = part.CFrame
		shell.Anchored = false
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.Massless = true
		shell.CastShadow = false
		shell.Color = GameConstants.ICE_COLOR
		local targetTransparency = if shell.Transparency < 0.99 then shell.Transparency else 0.2
		shell.Transparency = 1
		shell.Parent = Workspace

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = shell
		weld.Parent = shell

		local delaySec = ((part.Position.Y - minY) / span) * cascade
		task.delay(delaySec, function()
			if not shell.Parent then
				return
			end
			TweenService:Create(
				shell,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = targetTransparency }
			):Play()
		end)
		table.insert(shells, shell)
	end
	return shells
end

local function detachShells(shells: { BasePart })
	for _, shell in shells do
		if not shell.Parent then
			continue
		end
		for _, child in shell:GetChildren() do
			if child:IsA("WeldConstraint") or child:IsA("Weld") or child:IsA("Motor6D") then
				child:Destroy()
			end
		end
		shell.Anchored = false
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.Massless = false
	end
end

--[[ Shatter FX: ice pieces fly randomly up, then drop and fade (no collision). ]]
function FrostStatus.flingShells(shells: { BasePart })
	detachShells(shells)
	local up = GameConstants.ICE_SHATTER_ICE_UP
	local spread = GameConstants.ICE_SHATTER_ICE_SPREAD
	local fade = GameConstants.ICE_SHATTER_ICE_FADE
	local life = GameConstants.ICE_SHATTER_ICE_LIFE
	for _, shell in shells do
		if not shell.Parent then
			continue
		end
		local vx = (math.random() - 0.5) * 2 * spread
		local vz = (math.random() - 0.5) * 2 * spread
		local vy = up * (0.65 + math.random() * 0.55)
		shell.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
		shell.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 14,
			(math.random() - 0.5) * 14,
			(math.random() - 0.5) * 14
		)
		task.delay(life * 0.35, function()
			if not shell.Parent then
				return
			end
			TweenService:Create(shell, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		end)
		task.delay(life + fade, function()
			if shell.Parent then
				shell:Destroy()
			end
		end)
	end
end

local function retireFreezeShells(shells: { BasePart }?)
	if not shells then
		return
	end
	for _, shell in shells do
		if shell.Parent then
			TweenService:Create(shell, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
			task.delay(0.55, function()
				if shell.Parent then
					shell:Destroy()
				end
			end)
		end
	end
end

function FrostStatus.getBodyParts(model: Model): { BasePart }
	return getBodyParts(model)
end

local function lockFrozen(model: Model, entry: ChillEntry, allowMotion: boolean?)
	local hum = CombatHelper.getHumanoid(model)
	local root = getRoot(model)
	if hum then
		if entry.baseWalk == nil then
			entry.baseWalk = hum.WalkSpeed
		end
		entry.baseAutoRotate = hum.AutoRotate
		if hum.UseJumpPower then
			entry.baseJumpPower = hum.JumpPower
			hum.JumpPower = 0
		else
			entry.baseJumpHeight = hum.JumpHeight
			hum.JumpHeight = 0
		end
		hum.WalkSpeed = 0
		hum.AutoRotate = false
		hum:Move(Vector3.zero, false)
	end
	if root and not allowMotion then
		entry.baseAnchored = root.Anchored
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
	end
end

local function unlockFrozen(model: Model, entry: ChillEntry)
	local hum = CombatHelper.getHumanoid(model)
	local root = getRoot(model)
	if hum and hum.Parent then
		if entry.baseAutoRotate ~= nil then
			hum.AutoRotate = entry.baseAutoRotate
		end
		if entry.baseJumpPower ~= nil then
			hum.JumpPower = entry.baseJumpPower
		end
		if entry.baseJumpHeight ~= nil then
			hum.JumpHeight = entry.baseJumpHeight
		end
	end
	if root and root.Parent and entry.baseAnchored ~= nil then
		root.Anchored = entry.baseAnchored
	end
	entry.baseAutoRotate = nil
	entry.baseJumpPower = nil
	entry.baseJumpHeight = nil
	entry.baseAnchored = nil
end

local function thaw(model: Model, entry: ChillEntry)
	unlockFrozen(model, entry)
	retireFreezeShells(entry.shells)
	entry.shells = nil
	entry.frozenUntil = nil
	entry.chill = 0
	entry.immuneUntil = AbilityCooldownHelper.getNow() + GameConstants.ICE_FREEZE_IMMUNE_TIME
	restoreSlow(model, entry)
	if model.Parent then
		model:SetAttribute(GameConstants.ICE_FROZEN_ATTRIBUTE, nil)
		publishChill(model, entry)
		-- Only lift the power lock we set; leave Fear / other locks alone
		if model:GetAttribute(GameConstants.POWERS_DISABLED_UNTIL) == entry.powerLockUntil then
			model:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
		end
	end
	entry.powerLockUntil = nil
end

export type FreezeOptions = {
	-- Keep root free to move (for Flash Freeze shove while ice climbs)
	allowMotion: boolean?,
}

--[[ Freeze solid regardless of current Chill (Flash Freeze / full bar). ]]
function FrostStatus.freeze(model: Model, duration: number?, options: FreezeOptions?): boolean
	if not isValidTarget(model) or FrostStatus.isImmune(model) then
		return false
	end
	if FrostStatus.isFrozen(model) then
		return false
	end
	local root = getRoot(model)
	if root and root.Anchored then
		-- Already held by another ability (slam / astral body) — don't fight it
		return false
	end

	local entry = ensureEntry(model)
	local dur = duration or GameConstants.ICE_FREEZE_DURATION
	local allowMotion = options ~= nil and options.allowMotion == true
	entry.chill = GameConstants.ICE_CHILL_MAX
	entry.frozenUntil = AbilityCooldownHelper.getNow() + dur
	entry.powerLockUntil = entry.frozenUntil
	lockFrozen(model, entry, allowMotion)
	entry.shells = spawnFreezeShells(model)

	model:SetAttribute(GameConstants.ICE_FROZEN_ATTRIBUTE, true)
	publishChill(model, entry)
	-- Keep a longer existing lock (Fear) instead of shortening it
	local existingLock = model:GetAttribute(GameConstants.POWERS_DISABLED_UNTIL)
	if type(existingLock) ~= "number" or existingLock < entry.frozenUntil then
		model:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, entry.frozenUntil)
	end
	return true
end

--[[ Anchor a soft (motion-allowed) freeze once the shove is done. ]]
function FrostStatus.seal(model: Model)
	if not FrostStatus.isFrozen(model) then
		return
	end
	local entry = byModel[model]
	local root = getRoot(model)
	if not entry or not root or not root.Parent then
		return
	end
	if entry.baseAnchored == nil then
		entry.baseAnchored = root.Anchored
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	local hum = CombatHelper.getHumanoid(model)
	if hum then
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero, false)
	end
end

function FrostStatus.addChill(model: Model, amount: number): number
	if amount <= 0 or not isValidTarget(model) or FrostStatus.isImmune(model) then
		return 0
	end
	if CombatHelper.isShielded(model) then
		-- Shields / barriers keep the cold out entirely
		return 0
	end
	if FrostStatus.isFrozen(model) then
		return GameConstants.ICE_CHILL_MAX
	end

	local entry = ensureEntry(model)
	entry.chill = math.clamp(entry.chill + amount, 0, GameConstants.ICE_CHILL_MAX)
	entry.lastAddAt = AbilityCooldownHelper.getNow()
	publishChill(model, entry)

	if entry.chill >= GameConstants.ICE_CHILL_MAX then
		FrostStatus.freeze(model, GameConstants.ICE_FREEZE_DURATION)
	else
		applySlow(model, entry)
	end
	return entry.chill
end

--[[ Shatter: take all stacks off the target and return any ice shells for FX. ]]
function FrostStatus.consumeChill(model: Model): (number, boolean, { BasePart })
	local entry = byModel[model]
	if not entry then
		return 0, false, {}
	end
	local amount = entry.chill
	local wasFrozen = FrostStatus.isFrozen(model)
	local shells = entry.shells or {}
	entry.shells = nil
	if wasFrozen then
		thaw(model, entry)
	else
		entry.chill = 0
		restoreSlow(model, entry)
		if model.Parent then
			publishChill(model, entry)
		end
	end
	return amount, wasFrozen, shells
end

--[[ Full cleanse (death / Purify / respawn). ]]
function FrostStatus.clear(model: Model)
	local entry = byModel[model]
	if not entry then
		if model.Parent then
			model:SetAttribute(GameConstants.ICE_CHILL_ATTRIBUTE, nil)
			model:SetAttribute(GameConstants.ICE_FROZEN_ATTRIBUTE, nil)
		end
		return
	end
	byModel[model] = nil
	unlockFrozen(model, entry)
	retireFreezeShells(entry.shells)
	restoreSlow(model, entry)
	if model.Parent then
		model:SetAttribute(GameConstants.ICE_CHILL_ATTRIBUTE, nil)
		model:SetAttribute(GameConstants.ICE_FROZEN_ATTRIBUTE, nil)
		-- Only lift the power lock the freeze itself set
		local lock = entry.powerLockUntil
		if lock and model:GetAttribute(GameConstants.POWERS_DISABLED_UNTIL) == lock then
			model:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
		end
	end
end

function FrostStatus.update(dt: number)
	local now = AbilityCooldownHelper.getNow()
	local dtClamped = math.clamp(dt, 0.001, 0.2)

	for model, entry in byModel do
		if not isValidTarget(model) then
			unlockFrozen(model, entry)
			retireFreezeShells(entry.shells)
			restoreSlow(model, entry)
			byModel[model] = nil
			continue
		end

		if entry.frozenUntil then
			if now >= entry.frozenUntil then
				thaw(model, entry)
			else
				local hum = CombatHelper.getHumanoid(model)
				if hum then
					hum.WalkSpeed = 0
					hum:Move(Vector3.zero, false)
				end
			end
			continue
		end

		if entry.chill <= 0 then
			if now >= entry.immuneUntil then
				restoreSlow(model, entry)
				byModel[model] = nil
			end
			continue
		end

		if now - entry.lastAddAt >= GameConstants.ICE_CHILL_DECAY_GRACE then
			entry.chill = math.max(0, entry.chill - GameConstants.ICE_CHILL_DECAY_PER_SEC * dtClamped)
			publishChill(model, entry)
		end

		if entry.chill > 0 then
			applySlow(model, entry)
		else
			restoreSlow(model, entry)
		end
	end
end

function FrostStatus.clearForPlayer(player: Player)
	local character = player.Character
	if character then
		FrostStatus.clear(character)
	end
end

Players.PlayerRemoving:Connect(function(player)
	FrostStatus.clearForPlayer(player)
end)

return FrostStatus
