-- Client-only Tidemend (water slot 4): Shift or key 4 + LMB on tagged water pulls; LMB again launches toward cursor while modifier active.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local WATER_TAG = "BendingWater"
local TIDEMEND_SLOT = 4
local MAX_PULL_RANGE = 92
local PULL_DURATION_SEC = 0.45
local MAX_LAUNCH_RANGE = 220
local ORB_RADIUS = 0.55

type UIBinding = {
	SetAbilitySlotFeedback: (self: UIBinding, index: number, mode: string) -> (),
	IsPickerOpen: (self: UIBinding) -> boolean,
	ConnectAbilitySlot: (self: UIBinding, index: number, handler: () -> ()) -> RBXScriptConnection,
}

local function isBlockingGuiClick(pg: Instance?, guiAt: { Instance })
	if not pg then
		return false
	end
	for _, inst in guiAt do
		if inst:IsDescendantOf(pg) and inst:IsA("GuiObject") then
			local go = inst :: GuiObject
			if go.Active and go.Visible and go:IsA("GuiButton") then
				return true
			end
		end
	end
	return false
end

local function modifierKeysDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.Four)
end

local function isWaterSurface(result: RaycastResult): boolean
	if not result then
		return false
	end
	if result.Material == Enum.Material.Water then
		return true
	end
	local inst = result.Instance
	if not inst or not inst:IsA("BasePart") then
		return false
	end
	if inst:GetAttribute("BendingWaterSurface") == true then
		return true
	end
	if CollectionService:HasTag(inst, WATER_TAG) then
		return true
	end
	return false
end

local function cameraMouseRay(): (Vector3?, Vector3?)
	local cam = workspace.CurrentCamera
	if not cam then
		return nil, nil
	end
	local m = UserInputService:GetMouseLocation()
	local r = cam:ViewportPointToRay(m.X, m.Y)
	return r.Origin, r.Direction
end

local function raycastWorld(origin: Vector3, direction: Vector3, params: RaycastParams, maxDist: number): RaycastResult?
	return workspace:Raycast(origin, direction * maxDist, params)
end

local function makeRayParams(character: Model): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { character }
	p.IgnoreWater = false
	return p
end

local function launchTargetPoint(origin: Vector3, direction: Vector3, character: Model): Vector3
	local params = makeRayParams(character)
	local hit = raycastWorld(origin, direction, params, MAX_LAUNCH_RANGE)
	if hit then
		return hit.Position
	end
	return origin + direction.Unit * MAX_LAUNCH_RANGE
end

return {
	TIDEMEND_SLOT = TIDEMEND_SLOT,
	WATER_TAG = WATER_TAG,

	start = function(player: Player, ui: UIBinding)
		local barAssistUntil = 0.0
		local hasBlob = false
		local pulling = false
		local orbPart: BasePart? = nil
		local orbFollowConn: RBXScriptConnection? = nil
		local lastFeedback = "idle"
		local character: Model? = nil

		local function setFeedback(mode: string, force: boolean?)
			if not force and lastFeedback == mode then
				return
			end
			lastFeedback = mode
			ui:SetAbilitySlotFeedback(TIDEMEND_SLOT, mode)
		end

		local function stopOrbFollow()
			if orbFollowConn then
				orbFollowConn:Disconnect()
				orbFollowConn = nil
			end
			if orbPart then
				orbPart:Destroy()
				orbPart = nil
			end
		end

		local function dropHeldWater()
			hasBlob = false
			stopOrbFollow()
			setFeedback("idle")
		end

		local function refreshAmbientFeedback()
			if ui:IsPickerOpen() then
				setFeedback("idle")
				return
			end
			local char = character
			if not char or char:GetAttribute("BendingElement") ~= "water" then
				setFeedback("idle")
				return
			end
			if hasBlob and not modifierKeysDown() and os.clock() >= barAssistUntil then
				dropHeldWater()
				return
			end
			if lastFeedback == "cast" then
				return
			end
			local mod = modifierKeysDown() or (os.clock() < barAssistUntil)
			if hasBlob then
				if mod then
					setFeedback("armed")
				else
					setFeedback("idle")
				end
				return
			end
			if pulling then
				return
			end
			if not mod then
				setFeedback("idle")
				return
			end
			local o, d = cameraMouseRay()
			if not o or not d then
				setFeedback("idle")
				return
			end
			local hit = raycastWorld(o, d, makeRayParams(char), MAX_PULL_RANGE)
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hit and hrp and isWaterSurface(hit) and (hit.Position - hrp.Position).Magnitude <= MAX_PULL_RANGE then
				setFeedback("aim")
			else
				setFeedback("idle")
			end
		end

		local function flashCast()
			setFeedback("cast", true)
			task.delay(0.11, refreshAmbientFeedback)
		end

		local function tryLaunch()
			local char = character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local o, d = cameraMouseRay()
			if not char or not hrp or not o or not d or not hasBlob then
				return
			end
			flashCast()
			local spawnPos = hrp.Position + hrp.CFrame.LookVector * 1.1 + Vector3.new(0, 1.1, 0)
			stopOrbFollow()

			local proj = Instance.new("Part")
			proj.Name = "TidemendBolt"
			proj.Shape = Enum.PartType.Ball
			proj.Size = Vector3.one * ORB_RADIUS * 2
			proj.Position = spawnPos
			proj.Color = Color3.fromRGB(90, 180, 220)
			proj.Material = Enum.Material.Glass
			proj.Transparency = 0.15
			proj.CastShadow = false
			proj.CanCollide = false
			proj.CanQuery = false
			proj.Massless = true
			proj.Anchored = false
			proj.Parent = workspace
			Debris:AddItem(proj, 4)

			local att0 = Instance.new("Attachment")
			att0.Parent = proj

			local att1 = Instance.new("Attachment")
			att1.Position = Vector3.new(0, -ORB_RADIUS * 0.9, 0)
			att1.Parent = proj

			local beam = Instance.new("Beam")
			beam.Attachment0 = att0
			beam.Attachment1 = att1
			beam.Color = ColorSequence.new(Color3.fromRGB(120, 210, 255))
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 0.6),
			})
			beam.Width0 = 0.65
			beam.Width1 = 0.1
			beam.FaceCamera = true
			beam.Parent = proj

			local goal = launchTargetPoint(o, d, char)
			local delta = goal - spawnPos
			local dist = delta.Magnitude
			if dist < 1 then
				proj.Anchored = true
				proj:Destroy()
				hasBlob = false
				setFeedback("idle")
				return
			end

			task.defer(function()
				local startT = os.clock()
				local maxT = math.clamp(dist / 140 + 1.8, 0.6, 3.8)
				while proj.Parent == workspace do
					local toGoal = goal - proj.Position
					local mag = toGoal.Magnitude
					if mag < 1.3 or os.clock() - startT > maxT then
						break
					end
					proj.AssemblyLinearVelocity = toGoal.Unit * math.min(150, math.max(40, mag * 8))
					RunService.Stepped:Wait()
				end
				if proj.Parent then
					proj.AssemblyLinearVelocity = Vector3.zero
					task.delay(0.05, function()
						if proj.Parent then
							proj:Destroy()
						end
					end)
				end
			end)

			hasBlob = false
		end

		local function startPull(hit: RaycastResult)
			local char = character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hand =
				char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
			if not char or not hrp then
				return
			end
			pulling = true
			setFeedback("cast", true)
			stopOrbFollow()

			local anchor = Instance.new("Part")
			anchor.Name = "TidemendPullAnchor"
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CastShadow = false
			anchor.Transparency = 1
			anchor.Size = Vector3.one * 0.08
			anchor.Position = hit.Position + hit.Normal * 0.04
			anchor.Parent = workspace
			Debris:AddItem(anchor, math.ceil(PULL_DURATION_SEC) + 3)

			local a0 = Instance.new("Attachment")
			a0.Parent = anchor

			local a1 = Instance.new("Attachment")
			a1.Parent = hand or hrp
			a1.Position = Vector3.new(0, 0.4, -0.5)

			local beam = Instance.new("Beam")
			beam.Width0 = 0.42
			beam.Width1 = 0.92
			beam.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255))
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 0.45),
			})
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.FaceCamera = true
			beam.LightEmission = 0.85
			beam.Parent = anchor

			local target = hrp.Position + Vector3.new(0, 1, 0)
			TweenService:Create(anchor, TweenInfo.new(PULL_DURATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = target,
			}):Play()

			task.delay(PULL_DURATION_SEC, function()
				if beam.Parent then
					beam:Destroy()
				end
				if anchor.Parent then
					anchor:Destroy()
				end
				pulling = false
				if not character or character ~= char then
					dropHeldWater()
					return
				end
				hasBlob = true

				local orb = Instance.new("Part")
				orb.Name = "TidemendOrb"
				orb.Shape = Enum.PartType.Ball
				orb.Size = Vector3.one * ORB_RADIUS * 2
				orb.Color = Color3.fromRGB(100, 200, 255)
				orb.Material = Enum.Material.Glass
				orb.Transparency = 0.12
				orb.CastShadow = false
				orb.CanCollide = false
				orb.CanQuery = false
				orb.Massless = true
				orb.Anchored = true
				orb.Parent = workspace
				orbPart = orb

				local followHrp = hrp
				orbFollowConn = RunService.RenderStepped:Connect(function()
					local h = followHrp
					if orb.Parent and orbPart == orb and h and h.Parent then
						local look = h.CFrame.LookVector
						orb.Position = h.Position + look * 1.15 + Vector3.new(0, 1.15, 0)
					elseif orbFollowConn then
						orbFollowConn:Disconnect()
						orbFollowConn = nil
					end
				end)

				if modifierKeysDown() or os.clock() < barAssistUntil then
					setFeedback("armed")
				else
					setFeedback("idle")
				end
			end)
		end

		local function onMouseDown()
			if ui:IsPickerOpen() then
				return
			end
			local char = character
			if not char or char:GetAttribute("BendingElement") ~= "water" then
				setFeedback("idle")
				return
			end

			local mod = modifierKeysDown() or (os.clock() < barAssistUntil)
			if not mod then
				return
			end

			local o, d = cameraMouseRay()
			if not o or not d then
				return
			end

			local p = makeRayParams(char)
			if hasBlob and not pulling then
				tryLaunch()
				return
			end
			if pulling then
				return
			end

			local hit = raycastWorld(o, d, p, MAX_PULL_RANGE)
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				return
			end
			if hit and isWaterSurface(hit) and (hit.Position - hrp.Position).Magnitude <= MAX_PULL_RANGE then
				startPull(hit)
			elseif hasBlob then
				tryLaunch()
			end
		end

		local inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local pos = UserInputService:GetMouseLocation()
				local guiAt = GuiService:GetGuiObjectsAtPosition(pos.X, pos.Y)
				local pg = player:FindFirstChildOfClass("PlayerGui")
				if isBlockingGuiClick(pg, guiAt) then
					return
				end
				onMouseDown()
			end
		end)

		local inputEndedConn = UserInputService.InputEnded:Connect(function(input, _)
			if
				input.KeyCode == Enum.KeyCode.LeftShift
				or input.KeyCode == Enum.KeyCode.RightShift
				or input.KeyCode == Enum.KeyCode.Four
			then
				if not modifierKeysDown() and os.clock() >= barAssistUntil and hasBlob then
					dropHeldWater()
				end
			end
		end)

		local hbConn = RunService.Heartbeat:Connect(refreshAmbientFeedback)

		local charConn: RBXScriptConnection? = nil
		local slotConn: RBXScriptConnection? = nil

		local function clearCharacter()
			dropHeldWater()
			pulling = false
			character = nil
		end

		local function bindChar(ch: Model)
			clearCharacter()
			character = ch
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Died:Once(function()
					clearCharacter()
				end)
			end
		end

		charConn = player.CharacterAdded:Connect(bindChar)
		if player.Character then
			bindChar(player.Character)
		end

		slotConn = ui:ConnectAbilitySlot(TIDEMEND_SLOT, function()
			if character and character:GetAttribute("BendingElement") == "water" then
				barAssistUntil = os.clock() + 8
				refreshAmbientFeedback()
			end
		end)

		local function cleanup()
			inputBeganConn:Disconnect()
			inputEndedConn:Disconnect()
			hbConn:Disconnect()
			if charConn then
				charConn:Disconnect()
			end
			if slotConn then
				slotConn:Disconnect()
			end
			dropHeldWater()
			setFeedback("idle")
		end

		Players.PlayerRemoving:Connect(function(p)
			if p == player then
				cleanup()
			end
		end)
	end,
}
