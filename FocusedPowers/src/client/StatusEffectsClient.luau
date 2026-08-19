--!strict
--[[
	Applies debuff attributes to local movement.
]]

local Players = game:GetService("Players")

local StatusEffectsClient = {}
function StatusEffectsClient.start(player: Player)
	local baseSpeed = 16
	local conns: { RBXScriptConnection } = {}

	local function clearConns()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end

	local function applySpeed(char: Model)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		if baseSpeed <= 0 then
			baseSpeed = hum.WalkSpeed
		end
		local terror = char:GetAttribute("TerrorVeilSlow")
		local blind = char:GetAttribute("BlindingFlashSlow")
		local mult = 1
		if typeof(terror) == "number" then
			mult = math.min(mult, terror)
		end
		if typeof(blind) == "number" then
			mult = math.min(mult, blind)
		end
		if char:GetAttribute("HexSlow") == true then
			mult = math.min(mult, 0.5)
		end
		if char:GetAttribute("DarkBound") == true or char:GetAttribute("Frozen") == true then
			mult = 0
		end
		hum.WalkSpeed = baseSpeed * mult
	end

	local function bindCharacter(char: Model)
		clearConns()
		baseSpeed = 16
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if hum then
			baseSpeed = hum.WalkSpeed
		end
		for _, attr in { "TerrorVeilSlow", "BlindingFlashSlow", "DarkBound", "Frozen", "HexSlow" } do
			table.insert(conns, char:GetAttributeChangedSignal(attr):Connect(function()
				applySpeed(char)
			end))
		end
		applySpeed(char)
	end

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

return StatusEffectsClient
