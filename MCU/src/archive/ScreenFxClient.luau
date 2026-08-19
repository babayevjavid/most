--!strict
--[[
	Camera-locked copies of Assets.UIEffects (JeanUI / InvisWomanUI).
	Particles sit in front of the camera like a screen overlay.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScreenFxClient = {}

local FOLDER_BY_KIND: { [string]: string } = {
	jean = "JeanUI",
	invisible_woman = "InvisWomanUI",
}

local CAM_OFFSET = CFrame.new(0, 0, -3.1)
local FADE = 0.42

type Layer = {
	host: BasePart,
	root: Instance,
	wanted: boolean,
	token: number,
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
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UIEffects")
	return ui and ui:FindFirstChild(folderName)
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

local function parentToCamera(inst: Instance)
	local cam = Workspace.CurrentCamera
	if cam then
		inst.Parent = cam
	else
		inst.Parent = Workspace
	end
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
		return nil
	end

	local host = Instance.new("Part")
	host.Name = "MCU_ScreenFx_" .. kind
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	hardenPart(host)
	parentToCamera(host)

	local clone = template:Clone()
	clone.Name = "Fx"
	if clone:IsA("BasePart") then
		hardenPart(clone)
		clone.CFrame = host.CFrame
		clone.Parent = host
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = host
		weld.Part1 = clone
		weld.Parent = host
	elseif clone:IsA("Model") then
		clone.Parent = host
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				hardenPart(desc)
			end
		end
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			if not clone.PrimaryPart then
				clone.PrimaryPart = primary
			end
			clone:PivotTo(host.CFrame)
		end
	elseif clone:IsA("Folder") or clone:IsA("Attachment") then
		clone.Parent = host
		if clone:IsA("Attachment") then
			(clone :: Attachment).CFrame = CFrame.identity
		end
		for _, child in clone:GetChildren() do
			if child:IsA("Attachment") then
				child.Parent = host
			elseif child:IsA("ParticleEmitter") then
				child.Parent = host
			elseif child:IsA("BasePart") then
				hardenPart(child)
				child.Parent = host
			end
		end
	else
		clone.Parent = host
	end

	local emitters = collectEmitters(host)
	for _, em in emitters do
		em:SetAttribute("ScreenFxOrigRate", em.Rate)
		em.Enabled = false
		em.Rate = 0
	end

	local layer: Layer = {
		host = host,
		root = clone,
		wanted = false,
		token = 0,
		emitters = emitters,
	}
	layers[kind] = layer
	return layer
end

local function fadeEmitters(layer: Layer, enabled: boolean)
	layer.token += 1
	local token = layer.token
	local t0 = os.clock()
	if enabled then
		for _, em in layer.emitters do
			if em.Parent then
				local orig = em:GetAttribute("ScreenFxOrigRate")
				local target = if type(orig) == "number" then orig else em.Rate
				if target <= 0 then
					target = 12
				end
				em.Enabled = true
				em.Rate = 0
				task.spawn(function()
					while em.Parent and layer.token == token and (os.clock() - t0) < FADE do
						local a = math.clamp((os.clock() - t0) / FADE, 0, 1)
						em.Rate = target * a
						task.wait()
					end
					if em.Parent and layer.token == token then
						em.Rate = target
						em.Enabled = true
					end
				end)
			end
		end
	else
		for _, em in layer.emitters do
			if em.Parent then
				local startRate = em.Rate
				task.spawn(function()
					while em.Parent and layer.token == token and (os.clock() - t0) < FADE do
						local a = math.clamp((os.clock() - t0) / FADE, 0, 1)
						em.Rate = startRate * (1 - a)
						task.wait()
					end
					if em.Parent and layer.token == token then
						em.Rate = 0
						em.Enabled = false
					end
				end)
			end
		end
	end
end

local function ensureLoop()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep("MCU_ScreenFx", Enum.RenderPriority.Camera.Value + 4, function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local cf = cam.CFrame * CAM_OFFSET
		for _, layer in layers do
			if layer.host.Parent ~= cam then
				layer.host.Parent = cam
			end
			layer.host.CFrame = cf
			if layer.root:IsA("Model") and layer.root.Parent then
				(layer.root :: Model):PivotTo(cf)
			end
		end
	end)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		for _, layer in layers do
			layer.host.Parent = cam
		end
	end)
end

function ScreenFxClient.setEnabled(kind: string, enabled: boolean)
	ensureLoop()
	local layer = ensureLayer(kind)
	if not layer then
		return
	end
	if layer.wanted == enabled then
		return
	end
	layer.wanted = enabled
	fadeEmitters(layer, enabled)
end

function ScreenFxClient.clear()
	for kind, layer in layers do
		layer.wanted = false
		fadeEmitters(layer, false)
		task.delay(FADE + 0.05, function()
			if layers[kind] == layer and not layer.wanted and layer.host.Parent then
				layer.host:Destroy()
				layers[kind] = nil
			end
		end)
	end
end

return ScreenFxClient
