local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create RemoteEvent for client-server communication
local HexBoltEvent = Instance.new("RemoteEvent")
HexBoltEvent.Name = "HexBoltEvent"
HexBoltEvent.Parent = ReplicatedStorage

-- Configuration
local DAMAGE = 15
local KNOCKBACK_FORCE = 50
local BOLT_SPEED = 100
local BOLT_LIFETIME = 3
local BOLT_SIZE = 1.5
local AREA_DAMAGE_RADIUS = 5
local AREA_DAMAGE = 15 -- Same as direct damage
local AREA_DURATION = 0.5 -- How long the area effect lasts

-- Track which hand to use next
local playerHands = {}

-- Function to create impact effect
local function createImpactEffect(position)
    -- Create the impact area
    local impactArea = Instance.new("Part")
    impactArea.Name = "HexBoltImpact"
    impactArea.Shape = Enum.PartType.Ball
    impactArea.Size = Vector3.new(AREA_DAMAGE_RADIUS * 2, AREA_DAMAGE_RADIUS * 2, AREA_DAMAGE_RADIUS * 2)
    impactArea.Position = position
    impactArea.Anchored = true
    impactArea.CanCollide = false
    impactArea.Transparency = 0.5
    impactArea.Color = Color3.fromRGB(255, 0, 0)
    impactArea.Material = Enum.Material.Neon
    
    -- Add particle effect
    local attachment = Instance.new("Attachment")
    attachment.Parent = impactArea
    
    local particles = Instance.new("ParticleEmitter")
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Speed = NumberRange.new(10)
    particles.Lifetime = NumberRange.new(0.5)
    particles.Rate = 100
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Parent = attachment
    
    impactArea.Parent = workspace
    
    -- Apply damage and knockback to players in area
    local parts = workspace:GetPartsInPart(impactArea)
    for _, part in ipairs(parts) do
        local hitPlayer = Players:GetPlayerFromCharacter(part.Parent)
        if hitPlayer then
            local humanoid = part.Parent:FindFirstChild("Humanoid")
            if humanoid then
                -- Calculate distance-based damage
                local distance = (part.Position - position).Magnitude
                local damageMultiplier = 1 - (distance / AREA_DAMAGE_RADIUS)
                local finalDamage = math.floor(AREA_DAMAGE * damageMultiplier)
                
                if finalDamage > 0 then
                    humanoid:TakeDamage(finalDamage)
                    
                    -- Apply knockback from center
                    local knockbackDirection = (part.Position - position).Unit
                    local rootPart = part.Parent:FindFirstChild("HumanoidRootPart")
                    if rootPart then
                        local bodyVelocity = Instance.new("BodyVelocity")
                        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                        bodyVelocity.Velocity = knockbackDirection * KNOCKBACK_FORCE * damageMultiplier
                        bodyVelocity.Parent = rootPart
                        game:GetService("Debris"):AddItem(bodyVelocity, 0.1)
                    end
                end
            end
        end
    end
    
    -- Fade out and destroy
    game:GetService("Debris"):AddItem(impactArea, AREA_DURATION)
end

-- Function to create the hex bolt projectile
local function createHexBolt(player, targetPosition)
    local character = player.Character
    if not character then return end
    
    -- Get the hand to use
    local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
    local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
    
    if not rightHand or not leftHand then return end
    
    -- Initialize player's hand tracking if not exists
    if not playerHands[player.UserId] then
        playerHands[player.UserId] = "right"
    end
    
    -- Get the current hand to use
    local currentHand = playerHands[player.UserId] == "right" and rightHand or leftHand
    
    -- Switch hands for next time
    playerHands[player.UserId] = playerHands[player.UserId] == "right" and "left" or "right"
    
    -- Create the bolt
    local bolt = Instance.new("Part")
    bolt.Name = "HexBolt"
    bolt.Shape = Enum.PartType.Ball -- Make it circular
    bolt.Size = Vector3.new(BOLT_SIZE, BOLT_SIZE, BOLT_SIZE)
    bolt.Color = Color3.fromRGB(255, 0, 0) -- Red color
    bolt.Material = Enum.Material.Neon
    bolt.CanCollide = false
    bolt.Anchored = true
    
    -- Create attachment for effects
    local attachment = Instance.new("Attachment")
    attachment.Parent = bolt
    
    -- Add particle effect
    local particles = Instance.new("ParticleEmitter")
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
    particles.Size = NumberSequence.new(0.5)
    particles.Speed = NumberRange.new(5)
    particles.Lifetime = NumberRange.new(0.5)
    particles.Rate = 50
    particles.Parent = attachment
    
    -- Position the bolt at the hand
    local startPos = currentHand.Position
    bolt.CFrame = CFrame.new(startPos)
    bolt.Parent = workspace
    
    -- Calculate direction to target
    local direction = (targetPosition - startPos).Unit
    local startTime = tick()
    
    -- Move the bolt
    game:GetService("RunService").Heartbeat:Connect(function()
        if not bolt.Parent then return end
        
        local elapsed = tick() - startTime
        if elapsed > BOLT_LIFETIME then
            bolt:Destroy()
            return
        end
        
        bolt.CFrame = bolt.CFrame + direction * BOLT_SPEED * (1/60)
        
        -- Check for hits
        local hit = workspace:FindPartOnRay(Ray.new(bolt.Position, direction * 2))
        if hit and hit.Parent then
            -- Create impact effect
            createImpactEffect(bolt.Position)
            bolt:Destroy()
        end
    end)
end

-- Server-side handling
HexBoltEvent.OnServerEvent:Connect(function(player, targetPosition)
    createHexBolt(player, targetPosition)
end)

-- Clean up when player leaves
game.Players.PlayerRemoving:Connect(function(player)
    playerHands[player.UserId] = nil
end) 