--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InteractableHelper = require(ReplicatedStorage.Shared.InteractableHelper)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)

local MouseHelper = {}

local function getSoftLock()
	return require(script.Parent.SoftLockClient)
end

local function getRay(player: Player): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.new(0, 0, -1)
	end
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	return ray.Origin, ray.Direction
end

local function characterFromInstance(inst: Instance?, selfChar: Model?): Model?
	if not inst then
		return nil
	end
	local current: Instance? = inst
	while current do
		if current:IsA("Model") and current ~= selfChar then
			local hum = current:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function getCharacterRoot(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function distPointToRay(point: Vector3, origin: Vector3, dir: Vector3, range: number): number
	local to = point - origin
	local along = to:Dot(dir)
	if along < 0 or along > range then
		return math.huge
	end
	return (point - (origin + dir * along)).Magnitude
end

local function closestCharacterAlongRay(selfChar: Model?, origin: Vector3, dir: Vector3, range: number): Model?
	local best: Model? = nil
	local bestDist = 10
	local function consider(model: Model)
		if model == selfChar or not CombatHelper.isCombatEligible(model) then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end
		local root = getCharacterRoot(model)
		if not root then
			return
		end
		local d = distPointToRay(root.Position, origin, dir, range)
		if d < bestDist then
			bestDist = d
			best = model
		end
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			consider(plr.Character)
		end
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") then
			consider(child)
		end
	end
	return best
end

function MouseHelper.getWorldDirection(player: Player): Vector3
	local SoftLock = getSoftLock()
	local lockPoint = SoftLock.getLockedAimPoint()
	if lockPoint then
		local origin = getRay(player)
		local to = lockPoint - origin
		if to.Magnitude > 0.05 then
			return to.Unit
		end
	end
	local _, dir = getRay(player)
	if dir.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return dir.Unit
end

function MouseHelper.getHitPosition(player: Player, maxDist: number?): Vector3
	local SoftLock = getSoftLock()
	local lockPoint = SoftLock.getLockedAimPoint()
	if lockPoint then
		return lockPoint
	end

	local origin, dir = getRay(player)
	local range = maxDist or 500
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(origin, dir.Unit * range, params)
	if result then
		return result.Position
	end
	return origin + dir.Unit * range
end

function MouseHelper.getHoveredPart(player: Player, maxDist: number?): BasePart?
	local SoftLock = getSoftLock()
	local locked = SoftLock.getLockedTarget()
	if locked then
		local root = getCharacterRoot(locked)
		if root then
			return root
		end
	end

	local selfChar = player.Character
	local range = maxDist or 70
	local mouse = player:GetMouse()
	if mouse.Target and mouse.Target:IsA("BasePart") then
		local part = mouse.Target
		if not selfChar or not part:IsDescendantOf(selfChar) then
			return part
		end
	end
	local origin, dir = getRay(player)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if selfChar then
		params.FilterDescendantsInstances = { selfChar }
	end
	local result = workspace:Raycast(origin, dir.Unit * range, params)
	if result and result.Instance:IsA("BasePart") then
		return result.Instance
	end
	return nil
end

function MouseHelper.getHoveredCharacter(player: Player, maxDist: number?): Model?
	local SoftLock = getSoftLock()
	local locked = SoftLock.getLockedTarget()
	if locked and locked.Parent and CombatHelper.isCombatEligible(locked) then
		return locked
	end

	local selfChar = player.Character
	local range = maxDist or 200
	local casterRoot = if selfChar then getCharacterRoot(selfChar) else nil
	local origin, dir = getRay(player)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end

	local mouse = player:GetMouse()
	local fromMouse = characterFromInstance(mouse.Target, selfChar)
	if fromMouse and CombatHelper.isCombatEligible(fromMouse) then
		local root = getCharacterRoot(fromMouse)
		if root then
			if not casterRoot or (root.Position - casterRoot.Position).Magnitude <= range then
				return fromMouse
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if selfChar then
		params.FilterDescendantsInstances = { selfChar }
	end
	local sphere = workspace:Spherecast(origin, 8, dir * range, params)
	local fromSphere = characterFromInstance(if sphere then sphere.Instance else nil, selfChar)
	if fromSphere and CombatHelper.isCombatEligible(fromSphere) then
		return fromSphere
	end

	local along = closestCharacterAlongRay(selfChar, origin, dir, range)
	if along then
		return along
	end

	local result = workspace:Raycast(origin, dir * range, params)
	local fromRay = characterFromInstance(if result then result.Instance else nil, selfChar)
	if fromRay and CombatHelper.isCombatEligible(fromRay) then
		return fromRay
	end
	return nil
end

function MouseHelper.getDirectHoveredCharacter(player: Player, maxDist: number?): Model?
	local selfChar = player.Character
	local range = maxDist or 200
	local casterRoot = if selfChar then getCharacterRoot(selfChar) else nil
	local mouse = player:GetMouse()
	local fromMouse = characterFromInstance(mouse.Target, selfChar)
	if fromMouse and CombatHelper.isCombatEligible(fromMouse) then
		local root = getCharacterRoot(fromMouse)
		if root then
			if not casterRoot or (root.Position - casterRoot.Position).Magnitude <= range then
				return fromMouse
			end
		end
	end
	local origin, dir = getRay(player)
	if dir.Magnitude < 0.01 then
		return nil
	end
	dir = dir.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if selfChar then
		params.FilterDescendantsInstances = { selfChar }
	end
	local result = workspace:Raycast(origin, dir * range, params)
	local fromRay = characterFromInstance(if result then result.Instance else nil, selfChar)
	if fromRay and CombatHelper.isCombatEligible(fromRay) then
		return fromRay
	end
	return nil
end

function MouseHelper.getHoveredInteractable(player: Player, maxDist: number?): Instance?
	local selfChar = player.Character
	local origin, dir = getRay(player)
	return InteractableHelper.raycast(origin, dir, maxDist or 70, selfChar)
end

return MouseHelper
