local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local bendingModule = ReplicatedStorage:WaitForChild("BendingUI", 30)
if not bendingModule or not bendingModule:IsA("ModuleScript") then
	warn(
		"[Bending] Missing ReplicatedStorage.BendingUI (ModuleScript). "
			.. "Use Rojo: connect the plugin to `rojo serve`, or open a file built with `rojo build`."
	)
	return
end

local ok, BendingUI = pcall(require, bendingModule)
if not ok then
	warn("[Bending] require(BendingUI) failed:", BendingUI)
	return
end

print(
	"[Bending] HUD starting — run `rojo serve` from the **Bending** folder (not the parent RobloxCursor folder), then sync the plugin."
)

local ui = BendingUI.new()

local waterTm = ReplicatedStorage:WaitForChild("WaterTidemend", 30)
if waterTm and waterTm:IsA("ModuleScript") then
	local okWt, WD = pcall(require, waterTm)
	if okWt then
		WD.start(player, ui)
	else
		warn("[Bending] require(WaterTidemend) failed:", WD)
	end
else
	warn("[Bending] Missing ReplicatedStorage.WaterTidemend (ModuleScript). Add it via Rojo or sync.")
end

local function onCharacter(character: Model)
	ui:BindCharacter(character)
	ui:ShowElementPicker(function(elementId: string, subLabel: string)
		character:SetAttribute("BendingElement", elementId)
		character:SetAttribute("BendingSub", subLabel)
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end
