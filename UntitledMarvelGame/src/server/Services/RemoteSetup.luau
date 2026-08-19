--!strict



local ReplicatedStorage = game:GetService("ReplicatedStorage")



local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))



export type RemoteFolder = {

	SelectHero: RemoteEvent,

	HeroConfirmed: RemoteEvent,

	RequireReselect: RemoteEvent,

	UseAbility: RemoteEvent,

	CooldownUpdate: RemoteEvent,

	StatUpdate: RemoteEvent,

	SetSprinting: RemoteEvent,

	TelekinesisRequest: RemoteEvent,

	TelekinesisUpdate: RemoteEvent,

	TelekinesisThrow: RemoteEvent,

	TelekinesisEnd: RemoteEvent,

	ShieldSetActive: RemoteEvent,

	ChaosBeamSetActive: RemoteEvent,

	ChaosBeamLookUpdate: RemoteEvent,

	FlightToggle: RemoteEvent,

	FlightInput: RemoteEvent,

	ProjectileSteerUpdate: RemoteEvent,

}



local RemoteSetup = {}



function RemoteSetup.create(): RemoteFolder

	local folder = ReplicatedStorage:FindFirstChild("Remotes")

	if not folder then

		folder = Instance.new("Folder")

		folder.Name = "Remotes"

		folder.Parent = ReplicatedStorage

	end



	local function ensureRemote(name: string): RemoteEvent

		local existing = folder:FindFirstChild(name)

		if existing and existing:IsA("RemoteEvent") then

			return existing

		end

		if existing then

			existing:Destroy()

		end

		local remote = Instance.new("RemoteEvent")

		remote.Name = name

		remote.Parent = folder

		return remote

	end



	return {

		SelectHero = ensureRemote(Remotes.SelectHero),

		HeroConfirmed = ensureRemote(Remotes.HeroConfirmed),

		RequireReselect = ensureRemote(Remotes.RequireReselect),

		UseAbility = ensureRemote(Remotes.UseAbility),

		CooldownUpdate = ensureRemote(Remotes.CooldownUpdate),

		StatUpdate = ensureRemote(Remotes.StatUpdate),

		SetSprinting = ensureRemote(Remotes.SetSprinting),

		TelekinesisRequest = ensureRemote(Remotes.TelekinesisRequest),

		TelekinesisUpdate = ensureRemote(Remotes.TelekinesisUpdate),

		TelekinesisThrow = ensureRemote(Remotes.TelekinesisThrow),

		TelekinesisEnd = ensureRemote(Remotes.TelekinesisEnd),

		ShieldSetActive = ensureRemote(Remotes.ShieldSetActive),

		ChaosBeamSetActive = ensureRemote(Remotes.ChaosBeamSetActive),

		ChaosBeamLookUpdate = ensureRemote(Remotes.ChaosBeamLookUpdate),

		FlightToggle = ensureRemote(Remotes.FlightToggle),

		FlightInput = ensureRemote(Remotes.FlightInput),

		ProjectileSteerUpdate = ensureRemote(Remotes.ProjectileSteerUpdate),

	}

end



return RemoteSetup

