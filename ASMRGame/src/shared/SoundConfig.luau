local function id(assetId: number | string): string
	return "rbxassetid://" .. tostring(assetId)
end

local pools = {
	BalloonPop = {
		id(7948526859),
		id(118644925977836),
		id(9113263649),
		id(6153757830),
		id(9113263647),
		id(9113263444),
	},

	KeyboardClick = {
		id(127105730240202),
		id(72826565018765),
		id(96591611478915),
		id(70396624145217),
		id(18439146929),
		id(18439142106),
		id(18439144240),
	},

	SlimeSquish = {
		id(87295773843957),
		id(133222321566847),
		id(132692232535882),
		id(109872799119131),
		id(6916371803),
	},

	FidgetClick = {
		id(9113977066),
		id(103866342467024),
		id(9118828698),
	},

	WaterDrop = {
		id(125517655791883),
		id(102332681553777),
		id(127983695683416),
		id(18180833536),
		id(92026048274511),
	},
}

local SoundConfig = {
	BalloonPop = pools.BalloonPop,
	KeyboardClick = pools.KeyboardClick,
	SlimeSquish = pools.SlimeSquish,
	FidgetClick = pools.FidgetClick,
	WaterDrop = pools.WaterDrop,

	-- Reuse your working uploads until dedicated IDs are added
	BubblePop = pools.BalloonPop,
	SoapCut = pools.KeyboardClick,
	Crinkle = pools.FidgetClick,
	SandPour = pools.SlimeSquish,
	SwitchToggle = pools.FidgetClick,
}

function SoundConfig.pick(key: string): string?
	local entry = SoundConfig[key]
	if entry == nil then
		return nil
	end
	if type(entry) == "string" then
		return entry
	end
	if type(entry) == "table" and #entry > 0 then
		return entry[math.random(1, #entry)]
	end
	return nil
end

return SoundConfig
