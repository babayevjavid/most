--!strict

local StarterGui = game:GetService("StarterGui")

local StarterGuiUtil = {}

local function asClass(inst: Instance?, className: string): Instance?
	if inst and inst:IsA(className) then
		return inst
	end
	return nil
end

function StarterGuiUtil.find(parent: Instance, name: string, className: string, recursive: boolean?): any?
	return asClass(parent:FindFirstChild(name, recursive == true), className)
end

function StarterGuiUtil.createFreshScreenGui(playerGui: PlayerGui, name: string, displayOrder: number?): ScreenGui
	local starter = StarterGui:FindFirstChild(name)
	if starter and starter:IsA("ScreenGui") then
		starter.Enabled = false
		starter.ResetOnSpawn = false
		pcall(function()
			starter:Destroy()
		end)
	end
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	gui.Enabled = false
	gui.Parent = playerGui
	return gui
end

function StarterGuiUtil.child(parent: Instance, name: string, className: string): any
	local inst = StarterGuiUtil.find(parent, name, className)
	if inst then
		return inst
	end
	local waited = parent:WaitForChild(name, 2)
	inst = asClass(waited, className)
	if not inst then
		error(`[StarterGui] Expected {className} '{name}' under {parent:GetFullName()}`)
	end
	return inst
end

function StarterGuiUtil.ensureFrame(parent: Instance, name: string): Frame
	local existing = StarterGuiUtil.find(parent, name, "Frame")
	if existing then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	return frame
end

function StarterGuiUtil.statBar(barsColumn: Frame, barName: string): (TextLabel?, Frame?)
	local row = StarterGuiUtil.find(barsColumn, barName .. "Row", "Frame")
		or StarterGuiUtil.find(barsColumn, barName, "Frame")
	if not row then
		return nil, nil
	end
	local track = StarterGuiUtil.find(row, "Track", "Frame") or row
	local fill = StarterGuiUtil.find(track, "Fill", "Frame") or StarterGuiUtil.find(row, "Fill", "Frame")
	local label = track:FindFirstChildWhichIsA("TextLabel") or row:FindFirstChildWhichIsA("TextLabel")
	if not fill or not fill:IsA("Frame") then
		return nil, nil
	end
	return label :: TextLabel?, fill
end

function StarterGuiUtil.ensureStatBar(barsColumn: Frame, barName: string): (TextLabel, Frame)
	local label, fill = StarterGuiUtil.statBar(barsColumn, barName)
	if label and fill then
		return label, fill
	end
	local row = StarterGuiUtil.ensureFrame(barsColumn, barName .. "Row")
	row.Visible = true
	row.Size = UDim2.new(1, 0, 0.28, 0)
	local track = StarterGuiUtil.ensureFrame(row, "Track")
	track.Visible = true
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.2
	fill = StarterGuiUtil.ensureFrame(track, "Fill")
	fill.Visible = true
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 70, 80)
	local existingLabel = track:FindFirstChildWhichIsA("TextLabel")
	if existingLabel then
		label = existingLabel
	else
		label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = barName
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Parent = track
	end
	return label, fill
end

return StarterGuiUtil
