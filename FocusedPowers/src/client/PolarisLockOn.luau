--!strict
--[[ Lock-on reticle for single-target Polaris abilities (client-only). ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

local LOCK_ON_IMAGE = "rbxassetid://262619584"

local PolarisLockOn = {}

local activeBillboard: BillboardGui? = nil
local activeAdornee: Instance? = nil

local function destroyBillboard()
	if activeBillboard then
		activeBillboard:Destroy()
		activeBillboard = nil
	end
	activeAdornee = nil
end

local function getAttachPart(adornee: Instance): (BasePart?, Vector3)
	if adornee:IsA("BasePart") then
		return adornee, Vector3.zero
	end
	if adornee:IsA("Model") then
		local attach = adornee:FindFirstChild("HumanoidRootPart") :: BasePart?
			or adornee:FindFirstChild("Head") :: BasePart?
			or adornee:FindFirstChildWhichIsA("BasePart")
		if not attach then
			return nil, Vector3.zero
		end
		local cf, _size = adornee:GetBoundingBox()
		local centerOffset = attach.CFrame:PointToObjectSpace(cf.Position)
		return attach, centerOffset
	end
	return nil, Vector3.zero
end

function PolarisLockOn.setTarget(adornee: Instance?)
	if adornee == activeAdornee and activeBillboard then
		return
	end
	destroyBillboard()
	if not adornee then
		return
	end

	local attachPart, studsOffset = getAttachPart(adornee)
	if not attachPart then
		return
	end

	local size = HudConstants.LOCK_ON_CURSOR_SIZE
	local bb = Instance.new("BillboardGui")
	bb.Name = "PolarisLockOn"
	bb.Adornee = attachPart
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Size = UDim2.fromOffset(size, size)
	bb.StudsOffset = studsOffset
	bb.ResetOnSpawn = false
	bb.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local icon = Instance.new("ImageLabel")
	icon.Name = "Cursor"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Image = LOCK_ON_IMAGE
	icon.ImageColor3 = Color3.new(1, 1, 1)
	icon.ImageTransparency = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = bb

	activeBillboard = bb
	activeAdornee = adornee
end

function PolarisLockOn.clear()
	destroyBillboard()
end

return PolarisLockOn
