local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Flight settings
local isFlying = false
local canToggleFlight = true
local cooldownTime = 1

-- Movement settings
local SPEED = 25
local ROTATION_SPEED = 0.1

-- Movement state
local moveDirection = Vector3.new(0, 0, 0)
local startHeight = 0

-- Function to handle flight toggle
local function toggleFlight()
    if not canToggleFlight then return end
    
    isFlying = not isFlying
    canToggleFlight = false
    
    if isFlying then
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        startHeight = rootPart.Position.Y
        rootPart.Velocity = Vector3.new(0, 0, 0)
    else
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        rootPart.Velocity = Vector3.new(0, 0, 0)
    end
    
    task.delay(cooldownTime, function()
        canToggleFlight = true
    end)
end

-- Handle input for flight toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.F then
        toggleFlight()
    end
end)

-- Handle movement input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not isFlying then return end
    
    if input.KeyCode == Enum.KeyCode.W then
        moveDirection = moveDirection + Vector3.new(0, 0, -1)
    elseif input.KeyCode == Enum.KeyCode.S then
        moveDirection = moveDirection + Vector3.new(0, 0, 1)
    elseif input.KeyCode == Enum.KeyCode.A then
        moveDirection = moveDirection + Vector3.new(-1, 0, 0)
    elseif input.KeyCode == Enum.KeyCode.D then
        moveDirection = moveDirection + Vector3.new(1, 0, 0)
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if not isFlying then return end
    
    if input.KeyCode == Enum.KeyCode.W then
        moveDirection = moveDirection - Vector3.new(0, 0, -1)
    elseif input.KeyCode == Enum.KeyCode.S then
        moveDirection = moveDirection - Vector3.new(0, 0, 1)
    elseif input.KeyCode == Enum.KeyCode.A then
        moveDirection = moveDirection - Vector3.new(-1, 0, 0)
    elseif input.KeyCode == Enum.KeyCode.D then
        moveDirection = moveDirection - Vector3.new(1, 0, 0)
    end
end)

-- Main flight loop
RunService.Heartbeat:Connect(function(deltaTime)
    if not isFlying then return end
    
    -- Get camera direction
    local camera = workspace.CurrentCamera
    local cameraCFrame = camera.CFrame
    
    -- Calculate movement direction relative to camera
    local forward = cameraCFrame.LookVector
    local right = cameraCFrame.RightVector
    forward = Vector3.new(forward.X, 0, forward.Z).Unit
    right = Vector3.new(right.X, 0, right.Z).Unit
    
    -- Calculate movement
    local move = Vector3.new(0, 0, 0)
    
    if moveDirection.Z < 0 then -- W
        move = move + forward
    elseif moveDirection.Z > 0 then -- S
        move = move - forward
    end
    
    if moveDirection.X < 0 then -- A
        move = move - right
    elseif moveDirection.X > 0 then -- D
        move = move + right
    end
    
    -- Normalize movement
    if move.Magnitude > 0 then
        move = move.Unit * SPEED
    end
    
    -- Apply movement
    if move.Magnitude > 0 then
        -- Rotate character
        local targetCFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + move)
        rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, ROTATION_SPEED)
        
        -- Move character
        local newPosition = rootPart.Position + move * deltaTime
        newPosition = Vector3.new(newPosition.X, startHeight, newPosition.Z)
        rootPart.CFrame = CFrame.new(newPosition, newPosition + move)
    else
        -- Maintain position and height
        local currentPos = rootPart.Position
        local targetPos = Vector3.new(currentPos.X, startHeight, currentPos.Z)
        rootPart.CFrame = CFrame.new(targetPos, targetPos + rootPart.CFrame.LookVector)
    end
end)

-- Handle character respawning
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
    isFlying = false
end) 