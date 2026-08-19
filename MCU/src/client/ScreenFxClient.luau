--!strict
--[[
	Clone UIEffects folders (JeanUI, PhoenixForceUI, InvisWomanUI, ScarletWitchUI)
	and keep the root BasePart on the camera. Emitters stay parented as authored.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientSettings = require(script.Parent.ClientSettings)

local ScreenFxClient = {}

local FOLDER_BY_KIND: { [string]: string } = {
	jean = "JeanUI",
	phoenix = "PhoenixForceUI",
	invisible_woman = "InvisWomanUI",
	scarlet_witch = "ScarletWitchUI",
}

local CAM_OFFSET = CFrame.new(0, 0, -3.2)
local CAM_OFFSET_BY_KIND: { [string]: CFrame } = {
	scarlet_witch = CFrame.new(0, 0, -2.8),
}

type Layer = {
	root: Instance,
	host: BasePart,
	wanted: boolean,
	emitters: { ParticleEmitter },
}

local layers: { [string]: Layer } = {}
local bound = false

local function collectEmitters(root: Instance): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	if root:IsA("ParticleEmitter") then
		table.insert(list, root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			table.insert(list, desc)
		end
	end
	return list
end

local function getTemplate(folderName: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets") or ReplicatedStorage:WaitForChild("Assets", 12)
	if not assets then
		return nil
	end
	local ui = assets:FindFirstChild("UIEffects") or assets:WaitForChild("UIEffects", 8)
	if ui then
		return ui:FindFirstChild(folderName)
	end
	return nil
end

local function hardenPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	if part.Transparency < 1 then
		part.Transparency = 1
	end
end

local function resolvePart(clone: Instance): BasePart?
	if clone:IsA("BasePart") then
		return clone
	end
	if clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		return primary
	end
	return clone:FindFirstChildWhichIsA("BasePart", true)
end

local function parentToCamera(inst: Instance)
	local cam = Workspace.CurrentCamera
	inst.Parent = cam or Workspace
end

local function ensureLayer(kind: string): Layer?
	local existing = layers[kind]
	if existing and existing.host.Parent then
		return existing
	end
	local folderName = FOLDER_BY_KIND[kind]
	if not folderName then
		return nil
	end
	local template = getTemplate(folderName)
	if not template then
		warn("[ScreenFx] Missing ReplicatedStorage.Assets.UIEffects." .. folderName)
		return nil
	end

	local clone = template:Clone()
	clone.Name = "MCU_ScreenFx_" .. kind
	local host = resolvePart(clone)
	if not host then
		warn("[ScreenFx] " .. folderName .. " has no BasePart")
		clone:Destroy()
		return nil
	end

	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			hardenPart(desc)
		end
	end
	hardenPart(host)
	parentToCamera(clone)

	for _, em in collectEmitters(clone) do
		em.Enabled = false
	end

	local layer: Layer = {
		root = clone,
		host = host,
		wanted = false,
		emitters = collectEmitters(clone),
	}
	layers[kind] = layer
	return layer
end

local function setEmittersEnabled(layer: Layer, enabled: boolean)
	local mul = ClientSettings.getParticleMul()
	for _, em in layer.emitters do
		if em.Parent then
			em.Enabled = enabled and ClientSettings.isScreenVfxEnabled()
			if em.Enabled and mul < 1 then
				em.Rate = math.max(1, em.Rate * mul)
			end
		end
	end
end

local function ensureLoop()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep("MCU_ScreenFx", Enum.RenderPriority.Camera.Value + 3, function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		for kind, layer in layers do
			local cf = cam.CFrame * (CAM_OFFSET_BY_KIND[kind] or CAM_OFFSET)
			if layer.root.Parent ~= cam then
				layer.root.Parent = cam
			end
			if layer.root:IsA("Model") then
				(layer.root :: Model):PivotTo(cf)
			else
				layer.host.CFrame = cf
			end
		end
	end)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		for _, layer in layers do
			layer.root.Parent = cam
		end
	end)
end

function ScreenFxClient.setTint(kind: string, color: Color3)
	local layer = ensureLayer(kind)
	if not layer then
		return
	end
	local seq = ColorSequence.new(color)
	for _, em in layer.emitters do
		if em.Parent then
			em.Color = seq
		end
	end
end

function ScreenFxClient.setEnabled(kind: string, enabled: boolean)
	if enabled and not ClientSettings.isScreenVfxEnabled() then
		return
	end
	ensureLoop()
	local layer = ensureLayer(kind)
	if not layer then
		return
	end
	if layer.wanted == enabled then
		return
	end
	layer.wanted = enabled
	setEmittersEnabled(layer, enabled)
end

function ScreenFxClient.pulse(kind: string)
	ScreenFxClient.setEnabled(kind, true)
end

function ScreenFxClient.clear()
	for kind, layer in layers do
		layer.wanted = false
		setEmittersEnabled(layer, false)
		if layer.root.Parent then
			layer.root:Destroy()
		end
		layers[kind] = nil
	end
end

ClientSettings.onChanged(function()
	if not ClientSettings.isScreenVfxEnabled() then
		ScreenFxClient.clear()
	end
end)

return ScreenFxClient
