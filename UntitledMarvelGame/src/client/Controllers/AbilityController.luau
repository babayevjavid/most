--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ProjectileSteerClient = require(script.Parent.Parent.ProjectileSteerClient)

local AbilityController = {}

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local useAbilityRemote = remotesFolder:WaitForChild(Remotes.UseAbility) :: RemoteEvent
local cooldownRemote = remotesFolder:WaitForChild(Remotes.CooldownUpdate) :: RemoteEvent

local STEERED_BASICS: { [string]: boolean } = {
	ChaosBlast = true,
}

local currentHeroId: string? = nil
local abilityLayout: any = nil
local onCooldownUpdate: ((abilityId: string, duration: number) -> ())? = nil

function AbilityController.setup(hudCooldownCallback: (abilityId: string, duration: number) -> ())
	onCooldownUpdate = hudCooldownCallback

	cooldownRemote.OnClientEvent:Connect(function(abilityId: string, duration: number)
		if onCooldownUpdate then
			onCooldownUpdate(abilityId, duration)
		end
	end)
end

function AbilityController.setHero(heroId: string, layout: any)
	currentHeroId = heroId
	abilityLayout = layout
end

function AbilityController.clearHero()
	currentHeroId = nil
	abilityLayout = nil
end

function AbilityController.hasHero(): boolean
	return currentHeroId ~= nil
end

function AbilityController.getBasicId(): string?
	if not abilityLayout then
		return nil
	end
	return abilityLayout.basic.Id
end

function AbilityController.getAbilityIdForSlot(slotIndex: number): string?
	if not abilityLayout then
		return nil
	end
	local def = abilityLayout.abilities[slotIndex]
	return if def then def.Id else nil
end

function AbilityController.getMovementId(): string?
	if not abilityLayout then
		return nil
	end
	return abilityLayout.movement.Id
end

local function getCameraAimDirection(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.new(0, 0, -1)
	end
	return camera.CFrame.LookVector
end

function AbilityController.fire(abilityId: string)
	if not currentHeroId then
		return
	end

	if STEERED_BASICS[abilityId] then
		local player = Players.LocalPlayer
		local char = player.Character
		if not char then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		local aim = ProjectileSteerClient.getAimWorldPos(char, 300)
		local dir = if aim then (aim - root.Position) else getCameraAimDirection()
		if dir.Magnitude < 0.01 then
			dir = getCameraAimDirection()
		end
		dir = dir.Unit

		local token = ProjectileSteerClient.generateSteerToken()
		useAbilityRemote:FireServer(abilityId, dir.X, dir.Y, dir.Z, token)
		ProjectileSteerClient.beginMouseSteerSession(token)
		return
	end

	local aim = getCameraAimDirection()
	useAbilityRemote:FireServer(abilityId, aim.X, aim.Y, aim.Z)
end

return AbilityController
