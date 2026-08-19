--!strict
--[[
	Living "Ragdolled" status drives constraint ragdoll.
	Adapted from NewMarvelProject RagdollService.server — same physics path.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollHandlerFolder = script.Parent:WaitForChild("RagdollHandler")
local BuildRagdoll = require(RagdollHandlerFolder:WaitForChild("buildRagdoll"))
local RagdollHandler = require(RagdollHandlerFolder)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local GET_UP_TOKEN_ATTR = "GetUpToken"

type TkLandWatch = {
	armed: boolean,
	startedAt: number,
}

local tkLandWatch: { [Model]: TkLandWatch } = {}

local function playGetUpAnim(character: Model): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = GameConstants.GET_UP_ANIM
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.12, 1, 1)
	return track
end

local function finishGetUp(character: Model, token: number)
	if not character.Parent then
		return
	end
	if character:GetAttribute(GET_UP_TOKEN_ATTR) ~= token then
		return
	end
	if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) ~= true then
		return
	end
	character:SetAttribute(GameConstants.GETTING_UP_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
		humanoid.JumpPower = 50
		pcall(function()
			humanoid.JumpHeight = 7.2
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end)
	end
end

local function stampGetUp(character: Model): number?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local token = ((character:GetAttribute(GET_UP_TOKEN_ATTR) :: number?) or 0) + 1
	character:SetAttribute(GET_UP_TOKEN_ATTR, token)
	character:SetAttribute(GameConstants.GETTING_UP_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	local now = AbilityCooldownHelper.getNow()
	local existing = character:GetAttribute(GameConstants.PROTECTED_UNTIL_ATTRIBUTE)
	local untilTime = now + GameConstants.GET_UP_IFRAME
	if type(existing) == "number" then
		untilTime = math.max(untilTime, existing)
	end
	character:SetAttribute(GameConstants.PROTECTED_UNTIL_ATTRIBUTE, untilTime)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	pcall(function()
		humanoid.JumpHeight = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	return token
end

local function startGetUpAnim(character: Model, token: number)
	local track = playGetUpAnim(character)
	local duration = 1.8
	if track and track.Length > 0.05 then
		duration = track.Length / math.max(track.Speed, 0.01)
	end
	task.delay(duration + 0.05, function()
		finishGetUp(character, token)
	end)
end

local function cancelGetUp(character: Model)
	local token = ((character:GetAttribute(GET_UP_TOKEN_ATTR) :: number?) or 0) + 1
	character:SetAttribute(GET_UP_TOKEN_ATTR, token)
	if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true then
		character:SetAttribute(GameConstants.GETTING_UP_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
end

local RagdollService = {}

local ragdollVisualLast: { [Model]: boolean? } = {}
local ragdollAttrConns: { [Model]: RBXScriptConnection } = {}
local ragdollImpactConns: { [Model]: RBXScriptConnection } = {}
local ragdollImpactPlayed: { [Model]: boolean } = {}
local npcDescendantScriptConns: { [Model]: RBXScriptConnection } = {}
local npcLastAnimatorStop: { [Model]: number } = {}
local abilityInterruptListeners: { (Player, Model) -> () } = {}

local function notifyAbilityInterrupt(character: Model)
	if character:GetAttribute("BeamClashActive") == true then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	for _, fn in abilityInterruptListeners do
		task.spawn(fn, player, character)
	end
end

local function bindRagdollImpactSound(character: Model)
	local old = ragdollImpactConns[character]
	if old then
		old:Disconnect()
		ragdollImpactConns[character] = nil
	end
	local torso = character:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	ragdollImpactConns[character] = torso.Touched:Connect(function(otherPart)
		if character:GetAttribute("Ragdolled") ~= true or ragdollImpactPlayed[character] then
			return
		end
		if not otherPart.CanCollide or otherPart:IsDescendantOf(character) then
			return
		end
		-- A downward surface check prevents walls/characters from counting as ground impact.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local distance = torso.Size.Y * 0.5 + 1.75
		local hit = Workspace:Raycast(torso.Position, Vector3.new(0, -distance, 0), params)
		if not hit or hit.Normal.Y < 0.45 then
			return
		end
		ragdollImpactPlayed[character] = true
		local sounds = GameConstants.RAGDOLL_SOUNDS
		if type(sounds) == "table" and #sounds > 0 then
			VfxHelper.playWorldSound(sounds[math.random(1, #sounds)], torso.Position, 0.95)
		end
	end)
end

function RagdollService.onAbilityInterrupt(listener: (Player, Model) -> ())
	table.insert(abilityInterruptListeners, listener)
end

local SCRIPT_WAS_ENABLED_ATTR = "RagdollNpcScriptWasEnabled"
local NPC_ANIMATOR_STOP_INTERVAL = 0.4

local function isCharacterBodyPart(part: BasePart): boolean
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		return false
	end
	return true
end

local function ensureBodyUnanchored(character: Model)
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and isCharacterBodyPart(desc) and desc.Anchored then
			desc.Anchored = false
		end
	end
end

local function stopNpcAnimatorTracks(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		pcall(function()
			track:Stop(0)
		end)
	end
end

local function suspendNpcServerScripts(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Script") and d:GetAttribute("RagdollNeverSuspend") ~= true then
			if d:GetAttribute(SCRIPT_WAS_ENABLED_ATTR) == nil then
				d:SetAttribute(SCRIPT_WAS_ENABLED_ATTR, d.Enabled)
				d.Enabled = false
			end
		end
	end
end

local function resumeNpcServerScripts(character: Model)
	if not character.Parent then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Script") then
			local was = d:GetAttribute(SCRIPT_WAS_ENABLED_ATTR)
			if typeof(was) == "boolean" then
				d.Enabled = was
				d:SetAttribute(SCRIPT_WAS_ENABLED_ATTR, nil)
			end
		end
	end
end

local function suspendOneNpcScriptIfNeeded(scriptInst: Script)
	if scriptInst:GetAttribute("RagdollNeverSuspend") == true then
		return
	end
	if scriptInst:GetAttribute(SCRIPT_WAS_ENABLED_ATTR) ~= nil then
		return
	end
	scriptInst:SetAttribute(SCRIPT_WAS_ENABLED_ATTR, scriptInst.Enabled)
	scriptInst.Enabled = false
end

local function startNpcScriptDescendantWatcher(character: Model)
	if npcDescendantScriptConns[character] then
		return
	end
	npcDescendantScriptConns[character] = character.DescendantAdded:Connect(function(inst)
		if character:GetAttribute("Ragdolled") ~= true then
			return
		end
		if inst:IsA("Script") then
			suspendOneNpcScriptIfNeeded(inst)
		end
	end)
end

local function stopNpcScriptDescendantWatcher(character: Model)
	local c = npcDescendantScriptConns[character]
	if c then
		c:Disconnect()
		npcDescendantScriptConns[character] = nil
	end
end

local function setServerOwnership(character: Model, owner: Player?)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function()
				d:SetNetworkOwner(owner)
			end)
		end
	end
end

local function countMotor6Ds(character: Model): number
	local n = 0
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") then
			n += 1
		end
	end
	return n
end

local function countValidRagdollConstraints(folder: Instance): number
	local n = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Constraint") then
			local rigid = child:FindFirstChild("RigidJoint")
			if rigid and rigid:IsA("ObjectValue") and rigid.Value and rigid.Value:IsA("Motor6D") then
				n += 1
			end
		end
	end
	return n
end

local function waitForCharacterRig(character: Model): boolean
	character:WaitForChild("HumanoidRootPart", 8)
	local plr = Players:GetPlayerFromCharacter(character)
	if plr then
		-- Don't hang if appearance already loaded
		pcall(function()
			if not plr:HasAppearanceLoaded() then
				plr.CharacterAppearanceLoaded:Wait()
			end
		end)
	end
	local t0 = os.clock()
	while os.clock() - t0 < 6 do
		-- R6 ~5-6 motors, R15 ~14-16 (blocky packages stream in late)
		if countMotor6Ds(character) >= 5 then
			task.wait(0.15)
			return true
		end
		task.wait(0.05)
	end
	return character:FindFirstChildWhichIsA("Motor6D", true) ~= nil
end

local function ensureRagdollBuilt(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local folder = character:FindFirstChild("RagdollConstraints")
	local motors = countMotor6Ds(character)
	local valid = 0
	if folder then
		valid = countValidRagdollConstraints(folder)
	end
	-- Empty / premature builds (CharacterAdded before package Motor6Ds) must be rebuilt.
	-- Expect roughly one constraint per non-root motor.
	local needRebuild = (not folder) or valid < 3 or (motors >= 5 and valid < math.max(3, motors - 3))
	if not needRebuild then
		return
	end
	if folder then
		folder:Destroy()
	end
	BuildRagdoll(humanoid)
	RagdollHandler:ragdollAdded(humanoid)
end

local function disconnectRagdoll(character: Model)
	stopNpcScriptDescendantWatcher(character)
	resumeNpcServerScripts(character)
	npcLastAnimatorStop[character] = nil
	local conn = ragdollAttrConns[character]
	if conn then
		conn:Disconnect()
		ragdollAttrConns[character] = nil
	end
	local impactConn = ragdollImpactConns[character]
	if impactConn then
		impactConn:Disconnect()
		ragdollImpactConns[character] = nil
	end
	ragdollImpactPlayed[character] = nil
	ragdollVisualLast[character] = nil
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and Players:GetPlayerFromCharacter(character) == nil then
		pcall(function()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		end)
	end
	if humanoid then
		RagdollHandler:ragdollRemoved(humanoid)
	end
end

local function syncPhysicsRagdollFromRagdolledAttribute(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local want = character:GetAttribute("Ragdolled") == true

	if humanoid.Health <= 0 and not want then
		return
	end
	if ragdollVisualLast[character] == want then
		return
	end
	ragdollVisualLast[character] = want

	ensureRagdollBuilt(humanoid)

	if want then
		ensureBodyUnanchored(character)
		local plr = Players:GetPlayerFromCharacter(character)
		if plr then
			setServerOwnership(character, nil)
		else
			suspendNpcServerScripts(character)
			startNpcScriptDescendantWatcher(character)
			stopNpcAnimatorTracks(humanoid)
			npcLastAnimatorStop[character] = nil
			pcall(function()
				humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			end)
		end
		RagdollHandler:ManualRagdoll(humanoid, true)
	else
		RagdollHandler:ManualRagdoll(humanoid, false)
		local plr = Players:GetPlayerFromCharacter(character)
		if plr then
			setServerOwnership(character, plr)
		else
			stopNpcScriptDescendantWatcher(character)
			resumeNpcServerScripts(character)
			npcLastAnimatorStop[character] = nil
			pcall(function()
				humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			end)
		end
	end
end

local function bindRagdolledAttributeSync(character: Model)
	if ragdollAttrConns[character] then
		ragdollAttrConns[character]:Disconnect()
		ragdollAttrConns[character] = nil
	end
	ragdollAttrConns[character] = character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		local nowRagdolled = character:GetAttribute("Ragdolled") == true
		if nowRagdolled then
			ragdollImpactPlayed[character] = false
		else
			ragdollImpactPlayed[character] = nil
		end
		syncPhysicsRagdollFromRagdolledAttribute(character)
		if nowRagdolled then
			notifyAbilityInterrupt(character)
		end
	end)
	syncPhysicsRagdollFromRagdolledAttribute(character)
end

local function setupRagdoll(character: Model)
	if ragdollAttrConns[character] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	-- Defer until Motor6Ds / blocky package parts exist (avoids empty RagdollConstraints forever)
	task.spawn(function()
		if not character.Parent then
			return
		end
		waitForCharacterRig(character)
		if not character.Parent or not humanoid.Parent then
			return
		end
		if ragdollAttrConns[character] then
			-- Already bound (e.g. apply raced ahead); just rebuild if needed
			ensureRagdollBuilt(humanoid)
			syncPhysicsRagdollFromRagdolledAttribute(character)
			return
		end
		BuildRagdoll(humanoid)
		RagdollHandler:ragdollAdded(humanoid)
		ensureRagdollBuilt(humanoid)
		bindRagdollImpactSound(character)
		bindRagdolledAttributeSync(character)
		character.Destroying:Once(function()
			disconnectRagdoll(character)
		end)
	end)
end

local function bindPlayerRagdoll(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupRagdoll(character)
	end)
	player.CharacterRemoving:Connect(function(character)
		disconnectRagdoll(character)
	end)
	if player.Character then
		setupRagdoll(player.Character)
	end
end

local function trySetupWorkspaceCharacter(model: Model)
	if Players:GetPlayerFromCharacter(model) then
		return
	end
	setupRagdoll(model)
end

function RagdollService.maintain(character: Model)
	if not character or not character.Parent then
		return
	end
	if character:GetAttribute("Ragdolled") ~= true then
		RagdollService.apply(character)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	ensureRagdollBuilt(humanoid)
	RagdollHandler:MaintainStatusRagdoll(humanoid)
end

function RagdollService.apply(character: Model)
	if not character or not character.Parent then
		return
	end
	-- Shields block all ragdoll CC: abilities may only damage the shield, never flop the holder.
	if CombatHelper.isShielded(character) then
		local liveHum = character:FindFirstChildOfClass("Humanoid")
		if liveHum and liveHum.Health > 0 then
			return
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and countMotor6Ds(character) < 5 then
		waitForCharacterRig(character)
	end
	if not ragdollAttrConns[character] then
		setupRagdoll(character)
	end
	if humanoid then
		ensureRagdollBuilt(humanoid)
	end
	local was = character:GetAttribute("Ragdolled") == true
	cancelGetUp(character)
	ragdollVisualLast[character] = nil
	character:SetAttribute("Ragdolled", true)
	syncPhysicsRagdollFromRagdolledAttribute(character)
	if not was then
		notifyAbilityInterrupt(character)
	end
end

function RagdollService.applyTimed(character: Model, duration: number)
	if not character or not character.Parent then
		return
	end
	RagdollService.apply(character)
	character:SetAttribute("RagdollEndTime", Workspace:GetServerTimeNow() + duration)
	local token = (character:GetAttribute("RagdollClearToken") :: number?) or 0
	token += 1
	character:SetAttribute("RagdollClearToken", token)
	task.delay(duration, function()
		if not character.Parent then
			return
		end
		if character:GetAttribute("RagdollClearToken") ~= token then
			return
		end
		if character:GetAttribute("TelekinesisHeld") == true then
			return
		end
		if character:GetAttribute("MgSlamHeld") == true then
			return
		end
		RagdollService.clear(character)
	end)
end

function RagdollService.clear(character: Model)
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local getUpToken: number? = nil
	if humanoid and humanoid.Health > 0 and character.Parent then
		getUpToken = stampGetUp(character)
	end
	character:SetAttribute("Ragdolled", nil)
	character:SetAttribute("RagdollEndTime", nil)
	ragdollVisualLast[character] = nil
	syncPhysicsRagdollFromRagdolledAttribute(character)
	if humanoid and humanoid.Parent and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) ~= true then
		humanoid.AutoRotate = true
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { "TKCasterFaceAlign", "TKCasterFaceAttachment", "MgFaceAlign", "MgFaceAtt", "IwCastFaceAlign", "IwCastFaceAtt" } do
			local inst = root:FindFirstChild(name)
			if inst then
				inst:Destroy()
			end
		end
	end
	if getUpToken then
		startGetUpAnim(character, getUpToken)
	end
end

local function torsoHeightAboveGround(character: Model): number
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		local root = character:FindFirstChild("HumanoidRootPart")
		torso = if root and root:IsA("BasePart") then root else nil
	end
	if not torso then
		return 80
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(torso.Position, Vector3.new(0, -80, 0), params)
	if hit then
		return math.max(0, torso.Position.Y - hit.Position.Y)
	end
	return 80
end

function RagdollService.markTelekineticLand(character: Model)
	if not character or not character.Parent then
		return
	end
	tkLandWatch[character] = {
		armed = torsoHeightAboveGround(character) > 3,
		startedAt = os.clock(),
	}
end

local function updateTkLandWatch()
	for character, watch in tkLandWatch do
		if not character.Parent then
			tkLandWatch[character] = nil
			continue
		end
		if os.clock() - watch.startedAt > 8 then
			tkLandWatch[character] = nil
			continue
		end
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			tkLandWatch[character] = nil
			continue
		end
		local height = torsoHeightAboveGround(character)
		local velY = root.AssemblyLinearVelocity.Y
		if torso and torso:IsA("BasePart") then
			velY = torso.AssemblyLinearVelocity.Y
		end
		if not watch.armed then
			if height > 3 or velY > 14 then
				watch.armed = true
			end
			continue
		end
		if height <= 1.05 and velY <= 12 then
			local at = if torso and torso:IsA("BasePart") then torso.Position else root.Position
			VfxHelper.playWorldSound(GameConstants.TK_LAND_SOUND, at, 1.05)
			tkLandWatch[character] = nil
		end
	end
end

function RagdollService.clearAfter(character: Model, delaySec: number)
	if not character or not character.Parent then
		return
	end
	RagdollService.apply(character)
	local token = (character:GetAttribute("RagdollClearToken") :: number?) or 0
	token += 1
	character:SetAttribute("RagdollClearToken", token)
	character:SetAttribute("RagdollEndTime", Workspace:GetServerTimeNow() + delaySec)
	task.delay(delaySec, function()
		if not character.Parent then
			return
		end
		if character:GetAttribute("RagdollClearToken") ~= token then
			return
		end
		if character:GetAttribute("TelekinesisHeld") == true then
			return
		end
		if character:GetAttribute("MgSlamHeld") == true then
			return
		end
		RagdollService.clear(character)
	end)
end

function RagdollService.init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	require(ReplicatedStorage.Shared.RagdollStatus).bindServer({
		apply = function(character: Model)
			RagdollService.apply(character)
		end,
		clear = function(character: Model)
			RagdollService.clear(character)
		end,
		applyTimed = function(character: Model, duration: number)
			RagdollService.applyTimed(character, duration)
		end,
		clearAfter = function(character: Model, delaySec: number)
			RagdollService.clearAfter(character, delaySec)
		end,
	})

	Players.PlayerAdded:Connect(bindPlayerRagdoll)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayerRagdoll(player)
	end

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local parent = inst.Parent
			if parent and parent:IsA("Model") then
				trySetupWorkspaceCharacter(parent)
			end
		end
	end

	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Humanoid") then
			local parent = inst.Parent
			if parent and parent:IsA("Model") then
				trySetupWorkspaceCharacter(parent)
			end
		end
	end)

	for _, character in ipairs(CollectionService:GetTagged("TestCharacter")) do
		if character:IsA("Model") then
			setupRagdoll(character)
		end
	end

	CollectionService:GetInstanceAddedSignal("TestCharacter"):Connect(function(character)
		if character:IsA("Model") then
			setupRagdoll(character)
		end
	end)

	local postSimOk, postSimEvent = pcall(function()
		return (RunService :: any).PostSimulation
	end)

	RunService.Heartbeat:Connect(function()
		updateTkLandWatch()
		for character, _ in pairs(ragdollAttrConns) do
			if not character.Parent then
				continue
			end
			if character:GetAttribute("Ragdolled") ~= true then
				continue
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
				continue
			end
			if postSimOk and postSimEvent and Players:GetPlayerFromCharacter(character) == nil then
				continue
			end
			RagdollHandler:MaintainStatusRagdoll(humanoid)
		end
	end)

	if postSimOk and postSimEvent then
		postSimEvent:Connect(function()
			local now = tick()
			for character, _ in pairs(ragdollAttrConns) do
				if not character.Parent then
					continue
				end
				if Players:GetPlayerFromCharacter(character) ~= nil then
					continue
				end
				if character:GetAttribute("Ragdolled") ~= true then
					continue
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
					continue
				end
				RagdollHandler:MaintainNpcRagdollAfterPhysics(humanoid)

				local lastAnim = npcLastAnimatorStop[character]
				if lastAnim == nil or now - lastAnim >= NPC_ANIMATOR_STOP_INTERVAL then
					npcLastAnimatorStop[character] = now
					stopNpcAnimatorTracks(humanoid)
				end
			end
		end)
	end
end

return RagdollService
