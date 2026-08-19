--!strict

local RunService = game:GetService("RunService")

local ViewportHelper = {}

local bindings: { [ViewportFrame]: { character: Model, conn: RBXScriptConnection? } } = {}

local function stripScripts(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
end

local function updateViewportCamera(viewport: ViewportFrame, character: Model, worldCamera: Camera)
	local clone = viewport:FindFirstChildWhichIsA("Model")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cloneRoot = if clone then clone:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local vpCamera = viewport.CurrentCamera
	if not root or not clone or not cloneRoot or not vpCamera then
		return
	end

	local _, rotation = root.CFrame:ToOrientation()
	clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.fromOrientation(rotation))
	local localCam = root.CFrame:ToObjectSpace(worldCamera.CFrame)
	vpCamera.CFrame = cloneRoot.CFrame * localCam
end

function ViewportHelper.bindCharacter(viewport: ViewportFrame, character: Model?)
	if bindings[viewport] and bindings[viewport].conn then
		bindings[viewport].conn:Disconnect()
		bindings[viewport] = nil
	end

	for _, child in viewport:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end

	if not character or not character.Parent or not character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local ok, clone = pcall(function()
		return character:Clone()
	end)
	if not ok or not clone or not clone:IsA("Model") then
		return
	end

	stripScripts(clone)

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	clone.Parent = viewport

	local conn = RunService.RenderStepped:Connect(function()
		if not character.Parent then
			return
		end
		local worldCamera = workspace.CurrentCamera
		if worldCamera then
			updateViewportCamera(viewport, character, worldCamera)
		end
	end)

	bindings[viewport] = { character = character, conn = conn }
	updateViewportCamera(viewport, character, workspace.CurrentCamera :: Camera)
end

function ViewportHelper.unbind(viewport: ViewportFrame)
	if bindings[viewport] and bindings[viewport].conn then
		bindings[viewport].conn:Disconnect()
	end
	bindings[viewport] = nil
end

return ViewportHelper
