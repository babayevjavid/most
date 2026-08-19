--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local MorphAnimationHelper = require(ReplicatedStorage.Shared.MorphAnimationHelper)
local MorphVfxTint = require(ReplicatedStorage.Shared.MorphVfxTint)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local HandParticleHelper = require(script.Parent.HandParticleHelper)
local PlayerDataService = require(script.Parent.PlayerDataService)

local CharacterService = {}

local selectedHero: { [Player]: string } = {}
local pendingDeploy: { [Player]: string } = {}
local pendingSkin: { [Player]: string } = {}
-- "starter" = plain StarterCharacter; "clothes" = starter + player clothes; "avatar" = true Roblox avatar; "morph" = Assets.Morphs
local lookModeByPlayer: { [Player]: string } = {}
local morphReady: { [Player]: boolean } = {}

local function clearHeroSelection(player: Player)
	selectedHero[player] = nil
	pendingDeploy[player] = nil
	pendingSkin[player] = nil
	lookModeByPlayer[player] = nil
	morphReady[player] = nil
end

local function normalizeLookMode(value: any): string
	if value == "starter" or value == "clothes" or value == "avatar" then
		return value
	end
	-- Legacy boolean from older clients
	if value == false then
		return "starter"
	end
	if value == true then
		return "clothes"
	end
	return "clothes"
end

local SPRINT_BLOCK_ABILITIES = {
	"hex_bolt",
	"probability_hex",
	"hex_displacement",
	"rune_entrapment",
	"hex_flight",
	"photon_flight",
	"photon_blast",
	"photon_beam",
	"photon_explosion",
	"binary_form",
	"telekinesis",
	"hex_beam",
	"hex_shield",
	"teleport",
	"fear",
	"regeneration",
	"ultimate",
	"telekinetic_slam",
	"forcefield_crush",
	"forcefield_smash",
}

local function getStarterCharacterTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("StarterCharacter")
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function ensureAnimator(humanoid: Humanoid): Animator
	local existing = humanoid:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Name = "Animator"
	animator.Parent = humanoid
	return animator
end

local function prepareDescriptionForRobloxian2(desc: HumanoidDescription): HumanoidDescription
	desc.HeightScale = 1
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	return desc
end

local function restoreStarterAnimate(morph: Model, animateBackup: Instance?)
	for _, child in morph:GetChildren() do
		if child.Name == "Animate" then
			child:Destroy()
		end
	end
	if animateBackup then
		animateBackup.Parent = morph
	end
end

local function applyPlayerAppearance(humanoid: Humanoid, morph: Model, player: Player, keepNaturalScale: boolean?)
	ensureAnimator(humanoid)
	local animateBackup: Instance? = nil
	local existingAnimate = morph:FindFirstChild("Animate")
	if existingAnimate then
		animateBackup = existingAnimate:Clone()
	end

	local ok, descOrErr = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok or typeof(descOrErr) ~= "Instance" then
		warn("[CharacterService] Failed to get HumanoidDescription for", player.Name, descOrErr)
		if animateBackup then
			animateBackup:Destroy()
		end
		return
	end
	local desc = descOrErr :: HumanoidDescription
	if not keepNaturalScale then
		-- StarterCharacter (Robloxian2) needs flattened scales
		desc = prepareDescriptionForRobloxian2(desc)
	end
	local applyOk, applyErr = pcall(function()
		humanoid:ApplyDescription(desc)
	end)
	if not applyOk then
		warn("[CharacterService] ApplyDescription failed for", player.Name, applyErr)
	end
	ensureAnimator(humanoid)
	restoreStarterAnimate(morph, animateBackup)
	MorphAnimationHelper.applyToModel(morph, GameConstants.BASIC_IDLE_ANIM)

	task.defer(function()
		local NameplateService = require(script.Parent.NameplateService)
		NameplateService.refresh(morph)
	end)
end

local function replaceWithStarterMorph(player: Player, oldCharacter: Model, applyAvatar: boolean): Model?
	local template = getStarterCharacterTemplate()
	if not template then
		warn("[CharacterService] Missing ReplicatedStorage.Assets.StarterCharacter")
		return nil
	end

	local spawnCf = oldCharacter:GetPivot()
	local morph = template:Clone()
	morph.Name = player.Name

	local humanoid = morph:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[CharacterService] StarterCharacter has no Humanoid")
		morph:Destroy()
		return nil
	end

	ensureAnimator(humanoid)

	local hrp = morph:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and not morph.PrimaryPart then
		morph.PrimaryPart = hrp
	end

	morph.Parent = workspace
	morph:PivotTo(spawnCf)

	-- End flight before swapping Character so movers don't stick across bodies
	local HexFlightService = require(script.Parent.HexFlightService)
	local PhotonFlightService = require(script.Parent.PhotonFlightService)
	HexFlightService.endFlight(player, false)
	PhotonFlightService.endFlight(player, false)

	morphReady[player] = true
	player.Character = morph
	if applyAvatar then
		applyPlayerAppearance(humanoid, morph, player)
	end
	ensureAnimator(humanoid)
	MorphAnimationHelper.applyToModel(morph, GameConstants.BASIC_IDLE_ANIM)
	morph:PivotTo(spawnCf)

	if oldCharacter.Parent then
		CombatHelper.silenceDeathSounds(oldCharacter)
		oldCharacter:Destroy()
	end

	return morph
end

local function freezeForMenu(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end
end

local function replaceWithHeroMorph(player: Player, oldCharacter: Model, heroId: string, skinId: string): Model?
	local template = CharacterRegistry.getMorphTemplate(heroId, skinId)
	if not template then
		warn("[CharacterService] Missing morph for", heroId, skinId)
		return nil
	end

	local spawnCf = oldCharacter:GetPivot()
	local morph = template:Clone()
	morph.Name = player.Name

	for _, desc in morph:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc.Disabled = true
		end
	end

	MorphVfxTint.applyForSkin(morph, heroId, skinId, template.Name)
	MorphAnimationHelper.applyToModel(morph, MorphAnimationHelper.idleIdForMorphName(template.Name))

	local humanoid = morph:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[CharacterService] Morph has no Humanoid:", template.Name)
		morph:Destroy()
		return nil
	end
	ensureAnimator(humanoid)

	local hrp = morph:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and not morph.PrimaryPart then
		morph.PrimaryPart = hrp
	end

	morph.Parent = workspace
	morph:PivotTo(spawnCf)

	local HexFlightService = require(script.Parent.HexFlightService)
	local PhotonFlightService = require(script.Parent.PhotonFlightService)
	HexFlightService.endFlight(player, false)
	PhotonFlightService.endFlight(player, false)

	morphReady[player] = true
	player.Character = morph
	ensureAnimator(humanoid)
	morph:PivotTo(spawnCf)

	if oldCharacter.Parent then
		CombatHelper.silenceDeathSounds(oldCharacter)
		oldCharacter:Destroy()
	end

	return morph
end

function CharacterService.getSelectedHero(player: Player): string?
	return selectedHero[player]
end

function CharacterService.getLookMode(player: Player): string
	return lookModeByPlayer[player] or "clothes"
end

function CharacterService.wantsPlayerAvatar(player: Player): boolean
	local mode = lookModeByPlayer[player]
	return mode == "clothes" or mode == "avatar"
end

function CharacterService.isSprintBlocked(character: Model): boolean
	if character:GetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute("AbsorbActive") == true then
		return true
	end
	if character:GetAttribute("BarrageSpinActive") == true then
		return true
	end
	if character:GetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.HIGH_FALL_LANDING_ATTRIBUTE) == true then
		return true
	end
	return AbilityCooldownHelper.isAnyActive(character, SPRINT_BLOCK_ABILITIES)
end

function CharacterService.applyHeroToCharacter(player: Player, character: Model, heroId: string?)
	local resolvedHeroId = heroId or selectedHero[player]
	if not resolvedHeroId then
		return
	end
	local entry = CharacterRegistry.getById(resolvedHeroId)
	if not entry then
		return
	end

	character:SetAttribute(
		GameConstants.HERO_ATTRIBUTE,
		if resolvedHeroId == "scarlet_witch_classic" then "scarlet_witch" else resolvedHeroId
	)
	character:SetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE, pendingSkin[player] or "base")
	character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, entry.maxEnergy)
	character:SetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE, entry.maxEnergy)
	character:SetAttribute(GameConstants.STAMINA_ATTRIBUTE, GameConstants.MAX_STAMINA)
	character:SetAttribute(GameConstants.MAX_STAMINA_ATTRIBUTE, GameConstants.MAX_STAMINA)
	if resolvedHeroId == "jean_grey" then
		character:SetAttribute(GameConstants.MG_RESTRAINT_ATTRIBUTE, 0)
		character:SetAttribute(GameConstants.MG_RESTRAINT_MAX_ATTRIBUTE, GameConstants.MG_RESTRAINT_MAX)
		character:SetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.MG_WAKING_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.MG_ASTRAL_END_AT_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.MG_HAIR_TIED_ATTRIBUTE, false)
	end
	if resolvedHeroId == "invisible_woman" then
		character:SetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE, 0)
		character:SetAttribute(GameConstants.IW_HYPERSPACE_MAX_ATTRIBUTE, GameConstants.IW_HYPERSPACE_MAX)
		character:SetAttribute(GameConstants.IW_HYPERSPACE_LOCK_ATTRIBUTE, nil)
	end
	if resolvedHeroId == "scarlet_witch" or resolvedHeroId == "scarlet_witch_classic" then
		character:SetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE, 0)
		character:SetAttribute(GameConstants.SW_CONTROL_MAX_ATTRIBUTE, GameConstants.SW_CONTROL_MAX)
		character:SetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.SW_CONTROL_LOCK_UNTIL_ATTRIBUTE, nil)
	end
	character:SetAttribute(GameConstants.SPRINTING_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.HEX_BLAST_MODE_ATTRIBUTE, "Single")
	character:SetAttribute(GameConstants.TK_MODE_ATTRIBUTE, "Single")
	character:SetAttribute(GameConstants.ULTIMATE_MODE_ATTRIBUTE, "Disintegration")
	character:SetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE, "Normal")
	character:SetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE, 0)
	character:SetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.BINARY_UNTIL_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.LOKI_REFLECT_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE, "Dash")
	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.PROTECTED_UNTIL_ATTRIBUTE, AbilityCooldownHelper.getNow() + GameConstants.PROTECTED_DURATION)
	character:SetAttribute(
		GameConstants.POWERS_DISABLED_UNTIL,
		AbilityCooldownHelper.getNow() + GameConstants.PROTECTED_DURATION
	)
	local skinId = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
	if type(skinId) ~= "string" then
		skinId = "base"
	end
	character:SetAttribute(
		GameConstants.SHOP_DAMAGE_BUFF_ATTRIBUTE,
		PlayerDataService.getDamageBuff(player, resolvedHeroId, skinId)
	)

	local spawnFx = VfxHelper.attachNamedAssetToHrp(character, "SpawnAura")
	if #spawnFx > 0 then
		task.delay(GameConstants.PROTECTED_DURATION, function()
			VfxHelper.fadeOutAndDestroyParticles(spawnFx, 0.35, 1.2)
		end)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local hp = entry.health
		if resolvedHeroId == "invisible_woman" and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
			hp = GameConstants.IW_HEALTH_MODERN
		end
		humanoid.MaxHealth = hp
		humanoid.Health = hp
		humanoid.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
		if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix" then
			humanoid.BreakJointsOnDeath = false
		end
	end

	if resolvedHeroId == "scarlet_witch" or resolvedHeroId == "scarlet_witch_classic" then
		task.defer(function()
			if character.Parent then
				HandParticleHelper.ensure(character)
			end
		end)
	elseif resolvedHeroId == "captain_marvel" then
		task.defer(function()
			if character.Parent then
				local PhotonParticleHelper = require(script.Parent.PhotonParticleHelper)
				PhotonParticleHelper.ensure(character)
			end
		end)
	end

	task.defer(function()
		local NameplateService = require(script.Parent.NameplateService)
		NameplateService.refresh(character)
	end)
	CombatHelper.bindSilenceDeathSounds(character)
end

function CharacterService.markAbilityUse(character: Model)
	character:SetAttribute(GameConstants.LAST_ABILITY_USE_ATTRIBUTE, AbilityCooldownHelper.getNow())
end

function CharacterService.spendEnergy(character: Model, amount: number): boolean
	local cost = amount
	if
		character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "captain_marvel"
		and character:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true
	then
		cost *= GameConstants.BINARY_ENERGY_MULT
	end
	local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" or energy < cost then
		return false
	end
	character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, energy - cost)
	CharacterService.markAbilityUse(character)
	return true
end

function CharacterService.regenEnergy(character: Model, dt: number)
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return
	end
	if AbilityCooldownHelper.isActive(character, "hex_beam") then
		return
	end
	if AbilityCooldownHelper.isActive(character, "photon_beam") then
		return
	end
	if AbilityCooldownHelper.isActive(character, "telekinesis") then
		return
	end
	if AbilityCooldownHelper.isActive(character, "regeneration") then
		return
	end
	local lastUse = character:GetAttribute(GameConstants.LAST_ABILITY_USE_ATTRIBUTE)
	if type(lastUse) == "number" then
		local now = AbilityCooldownHelper.getNow()
		if now - lastUse < GameConstants.ENERGY_REGEN_DELAY then
			return
		end
	end
	local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	local maxEnergy = character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" or type(maxEnergy) ~= "number" then
		return
	end
	if energy < maxEnergy then
		character:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.min(maxEnergy, energy + GameConstants.ENERGY_REGEN_PER_SEC * dt)
		)
	end
end

function CharacterService.setHero(player: Player, heroId: string, lookMode: any): boolean
	local entry = CharacterRegistry.getById(heroId)
	if not entry then
		return false
	end
	if heroId == "jean_grey" and lookMode == "phoenix" then
		return false
	end
	local skinId = if type(lookMode) == "string" and lookMode ~= "" then lookMode else "base"
	if skinId == "starter" or skinId == "clothes" or skinId == "avatar" then
		skinId = "base"
	end
	PlayerDataService.waitForProfile(player, 10)
	if not PlayerDataService.canDeploy(player, heroId, skinId) then
		return false
	end
	local skin = CharacterRegistry.getSkin(entry, skinId)
	if skin.blocked then
		return false
	end
	if not PlayerDataService.ownsSkin(player, heroId, skin.id) then
		return false
	end
	selectedHero[player] = heroId
	pendingDeploy[player] = heroId
	pendingSkin[player] = skin.id
	lookModeByPlayer[player] = "morph"
	return true
end

function CharacterService.init()
	Players.RespawnTime = 6
	MorphAnimationHelper.patchAssets()
	local selectHero = Remotes.getEvent("SelectHero")
	selectHero.OnServerEvent:Connect(function(player: Player, heroId: any, lookMode: any)
		if type(heroId) ~= "string" then
			return
		end
		if not CharacterService.setHero(player, heroId, lookMode) then
			return
		end
		player:LoadCharacter()
	end)

	local function onCharacterAdded(player: Player, character: Model)
		CombatHelper.bindSilenceDeathSounds(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			ensureAnimator(humanoid)
			humanoid.Died:Connect(function()
				CombatHelper.silenceDeathSounds(character)
				-- Only clear after a deployed hero dies — not blank LoadCharacter / morph swaps
				if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= nil then
					local okMg, MarvelGirlService = pcall(function()
						return require(script.Parent.MarvelGirlService)
					end)
					if okMg and MarvelGirlService.tryPhoenixDown(player, character) then
						return
					end
					clearHeroSelection(player)
				end
			end)
		end

		local deployId = pendingDeploy[player] or selectedHero[player]
		if not deployId then
			freezeForMenu(character)
			return
		end

		local skinId = pendingSkin[player] or "base"

		if morphReady[player] then
			morphReady[player] = false
			pendingDeploy[player] = nil
			task.defer(function()
				if character.Parent then
					local hum = character:FindFirstChildOfClass("Humanoid")
					if hum then
						ensureAnimator(hum)
					end
					CharacterService.applyHeroToCharacter(player, character, deployId)
				end
			end)
			return
		end

		task.spawn(function()
			if not character.Parent then
				return
			end
			task.wait()
			if not character.Parent or player.Character ~= character then
				return
			end

			local morph = replaceWithHeroMorph(player, character, deployId, skinId)
			if not morph then
				pendingDeploy[player] = nil
				freezeForMenu(character)
			end
		end)
	end

	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	Players.PlayerRemoving:Connect(clearHeroSelection)
end

return CharacterService
