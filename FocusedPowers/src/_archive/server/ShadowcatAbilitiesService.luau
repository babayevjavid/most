--!strict
--[[ Shadowcat abilities server ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCombatHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local ShadowcatConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShadowcatConstants"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))

local ResourceService = require(script.Parent:WaitForChild("ResourceService"))

local CHAR_ID = "Shadowcat"
local C = ShadowcatConstants
local COLOR = C.COLOR

local phasingPlayers: { [Player]: boolean } = {}
type AscensionState = {
	lookDir: Vector3,
	moveDir: Vector3,
}

local ascensionPlayers: { [Player]: AscensionState } = {}
local worldCollideSnapshot: { [BasePart]: boolean } = {}
local phasingRefCount = 0

local ShadowcatAbilitiesService = {}

local function isShadowcat(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function getRoot(char: Model): BasePart?
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isBaseplate(part: BasePart): boolean
	if part.Name == "Baseplate" then
		return true
	end
	local parent = part.Parent
	return parent ~= nil and parent.Name == "Baseplate"
end

local function shouldSkipWorldPart(part: BasePart): boolean
	if not part:IsA("BasePart") then
		return true
	end
	if isBaseplate(part) then
		return true
	end
	return false
end

local function enableWorldPhasing()
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("BasePart") and not shouldSkipWorldPart(inst) then
			if worldCollideSnapshot[inst] == nil then
				worldCollideSnapshot[inst] = inst.CanCollide
			end
			inst.CanCollide = false
		end
	end
end

local function disableWorldPhasing()
	for part, original in worldCollideSnapshot do
		if part.Parent then
			part.CanCollide = original
		end
	end
	table.clear(worldCollideSnapshot)
end

local function setPhasing(char: Model, active: boolean)
	char:SetAttribute("IsPhasingActive", if active then true else nil)
	char:SetAttribute("PhasingActive", if active then true else nil)
end

local function togglePhasing(plr: Player, want: boolean)
	local char = plr.Character
	if not char then
		return
	end
	if want then
		if not ResourceService.hasMinimum(char, CHAR_ID, C.Phasing.ABILITY_ID) then
			return
		end
		if char:GetAttribute("IsPhasingActive") == true then
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, C.Phasing.ABILITY_ID) then
			return
		end
		phasingPlayers[plr] = true
		phasingRefCount += 1
		if phasingRefCount == 1 then
			enableWorldPhasing()
		end
		setPhasing(char, true)
	else
		phasingPlayers[plr] = nil
		if char:GetAttribute("IsPhasingActive") == true then
			phasingRefCount = math.max(0, phasingRefCount - 1)
			if phasingRefCount == 0 then
				disableWorldPhasing()
			end
		end
		setPhasing(char, false)
		AbilityCooldownHelper.apply(char, C.Phasing.ABILITY_ID, C.Phasing.COOLDOWN_SEC)
	end
end

local function clawRush(plr: Player, char: Model)
	local root = getRoot(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local cfg = C.ClawRush
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit

	char:SetAttribute("IsClawRushing", true)
	hum.PlatformStand = true
	for _ = 1, cfg.HITS do
		local endPos = root.Position + flat * (cfg.LUNGE_DIST / cfg.HITS)
		SmoothMotionHelper.runSmoothTravel(root, root.Position, endPos, 0.12, flat)
		AbilityVfxHelper.spawnDirectionalBurst(root.Position, flat, COLOR, 5, 0.15)
		AbilityCombatHelper.raycastHit(root.Position, flat, 5, char, {
			damage = cfg.DAMAGE,
			pushSpeed = cfg.PUSH_SPEED,
			pushUp = cfg.PUSH_UP,
			excludePlayer = plr,
		})
		task.wait(0.05)
	end
	hum.PlatformStand = false
	char:SetAttribute("IsClawRushing", nil)
end

local function findTarget(origin: Vector3, targetUserId: number?, exclude: Model): Model?
	if typeof(targetUserId) ~= "number" then
		return nil
	end
	for _, p in Players:GetPlayers() do
		if p.UserId == targetUserId then
			local c = p.Character
			if c and c ~= exclude then
				local r = getRoot(c)
				local h = c:FindFirstChildOfClass("Humanoid")
				if r and h and h.Health > 0 and (r.Position - origin).Magnitude <= C.ShadowPounce.MAX_RANGE then
					return c
				end
			end
			break
		end
	end
	return nil
end

local function shadowPounce(plr: Player, char: Model, targetUserId: number)
	local root = getRoot(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local target = findTarget(root.Position, targetUserId, char)
	if not target then
		return
	end
	local tRoot = getRoot(target)
	if not tRoot then
		return
	end

	local endPos = Vector3.new(tRoot.Position.X, tRoot.Position.Y, tRoot.Position.Z)
	char:SetAttribute("IsShadowPouncing", true)
	hum.PlatformStand = true
	SmoothMotionHelper.runSmoothTravel(root, root.Position, endPos, C.ShadowPounce.TRAVEL_DURATION, (endPos - root.Position).Unit)
	hum.PlatformStand = false
	char:SetAttribute("IsShadowPouncing", nil)

	AbilityVfxHelper.spawnGroundRing(endPos, COLOR, 2, C.ShadowPounce.LAND_RADIUS, 0.35)
	AbilityCombatHelper.hitInRadius(endPos, C.ShadowPounce.LAND_RADIUS, char, {
		damage = C.ShadowPounce.DAMAGE,
		pushSpeed = C.ShadowPounce.PUSH_SPEED,
		pushUp = C.ShadowPounce.PUSH_UP,
		excludePlayer = plr,
	})
end

local function normalizeLook(x: number, y: number, z: number, fallback: Vector3): Vector3
	local v = Vector3.new(x, y, z)
	if v.Magnitude < 0.01 then
		return fallback
	end
	return v.Unit
end

local function setWallAscension(plr: Player, active: boolean, lookX: number?, lookY: number?, lookZ: number?, moveX: number?, moveY: number?, moveZ: number?)
	local char = plr.Character
	if not char then
		return
	end
	if active then
		if not ResourceService.hasMinimum(char, CHAR_ID, C.WallAscension.ABILITY_ID) then
			return
		end
		if char:GetAttribute("IsWallAscensionActive") == true then
			local state = ascensionPlayers[plr]
			if state and lookX and lookY and lookZ then
				state.lookDir = normalizeLook(lookX, lookY, lookZ, state.lookDir)
			end
			if state and moveX and moveY and moveZ then
				state.moveDir = normalizeLook(moveX, moveY, moveZ, state.moveDir)
			end
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, C.WallAscension.ABILITY_ID) then
			return
		end
		local root = getRoot(char)
		local lookDir = if root then normalizeLook(lookX or 0, lookY or 0, lookZ or 0, root.CFrame.LookVector) else Vector3.new(0, 0, -1)
		local moveDir = normalizeLook(moveX or lookX or 0, moveY or lookY or 0, moveZ or lookZ or 0, lookDir)
		ascensionPlayers[plr] = {
			lookDir = lookDir,
			moveDir = moveDir,
		}
		char:SetAttribute("IsWallAscensionActive", true)
	else
		ascensionPlayers[plr] = nil
		char:SetAttribute("IsWallAscensionActive", nil)
		AbilityCooldownHelper.apply(char, C.WallAscension.ABILITY_ID, C.WallAscension.COOLDOWN_SEC)
	end
end

local function isInsideSolid(root: BasePart, char: Model): boolean
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char }
	local probe = Instance.new("Part")
	probe.Size = Vector3.new(1.5, 2.5, 1.5)
	probe.CFrame = root.CFrame
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = true
	probe.CanTouch = false
	probe.Transparency = 1
	probe.Parent = workspace
	local parts = workspace:GetPartsInPart(probe, overlap)
	probe:Destroy()
	for _, part in parts do
		if part:IsA("BasePart") and part.CanCollide and not shouldSkipWorldPart(part) then
			return true
		end
	end
	return false
end

local function disruptiveTouch(plr: Player, char: Model, lookX: number, lookY: number, lookZ: number)
	local root = getRoot(char)
	if not root then
		return
	end
	local cfg = C.DisruptiveTouch
	local look = Vector3.new(lookX, lookY, lookZ)
	if look.Magnitude < 0.01 then
		look = root.CFrame.LookVector
	else
		look = look.Unit
	end
	local endPos = root.Position + look * cfg.RANGE
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char }
	local best: Model? = nil
	local bestDist = cfg.RANGE + 1
	for _, part in workspace:GetPartBoundsInRadius(endPos, 4, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local tRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if tRoot then
					local dist = (tRoot.Position - root.Position).Magnitude
					if dist <= cfg.RANGE and dist < bestDist then
						bestDist = dist
						best = model
					end
				end
			end
		end
	end
	local hitPos = if best then (best :: Model):GetPivot().Position else endPos
	AbilityVfxHelper.spawnDirectionalBurst(hitPos, look, COLOR, 5, 0.2)
	if best then
		local hum = best:FindFirstChildOfClass("Humanoid")
		if hum then
			AbilityCombatHelper.damageAndPush(best, hum, getRoot(best) or root, look, {
				damage = cfg.DAMAGE,
				pushSpeed = cfg.PUSH_SPEED,
				pushUp = cfg.PUSH_UP,
			})
		end
	else
		AbilityCombatHelper.raycastHit(root.Position, look, cfg.RANGE, char, {
			damage = cfg.DAMAGE,
			pushSpeed = cfg.PUSH_SPEED,
			pushUp = cfg.PUSH_UP,
			excludePlayer = plr,
		})
	end
end

function ShadowcatAbilitiesService.setup(
	phasingRemote: RemoteEvent,
	clawRemote: RemoteEvent,
	pounceRemote: RemoteEvent,
	wallAscensionRemote: RemoteEvent,
	disruptiveTouchRemote: RemoteEvent
)
	ResourceService.registerStopCallback("IsPhasingActive", function(p)
		phasingPlayers[p] = nil
		local c = p.Character
		if c and c:GetAttribute("IsPhasingActive") == true then
			phasingRefCount = math.max(0, phasingRefCount - 1)
			if phasingRefCount == 0 then
				disableWorldPhasing()
			end
			setPhasing(c, false)
		end
	end)
	ResourceService.registerStopCallback("IsWallAscensionActive", function(p)
		setWallAscension(p, false)
	end)

	phasingRemote.OnServerEvent:Connect(function(plr, want: unknown)
		if not isShadowcat(plr) or typeof(want) ~= "boolean" then
			return
		end
		togglePhasing(plr, want)
	end)

	clawRemote.OnServerEvent:Connect(function(plr)
		if not isShadowcat(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.ClawRush.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 12) then
			return
		end
		AbilityCooldownHelper.apply(char, C.ClawRush.ABILITY_ID, C.ClawRush.COOLDOWN_SEC)
		task.spawn(function()
			clawRush(plr, char)
		end)
	end)

	pounceRemote.OnServerEvent:Connect(function(plr, targetUserId: unknown)
		if not isShadowcat(plr) or typeof(targetUserId) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.ShadowPounce.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 18) then
			return
		end
		AbilityCooldownHelper.apply(char, C.ShadowPounce.ABILITY_ID, C.ShadowPounce.COOLDOWN_SEC)
		task.spawn(function()
			shadowPounce(plr, char, targetUserId)
		end)
	end)

	wallAscensionRemote.OnServerEvent:Connect(function(plr, active: unknown, lookX: unknown, lookY: unknown, lookZ: unknown, moveX: unknown, moveY: unknown, moveZ: unknown)
		if not isShadowcat(plr) or typeof(active) ~= "boolean" then
			return
		end
		local lx = if typeof(lookX) == "number" then lookX else nil
		local ly = if typeof(lookY) == "number" then lookY else nil
		local lz = if typeof(lookZ) == "number" then lookZ else nil
		local mx = if typeof(moveX) == "number" then moveX else nil
		local my = if typeof(moveY) == "number" then moveY else nil
		local mz = if typeof(moveZ) == "number" then moveZ else nil
		setWallAscension(plr, active, lx, ly, lz, mx, my, mz)
	end)

	disruptiveTouchRemote.OnServerEvent:Connect(function(plr, lookX: unknown, lookY: unknown, lookZ: unknown)
		if not isShadowcat(plr) then
			return
		end
		if typeof(lookX) ~= "number" or typeof(lookY) ~= "number" or typeof(lookZ) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.DisruptiveTouch.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 14) then
			return
		end
		AbilityCooldownHelper.apply(char, C.DisruptiveTouch.ABILITY_ID, C.DisruptiveTouch.COOLDOWN_SEC)
		disruptiveTouch(plr, char, lookX, lookY, lookZ)
	end)
end

function ShadowcatAbilitiesService.update(_dt: number)
	for plr, state in ascensionPlayers do
		local char = plr.Character
		if not char or char:GetAttribute("IsWallAscensionActive") ~= true then
			ascensionPlayers[plr] = nil
			continue
		end
		local root = getRoot(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then
			continue
		end
		local phasing = char:GetAttribute("IsPhasingActive") == true
		local insideSolid = isInsideSolid(root, char)
		if phasing and insideSolid then
			local moveDir = state.moveDir
			if moveDir.Magnitude < 0.01 then
				moveDir = state.lookDir
			end
			root.AssemblyLinearVelocity = moveDir.Unit * C.WallAscension.PHASE_MOVE_SPEED
			hum.AutoRotate = false
			local flatLook = Vector3.new(state.lookDir.X, state.lookDir.Y, state.lookDir.Z)
			if flatLook.Magnitude > 0.01 then
				local targetCF = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
				root.CFrame = root.CFrame:Lerp(targetCF, 0.2)
			end
		elseif insideSolid then
			root.AssemblyLinearVelocity = Vector3.new(
				root.AssemblyLinearVelocity.X,
				C.WallAscension.ASCEND_SPEED,
				root.AssemblyLinearVelocity.Z
			)
		end
	end
end

function ShadowcatAbilitiesService.onPlayerRemoving(plr: Player)
	if phasingPlayers[plr] then
		phasingPlayers[plr] = nil
		phasingRefCount = math.max(0, phasingRefCount - 1)
		if phasingRefCount == 0 then
			disableWorldPhasing()
		end
	end
	ascensionPlayers[plr] = nil
end

return ShadowcatAbilitiesService
