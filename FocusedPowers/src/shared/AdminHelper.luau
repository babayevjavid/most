--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AdminConstants"))

local AdminHelper = {}

local userIdSet: { [number]: boolean } = {}
for _, id in AdminConstants.USER_IDS do
	if typeof(id) == "number" then
		userIdSet[id] = true
	end
end

function AdminHelper.isAdmin(player: Player): boolean
	if AdminConstants.STUDIO_GRANTS_ADMIN and RunService:IsStudio() then
		return true
	end
	if AdminConstants.CREATOR_IS_ADMIN then
		local creatorId = game.CreatorId
		if creatorId > 0 and player.UserId == creatorId then
			return true
		end
	end
	return userIdSet[player.UserId] == true
end

function AdminHelper.isAdminUserId(userId: number): boolean
	if AdminConstants.STUDIO_GRANTS_ADMIN and RunService:IsStudio() then
		return true
	end
	if AdminConstants.CREATOR_IS_ADMIN then
		local creatorId = game.CreatorId
		if creatorId > 0 and userId == creatorId then
			return true
		end
	end
	return userIdSet[userId] == true
end

function AdminHelper.tagPlayer(player: Player)
	player:SetAttribute("IsAdmin", AdminHelper.isAdmin(player))
end

function AdminHelper.tagAllPlayers()
	for _, player in Players:GetPlayers() do
		AdminHelper.tagPlayer(player)
	end
end

return AdminHelper
