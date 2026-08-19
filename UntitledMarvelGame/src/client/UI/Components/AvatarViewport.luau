--!strict

local Players = game:GetService("Players")

local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDTheme"))

export type AvatarViewportHandle = {
	Frame: Frame,
	Refresh: (self: AvatarViewportHandle, player: Player) -> (),
}

local AvatarViewport = {}

local function stripScripts(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
end

local function buildDisplayModel(player: Player): Model?
	local character = player.Character
	if character then
		local wasArchivable = character.Archivable
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = wasArchivable
		if clone then
			return clone
		end
	end

	local ok, model = pcall(Players.CreateHumanoidModelFromUserId, Players, player.UserId)
	if ok and model and model:IsA("Model") then
		return model
	end

	return nil
end

local function frameModel(camera: Camera, model: Model)
	local cf, size = model:GetBoundingBox()
	local focus = cf.Position + Vector3.new(0, size.Y * 0.12, 0)

	local distance = math.max(size.X, size.Y) * 0.72
	local sideOffset = size.X * 0.38
	local heightOffset = size.Y * 0.18
	local cameraPos = focus + Vector3.new(sideOffset, heightOffset, distance)

	camera.CFrame = CFrame.new(cameraPos, focus)
end

function AvatarViewport.create(parent: Instance): AvatarViewportHandle
	local container = Instance.new("Frame")
	container.Name = "AvatarViewport"
	container.BackgroundColor3 = Theme.PanelBg
	container.BackgroundTransparency = Theme.PanelBgTransparency
	container.BorderSizePixel = 0
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromScale(0.94, 0.94)
	container.ClipsDescendants = true
	container.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Stroke
	stroke.Transparency = Theme.StrokeTransparency
	stroke.Thickness = 2
	stroke.Parent = container

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	viewport.BackgroundTransparency = 0.2
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Parent = container

	local viewportCorner = Instance.new("UICorner")
	viewportCorner.CornerRadius = UDim.new(1, 0)
	viewportCorner.Parent = viewport

	local viewportStroke = Instance.new("UIStroke")
	viewportStroke.Color = Color3.fromRGB(28, 32, 40)
	viewportStroke.Transparency = 0.35
	viewportStroke.Thickness = 1
	viewportStroke.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local ambient = Instance.new("Part")
	ambient.Name = "ViewportLight"
	ambient.Anchored = true
	ambient.CanCollide = false
	ambient.Transparency = 1
	ambient.Size = Vector3.new(1, 1, 1)
	ambient.CFrame = CFrame.new(2, 4, 4)
	ambient.Parent = worldModel

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 20
	light.Parent = ambient

	local currentClone: Model? = nil

	local handle: AvatarViewportHandle = {
		Frame = container,
		Refresh = function(_self, player: Player)
			if currentClone then
				currentClone:Destroy()
				currentClone = nil
			end

			local clone = buildDisplayModel(player)
			if not clone then
				return
			end

			currentClone = clone
			stripScripts(clone)

			local hrp = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0))
			else
				clone:MoveTo(Vector3.zero)
			end

			clone.Parent = worldModel
			frameModel(camera, clone)
		end,
	}

	return handle
end

return AvatarViewport
