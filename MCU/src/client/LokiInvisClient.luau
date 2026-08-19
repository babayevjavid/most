--!strict
--[[
	Loki invisibility (God of Mischief):
	- Server already sets real Transparency = 1 (invisible everywhere including Studio server).
	- Local Loki: ghost silhouette so the caster can still see themselves.
	- Everyone else: keep fully invisible / FX off.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local LokiInvisClient = {}

local LOCAL_GHOST = 0.55

local function applyToInstance(desc: Instance, isLocal: boolean, on: boolean)
	if desc:IsA("BasePart") then
		if on then
			desc.LocalTransparencyModifier = 0
			if isLocal then
				desc.Transparency = if desc.Name == "HumanoidRootPart" then 1 else LOCAL_GHOST
			else
				desc.Transparency = 1
			end
		else
			desc.LocalTransparencyModifier = 0
			-- Server restores real transparencies; don't fight replication here.
		end
	elseif desc:IsA("Decal") or desc:IsA("Texture") then
		if on then
			if isLocal then
				if desc:GetAttribute("LokiInvisLocalOrigT") == nil then
					desc:SetAttribute("LokiInvisLocalOrigT", desc.Transparency)
				end
				desc.Transparency = LOCAL_GHOST
			else
				desc.Transparency = 1
			end
		else
			local orig = desc:GetAttribute("LokiInvisLocalOrigT")
			if type(orig) == "number" then
				desc.Transparency = orig
				desc:SetAttribute("LokiInvisLocalOrigT", nil)
			end
		end
	elseif desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Fire") or desc:IsA("Smoke") then
		if on then
			if desc:GetAttribute("LokiInvisWasEnabled") == nil then
				desc:SetAttribute("LokiInvisWasEnabled", desc.Enabled)
			end
			desc.Enabled = false
		else
			local was = desc:GetAttribute("LokiInvisWasEnabled")
			if typeof(was) == "boolean" then
				desc.Enabled = was
				desc:SetAttribute("LokiInvisWasEnabled", nil)
			end
		end
	elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
		desc.Enabled = not on
	elseif desc:IsA("Highlight") then
		desc.Enabled = not on
	elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
		if on then
			if desc:GetAttribute("LokiInvisWasEnabled") == nil then
				desc:SetAttribute("LokiInvisWasEnabled", desc.Enabled)
			end
			desc.Enabled = false
		else
			local was = desc:GetAttribute("LokiInvisWasEnabled")
			if typeof(was) == "boolean" then
				desc.Enabled = was
				desc:SetAttribute("LokiInvisWasEnabled", nil)
			end
		end
	end
end

local function applyInvis(character: Model, isLocal: boolean, on: boolean)
	for _, desc in character:GetDescendants() do
		applyToInstance(desc, isLocal, on)
	end
end

local function hookCharacter(player: Player, character: Model)
	local isLocal = player == Players.LocalPlayer

	local function refresh()
		local on = character:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) == true
		applyInvis(character, isLocal, on)
	end

	refresh()
	character:GetAttributeChangedSignal(GameConstants.LOKI_INVISIBLE_ATTRIBUTE):Connect(refresh)

	character.DescendantAdded:Connect(function(desc)
		local on = character:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) == true
		if on then
			-- Defer so server invis attrs apply first, then local ghost override
			task.defer(function()
				if character.Parent and character:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) == true then
					applyToInstance(desc, isLocal, true)
				end
			end)
		end
	end)
end

function LokiInvisClient.init(localPlayer: Player)
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			hookCharacter(player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
end

return LokiInvisClient
