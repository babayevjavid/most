local Lighting = game:GetService("Lighting")

local CosmicLightingService = {}

local function safeSet(label: string, callback: () -> ())
	local ok, err = pcall(callback)
	if not ok then
		warn(("[CosmicLighting] Skipped %s: %s"):format(label, tostring(err)))
	end
end

function CosmicLightingService.Apply()
	safeSet("core lighting", function()
		Lighting.GlobalShadows = true
		Lighting.ShadowSoftness = 0.18
		Lighting.ClockTime = 13.5
		Lighting.Brightness = 2.15
		Lighting.ExposureCompensation = 0.02
		Lighting.EnvironmentDiffuseScale = 0.42
		Lighting.EnvironmentSpecularScale = 0.48
		Lighting.OutdoorAmbient = Color3.fromRGB(168, 172, 178)
		Lighting.Ambient = Color3.fromRGB(138, 142, 148)
		Lighting.ColorShift_Top = Color3.fromRGB(240, 244, 250)
		Lighting.ColorShift_Bottom = Color3.fromRGB(210, 205, 198)
	end)

	safeSet("atmosphere", function()
		local atmosphere = Lighting:FindFirstChild("TrainingAtmosphere")
		if atmosphere and atmosphere:IsA("Atmosphere") then
			atmosphere.Density = 0.18
			atmosphere.Haze = 0.45
			atmosphere.Glare = 0.05
		end
	end)

	safeSet("post effects", function()
		local bloom = Lighting:FindFirstChild("TrainingBloom")
		if bloom and bloom:IsA("BloomEffect") then
			bloom.Intensity = 0.08
			bloom.Threshold = 1.6
		end

		local colorCorrection = Lighting:FindFirstChild("TrainingColor")
		if colorCorrection and colorCorrection:IsA("ColorCorrectionEffect") then
			colorCorrection.Brightness = 0.02
			colorCorrection.Contrast = 0.03
			colorCorrection.Saturation = 0.04
		end
	end)

	safeSet("sky", function()
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			sky.StarCount = 0
			sky.SunAngularSize = 14
		end
	end)
end

return CosmicLightingService
