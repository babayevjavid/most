--!strict
--[[
	Beam clash:
	- Start at 3 / first to 10; each hit +1 self and -1 opponent
	- Win: soft push + 25 damage; miss respawns mark; >30s both lose
	- BeamChar testing auto-score +1/sec; flying range >70 smoothly retracts
	- Workspace.BeamChar uses real Scarlet Witch beam FX + tip damage
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local BeamClashService = {}

export type BeamSegment = {
	id: string,
	kind: "player" | "dummy",
	player: Player?,
	character: Model?,
	origin: Vector3,
	tip: Vector3,
	label: string,
}

type ClashSide = {
	id: string,
	kind: "player" | "dummy",
	player: Player?,
	character: Model?,
	label: string,
}

type PromptState = {
	id: string,
	forSideId: string,
	expiresAt: number,
}

type LockState = {
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
	att: Attachment,
	alignOri: AlignOrientation,
	alignPos: AlignPosition,
	holdPos: Vector3,
}

type ClashState = {
	id: string,
	a: ClashSide,
	b: ClashSide,
	scoreA: number,
	scoreB: number,
	startedAt: number,
	clashPoint: Vector3,
	displayClashPoint: Vector3, -- smoothed for non-AI beam feel
	resolved: boolean,
	prompt: PromptState?,
	pendingPrompt: boolean,
	promptTurn: number,
	lastBeamCharScoreAt: number,
	retracting: boolean,
	retractStartedAt: number,
	retractFromA: Vector3,
	retractFromB: Vector3,
}

local clashById: { [string]: ClashState } = {}
local lockoutUntil: { [string]: number } = {}
local lockByCharacter: { [Model]: LockState } = {}
local forcedTipByCharacter: { [Model]: Vector3 } = {}
local beamEvent: RemoteEvent? = nil

-- Workspace.BeamChar (real hex beam)
local beamCharModel: Model? = nil
local beamCharHand: BasePart? = nil
local beamCharHrp: BasePart? = nil
local beamCharTip: BasePart? = nil
local beamCharBeam: Beam? = nil
local beamCharStartAtt: Attachment? = nil
local beamCharEndAtt: Attachment? = nil
local beamCharLastHit = 0

local segmentProviders: { () -> { BeamSegment } } = {}

local function now(): number
	return os.clock()
end

local function sideKey(side: ClashSide): string
	if side.kind == "player" and side.player then
		return "p:" .. tostring(side.player.UserId)
	end
	return "d:" .. side.id
end

local function isLockedOut(side: ClashSide): boolean
	local untilT = lockoutUntil[sideKey(side)]
	return type(untilT) == "number" and now() < untilT
end

local function setClashFlag(character: Model?, active: boolean, clashId: string?, opponentName: string?)
	if not character then
		return
	end
	character:SetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE, if active then true else nil)
	character:SetAttribute("BeamClashId", if active and clashId then clashId else nil)
	character:SetAttribute("BeamClashOpponent", if active and opponentName then opponentName else nil)
end

local function fireClash(player: Player, payload: { [string]: any })
	local ev = beamEvent
	if ev then
		ev:FireClient(player, payload)
	end
end

local function findRoot(model: Model?): BasePart?
	if not model then
		return nil
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return model.PrimaryPart
end

local function getHandOrRoot(model: Model): BasePart?
	for _, name in { "RightHand", "Right Arm", "RightLowerArm", "HumanoidRootPart" } do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return findRoot(model)
end

local function cloneScarletAttachment(assetName: string): Attachment?
	local template = VfxHelper.getScarletAsset(assetName)
	if not template then
		return nil
	end
	if template:IsA("Attachment") then
		return template:Clone()
	end
	local nested = template:FindFirstChildWhichIsA("Attachment", true)
	if nested then
		return nested:Clone()
	end
	return nil
end

local function distPointToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local denom = ab:Dot(ab)
	if denom < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / denom, 0, 1)
	return (a + ab * t - p).Magnitude
end

local function segmentsClash(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, threshold: number): (boolean, Vector3?)
	local bestDist = threshold + 1
	local bestPoint: Vector3? = nil
	local samples = 10
	for i = 0, samples do
		local t = i / samples
		local p = a0:Lerp(a1, t)
		local d = distPointToSegment(p, b0, b1)
		if d < bestDist then
			bestDist = d
			bestPoint = p
		end
	end
	for i = 0, samples do
		local t = i / samples
		local p = b0:Lerp(b1, t)
		local d = distPointToSegment(p, a0, a1)
		if d < bestDist then
			bestDist = d
			bestPoint = p
		end
	end
	if bestDist <= threshold and bestPoint then
		return true, bestPoint
	end
	return false, nil
end

function BeamClashService.registerSegmentProvider(provider: () -> { BeamSegment })
	table.insert(segmentProviders, provider)
end

function BeamClashService.isCharacterClashing(character: Model): boolean
	return character:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true
end

function BeamClashService.shouldKeepBeamAlive(character: Model): boolean
	-- Keep beam during active clash AND while tips retract after range break
	return character:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true
		or forcedTipByCharacter[character] ~= nil
end

function BeamClashService.getForcedBeamTip(character: Model): Vector3?
	return forcedTipByCharacter[character]
end

local function unlockCharacter(character: Model?, keepForcedTip: boolean?)
	if not character then
		return
	end
	if not keepForcedTip then
		forcedTipByCharacter[character] = nil
	end
	local lock = lockByCharacter[character]
	if not lock then
		return
	end
	lockByCharacter[character] = nil
	if lock.alignOri.Parent then
		lock.alignOri:Destroy()
	end
	if lock.alignPos.Parent then
		lock.alignPos:Destroy()
	end
	if lock.att.Parent then
		lock.att:Destroy()
	end
	local hum = CombatHelper.getHumanoid(character)
	if hum and hum.Health > 0 then
		hum.WalkSpeed = lock.walk
		hum.AutoRotate = lock.autoRotate
		if lock.jumpPower ~= nil then
			hum.JumpPower = lock.jumpPower
		end
		if lock.jumpHeight ~= nil then
			hum.JumpHeight = lock.jumpHeight
		end
	end
end

local function lockCharacter(character: Model?, faceTarget: Vector3)
	if not character then
		return
	end
	unlockCharacter(character)
	local root = findRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum then
		return
	end

	local att = Instance.new("Attachment")
	att.Name = "BeamClashLockAtt"
	att.Parent = root

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "BeamClashFace"
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = att
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque = 200000
	alignOri.Responsiveness = 18
	local flat = Vector3.new(faceTarget.X, root.Position.Y, faceTarget.Z)
	if (flat - root.Position).Magnitude > 0.05 then
		alignOri.CFrame = CFrame.lookAt(root.Position, flat)
	else
		alignOri.CFrame = root.CFrame
	end
	alignOri.Parent = root

	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "BeamClashHold"
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = att
	alignPos.Position = root.Position
	alignPos.MaxForce = 200000
	alignPos.Responsiveness = 20
	alignPos.Parent = root

	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	if hum.UseJumpPower then
		jumpPower = hum.JumpPower
		hum.JumpPower = 0
	else
		jumpHeight = hum.JumpHeight
		hum.JumpHeight = 0
	end

	lockByCharacter[character] = {
		walk = hum.WalkSpeed,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		autoRotate = hum.AutoRotate,
		att = att,
		alignOri = alignOri,
		alignPos = alignPos,
		holdPos = root.Position,
	}
	hum.WalkSpeed = 0
	hum.AutoRotate = false
end

local function updateLockFacing(character: Model?, faceTarget: Vector3)
	if not character then
		return
	end
	local lock = lockByCharacter[character]
	local root = findRoot(character)
	if not lock or not root then
		return
	end
	local flat = Vector3.new(faceTarget.X, root.Position.Y, faceTarget.Z)
	if (flat - root.Position).Magnitude > 0.05 then
		lock.alignOri.CFrame = CFrame.lookAt(root.Position, flat)
	end
	lock.alignPos.Position = lock.holdPos
	local hum = CombatHelper.getHumanoid(character)
	if hum then
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero, false)
	end
end

local function computeClashPoint(clash: ClashState): Vector3
	local rootA = findRoot(clash.a.character)
	local rootB = findRoot(clash.b.character)
	local posA = if rootA then rootA.Position else clash.clashPoint
	local posB = if rootB then rootB.Position else clash.clashPoint
	local need = math.max(1, GameConstants.BEAM_CLASH_PROMPTS_TO_WIN)
	local start = GameConstants.BEAM_CLASH_START_SCORE
	-- Normalize around starting scores so beam push feels human, not robotic
	local advantage = (clash.scoreA - clash.scoreB) / need
	local alpha = math.clamp(0.5 + advantage * 0.42, 0.18, 0.82)
	return posA:Lerp(posB, alpha)
end

local function applyForcedTips(clash: ClashState)
	local target = computeClashPoint(clash)
	clash.clashPoint = target
	-- Smooth lerp so beams don't snap like AI
	clash.displayClashPoint = clash.displayClashPoint:Lerp(target, 0.18)
	local point = clash.displayClashPoint
	if clash.a.character then
		forcedTipByCharacter[clash.a.character] = point
	end
	if clash.b.character then
		forcedTipByCharacter[clash.b.character] = point
	end
	if beamCharTip and ((clash.a.id == "beam_char") or (clash.b.id == "beam_char")) then
		local origin = if beamCharHand then beamCharHand.Position else point
		if (origin - point).Magnitude > 0.05 then
			beamCharTip.CFrame = CFrame.lookAt(point, origin)
		else
			beamCharTip.CFrame = CFrame.new(point)
		end
	end
end

local function releasePlayerBeams(side: ClashSide)
	if not side.player then
		return
	end
	local hero = side.character and side.character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if hero == "scarlet_witch" then
		local ok, svc = pcall(function()
			return require(script.Parent.ScarletWitchService)
		end)
		if ok and svc and type(svc.forceStopBeam) == "function" then
			svc.forceStopBeam(side.player, true)
		end
	elseif hero == "captain_marvel" then
		local ok, svc = pcall(function()
			return require(script.Parent.CaptainMarvelService)
		end)
		if ok and svc and type(svc.forceStopBeam) == "function" then
			svc.forceStopBeam(side.player, true)
		end
	end
end

local function collectSegments(): { BeamSegment }
	local list: { BeamSegment } = {}
	for _, provider in segmentProviders do
		local ok, result = pcall(provider)
		if ok and type(result) == "table" then
			for _, seg in result do
				table.insert(list, seg)
			end
		end
	end
	if beamCharModel and beamCharModel.Parent and beamCharHand and beamCharTip and beamCharTip.Parent then
		table.insert(list, {
			id = "beam_char",
			kind = "dummy",
			player = nil,
			character = beamCharModel,
			origin = beamCharHand.Position,
			tip = beamCharTip.Position,
			label = beamCharModel.Name,
		})
	end
	return list
end

local function alreadyInClash(sideId: string): boolean
	for _, clash in clashById do
		if not clash.resolved and (clash.a.id == sideId or clash.b.id == sideId) then
			return true
		end
	end
	return false
end

local function pushSide(side: ClashSide, awayFrom: Vector3, speedMult: number?)
	local root = findRoot(side.character)
	if not root or not side.character then
		return
	end
	local dir = root.Position - awayFrom
	if dir.Magnitude < 0.05 then
		dir = root.CFrame.LookVector * -1
	end
	local mult = speedMult or 1
	PushHelper.applyToCharacter(side.character, dir.Unit, {
		speed = GameConstants.BEAM_CLASH_PUSH_SPEED * mult,
		upBoost = GameConstants.BEAM_CLASH_PUSH_UP * mult,
	})
end

local function clearPrompt(clash: ClashState)
	clash.prompt = nil
end

local function sideOrigin(side: ClashSide): Vector3
	if side.character then
		local hand = getHandOrRoot(side.character)
		if hand then
			return hand.Position
		end
		local root = findRoot(side.character)
		if root then
			return root.Position
		end
	end
	return Vector3.zero
end

local function isSideFlying(side: ClashSide): boolean
	local character = side.character
	if not character then
		return false
	end
	return character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
end

local function applyRetractTips(clash: ClashState, alpha: number)
	local tipA = clash.retractFromA:Lerp(sideOrigin(clash.a), alpha)
	local tipB = clash.retractFromB:Lerp(sideOrigin(clash.b), alpha)
	if clash.a.character then
		forcedTipByCharacter[clash.a.character] = tipA
	end
	if clash.b.character then
		forcedTipByCharacter[clash.b.character] = tipB
	end
	if beamCharTip and ((clash.a.id == "beam_char") or (clash.b.id == "beam_char")) then
		local tip = if clash.a.id == "beam_char" then tipA else tipB
		local origin = if beamCharHand then beamCharHand.Position else tip
		if (origin - tip).Magnitude > 0.05 then
			beamCharTip.CFrame = CFrame.lookAt(tip, origin)
		else
			beamCharTip.CFrame = CFrame.new(tip)
		end
	end
	clash.displayClashPoint = tipA:Lerp(tipB, 0.5)
	clash.clashPoint = clash.displayClashPoint
end

local function finishClashCleanup(clash: ClashState)
	if clash.a.character then
		forcedTipByCharacter[clash.a.character] = nil
	end
	if clash.b.character then
		forcedTipByCharacter[clash.b.character] = nil
	end
	releasePlayerBeams(clash.a)
	releasePlayerBeams(clash.b)
	if ((clash.a.id == "beam_char") or (clash.b.id == "beam_char")) and beamCharBeam then
		beamCharBeam.Enabled = false
		task.delay(1.2, function()
			if beamCharBeam and beamCharBeam.Parent then
				beamCharBeam.Enabled = true
			end
		end)
	end
end

local function endClash(clash: ClashState, winner: "a" | "b" | "tie" | "cancel")
	if clash.resolved then
		return
	end
	clash.resolved = true
	clearPrompt(clash)
	clashById[clash.id] = nil

	unlockCharacter(clash.a.character)
	unlockCharacter(clash.b.character)
	setClashFlag(clash.a.character, false)
	setClashFlag(clash.b.character, false)
	lockoutUntil[sideKey(clash.a)] = now() + GameConstants.BEAM_CLASH_LOCKOUT
	lockoutUntil[sideKey(clash.b)] = now() + GameConstants.BEAM_CLASH_LOCKOUT

	local function notify(side: ClashSide, won: boolean?, tied: boolean?, canceled: boolean?)
		if side.player then
			fireClash(side.player, {
				phase = "end",
				clashId = clash.id,
				won = won == true,
				tied = tied == true,
				canceled = canceled == true,
				score = if side.id == clash.a.id then clash.scoreA else clash.scoreB,
				need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN,
			})
			if canceled then
				Remotes.getEvent("CameraShake"):FireClient(side.player, { intensity = 0.25, duration = 0.2 })
			elseif won then
				Remotes.getEvent("CameraShake"):FireClient(side.player, { intensity = 0.75, duration = 0.4 })
			elseif tied then
				Remotes.getEvent("CameraShake"):FireClient(side.player, { intensity = 0.4, duration = 0.25 })
			else
				Remotes.getEvent("CameraShake"):FireClient(side.player, { intensity = 0.95, duration = 0.55 })
			end
		end
	end

	if winner == "cancel" then
		notify(clash.a, false, false, true)
		notify(clash.b, false, false, true)
		finishClashCleanup(clash)
		return
	end

	if winner == "tie" then
		notify(clash.a, false, true, false)
		notify(clash.b, false, true, false)
		pushSide(clash.a, clash.clashPoint, 0.55)
		pushSide(clash.b, clash.clashPoint, 0.55)
	else
		local winSide = if winner == "a" then clash.a else clash.b
		local loseSide = if winner == "a" then clash.b else clash.a
		notify(winSide, true, false, false)
		notify(loseSide, false, false, false)
		pushSide(loseSide, clash.clashPoint, 0.7)
		if winSide.character and loseSide.character then
			CombatHelper.dealDamage(
				winSide.character,
				loseSide.character,
				GameConstants.BEAM_CLASH_WIN_DAMAGE,
				clash.clashPoint,
				"beam"
			)
		end
		local winRoot = findRoot(winSide.character)
		if winRoot and winSide.character then
			local forward = clash.clashPoint - winRoot.Position
			if forward.Magnitude > 0.05 then
				PushHelper.applyToCharacter(winSide.character, forward.Unit, {
					speed = 6,
					upBoost = 1,
				})
			end
		end
	end

	finishClashCleanup(clash)
end

local function beginSmoothCancel(clash: ClashState)
	if clash.resolved or clash.retracting then
		return
	end
	clash.retracting = true
	clash.retractStartedAt = now()
	clash.retractFromA = if clash.a.character and forcedTipByCharacter[clash.a.character]
		then forcedTipByCharacter[clash.a.character]
		else clash.displayClashPoint
	clash.retractFromB = if clash.b.character and forcedTipByCharacter[clash.b.character]
		then forcedTipByCharacter[clash.b.character]
		else clash.displayClashPoint
	clearPrompt(clash)
	clash.pendingPrompt = false
	unlockCharacter(clash.a.character, true)
	unlockCharacter(clash.b.character, true)
	-- Keep tips alive while beams retract to each caster
	applyRetractTips(clash, 0)
	if clash.a.player then
		fireClash(clash.a.player, { phase = "retract", clashId = clash.id })
	end
	if clash.b.player then
		fireClash(clash.b.player, { phase = "retract", clashId = clash.id })
	end
end

local function randomPromptOffset(): (number, number)
	local angle = math.random() * math.pi * 2
	local radius = 0.08 + math.random() * 0.14
	local x = 0.5 + math.cos(angle) * radius
	local y = 0.48 + math.sin(angle) * radius * 0.85
	return math.clamp(x, 0.18, 0.82), math.clamp(y, 0.28, 0.72)
end

local function spawnPromptForSide(clash: ClashState, side: ClashSide)
	if clash.resolved or clash.retracting or side.kind ~= "player" or not side.player then
		clash.pendingPrompt = false
		return
	end
	local promptId = HttpService:GenerateGUID(false)
	local x, y = randomPromptOffset()
	clash.prompt = {
		id = promptId,
		forSideId = side.id,
		expiresAt = now() + GameConstants.BEAM_CLASH_PROMPT_LIFE,
	}
	clash.pendingPrompt = false
	local score = if side.id == clash.a.id then clash.scoreA else clash.scoreB
	fireClash(side.player, {
		phase = "prompt",
		clashId = clash.id,
		promptId = promptId,
		x = x,
		y = y,
		score = score,
		need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN,
		opponent = if side.id == clash.a.id then clash.b.label else clash.a.label,
		life = GameConstants.BEAM_CLASH_PROMPT_LIFE,
	})
end

local function sideById(clash: ClashState, sideId: string): ClashSide?
	if clash.a.id == sideId then
		return clash.a
	end
	if clash.b.id == sideId then
		return clash.b
	end
	return nil
end

local function nextPromptOwner(clash: ClashState): ClashSide?
	local aPlayer = clash.a.kind == "player"
	local bPlayer = clash.b.kind == "player"
	if aPlayer and not bPlayer then
		return clash.a
	end
	if bPlayer and not aPlayer then
		return clash.b
	end
	if aPlayer and bPlayer then
		-- Alternate by turn count (score sum stays flat with +1/-1 scoring)
		return if clash.promptTurn % 2 == 0 then clash.a else clash.b
	end
	return nil
end

local function issueNextPrompt(clash: ClashState, preferSideId: string?)
	if clash.resolved or clash.retracting or clash.prompt or clash.pendingPrompt then
		return
	end
	local side: ClashSide? = nil
	if preferSideId then
		side = sideById(clash, preferSideId)
	end
	if not side then
		side = nextPromptOwner(clash)
	end
	if not side or side.kind ~= "player" then
		return
	end
	clash.pendingPrompt = true
	-- Tiny delay so the old button clears cleanly, then a new one appears
	task.delay(0.08, function()
		if clash.resolved or clashById[clash.id] ~= clash or clash.prompt then
			clash.pendingPrompt = false
			return
		end
		-- Only advance turn for fresh prompts (misses re-issue to same player)
		if not preferSideId then
			clash.promptTurn += 1
		end
		spawnPromptForSide(clash, side :: ClashSide)
	end)
end

local function beginClash(segA: BeamSegment, segB: BeamSegment, point: Vector3)
	if alreadyInClash(segA.id) or alreadyInClash(segB.id) then
		return
	end
	local sideA: ClashSide = {
		id = segA.id,
		kind = segA.kind,
		player = segA.player,
		character = segA.character,
		label = segA.label,
	}
	local sideB: ClashSide = {
		id = segB.id,
		kind = segB.kind,
		player = segB.player,
		character = segB.character,
		label = segB.label,
	}
	if isLockedOut(sideA) or isLockedOut(sideB) then
		return
	end

	local clashId = HttpService:GenerateGUID(false)
	local startScore = GameConstants.BEAM_CLASH_START_SCORE
	local clash: ClashState = {
		id = clashId,
		a = sideA,
		b = sideB,
		scoreA = startScore,
		scoreB = startScore,
		startedAt = now(),
		clashPoint = point,
		displayClashPoint = point,
		resolved = false,
		prompt = nil,
		pendingPrompt = false,
		promptTurn = 0,
		lastBeamCharScoreAt = now(),
		retracting = false,
		retractStartedAt = 0,
		retractFromA = point,
		retractFromB = point,
	}
	clashById[clashId] = clash
	setClashFlag(sideA.character, true, clashId, sideB.label)
	setClashFlag(sideB.character, true, clashId, sideA.label)

	local rootA = findRoot(sideA.character)
	local rootB = findRoot(sideB.character)
	lockCharacter(sideA.character, if rootB then rootB.Position else point)
	lockCharacter(sideB.character, if rootA then rootA.Position else point)
	applyForcedTips(clash)

	print("[BeamClash] START", sideA.label, "vs", sideB.label)

	if sideA.player then
		fireClash(sideA.player, {
			phase = "start",
			clashId = clashId,
			opponent = sideB.label,
			score = startScore,
			need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN,
		})
	end
	if sideB.player then
		fireClash(sideB.player, {
			phase = "start",
			clashId = clashId,
			opponent = sideA.label,
			score = startScore,
			need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN,
		})
	end
	issueNextPrompt(clash)
end

local function broadcastScores(clash: ClashState)
	if clash.a.player then
		fireClash(clash.a.player, {
			phase = "score",
			clashId = clash.id,
			score = clash.scoreA,
			need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN,
			opponent = clash.b.label,
		})
	end
	if clash.b.player then
		fireClash(clash.b.player, {
			phase = "score",
			clashId = clash.id,
			score = clash.scoreB,
			need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN,
			opponent = clash.a.label,
		})
	end
end

local function onPromptHit(clash: ClashState, sideId: string, promptId: string)
	if clash.resolved or clash.retracting or not clash.prompt then
		return
	end
	if clash.prompt.id ~= promptId or clash.prompt.forSideId ~= sideId then
		return
	end
	clearPrompt(clash)

	-- +1 self, -1 opponent (target pushed back)
	if clash.a.id == sideId then
		clash.scoreA = math.min(GameConstants.BEAM_CLASH_PROMPTS_TO_WIN, clash.scoreA + 1)
		clash.scoreB = math.max(0, clash.scoreB - 1)
	elseif clash.b.id == sideId then
		clash.scoreB = math.min(GameConstants.BEAM_CLASH_PROMPTS_TO_WIN, clash.scoreB + 1)
		clash.scoreA = math.max(0, clash.scoreA - 1)
	else
		return
	end
	applyForcedTips(clash)
	broadcastScores(clash)

	local need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN
	if clash.scoreA >= need then
		endClash(clash, "a")
		return
	end
	if clash.scoreB >= need then
		endClash(clash, "b")
		return
	end

	issueNextPrompt(clash)
end

function BeamClashService.handlePromptHit(player: Player, clashId: string?, promptId: string?)
	if type(clashId) ~= "string" or type(promptId) ~= "string" then
		return
	end
	local clash = clashById[clashId]
	if not clash or clash.resolved then
		return
	end
	local sideId: string? = nil
	if clash.a.player == player then
		sideId = clash.a.id
	elseif clash.b.player == player then
		sideId = clash.b.id
	end
	if not sideId then
		return
	end
	onPromptHit(clash, sideId, promptId)
end

local function updateBeamCharTipAndDamage()
	if not beamCharModel or not beamCharModel.Parent or not beamCharTip or not beamCharHand then
		return
	end
	local hrp = beamCharHrp or findRoot(beamCharModel)
	if not hrp then
		return
	end

	-- If locked in a clash, tip is driven by applyForcedTips
	local inClash = beamCharModel:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true
		or forcedTipByCharacter[beamCharModel] ~= nil

	if not inClash then
		local origin = beamCharHand.Position
		local dir = hrp.CFrame.LookVector
		if dir.Magnitude < 0.05 then
			dir = Vector3.new(0, 0, -1)
		end
		dir = dir.Unit
		local range = GameConstants.BEAM_CHAR_RANGE
		local tipPos = origin + dir * range
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { beamCharModel, beamCharTip }
		local hit = Workspace:Raycast(origin, dir * range, params)
		if hit then
			tipPos = hit.Position
		end
		beamCharTip.CFrame = CFrame.lookAt(tipPos, origin)

		local t = now()
		if t - beamCharLastHit >= 0.12 then
			beamCharLastHit = t
			local half = GameConstants.HEX_BEAM_HIT_SIZE
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Exclude
			overlap.FilterDescendantsInstances = { beamCharModel, beamCharTip }
			local box = Workspace:GetPartBoundsInBox(CFrame.new(tipPos), Vector3.new(half, half, half), overlap)
			local seen: { [Model]: boolean } = {}
			for _, part in box do
				local victim = CombatHelper.getCharacterFromPart(part)
				if victim and victim ~= beamCharModel and not seen[victim] then
					seen[victim] = true
					CombatHelper.dealDamage(beamCharModel, victim, GameConstants.HEX_BEAM_DAMAGE_PER_SEC * 0.12, tipPos, "beam")
				end
			end
		end
	end

	if beamCharBeam then
		beamCharBeam.Enabled = true
	end
	if beamCharStartAtt then
		VfxHelper.setParticlesEnabled(beamCharStartAtt, true)
	end
	if beamCharEndAtt then
		VfxHelper.setParticlesEnabled(beamCharEndAtt, true)
	end
end

local function setupBeamChar()
	local found = Workspace:FindFirstChild("BeamChar", true)
	if not (found and found:IsA("Model")) then
		warn("[BeamClash] Workspace.BeamChar not found — place a character Model named BeamChar")
		return
	end
	beamCharModel = found
	local hrp = findRoot(found)
	local hand = getHandOrRoot(found)
	if not hrp or not hand then
		warn("[BeamClash] BeamChar missing HRP/hand")
		return
	end
	beamCharHrp = hrp
	beamCharHand = hand
	print("[BeamClash] Found BeamChar at", found:GetFullName())

	for _, child in hand:GetChildren() do
		if child.Name == "BeamStartAttachment" or child.Name == "BeamCharBeam" or child.Name == "BeamCharStart" then
			child:Destroy()
		end
	end
	local oldTip = Workspace:FindFirstChild("BeamCharTip")
	if oldTip then
		oldTip:Destroy()
	end

	local startAtt = cloneScarletAttachment("BeamStartAttachment")
	local endAtt = cloneScarletAttachment("BeamEndAttachment")
	if not startAtt or not endAtt then
		warn("[BeamClash] Missing Assets.ScarletWitch BeamStartAttachment / BeamEndAttachment")
		return
	end
	startAtt.Name = "BeamStartAttachment"
	startAtt.Parent = hand
	beamCharStartAtt = startAtt

	local tip = Instance.new("Part")
	tip.Name = "BeamCharTip"
	tip.Size = Vector3.new(0.2, 0.2, 0.2)
	tip.Transparency = 1
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.CastShadow = false
	tip.CFrame = hrp.CFrame * CFrame.new(0, 0, -GameConstants.BEAM_CHAR_RANGE)
	tip.Parent = Workspace
	beamCharTip = tip

	endAtt.Name = "BeamEndAttachment"
	endAtt.Parent = tip
	beamCharEndAtt = endAtt

	local beam = startAtt:FindFirstChildWhichIsA("Beam", true)
	if beam then
		beam.Attachment0 = startAtt
		beam.Attachment1 = endAtt
		beam.Enabled = true
	else
		beam = Instance.new("Beam")
		beam.Name = "BeamCharBeam"
		beam.Attachment0 = startAtt
		beam.Attachment1 = endAtt
		beam.Width0 = 0.85
		beam.Width1 = 0.65
		beam.FaceCamera = true
		beam.LightEmission = 0.8
		beam.Color = ColorSequence.new(Color3.fromRGB(200, 40, 70))
		beam.Parent = startAtt
	end
	beamCharBeam = beam

	VfxHelper.setParticlesEnabled(startAtt, true)
	VfxHelper.setParticlesEnabled(endAtt, true)
	VfxHelper.emitAllParticles(startAtt, 8)
	VfxHelper.emitAllParticles(endAtt, 8)

	updateBeamCharTipAndDamage()
	print("[BeamClash] BeamChar hex beam armed (5 studs) + tip damage")
end

function BeamClashService.update(dt: number)
	updateBeamCharTipAndDamage()
	local _dt = dt

	local activeClashes: { ClashState } = {}
	for _, clash in clashById do
		table.insert(activeClashes, clash)
	end

	for _, clash in activeClashes do
		if clash.resolved then
			continue
		end

		-- Smooth cancel: pull tips back to each caster, then disable beams
		if clash.retracting then
			local dur = math.max(0.05, GameConstants.BEAM_CLASH_RETRACT_TIME)
			local alpha = math.clamp((now() - clash.retractStartedAt) / dur, 0, 1)
			-- Ease-out so the last stretch feels soft
			local eased = 1 - (1 - alpha) * (1 - alpha)
			applyRetractTips(clash, eased)
			if alpha >= 1 then
				endClash(clash, "cancel")
			end
			continue
		end

		local rootA = findRoot(clash.a.character)
		local rootB = findRoot(clash.b.character)
		if rootA and rootB then
			updateLockFacing(clash.a.character, rootB.Position)
			updateLockFacing(clash.b.character, rootA.Position)

			-- Flying range break: if either is flying and separation > 70, retract smoothly
			local dist = (rootA.Position - rootB.Position).Magnitude
			if dist > GameConstants.BEAM_CLASH_MAX_RANGE and (isSideFlying(clash.a) or isSideFlying(clash.b)) then
				beginSmoothCancel(clash)
				continue
			end
		end
		applyForcedTips(clash)

		-- Testing: BeamChar auto +1 every second
		if clash.a.id == "beam_char" or clash.b.id == "beam_char" then
			local interval = GameConstants.BEAM_CHAR_AUTO_SCORE_INTERVAL
			if now() - clash.lastBeamCharScoreAt >= interval then
				clash.lastBeamCharScoreAt = now()
				local beamSideId = if clash.a.id == "beam_char" then clash.a.id else clash.b.id
				if clash.a.id == beamSideId then
					clash.scoreA = math.min(GameConstants.BEAM_CLASH_PROMPTS_TO_WIN, clash.scoreA + 1)
					clash.scoreB = math.max(0, clash.scoreB - 1)
				else
					clash.scoreB = math.min(GameConstants.BEAM_CLASH_PROMPTS_TO_WIN, clash.scoreB + 1)
					clash.scoreA = math.max(0, clash.scoreA - 1)
				end
				applyForcedTips(clash)
				broadcastScores(clash)
				local need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN
				if clash.scoreA >= need then
					endClash(clash, "a")
					continue
				end
				if clash.scoreB >= need then
					endClash(clash, "b")
					continue
				end
			end
		end

		if now() - clash.startedAt >= GameConstants.BEAM_CLASH_MAX_TIME then
			endClash(clash, "tie")
			continue
		end

		if clash.prompt and now() >= clash.prompt.expiresAt then
			local missedSideId = clash.prompt.forSideId
			clearPrompt(clash)
			if clash.a.player then
				fireClash(clash.a.player, { phase = "prompt_miss", clashId = clash.id })
			end
			if clash.b.player then
				fireClash(clash.b.player, { phase = "prompt_miss", clashId = clash.id })
			end
			issueNextPrompt(clash, missedSideId)
		end
	end

	local segments = collectSegments()
	local n = #segments
	for i = 1, n do
		local a = segments[i]
		for j = i + 1, n do
			local b = segments[j]
			if a.id == b.id then
				continue
			end
			if a.kind ~= "player" and b.kind ~= "player" then
				continue
			end
			if alreadyInClash(a.id) or alreadyInClash(b.id) then
				continue
			end
			local sideA: ClashSide = {
				id = a.id,
				kind = a.kind,
				player = a.player,
				character = a.character,
				label = a.label,
			}
			local sideB: ClashSide = {
				id = b.id,
				kind = b.kind,
				player = b.player,
				character = b.character,
				label = b.label,
			}
			if isLockedOut(sideA) or isLockedOut(sideB) then
				continue
			end

			local hit, point = segmentsClash(a.origin, a.tip, b.origin, b.tip, GameConstants.BEAM_CLASH_HIT_DIST)
			if not hit then
				if (a.tip - b.origin).Magnitude <= 6 or (b.tip - a.origin).Magnitude <= 6 then
					hit = true
					point = if (a.tip - b.origin).Magnitude <= 6 then a.tip else b.tip
				elseif distPointToSegment(a.tip, b.origin, b.tip) <= 5 or distPointToSegment(b.tip, a.origin, a.tip) <= 5 then
					hit = true
					point = a.tip:Lerp(b.tip, 0.5)
				end
			end
			if hit and point then
				beginClash(a, b, point)
			end
		end
	end
end

function BeamClashService.init()
	beamEvent = Remotes.getEvent("BeamClash")
	setupBeamChar()
	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == "BeamChar" and inst:IsA("Model") and not beamCharModel then
			task.defer(setupBeamChar)
		end
	end)

	local ev = beamEvent :: RemoteEvent
	ev.OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.action == "prompt_hit" then
			BeamClashService.handlePromptHit(
				player,
				if type(payload.clashId) == "string" then payload.clashId else nil,
				if type(payload.promptId) == "string" then payload.promptId else nil
			)
		end
	end)
end

return BeamClashService
