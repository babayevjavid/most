local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local mouse = Players.LocalPlayer:GetMouse()

-- Wait for the RemoteEvent with a timeout
local HexBoltEvent
local startTime = tick()
local timeout = 5 -- 5 seconds timeout

while not HexBoltEvent and tick() - startTime < timeout do
    HexBoltEvent = ReplicatedStorage:FindFirstChild("HexBoltEvent")
    if not HexBoltEvent then
        wait(0.1)
    end
end

if not HexBoltEvent then
    warn("HexBoltEvent not found after timeout!")
    return
end

-- Handle input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.E then
        HexBoltEvent:FireServer(mouse.Hit.Position)
    end
end) 