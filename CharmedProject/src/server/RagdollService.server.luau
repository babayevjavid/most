--[[
	Living "Ragdolled" status (abilities, TK, Crystal, etc.) drives the constraint ragdoll.
	On death, main.server sets Ragdolled = true with BreakJointsOnDeath = false — we apply the same
	physics ragdoll once so the body collapses instead of staying in T-pose.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ragdollHandlerFolder = script.Parent:WaitForChild("RagdollHandler")
local BuildRagdoll = require(ragdollHandlerFolder:WaitForChild("buildRagdoll"))
local RagdollHandler = require(ragdollHandlerFolder)

local ragdollVisualLast: { [Model]: boolean? } = {}
local ragdollAttrConns: { [Model]: RBXScriptConnection } = {}
local npcDescendantScriptConns: { [Model]: RBXScriptConnection } = {}
local npcLastAnimatorStop: { [Model]: number } = {}

local SCRIPT_WAS_ENABLED_ATTR = "RagdollNpcScriptWasEnabled"
local NPC_ANIMATOR_STOP_INTERVAL = 0.4

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

-- NPC models often include server Scripts that reset Motor6D / pose on contact; suspend while Ragdolled.
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

-- Catch scripts spawned after ragdoll starts (no full GetDescendants every frame).
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

local function ensureRagdollBuilt(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	if character:FindFirstChild("RagdollConstraints") then
		return
	end
	BuildRagdoll(humanoid)
	RagdollHandler:ragdollAdded(humanoid)
end

local function syncPhysicsRagdollFromRagdolledAttribute(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local want = character:GetAttribute("Ragdolled") == true
	-- No work when dead and not marked ragdolled (corpse cleanup / unrelated attribute churn).
	if humanoid.Health <= 0 and not want then
		return
	end
	if ragdollVisualLast[character] == want then
		return
	end
	ragdollVisualLast[character] = want

	ensureRagdollBuilt(humanoid)

	if want then
		local plr = Players:GetPlayerFromCharacter(character)
		if plr then
			setServerOwnership(character, nil)
		else
			suspendNpcServerScripts(character)
			startNpcScriptDescendantWatcher(character)
			stopNpcAnimatorTracks(humanoid)
			npcLastAnimatorStop[character] = nil
			-- Humanoid can leave Physics / try to stand on limb contact; block until Ragdolled clears.
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
		syncPhysicsRagdollFromRagdolledAttribute(character)
	end)
	syncPhysicsRagdollFromRagdolledAttribute(character)
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

local function setupRagdoll(character: Model)
	if ragdollAttrConns[character] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	BuildRagdoll(humanoid)
	RagdollHandler:ragdollAdded(humanoid)
	bindRagdolledAttributeSync(character)
	humanoid.Died:Connect(function()
		character:SetAttribute("Ragdolled", true)
	end)
	character.Destroying:Once(function()
		disconnectRagdoll(character)
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

Players.PlayerAdded:Connect(bindPlayerRagdoll)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayerRagdoll(player)
end

-- NPCs / non-player models in Workspace that receive Ragdolled from abilities
local function trySetupWorkspaceCharacter(model: Model)
	if Players:GetPlayerFromCharacter(model) then
		return
	end
	setupRagdoll(model)
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
		-- NPCs: lightweight maintain runs on PostSimulation (after physics). Heartbeat here would duplicate work and miss touch re-welds.
		if postSimOk and postSimEvent and Players:GetPlayerFromCharacter(character) == nil then
			continue
		end
		RagdollHandler:MaintainStatusRagdoll(humanoid)
	end
end)

-- NPCs: dedicated simplified ragdoll mode. Keep joints disconnected + Physics every step.
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
