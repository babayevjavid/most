--!strict

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MouseHelper = require(script.Parent.MouseHelper)
local SoftLockClient = require(script.Parent.SoftLockClient)
local TeleportMarkerClient = require(script.Parent.TeleportMarkerClient)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local AbilityInput = {}

local inputBlocked = false

local KEY_MAP = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.V] = "V",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.G] = "G",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.B] = "B",
	[Enum.KeyCode.Z] = "Z",
	[Enum.KeyCode.H] = "H",
	[Enum.KeyCode.J] = "J",
}

local DECOY_MODE_KEYS = {
	[Enum.KeyCode.One] = "Punch",
	[Enum.KeyCode.Two] = "Run",
	[Enum.KeyCode.Three] = "Detonate",
	[Enum.KeyCode.Four] = "Lie of Place",
}

local ULT_ATTACK_KEYS = {
	[Enum.KeyCode.One] = "Attack",
	[Enum.KeyCode.Two] = "Idle",
}

local HOLD_FALLBACK = {
	E = true,
	T = true,
	C = true,
	B = true,
	Z = true,
}

local function isBarrierHold(character: Model): boolean
	return character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true
end

local holdKeys: { [string]: boolean } = {}
local keyboardHold: { [string]: boolean } = {}
local SCROLL_ACTION = "MCU_AbilityScroll"

local player: Player? = nil
local useAbility: RemoteEvent? = nil

local function isHoldKeyForHero(key: string): boolean
	local plr = player
	local character = plr and plr.Character
	if character then
		local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
		if type(heroId) == "string" then
			local entry = CharacterRegistry.getAbilityByKey(heroId, key)
			if entry then
				return entry.hold == true
			end
		end
	end
	return HOLD_FALLBACK[key] == true
end

local function resolveAimPoint(): Vector3
	local plr = player
	if not plr then
		return Vector3.zero
	end
	local character = plr.Character
	if character and character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
		local mark = TeleportMarkerClient.getAimWorldPosition()
		if mark then
			return mark
		end
	end
	return MouseHelper.getHitPosition(plr, 200)
end

local function payload(action: string, withTarget: boolean?, targetOverride: Model?): { [string]: any }
	local plr = player :: Player
	local data: { [string]: any } = {
		action = action,
		direction = MouseHelper.getWorldDirection(plr),
		aimPoint = resolveAimPoint(),
		softLock = SoftLockClient.isEnabled(),
	}
	if withTarget then
		if SoftLockClient.isEnabled() then
			data.target = targetOverride or SoftLockClient.getLockedTarget()
		else
			data.target = targetOverride or MouseHelper.getHoveredCharacter(plr, 200)
		end
		data.hitPart = MouseHelper.getHoveredPart(plr, 200)
		data.interactable = MouseHelper.getHoveredInteractable(plr, 70)
	end
	return data
end

local function keyFromAction(action: string): string
	local key = string.split(action, "_")[1]
	return key or action
end

local function isMindLinkerPart(part: Instance?): boolean
	if not part then
		return false
	end
	if part.Name == "MindLinker" then
		return true
	end
	local parent = part.Parent
	return parent ~= nil and parent.Name == "MindLinker"
end

local function resolveTargetedFire(action: string): (boolean, Model?)
	local plr = player
	local character = plr and plr.Character
	if not character or not plr then
		return false, nil
	end
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if type(heroId) ~= "string" then
		return true, nil
	end
	local entry = CharacterRegistry.getAbilityByKey(heroId, keyFromAction(action))
	if not entry or entry.requiresTarget ~= true then
		if SoftLockClient.isEnabled() then
			return true, SoftLockClient.getLockedTarget()
		end
		return true, MouseHelper.getHoveredCharacter(plr, 200)
	end
	if SoftLockClient.isEnabled() then
		local locked = SoftLockClient.getLockedTarget()
		if locked then
			return true, locked
		end
		if entry.id == "mind_link" then
			return true, nil
		end
		return false, nil
	end
	local hovered = MouseHelper.getDirectHoveredCharacter(plr, 200)
	if hovered then
		return true, hovered
	end
	if entry.id == "mind_link" and isMindLinkerPart(MouseHelper.getHoveredPart(plr, 200)) then
		return true, nil
	end
	return false, nil
end

local function send(action: string, withTarget: boolean?): boolean
	local remote = useAbility
	if not remote then
		return false
	end
	local forcedTarget: Model? = nil
	if withTarget then
		local ok, target = resolveTargetedFire(action)
		if not ok then
			return false
		end
		forcedTarget = target
	end
	remote:FireServer(payload(action, withTarget, forcedTarget))
	return true
end

local function abilityIdForKey(character: Model, key: string): string?
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if type(heroId) ~= "string" then
		return nil
	end
	local entry = CharacterRegistry.getAbilityByKey(heroId, key)
	return if entry then entry.id else nil
end

local function isKeyOnCooldown(key: string): boolean
	local plr = player
	local character = plr and plr.Character
	if not character then
		return true
	end
	local abilityId = abilityIdForKey(character, key)
	if not abilityId then
		return false
	end
	if
		abilityId == "shapeshift"
		and character:GetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE) == true
	then
		return false
	end
	if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
		if abilityId == "teleportation" or abilityId == "trickster_dash" or abilityId == "hex_displacement" then
			return false
		end
	end
	if abilityId and AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return true
	end
	if abilityId and AbilityCooldownHelper.isActive(character, abilityId) then
		if abilityId == "rune_entrapment" then
			return true
		end
	end
	return false
end

local function isHoldRunning(key: string): boolean
	if holdKeys[key] then
		return true
	end
	local plr = player
	local character = plr and plr.Character
	if not character then
		return false
	end
	local abilityId = abilityIdForKey(character, key)
	if abilityId and AbilityCooldownHelper.isActive(character, abilityId) then
		return true
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true and (key == "E" or key == "R") then
		return true
	end
	if key == "Q" and character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if key == "Q" and character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true then
		return true
	end
	return false
end

local function getMoveVector(): Vector3
	local plr = player
	local camera = workspace.CurrentCamera
	local move = Vector3.zero
	if camera then
		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude > 0.01 then
			flatLook = flatLook.Unit
		else
			flatLook = Vector3.new(0, 0, -1)
		end
		local right = camera.CFrame.RightVector
		local flatRight = Vector3.new(right.X, 0, right.Z)
		if flatRight.Magnitude > 0.01 then
			flatRight = flatRight.Unit
		else
			flatRight = Vector3.new(1, 0, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += flatLook
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move -= flatLook
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move -= flatRight
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += flatRight
		end
	end
	if move.Magnitude < 0.08 and plr and plr.Character then
		local hum = plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.MoveDirection.Magnitude > 0.08 then
			move = hum.MoveDirection
		end
	end
	return if move.Magnitude > 0.01 then move.Unit else Vector3.zero
end

local function swFlightAllowsKey(_character: Model, key: string): boolean
	-- While flying Scarlet Witch may Hex Bolt (E) and toggle flight (F).
	return key == "F" or key == "E"
end

local function iwFlightAllowsKey(character: Model, key: string): boolean
	if key == "F" or key == "T" then
		return true
	end
	if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
		return key == "E" or key == "X"
	end
	return false
end

local function tkAllowsKey(character: Model, key: string): boolean
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) ~= true then
		return true
	end
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "jean_grey" then
		return key == "R"
	end
	return key == "R"
end

local function otherAbilityBlocks(character: Model, key: string): boolean
	if key == "F" then
		return false
	end
	-- Astral companions: pain (C) / outburst (B) must work while astral (and barrier) stay active
	if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true and (key == "C" or key == "B") then
		return false
	end
	-- Area Forcefield companions: Choke (B) / Protect (C) are usable only while X remains active.
	if
		character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
		and AbilityCooldownHelper.isActive(character, "forcefield_area")
		and (key == "B" or key == "C")
	then
		return false
	end
	return AbilityCooldownHelper.hasBlockingActive(character, abilityIdForKey(character, key))
end

local function iwAreaCompanionAllowed(character: Model, key: string): boolean
	return character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
		and AbilityCooldownHelper.isActive(character, "forcefield_area")
		and (key == "B" or key == "C")
end

local function iwAreaActionAllowed(character: Model, key: string): boolean
	return character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
		and AbilityCooldownHelper.isActive(character, "forcefield_area")
		and (key == "X" or key == "B" or key == "C")
end

local function beginHold(key: string)
	if inputBlocked then
		return
	end
	if not isHoldKeyForHero(key) then
		return
	end
	-- Jean barrier: only allow releasing C
	local character = player and player.Character
	if character then
		if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
			and not iwAreaActionAllowed(character, key)
			or character:GetAttribute(GameConstants.MG_HAIR_SWITCHING_ATTRIBUTE) == true
			or character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true
			or CombatHelper.arePowersDisabled(character)
		then
			return
		end
		if otherAbilityBlocks(character, key) then
			return
		end
		if not tkAllowsKey(character, key) then
			return
		end
		if isBarrierHold(character) and key ~= "Q" then
			if iwAreaCompanionAllowed(character, key) then
				-- Choke / Protect while Area Forcefield is active
			elseif key == "C" and character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
				-- Jean astral outburst while barrier is up
			else
				return
			end
		end
		if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch"
			and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			and not swFlightAllowsKey(character, key)
		then
			return
		end
		if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
			and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			and not iwFlightAllowsKey(character, key)
		then
			return
		end
	end
	if isKeyOnCooldown(key) then
		return
	end
	local sent = if key == "E" or key == "Z" or key == "X" or key == "R" or key == "C" or key == "B"
		then send(key .. "_down", true)
		else send(key .. "_down")
	if sent then
		holdKeys[key] = true
	end
end

local function endHold(key: string)
	if not holdKeys[key] and not isHoldRunning(key) then
		return
	end
	holdKeys[key] = false
	send(key .. "_up")
end

local function fireTap(key: string)
	if inputBlocked then
		return
	end
	local character = player and player.Character
	if key == "J" then
		if character then
			if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "jean_grey" then
				return
			end
			if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
				or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
				or character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
			then
				return
			end
			if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "marvel_girl" then
				return
			end
			if AbilityCooldownHelper.isOnCooldown(character, "jean_hair") then
				return
			end
			if character:GetAttribute(GameConstants.MG_HAIR_SWITCHING_ATTRIBUTE) == true then
				return
			end
			if character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true
				or CombatHelper.arePowersDisabled(character)
				or character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true
			then
				return
			end
		end
		send("J")
		return
	end
	if character then
		if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
			and not iwAreaActionAllowed(character, key)
			or character:GetAttribute(GameConstants.MG_HAIR_SWITCHING_ATTRIBUTE) == true
			or character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true
			or CombatHelper.arePowersDisabled(character)
		then
			return
		end
		if otherAbilityBlocks(character, key) then
			return
		end
		if not tkAllowsKey(character, key) then
			return
		end
		-- Barrier: only astral (H / V) may fire; other taps blocked
		-- Barrier: Jean may still astral (H / V); Invisible Woman blocks all other taps
		if character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true
			and not iwAreaActionAllowed(character, key)
		then
			return
		end
		if character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true and key ~= "H" and key ~= "V" then
			if not (character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true and (key == "B" or key == "C")) then
				return
			end
		end
		if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch"
			and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			and not swFlightAllowsKey(character, key)
		then
			return
		end
		if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
			and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			and not iwFlightAllowsKey(character, key)
		then
			return
		end
	end
	if isKeyOnCooldown(key) then
		return
	end
	local remote = useAbility
	if not remote then
		return
	end
	local plr = player :: Player
	local heroId = character and character:GetAttribute(GameConstants.HERO_ATTRIBUTE)

	if key == "F" then
		-- Dagger Light Veil is a projectile toward aim (same as Q); others use F for flight/dash
		if heroId == "dagger" then
			send("F")
		else
			remote:FireServer({
				action = "F",
				direction = MouseHelper.getWorldDirection(plr),
				aimPoint = resolveAimPoint(),
				moveVector = getMoveVector(),
			})
		end
	elseif key == "X" or key == "G" or key == "V" or key == "T" or key == "E" or key == "R" or key == "C" or key == "Z" or key == "H" or key == "B" then
		send(key, true)
	else
		local entry = if character and type(heroId) == "string"
			then CharacterRegistry.getAbilityByKey(heroId, key)
			else nil
		if entry and entry.requiresTarget == true then
			send(key, true)
		else
			send(key)
		end
	end
end

--[[ HUD / mobile: press ability button. Hold abilities toggle on/off. ]]
function AbilityInput.setInputBlocked(blocked: boolean)
	inputBlocked = blocked == true
end

function AbilityInput.triggerFromHud(key: string, isHold: boolean?)
	if type(key) ~= "string" or key == "" then
		return
	end
	local character = player and player.Character
	if character and isBarrierHold(character) then
		-- Shield release (Q) or Jean astral (H) while barrier is up
		if key == "Q" and (isHold == true or isHoldKeyForHero(key)) then
			if isHoldRunning(key) then
				endHold(key)
			end
			return
		end
		if iwAreaCompanionAllowed(character, key) then
			if isHold == true or isHoldKeyForHero(key) then
				if isHoldRunning(key) then
					endHold(key)
				else
					beginHold(key)
				end
			end
			return
		end
		if character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true and (key == "H" or key == "V") then
			fireTap(key)
			return
		end
		return
	end
	if isHold == true or isHoldKeyForHero(key) then
		if isHoldRunning(key) then
			endHold(key)
		else
			beginHold(key)
		end
		return
	end
	fireTap(key)
end

function AbilityInput.init(localPlayer: Player)
	player = localPlayer
	useAbility = Remotes.getEvent("UseAbility")
	local flightInput = Remotes.getEvent("FlightInput")

	local function hookDeathFlight(character: Model)
		local hum = character:WaitForChild("Humanoid", 8)
		if not hum or not hum:IsA("Humanoid") then
			return
		end
		local function reportDead()
			if flightInput then
				flightInput:FireServer({ dead = true })
			end
		end
		hum.Died:Connect(reportDead)
		hum.HealthChanged:Connect(function(hp)
			if hp <= 0 then
				reportDead()
			end
		end)
		if hum.Health <= 0 then
			reportDead()
		end
	end
	localPlayer.CharacterAdded:Connect(hookDeathFlight)
	if localPlayer.Character then
		task.spawn(hookDeathFlight, localPlayer.Character)
	end

	-- Stream live mouse aim while Lumen Barrage / Jean slam / Jean bolts are active
	local lastBarrageAimAt = 0
	RunService.Heartbeat:Connect(function()
		local character = localPlayer.Character
		if not character or not useAbility then
			return
		end
		local now = os.clock()
		if now - lastBarrageAimAt < 0.03 then
			return
		end
		if AbilityCooldownHelper.isActive(character, "lumen_barrage") then
			lastBarrageAimAt = now
			useAbility:FireServer({
				action = "X_aim",
				direction = MouseHelper.getWorldDirection(localPlayer),
				aimPoint = resolveAimPoint(),
			})
		elseif AbilityCooldownHelper.isActive(character, "telekinetic_slam") then
			lastBarrageAimAt = now
			useAbility:FireServer({
				action = "X_aim",
				direction = MouseHelper.getWorldDirection(localPlayer),
				aimPoint = resolveAimPoint(),
			})
		elseif AbilityCooldownHelper.isActive(character, "telekinetic_debris") then
			lastBarrageAimAt = now
			useAbility:FireServer({
				action = "Z_aim",
				direction = MouseHelper.getWorldDirection(localPlayer),
				aimPoint = resolveAimPoint(),
			})
		elseif
			AbilityCooldownHelper.isActive(character, "disc_throw")
			or AbilityCooldownHelper.isActive(character, "forcefield_push")
			or AbilityCooldownHelper.isActive(character, "forcefield_area")
			or AbilityCooldownHelper.isActive(character, "forcefield_crush")
		then
			lastBarrageAimAt = now
			useAbility:FireServer({
				action = "Iw_aim",
				direction = MouseHelper.getWorldDirection(localPlayer),
				aimPoint = resolveAimPoint(),
			})
		end
	end)

	local function handleAbilityScroll(scrollDelta: number)
		local character = localPlayer.Character
		if not character then
			return false
		end
		local tkActive = character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
		local teleportAiming = character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true
		if not tkActive and not teleportAiming then
			return false
		end
			if tkActive then
				useAbility:FireServer({
					action = "R_scroll",
					scroll = scrollDelta,
					direction = MouseHelper.getWorldDirection(localPlayer),
					aimPoint = MouseHelper.getHitPosition(localPlayer, 200),
				})
			end
		if teleportAiming then
			local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			if hero ~= "scarlet_witch" then
				TeleportMarkerClient.adjustRange(scrollDelta)
			end
		end
		return true
	end

	ContextActionService:BindActionAtPriority(SCROLL_ACTION, function(_name, inputState, inputObject)
		if inputState ~= Enum.UserInputState.Change then
			return Enum.ContextActionResult.Pass
		end
		if handleAbilityScroll(inputObject.Position.Z) then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 55, Enum.UserInputType.MouseWheel)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- TK throw / teleport confirm (mouse / touch elsewhere handled by SoftLock / screen)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local character = localPlayer.Character
			local tkActive = character and character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
			if tkActive then
				-- Push/throw the held victim; do not require mouse-on-target.
				send("R_throw")
				return
			end
			if holdKeys.E then
				send("E_throw")
				return
			end
			if character and AbilityCooldownHelper.isActive(character, "telekinetic_debris") then
				send("Z_throw", true)
				return
			end
			if character and character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
				local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
				if hero == "loki" then
					send("F_confirm")
				elseif hero == "scarlet_witch" then
					send("V_confirm")
				end
				return
			end
		end

		if gameProcessed then
			return
		end

		local decoyMode = DECOY_MODE_KEYS[input.KeyCode]
		local ultMode = ULT_ATTACK_KEYS[input.KeyCode]
		if decoyMode or ultMode then
			local character = localPlayer.Character
			if character and character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "loki" then
				if character:GetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE) == true and decoyMode then
					useAbility:FireServer({
						action = "SetMode",
						abilityId = "illusion_decoy",
						mode = decoyMode,
					})
					character:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, decoyMode)
					return
				end
				if character:GetAttribute(GameConstants.LOKI_ULT_ACTIVE_ATTRIBUTE) == true and ultMode then
					useAbility:FireServer({
						action = "SetMode",
						abilityId = "god_of_mischief",
						mode = ultMode,
					})
					character:SetAttribute(
						GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE,
						if ultMode == "Attack" then true else false
					)
					return
				end
			end
		end

		local key = KEY_MAP[input.KeyCode]
		if not key then
			return
		end

		if isHoldKeyForHero(key) then
			keyboardHold[key] = true
			beginHold(key)
		else
			fireTap(key)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		local key = KEY_MAP[input.KeyCode]
		if key and keyboardHold[key] then
			keyboardHold[key] = false
			endHold(key)
		end
	end)

	localPlayer.CharacterRemoving:Connect(function()
		for key, held in holdKeys do
			if held then
				send(key .. "_up")
			end
		end
		table.clear(holdKeys)
		table.clear(keyboardHold)
	end)

	task.spawn(function()
		while true do
			task.wait(0.04)
			if holdKeys.T then
				send("T_aim")
			end
			if holdKeys.E then
				send("E_update")
			end
			if holdKeys.R then
				send("R_update")
			end
			local character = localPlayer.Character
			if
				character
				and character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "loki"
				and character:GetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE) == true
			then
				send("E_update")
			end
		end
	end)
end

return AbilityInput
