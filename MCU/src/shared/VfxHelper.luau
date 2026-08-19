--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConstants = require(script.Parent.GameConstants)

local VfxHelper = {}

-- Brighter scarlet / chaos red
local CHAOS = Color3.fromRGB(210, 45, 55)
local CHAOS_SOFT = Color3.fromRGB(235, 80, 90)
local PHOTON = Color3.fromRGB(255, 210, 70)
local PHOTON_SOFT = Color3.fromRGB(255, 235, 140)

function VfxHelper.chaosColor(): Color3
	return CHAOS
end

function VfxHelper.chaosSoft(): Color3
	return CHAOS_SOFT
end

function VfxHelper.photonColor(): Color3
	return PHOTON
end

function VfxHelper.photonSoft(): Color3
	return PHOTON_SOFT
end

local BLOCKED_SOUND_IDS: { [string]: boolean } = {
	["390417313"] = true,
	["4458980745"] = true,
	["4282172813"] = true,
	["5608513766"] = true,
}

local function soundIdKey(soundId: string): string
	local id = string.gsub(soundId, "^rbxassetid://", "")
	id = string.gsub(id, "^https?://www%.roblox%.com/asset/%?id=", "")
	return id
end

local scarletSoundsSanitized = false
local allSoundsSanitized = false

local function muteBlockedSound(sound: Sound)
	if BLOCKED_SOUND_IDS[soundIdKey(sound.SoundId)] then
		sound:Stop()
		sound.SoundId = ""
		sound.Volume = 0
		sound.Playing = false
	end
end

local function stripBlockedSounds(root: Instance)
	local function scrub(inst: Instance)
		if inst:IsA("Sound") then
			muteBlockedSound(inst)
		end
	end
	scrub(root)
	for _, desc in root:GetDescendants() do
		scrub(desc)
	end
end

local function sanitizeAllAssetSounds()
	if allSoundsSanitized then
		return
	end
	allSoundsSanitized = true
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return
	end
	stripBlockedSounds(assets)
	assets.DescendantAdded:Connect(function(desc)
		if desc:IsA("Sound") then
			muteBlockedSound(desc)
		end
	end)
end

local function sanitizeScarletSoundTemplates()
	if scarletSoundsSanitized then
		return
	end
	scarletSoundsSanitized = true
	sanitizeAllAssetSounds()
end

task.defer(function()
	local assets = ReplicatedStorage:WaitForChild("Assets", 60)
	if assets then
		sanitizeAllAssetSounds()
	end
end)

do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		sanitizeAllAssetSounds()
	end
end

	do
		stripBlockedSounds(game)
		game.DescendantAdded:Connect(function(desc)
			if desc:IsA("Sound") then
				muteBlockedSound(desc)
			end
		end)
	end

local function getLokiAsset(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Loki")
	return folder and folder:FindFirstChild(name)
end

local function getScarletAsset(...: string): Instance?
	sanitizeScarletSoundTemplates()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	for _, folderName in { "ScarletWitchClassic", "ScarletWitch" } do
		local current: Instance? = assets:FindFirstChild(folderName)
		local ok = current ~= nil
		for _, name in { ... } do
			if not current then
				ok = false
				break
			end
			current = current:FindFirstChild(name)
		end
		if ok and current then
			return current
		end
	end
	return nil
end

local function getCaptainMarvelAsset(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("CaptainMarvel")
	return folder and folder:FindFirstChild(name)
end

local function getDaggerAsset(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Dagger")
	return folder and folder:FindFirstChild(name)
end

function VfxHelper.daggerColor(): Color3
	return GameConstants.DAGGER_LIGHT
end

function VfxHelper.daggerSoft(): Color3
	return GameConstants.DAGGER_LIGHT_SOFT
end

function VfxHelper.tintParticles(root: Instance, color: Color3)
	local seq = ColorSequence.new(color)
	local function tint(inst: Instance)
		if inst:IsA("ParticleEmitter") then
			inst.Color = seq
		elseif inst:IsA("Beam") then
			inst.Color = seq
		elseif inst:IsA("Trail") then
			inst.Color = seq
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") then
			inst.Color = color
		end
	end
	tint(root)
	for _, desc in root:GetDescendants() do
		tint(desc)
	end
end

function VfxHelper.getMarvelGirlAsset(...: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local current: Instance? = assets and (assets:FindFirstChild("JeanGrey") or assets:FindFirstChild("MarvelGirl"))
	for _, name in { ... } do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

function VfxHelper.getInvisibleWomanAsset(...: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local current: Instance? = assets and assets:FindFirstChild("InvisibleWoman")
	for _, name in { ... } do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end
local function collectBeams(root: Instance): { Beam }
	local list: { Beam } = {}
	if root:IsA("Beam") then
		table.insert(list, root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("Beam") then
			table.insert(list, desc)
		end
	end
	return list
end

local function collectTrails(root: Instance): { Trail }
	local list: { Trail } = {}
	if root:IsA("Trail") then
		table.insert(list, root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("Trail") then
			table.insert(list, desc)
		end
	end
	return list
end

local function collectParticleEmitters(root: Instance): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			table.insert(list, desc)
		end
	end
	if root:IsA("ParticleEmitter") then
		table.insert(list, root)
	end
	return list
end

--[[ Enable + Emit immediately (do not wait on Rate). Uses EmitCount attr when set. ]]
local function emitAllParticles(root: Instance, count: number?)
	for _, em in collectParticleEmitters(root) do
		em.Enabled = true
		local attr = em:GetAttribute("EmitCount")
		local n: number
		if type(attr) == "number" and attr > 0 then
			n = math.floor(attr)
		elseif count then
			n = count
		else
			n = math.clamp(math.floor(em.Rate * 0.25 + 0.5), 8, 80)
		end
		em:Emit(n)
	end
end

local function setParticlesEnabled(root: Instance, enabled: boolean)
	for _, em in collectParticleEmitters(root) do
		em.Enabled = enabled
	end
	for _, beam in collectBeams(root) do
		beam.Enabled = enabled
	end
	for _, trail in collectTrails(root) do
		trail.Enabled = enabled
	end
end

--[[ BlastImpact attachment on an invisible damage-zone part at the hit/end position. ]]
function VfxHelper.spawnBlastImpact(origin: Vector3, radius: number?, heroFolder: string?)
	local r = math.clamp(radius or 3, 1.5, 8)
	local template = if heroFolder == "CaptainMarvel"
		then getCaptainMarvelAsset("BlastImpact")
		else getScarletAsset("BlastImpact")
	if not template and heroFolder == "CaptainMarvel" then
		template = getScarletAsset("BlastImpact")
	end

	local zone = Instance.new("Part")
	zone.Name = if heroFolder == "CaptainMarvel" then "PhotonBlastImpactZone" else "HexBlastImpactZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = workspace

	if template then
		local att = template:Clone()
		att.Name = "BlastImpact"
		att.Parent = zone
		emitAllParticles(att, 14)
		setParticlesEnabled(att, true)
		task.delay(0.15, function()
			if att.Parent then
				setParticlesEnabled(att, false)
			end
		end)
	else
		-- Fallback if asset missing
		local color = if heroFolder == "CaptainMarvel" then PHOTON else CHAOS
		VfxHelper.spawnPulseRing(origin, r * 0.7, color, 0.28)
		VfxHelper.spawnBurstSparks(origin, color, 10)
	end

	Debris:AddItem(zone, 2.2)
	return zone
end

function VfxHelper.spawnPhotonBlastImpact(origin: Vector3, radius: number?)
	return VfxHelper.spawnBlastImpact(origin, radius, "CaptainMarvel")
end

function VfxHelper.spawnLokiBlastImpact(origin: Vector3, radius: number?)
	local r = math.clamp(radius or 3, 1.5, 8)
	local template = getLokiAsset("ImpactParticle")
	local zone = Instance.new("Part")
	zone.Name = "LokiBlastImpactZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = workspace

	if template then
		local att = template:Clone()
		att.Name = "ImpactParticle"
		att.Parent = zone
		emitAllParticles(att, 14)
		setParticlesEnabled(att, true)
		task.delay(0.15, function()
			if att.Parent then
				setParticlesEnabled(att, false)
			end
		end)
	else
		VfxHelper.spawnPulseRing(origin, r * 0.7, Color3.fromRGB(80, 255, 120), 0.28)
		VfxHelper.spawnBurstSparks(origin, Color3.fromRGB(80, 255, 120), 10)
	end

	Debris:AddItem(zone, 2.2)
	return zone
end

function VfxHelper.spawnTemplateImpact(template: Instance?, origin: Vector3, emitCount: number?)
	if not template then
		return nil
	end
	local host = Instance.new("Part")
	host.Name = "HeroImpactHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.CastShadow = false
	host.Size = Vector3.new(1.2, 1.2, 1.2)
	host.CFrame = CFrame.new(origin)
	host.Parent = workspace
	local fx = template:Clone()
	if fx:IsA("Attachment") then
		fx.Parent = host
		fx.CFrame = CFrame.identity
	else
		fx.Parent = host
		if fx:IsA("BasePart") then
			fx.CFrame = CFrame.new(origin)
			fx.Anchored = true
			fx.CanCollide = false
			fx.Transparency = 1
		elseif fx:IsA("Model") then
			fx:PivotTo(CFrame.new(origin))
		end
		local nested = fx:FindFirstChildWhichIsA("Attachment", true)
		if nested then
			nested.CFrame = CFrame.identity
		end
	end
	emitAllParticles(fx, emitCount or 10)
	setParticlesEnabled(fx, true)
	task.delay(0.1, function()
		if fx.Parent then
			setParticlesEnabled(fx, false)
		end
	end)
	Debris:AddItem(host, 3.2)
	return host
end

function VfxHelper.spawnMarvelGirlPsionicImpact(origin: Vector3, radius: number?, tintColor: Color3?)
	local r = math.clamp(radius or 3, 1.5, 12)
	local template = VfxHelper.getMarvelGirlAsset("PsionicBolt", "BoltImpactAttachment")
		or VfxHelper.getMarvelGirlAsset("PsionicBlastImpact")
	local zone = Instance.new("Part")
	zone.Name = "MgPsionicImpactZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.CastShadow = false
	zone.Parent = workspace

	if template then
		local att: Attachment
		if template:IsA("Attachment") then
			att = template:Clone()
		else
			local nested = template:FindFirstChildWhichIsA("Attachment", true)
			if nested then
				att = nested:Clone()
			else
				att = Instance.new("Attachment")
			end
		end
		att.Parent = zone
		if tintColor then
			VfxHelper.tintParticles(att, tintColor)
		end
		VfxHelper.setParticlesEnabled(att, true)
		VfxHelper.emitAllParticles(att, 10)
		VfxHelper.disableImpactSoon(att)
	end
	task.delay(3, function()
		if zone.Parent then
			zone:Destroy()
		end
	end)
	return zone
end

--[[ Dagger radiant / light impact burst. Tries several asset names. ]]
function VfxHelper.spawnDaggerLightImpact(origin: Vector3, radius: number?)
	local r = math.clamp(radius or 3, 1.5, 12)
	local template: Instance? = nil
	for _, name in {
		"LightImpactAttachment",
		"RadiantImpact",
		"RadiantBombImpact",
		"RadiantImpactAttachment",
		"BlastImpact",
		"ImpactAttachment",
	} do
		template = getDaggerAsset(name)
		if template then
			break
		end
	end

	local zone = Instance.new("Part")
	zone.Name = "DaggerLightImpactZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.CastShadow = false
	zone.Parent = workspace

	if template then
		local att: Attachment? = nil
		if template:IsA("Attachment") then
			att = template:Clone()
		else
			local nested = template:FindFirstChildWhichIsA("Attachment", true)
			if nested then
				att = nested:Clone()
			end
		end
		if att then
			att.Name = "DaggerImpact"
			att.Position = Vector3.zero
			att.Orientation = Vector3.zero
			att.Parent = zone
			VfxHelper.tintParticles(att, GameConstants.DAGGER_LIGHT)
			setParticlesEnabled(att, true)
			emitAllParticles(att, 24)
			task.delay(0.1, function()
				if att and att.Parent then
					setParticlesEnabled(att, false)
				end
			end)
		else
			warn("[VfxHelper] Dagger impact asset found but no Attachment inside")
		end
	else
		warn("[VfxHelper] Missing Dagger LightImpactAttachment / RadiantImpact under Assets.Dagger")
	end

	Debris:AddItem(zone, 2.5)
	return zone
end

--[[ Scarlet Witch LandingAttachment (Chaos Impact). ]]
function VfxHelper.spawnScarletLandingImpact(origin: Vector3, radius: number?)
	local r = math.clamp(radius or GameConstants.CHAOS_IMPACT_RADIUS, 4, 40)
	local template = getScarletAsset("LandingAttachment")
	local zone = Instance.new("Part")
	zone.Name = "ChaosImpactZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = workspace

	if template then
		local att = template:Clone()
		att.Name = "LandingAttachment"
		att.Parent = zone
		-- Burst immediately (no wait for Rate)
		for _, em in collectParticleEmitters(att) do
			em.Enabled = true
			local burst = math.clamp(math.floor(em.Rate * 0.2 + 0.5), 12, 80)
			em:Emit(burst)
		end
		task.delay(0.35, function()
			if att.Parent then
				setParticlesEnabled(att, false)
			end
		end)
	else
		VfxHelper.spawnPulseRing(origin, r * 0.55, VfxHelper.chaosColor(), 0.4)
		VfxHelper.spawnBurstSparks(origin, VfxHelper.chaosColor(), 18)
	end
	VfxHelper.spawnPulseRing(origin, r * 0.85, VfxHelper.chaosSoft(), 0.35)

	Debris:AddItem(zone, 2.8)
	return zone
end

--[[ Captain Marvel GroundSlamAttachment impact burst. ]]
function VfxHelper.spawnPhotonGroundSlam(origin: Vector3, radius: number?)
	local r = math.clamp(radius or 10, 2, 16)
	local template = getCaptainMarvelAsset("GroundSlamAttachment")

	local zone = Instance.new("Part")
	zone.Name = "PhotonGroundSlamZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = workspace

	if template then
		local att = template:Clone()
		att.Name = "GroundSlamAttachment"
		if att:IsA("Attachment") then
			att.Parent = zone
		else
			local nested = att:FindFirstChildWhichIsA("Attachment", true)
			if nested then
				nested.Parent = zone
				att:Destroy()
				att = nested
			else
				att.Parent = zone
			end
		end
		emitAllParticles(att, 20)
		setParticlesEnabled(att, true)
		task.delay(0.25, function()
			if att.Parent then
				setParticlesEnabled(att, false)
			end
		end)
		task.delay(3, function()
			if zone.Parent then
				zone:Destroy()
			end
		end)
	else
		VfxHelper.spawnPulseRing(origin, r * 0.75, PHOTON, 0.35)
		VfxHelper.spawnBurstSparks(origin, PHOTON, 16)
		Debris:AddItem(zone, 2.5)
	end
	return zone
end

--[[ Captain Marvel ExplosionAttachment impact burst. ]]
function VfxHelper.spawnPhotonExplosionImpact(origin: Vector3, radius: number?)
	local r = math.clamp(radius or 10, 2, 16)
	local template = getCaptainMarvelAsset("ExplosionAttachment")

	local zone = Instance.new("Part")
	zone.Name = "PhotonExplosionImpactZone"
	zone.Shape = Enum.PartType.Ball
	zone.Size = Vector3.new(r * 2, r * 2, r * 2)
	zone.CFrame = CFrame.new(origin)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = workspace

	if template then
		local att = template:Clone()
		att.Name = "ExplosionAttachment"
		if att:IsA("Attachment") then
			att.Parent = zone
		else
			local nested = att:FindFirstChildWhichIsA("Attachment", true)
			if nested then
				nested.Parent = zone
				att:Destroy()
				att = nested
			else
				att.Parent = zone
			end
		end
		emitAllParticles(att, 18)
		setParticlesEnabled(att, true)
		task.delay(0.2, function()
			if att.Parent then
				setParticlesEnabled(att, false)
			end
		end)
	else
		VfxHelper.spawnPulseRing(origin, r * 0.7, PHOTON, 0.32)
		VfxHelper.spawnBurstSparks(origin, PHOTON, 14)
	end

	Debris:AddItem(zone, 2.5)
	return zone
end

function VfxHelper.getScarletAsset(...: string): Instance?
	return getScarletAsset(...)
end

function VfxHelper.getCaptainMarvelAsset(name: string): Instance?
	return getCaptainMarvelAsset(name)
end

function VfxHelper.emitAllParticles(root: Instance, count: number?)
	emitAllParticles(root, count)
end

function VfxHelper.setParticlesEnabled(root: Instance, enabled: boolean)
	setParticlesEnabled(root, enabled)
end

function VfxHelper.disableImpactSoon(root: Instance)
	task.delay(0.1, function()
		if root.Parent then
			setParticlesEnabled(root, false)
		end
	end)
end

function VfxHelper.spawnInvisibleWomanDiscImpact(origin: Vector3)
	local folder = VfxHelper.getInvisibleWomanAsset("DiscThrow")
	local names = {
		"DiscImpactAttachment",
		"DiscImpact",
		"ImpactAttachment",
		"Impact",
		"BoltImpactAttachment",
		"BoltImpact",
		"HitImpact",
	}
	local template: Instance? = nil
	if folder then
		for _, name in names do
			local found = folder:FindFirstChild(name)
			if found then
				template = found
				break
			end
		end
		if not template then
			for _, name in names do
				local found = folder:FindFirstChild(name, true)
				if found then
					template = found
					break
				end
			end
		end
		if not template then
			for _, desc in folder:GetDescendants() do
				if string.find(string.lower(desc.Name), "impact") then
					template = desc
					break
				end
			end
		end
	end

	local host = Instance.new("Part")
	host.Name = "IwDiscImpactHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.CastShadow = false
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(origin)
	host.Parent = workspace

	local spawned: Instance? = nil
	if template then
		local fx = template:Clone()
		spawned = fx
		if fx:IsA("Attachment") then
			fx.CFrame = CFrame.identity
			fx.Parent = host
		elseif fx:IsA("BasePart") then
			fx.Anchored = true
			fx.CanCollide = false
			fx.CanQuery = false
			fx.CanTouch = false
			fx.CFrame = CFrame.new(origin)
			fx.Parent = workspace
		elseif fx:IsA("Model") then
			fx.Parent = workspace
			fx:PivotTo(CFrame.new(origin))
			for _, desc in fx:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
					desc.CanQuery = false
					desc.CanTouch = false
				end
			end
		else
			fx.Parent = host
		end
		for _, desc in fx:GetDescendants() do
			if desc:IsA("Beam") or desc:IsA("Trail") then
				desc.Enabled = true
			end
		end
		if fx:IsA("Beam") or fx:IsA("Trail") then
			fx.Enabled = true
		end
		local emitRoot = if fx:IsA("Attachment") or fx:IsA("BasePart") or fx:IsA("Model") then fx else host
		emitAllParticles(emitRoot, 5)
		VfxHelper.disableImpactSoon(emitRoot)
	end

	Debris:AddItem(host, 3.2)
	if spawned and spawned ~= host and spawned.Parent then
		Debris:AddItem(spawned, 3.2)
	end
	if not template then
		VfxHelper.spawnBurstSparks(origin, GameConstants.IW_COLOR, 16)
		VfxHelper.spawnPulseRing(origin, 2.4, GameConstants.IW_COLOR, 0.32)
	end
	return host
end

function VfxHelper.collectParticleEmitters(root: Instance): { ParticleEmitter }
	return collectParticleEmitters(root)
end

--[[
	Invisible Ball shell + PartialShieldParticleNew, oriented toward the hit.
]]
function VfxHelper.spawnPartialShieldShell(root: BasePart, hitFrom: Vector3?, emitCount: number?): BasePart?
	local template = getScarletAsset("PartialShieldParticleNew")
	if not template then
		warn("[VfxHelper] Missing Assets.ScarletWitch.PartialShieldParticleNew")
		return nil
	end

	local size = GameConstants.SHIELD_PARTIAL_SHELL_SIZE
	local shell = Instance.new("Part")
	shell.Name = "PartialShieldShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(size, size, size)
	shell.Transparency = 1
	shell.Anchored = false
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.Massless = true
	shell.CastShadow = false
	shell.Material = Enum.Material.SmoothPlastic

	-- Face the incoming projectile
	if hitFrom and (hitFrom - root.Position).Magnitude > 0.05 then
		shell.CFrame = CFrame.lookAt(root.Position, hitFrom)
	else
		shell.CFrame = root.CFrame
	end
	shell.Parent = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = shell
	weld.Parent = shell

	local clone = template:Clone()
	clone.Name = "PartialShieldParticleNew"
	if clone:IsA("Attachment") then
		clone.Parent = shell
		clone.Position = Vector3.zero
	elseif clone:IsA("ParticleEmitter") then
		clone.Parent = shell
	elseif clone:IsA("BasePart") then
		for _, em in collectParticleEmitters(clone) do
			em.Parent = shell
		end
		clone:Destroy()
	else
		-- Folder / Model / other: move emitters (and attachments) onto the shell
		for _, child in clone:GetChildren() do
			if child:IsA("Attachment") or child:IsA("ParticleEmitter") then
				child.Parent = shell
			end
		end
		for _, em in collectParticleEmitters(clone) do
			em.Parent = shell
		end
		clone:Destroy()
	end

	local count = emitCount or 10
	for _, em in collectParticleEmitters(shell) do
		em.Enabled = true
		em:Emit(count)
	end

	return shell
end

function VfxHelper.spawnBeamLine(startPos: Vector3, endPos: Vector3, color: Color3, thickness: number?, life: number?)
	-- Procedural beam-line parts disabled — use real Beam instances / Assets.
	return
end

function VfxHelper.spawnTrail(root: BasePart, color: Color3, lifetime: number)
	local trail = Instance.new("Part")
	trail.Name = "AbilityTrail"
	trail.Size = Vector3.new(1.2, 0.2, 1.2)
	trail.CFrame = root.CFrame
	trail.Anchored = true
	trail.CanCollide = false
	trail.CanQuery = false
	trail.Material = Enum.Material.ForceField
	trail.Color = color
	trail.Transparency = 0.65
	trail.Parent = workspace
	TweenService:Create(trail, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, 0.05, 0.2),
	}):Play()
	Debris:AddItem(trail, lifetime + 0.05)
end

function VfxHelper.spawnBurstSparks(origin: Vector3, color: Color3, count: number?)
	-- Procedural spark parts disabled — use Assets particle attachments.
	return
end

function VfxHelper.spawnPulseRing(origin: Vector3, radius: number, color: Color3, duration: number?)
	-- Procedural ring parts disabled — use Assets particle attachments.
	return
end

function VfxHelper.spawnImpact(origin: Vector3, color: Color3?, radius: number?)
	-- Procedural ForceField flash / ring / sparks disabled.
	return
end

--[[ Place Loki.DaggerImpact at origin and Emit(5) on each ParticleEmitter. ]]
function VfxHelper.spawnLokiDaggerImpact(origin: Vector3)
	local template = getLokiAsset("DaggerImpact")
	if not template then
		VfxHelper.spawnImpact(origin, Color3.fromRGB(80, 255, 120), 1.8)
		return
	end
	local host = Instance.new("Part")
	host.Name = "LokiDaggerImpactHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(origin)
	host.Parent = workspace

	local clone = template:Clone()
	clone.Parent = host
	if clone:IsA("Attachment") then
		clone.WorldPosition = origin
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(origin)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.Transparency = 1
	end
	emitAllParticles(clone, 5)
	Debris:AddItem(host, 3)
end

--[[ Place Loki.DetonateAttachment at origin; disable after 0.5s; delete after 3s. ]]
function VfxHelper.spawnLokiDetonateAttachment(origin: Vector3)
	local template = getLokiAsset("DetonateAttachment")
	if not template then
		VfxHelper.spawnImpact(origin, Color3.fromRGB(80, 255, 120), 4)
		return
	end
	local host = Instance.new("Part")
	host.Name = "LokiDetonateHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(origin)
	host.Parent = workspace

	local clone = template:Clone()
	clone.Parent = host
	if clone:IsA("Attachment") then
		clone.WorldCFrame = CFrame.new(origin)
	end
	setParticlesEnabled(clone, true)
	emitAllParticles(clone, 8)

	task.delay(0.5, function()
		if clone.Parent then
			setParticlesEnabled(clone, false)
			for _, em in collectParticleEmitters(clone) do
				em.Enabled = false
			end
		end
	end)
	task.delay(3, function()
		if host.Parent then
			host:Destroy()
		end
	end)
end

function VfxHelper.attachProjectileTrail(part: BasePart, color: Color3)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA0"
	a0.Position = Vector3.new(0, 0.12, 0.3)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailA1"
	a1.Position = Vector3.new(0, -0.12, -0.3)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.MinLength = 0.06
	trail.FaceCamera = true
	trail.LightEmission = 0.15
	trail.LightInfluence = 0.6
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.55, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Parent = part
end

function VfxHelper.castHandFlash(origin: Vector3, color: Color3?)
	local c = color or CHAOS
	local orb = Instance.new("Part")
	orb.Name = "HexCastFlash"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(0.5, 0.5, 0.5)
	orb.CFrame = CFrame.new(origin)
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.Material = Enum.Material.ForceField
	orb.Color = c
	orb.Transparency = 0.35
	orb.Parent = workspace
	TweenService:Create(orb, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = Vector3.new(2, 2, 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(orb, 0.35)
	VfxHelper.spawnBurstSparks(origin, c, 4)
end

function VfxHelper.getBodyPartsSorted(character: Model, feetFirst: boolean): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			table.insert(parts, desc)
		end
	end
	table.sort(parts, function(a, b)
		if feetFirst then
			return a.Position.Y < b.Position.Y
		end
		return a.Position.Y > b.Position.Y
	end)
	return parts
end

function VfxHelper.fadePartsByHeight(
	character: Model,
	toTransparency: number,
	duration: number,
	feetFirst: boolean,
	onDone: (() -> ())?,
	onPartStart: ((BasePart) -> ())?
)
	local parts = VfxHelper.getBodyPartsSorted(character, feetFirst)
	if #parts == 0 then
		if onDone then
			onDone()
		end
		return
	end
	local step = duration / math.max(#parts, 1)
	task.spawn(function()
		for _, part in parts do
			if not part.Parent then
				continue
			end
			-- Already-hidden geometry (HRP, invisible accessories) stays untouched.
			if part.Transparency >= 0.999 then
				continue
			end
			if onPartStart then
				onPartStart(part)
			end
			local tweenTime = math.max(0.08, step * 1.6)
			TweenService:Create(part, TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Transparency = toTransparency,
			}):Play()
			for _, child in part:GetChildren() do
				if child:IsA("Decal") or child:IsA("Texture") then
					if child.Transparency >= 0.999 then
						continue
					end
					TweenService:Create(child, TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
						Transparency = toTransparency,
					}):Play()
				end
			end
			task.wait(step * 0.65)
		end
		task.wait(step * 0.8)
		if onDone then
			onDone()
		end
	end)
end

export type VisiblePartSnap = {
	part: BasePart,
	transparency: number,
	decals: { { inst: Decal | Texture, transparency: number } },
}

function VfxHelper.captureVisibleParts(character: Model): { VisiblePartSnap }
	local snaps: { VisiblePartSnap } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			if desc.Name == "HumanoidRootPart" or desc.Transparency >= 0.999 then
				continue
			end
			local decals: { { inst: Decal | Texture, transparency: number } } = {}
			for _, child in desc:GetChildren() do
				if (child:IsA("Decal") or child:IsA("Texture")) and child.Transparency < 0.999 then
					table.insert(decals, { inst = child, transparency = child.Transparency })
				end
			end
			table.insert(snaps, {
				part = desc,
				transparency = desc.Transparency,
				decals = decals,
			})
		end
	end
	return snaps
end

function VfxHelper.hideCapturedParts(snaps: { VisiblePartSnap }?)
	if type(snaps) ~= "table" then
		return
	end
	for _, snap in snaps do
		if snap and snap.part and snap.part.Parent then
			snap.part.Transparency = 1
		end
		if type(snap.decals) == "table" then
			for _, d in snap.decals do
				if d and d.inst and d.inst.Parent then
					d.inst.Transparency = 1
				end
			end
		end
	end
end

function VfxHelper.restoreCapturedParts(snaps: { VisiblePartSnap }?, duration: number?, onDone: (() -> ())?)
	local fade = duration or 0.35
	if type(snaps) ~= "table" then
		if onDone then
			onDone()
		end
		return
	end
	for _, snap in snaps do
		if not snap or not snap.part or not snap.part.Parent then
			continue
		end
		TweenService:Create(snap.part, TweenInfo.new(fade, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Transparency = snap.transparency,
		}):Play()
		if type(snap.decals) == "table" then
			for _, d in snap.decals do
				if d and d.inst and d.inst.Parent then
					TweenService:Create(d.inst, TweenInfo.new(fade, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
						Transparency = d.transparency,
					}):Play()
				end
			end
		end
	end
	if onDone then
		task.delay(fade, onDone)
	end
end

function VfxHelper.setCharacterTransparency(character: Model, transparency: number)
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			if desc.Name == "HumanoidRootPart" then
				desc.Transparency = 1
			elseif desc.Transparency < 0.999 then
				desc.Transparency = transparency
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			if desc.Transparency < 0.999 then
				desc.Transparency = transparency
			end
		end
	end
end

local function isAccessoryPart(part: BasePart): boolean
	local parent = part.Parent
	while parent and parent ~= game do
		if parent:IsA("Accessory") or parent:IsA("Accoutrement") then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function VfxHelper.attachTelekinesisParticleToPart(part: BasePart): Instance?
	if part.Name == "HumanoidRootPart" or isAccessoryPart(part) then
		return nil
	end
	if part:FindFirstChild("TelekinesisParticle") then
		return part:FindFirstChild("TelekinesisParticle")
	end
	local template = getScarletAsset("TelekinesisParticle")
		or VfxHelper.getMarvelGirlAsset("TelekineticPush")
		or VfxHelper.getMarvelGirlAsset("HeadAttachment")
		or VfxHelper.getMarvelGirlAsset("HandVFXRightAttachment")
	if not template then
		return nil
	end
	local clone = template:Clone()
	clone.Name = "TelekinesisParticle"
	if clone:IsA("ParticleEmitter") or clone:IsA("Attachment") or clone:IsA("Folder") then
		clone.Parent = part
	else
		local nested = clone:FindFirstChildWhichIsA("Attachment", true)
			or clone:FindFirstChildWhichIsA("ParticleEmitter", true)
		if nested then
			local use = nested:Clone()
			use.Name = "TelekinesisParticle"
			use.Parent = part
			clone:Destroy()
			clone = use
		else
			clone.Parent = part
		end
	end
	setParticlesEnabled(clone, true)
	return clone
end

function VfxHelper.attachTelekinesisParticles(model: Model): { Instance }
	local clones: { Instance } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local clone = VfxHelper.attachTelekinesisParticleToPart(child)
			if clone then
				table.insert(clones, clone)
			end
		end
	end
	return clones
end

function VfxHelper.smoothDisableParticles(root: Instance, duration: number?)
	-- Stop spawning immediately; leftover particles die on their own lifetime.
	local fade = duration or 0.35
	for _, em in collectParticleEmitters(root) do
		em.Enabled = false
		local startRate = em.Rate
		local t0 = os.clock()
		task.spawn(function()
			while em.Parent and (os.clock() - t0) < fade do
				local a = math.clamp((os.clock() - t0) / fade, 0, 1)
				em.Rate = startRate * (1 - a)
				task.wait()
			end
			if em.Parent then
				em.Rate = 0
				em.Enabled = false
			end
		end)
	end
	for _, beam in collectBeams(root) do
		local w0 = beam.Width0
		local w1 = beam.Width1
		local t0 = os.clock()
		task.spawn(function()
			while beam.Parent and (os.clock() - t0) < fade do
				local a = math.clamp((os.clock() - t0) / fade, 0, 1)
				beam.Width0 = w0 * (1 - a)
				beam.Width1 = w1 * (1 - a)
				task.wait()
			end
			if beam.Parent then
				beam.Width0 = 0
				beam.Width1 = 0
				beam.Enabled = false
			end
		end)
	end
	for _, trail in collectTrails(root) do
		trail.Enabled = false
	end
end

function VfxHelper.fadeOutAndDestroyParticles(clones: { Instance }, fadeDuration: number?, deleteAfter: number?)
	local fade = fadeDuration or 0.4
	local waitDelete = deleteAfter or 2.4
	for _, clone in clones do
		if clone.Parent then
			VfxHelper.smoothDisableParticles(clone, fade)
		end
	end
	task.delay(waitDelete, function()
		for _, clone in clones do
			if clone.Parent then
				clone:Destroy()
			end
		end
	end)
end

function VfxHelper.retireFxSmooth(root: Instance?, fadeDuration: number?, deleteAfter: number?)
	if not root or not root.Parent then
		return
	end
	VfxHelper.fadeOutAndDestroyParticles({ root }, fadeDuration, deleteAfter)
end

--[[ Clone ReplicatedStorage.Assets.<name> attachments/particles onto HumanoidRootPart. ]]
function VfxHelper.attachNamedAssetToHrp(character: Model, assetName: string): { Instance }
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(assetName)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not template or not (hrp and hrp:IsA("BasePart")) then
		return {}
	end
	local clones: { Instance } = {}
	local function take(inst: Instance)
		local clone = inst:Clone()
		if clone:IsA("Attachment") then
			clone.Position = Vector3.zero
		end
		clone.Parent = hrp
		setParticlesEnabled(clone, true)
		emitAllParticles(clone, 10)
		table.insert(clones, clone)
	end
	if template:IsA("Attachment") or template:IsA("ParticleEmitter") then
		take(template)
	else
		for _, child in template:GetChildren() do
			if child:IsA("Attachment") or child:IsA("ParticleEmitter") then
				take(child)
			end
		end
		if #clones == 0 then
			take(template)
		end
	end
	return clones
end

local TK_MORPH_ALIASES: { [string]: { string } } = {
	UpperTorso = { "UpperTorso", "Torso" },
	LowerTorso = { "LowerTorso", "Torso" },
	Torso = { "Torso", "UpperTorso" },
	Head = { "Head" },
	LeftUpperArm = { "LeftUpperArm", "Left Arm" },
	LeftLowerArm = { "LeftLowerArm", "Left Arm" },
	LeftHand = { "LeftHand", "Left Arm" },
	RightUpperArm = { "RightUpperArm", "Right Arm" },
	RightLowerArm = { "RightLowerArm", "Right Arm" },
	RightHand = { "RightHand", "Right Arm" },
	LeftUpperLeg = { "LeftUpperLeg", "Left Leg" },
	LeftLowerLeg = { "LeftLowerLeg", "Left Leg" },
	LeftFoot = { "LeftFoot", "Left Leg" },
	RightUpperLeg = { "RightUpperLeg", "Right Leg" },
	RightLowerLeg = { "RightLowerLeg", "Right Leg" },
	RightFoot = { "RightFoot", "Right Leg" },
	["Left Arm"] = { "Left Arm", "LeftUpperArm" },
	["Right Arm"] = { "Right Arm", "RightUpperArm" },
	["Left Leg"] = { "Left Leg", "LeftUpperLeg" },
	["Right Leg"] = { "Right Leg", "RightUpperLeg" },
}

local function findVictimBodyPart(model: Model, morphName: string): BasePart?
	if morphName == "HumanoidRootPart" then
		return nil
	end
	local names = TK_MORPH_ALIASES[morphName] or { morphName }
	for _, name in names do
		local found = model:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

local function isTkMorphFx(inst: Instance): boolean
	return inst:IsA("ParticleEmitter")
		or inst:IsA("Attachment")
		or inst:IsA("Trail")
		or inst:IsA("Beam")
		or inst:IsA("PointLight")
		or inst:IsA("SpotLight")
		or inst:IsA("Folder")
end

local function hardenFollowPart(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
end

function VfxHelper.attachFxToBodyPart(template: Instance, bodyPart: BasePart, namePrefix: string?): Instance?
	local clone = template:Clone()
	stripBlockedSounds(clone)
	clone.Name = (namePrefix or "BodyFx_") .. template.Name
	if clone:IsA("Attachment") then
		clone.Position = Vector3.zero
		clone.Orientation = Vector3.zero
		clone.Parent = bodyPart
		return clone
	end
	local weldTarget: BasePart? = nil
	if clone:IsA("BasePart") then
		hardenFollowPart(clone)
		clone.CFrame = bodyPart.CFrame
		clone.Parent = bodyPart
		weldTarget = clone
	elseif clone:IsA("Model") then
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				hardenFollowPart(desc)
			end
		end
		clone:PivotTo(bodyPart.CFrame)
		clone.Parent = bodyPart
		weldTarget = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
	else
		clone.Parent = bodyPart
		return clone
	end
	if weldTarget then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "BodyFxWeld"
		weld.Part0 = bodyPart
		weld.Part1 = weldTarget
		weld.Parent = weldTarget
	end
	return clone
end

local function attachMorphFxChildren(model: Model, morph: Instance, namePrefix: string): { Instance }
	local clones: { Instance } = {}
	for _, morphPart in morph:GetDescendants() do
		if not morphPart:IsA("BasePart") then
			continue
		end
		local victimPart = findVictimBodyPart(model, morphPart.Name)
		if not victimPart then
			continue
		end
		for _, child in morphPart:GetChildren() do
			if not isTkMorphFx(child) then
				continue
			end
			local clone = child:Clone()
			stripBlockedSounds(clone)
			clone.Name = namePrefix .. child.Name
			if clone:IsA("Attachment") then
				clone.Position = Vector3.zero
				clone.Orientation = Vector3.zero
			end
			clone.Parent = victimPart
			setParticlesEnabled(clone, true)
			table.insert(clones, clone)
		end
	end
	return clones
end

function VfxHelper.attachMorphParticles(model: Model, morph: Instance): { Instance }
	return attachMorphFxChildren(model, morph, "TkMorph_")
end

function VfxHelper.attachRuneMorphFx(model: Model, morph: Instance): { Instance }
	return attachMorphFxChildren(model, morph, "SwRuneMorph_")
end

type TransparencySnap = {
	part: BasePart,
	transparency: number,
	decals: { { inst: Decal | Texture, transparency: number } },
}

function VfxHelper.capturePartTransparencies(model: Model): { TransparencySnap }
	local snaps: { TransparencySnap } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local decals: { { inst: Decal | Texture, transparency: number } } = {}
			for _, child in desc:GetChildren() do
				if child:IsA("Decal") or child:IsA("Texture") then
					table.insert(decals, { inst = child, transparency = child.Transparency })
				end
			end
			table.insert(snaps, {
				part = desc,
				transparency = desc.Transparency,
				decals = decals,
			})
		end
	end
	return snaps
end

function VfxHelper.restorePartTransparencies(snaps: { TransparencySnap }?)
	if type(snaps) ~= "table" then
		return
	end
	for _, snap in snaps do
		if snap.part and snap.part.Parent then
			snap.part.Transparency = snap.transparency
		end
		for _, d in snap.decals do
			if d.inst and d.inst.Parent then
				d.inst.Transparency = d.transparency
			end
		end
	end
end

function VfxHelper.attachHeroTelekinesisMorphParticles(model: Model, heroId: string, caster: Model?): { Instance }
	local morph: Instance? = nil
	if heroId == "jean_grey" then
		morph = VfxHelper.getMarvelGirlAsset("TelekinesisMorph")
		if not morph then
			warn("[VfxHelper] Missing Assets.JeanGrey.TelekinesisMorph")
		end
	elseif heroId == "scarlet_witch" then
		morph = getScarletAsset("TelekinesisMorph")
		if not morph then
			warn("[VfxHelper] Missing Assets.ScarletWitchClassic.TelekinesisMorph")
		end
	end
	if not morph then
		return VfxHelper.attachTelekinesisParticles(model)
	end
	local clones = VfxHelper.attachMorphParticles(model, morph)
	if heroId == "jean_grey" and caster and caster.Parent then
		local MorphVfxTint = require(script.Parent.MorphVfxTint)
		local skin = caster:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
		if skin ~= "phoenix" then
			local color = if skin == "marvel_girl"
				then GameConstants.MG_PSI_COLOR_MARVEL_GIRL
				else GameConstants.MG_PSI_COLOR
			for _, clone in clones do
				MorphVfxTint.paintFx(clone, color)
			end
		end
	end
	return clones
end

function VfxHelper.attachTelekinesisMorphParticles(model: Model): { Instance }
	return VfxHelper.attachHeroTelekinesisMorphParticles(model, "scarlet_witch", nil)
end

local function hardenWorldFx(root: Instance)
	stripBlockedSounds(root)
	local function harden(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
	end
	if root:IsA("BasePart") then
		harden(root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") then
			harden(desc)
		end
	end
end

local function snapFxToFloor(pos: Vector3, extraExclude: { Instance }?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = extraExclude and table.clone(extraExclude) or {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -180, 0), params)
	if result then
		return result.Position
	end
	return Vector3.new(pos.X, pos.Y, pos.Z)
end

function VfxHelper.snapToFloor(pos: Vector3, extraExclude: { Instance }?): Vector3
	return snapFxToFloor(pos, extraExclude)
end

local function placeWorldClone(template: Instance, at: CFrame): Instance?
	local clone = template:Clone()
	hardenWorldFx(clone)
	local pos = at.Position
	if clone:IsA("Attachment") then
		local host = Instance.new("Part")
		host.Name = clone.Name .. "Host"
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.Transparency = 1
		hardenWorldFx(host)
		host.CFrame = CFrame.new(pos)
		host.Parent = workspace
		clone.Parent = host
		setParticlesEnabled(clone, true)
		emitAllParticles(clone, 14)
		return host
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(pos) * clone.CFrame.Rotation
		clone.Parent = workspace
		setParticlesEnabled(clone, true)
		emitAllParticles(clone, 14)
		return clone
	elseif clone:IsA("Model") then
		clone.Parent = workspace
		clone:PivotTo(CFrame.new(pos) * clone:GetPivot().Rotation)
		setParticlesEnabled(clone, true)
		emitAllParticles(clone, 14)
		return clone
	else
		local host = Instance.new("Part")
		host.Name = "HexTeleportHost"
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.Transparency = 1
		hardenWorldFx(host)
		host.CFrame = CFrame.new(pos)
		host.Parent = workspace
		clone.Parent = host
		setParticlesEnabled(clone, true)
		emitAllParticles(clone, 14)
		return host
	end
end

function VfxHelper.spawnHexTeleportMark(position: Vector3): Instance?
	local template = getScarletAsset("HexTeleport", "Teleport")
	if not template then
		warn("[VfxHelper] Missing Assets.ScarletWitchClassic.HexTeleport.Teleport")
		return nil
	end
	local floorPos = snapFxToFloor(position)
	local at = CFrame.new(floorPos + Vector3.new(0, GameConstants.HEX_TELEPORT_FX_HEIGHT, 0))
	return placeWorldClone(template, at)
end

function VfxHelper.spawnHexTeleportExplosion(position: Vector3): Instance?
	local floorPos = snapFxToFloor(position)
	local fxPos = floorPos + Vector3.new(0, GameConstants.HEX_TELEPORT_FX_HEIGHT, 0)
	VfxHelper.playWorldSound(GameConstants.HEX_TELEPORT_EXPLOSION_SOUND, fxPos, 1.15)
	local at = CFrame.new(fxPos)
	local explosion = getScarletAsset("HexTeleport", "Explosion")
	local attachment = getScarletAsset("HexTeleport", "ExplosionAttachment")
	if not explosion and not attachment then
		warn("[VfxHelper] Missing Assets.ScarletWitchClassic.HexTeleport.Explosion / ExplosionAttachment")
		return nil
	end
	local spawned: { Instance } = {}
	if explosion then
		local fx = placeWorldClone(explosion, at)
		if fx then
			table.insert(spawned, fx)
		end
	end
	if attachment then
		local fx = placeWorldClone(attachment, at)
		if fx then
			table.insert(spawned, fx)
		end
	end
	task.delay(0.35, function()
		for _, fx in spawned do
			VfxHelper.retireFxSmooth(fx, 0.5, GameConstants.HEX_TELEPORT_FX_LIFE)
		end
	end)
	return spawned[1]
end

function VfxHelper.muteSounds(root: Instance)
	local function mute(inst: Instance)
		if inst:IsA("Sound") then
			inst:Stop()
			inst.Playing = false
			inst.Volume = 0
		end
	end
	mute(root)
	for _, desc in root:GetDescendants() do
		mute(desc)
	end
end

function VfxHelper.playWorldSound(soundId: string, at: Vector3, volume: number?, playbackSpeed: number?)
	if soundId == "" then
		return
	end
	local host = Instance.new("Part")
	host.Name = "WorldSfx"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.CFrame = CFrame.new(at)
	host.Parent = workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.9
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 90
	sound.RollOffMinDistance = 4
	sound.Parent = host
	if sound.IsLoaded then
		sound:Play()
	else
		sound.Loaded:Once(function()
			if sound.Parent then
				sound:Play()
			end
		end)
	end
	sound.Ended:Once(function()
		if host.Parent then
			host:Destroy()
		end
	end)
	Debris:AddItem(host, 8)
end

function VfxHelper.getWorldFollowPart(root: Instance?): BasePart?
	if not root then
		return nil
	end
	if root:IsA("BasePart") then
		return root
	end
	if root:IsA("Model") then
		return (root :: Model).PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
	end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function setWorldPosition(root: Instance, pos: Vector3)
	if root:IsA("Model") then
		local model = root :: Model
		local cf = model:GetPivot()
		model:PivotTo(CFrame.new(pos) * cf.Rotation)
	elseif root:IsA("BasePart") then
		local part = root :: BasePart
		part.CFrame = CFrame.new(pos) * part.CFrame.Rotation
	end
end

--[[
	Returns the travel VFX root plus a dedicated invisible BasePart for CameraSubject.
	camRide is NOT auto-destroyed — caller should clear the camera then destroy it after arrival.
]]
function VfxHelper.playHexTeleportTravel(
	fromPos: Vector3,
	toPos: Vector3,
	onArrived: (() -> ())?
): (Instance?, BasePart?)
	local template = getScarletAsset("HexTeleport", "Part")
	local duration = GameConstants.HEX_TELEPORT_TRAVEL_TIME
	local height = Vector3.new(0, GameConstants.HEX_TELEPORT_FX_HEIGHT, 0)
	fromPos = fromPos + height
	toPos = toPos + height
	local look = toPos - fromPos
	local fromCf = CFrame.new(fromPos)

	local camRide = Instance.new("Part")
	camRide.Name = "HexDisplacementCamRide"
	camRide.Size = Vector3.new(1.2, 1.2, 1.2)
	camRide.Transparency = 1
	camRide.Anchored = true
	camRide.CanCollide = false
	camRide.CanQuery = false
	camRide.CanTouch = false
	camRide.CastShadow = false
	camRide.Massless = true
	camRide.CFrame = fromCf
	camRide.Parent = workspace

	local mover: Instance? = nil
	if template then
		mover = placeWorldClone(template, fromCf)
	else
		warn("[VfxHelper] Missing Assets.ScarletWitchClassic.HexTeleport.Part")
	end

	local seed = math.random() * 32
	local wander = GameConstants.HEX_TELEPORT_WANDER
	local dir = if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
	local right = dir:Cross(Vector3.yAxis)
	if right.Magnitude < 0.05 then
		right = dir:Cross(Vector3.xAxis)
	end
	right = right.Unit
	local up = right:Cross(dir)
	if up.Magnitude > 0.05 then
		up = up.Unit
	else
		up = Vector3.yAxis
	end
	local dist = look.Magnitude
	local arcHeight = math.clamp(GameConstants.HEX_TELEPORT_ARC_HEIGHT + dist * 0.12, 14, 38)
	local peak = fromPos:Lerp(toPos, 0.5) + Vector3.new(0, arcHeight, 0)

	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local ease = a * a * (3 - 2 * a)
		local ab = fromPos:Lerp(peak, ease)
		local bc = peak:Lerp(toPos, ease)
		local along = ab:Lerp(bc, ease)
		local envelope = math.sin(math.pi * a)
		local ox = math.sin(a * 9.4 + seed) * wander * envelope
		local oy = math.cos(a * 6.7 + seed * 1.7) * wander * 0.55 * envelope
		local pos = along + right * ox + up * oy
		if camRide.Parent then
			camRide.CFrame = CFrame.new(pos)
		end
		if mover and mover.Parent then
			setWorldPosition(mover, pos)
		end
		if a >= 1 then
			if conn then
				conn:Disconnect()
			end
			if camRide.Parent then
				camRide.CFrame = CFrame.new(toPos)
			end
			if mover and mover.Parent then
				setWorldPosition(mover, toPos)
				VfxHelper.retireFxSmooth(mover, 0.4, GameConstants.HEX_TELEPORT_FX_LIFE)
			end
			VfxHelper.spawnHexTeleportExplosion(toPos)
			if onArrived then
				onArrived()
			end
		end
	end)
	return mover, camRide
end

task.defer(sanitizeScarletSoundTemplates)

return VfxHelper
