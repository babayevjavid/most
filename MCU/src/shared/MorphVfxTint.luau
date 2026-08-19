--!strict
--[[ Skin-specific particle / beam / trail recolors for morphs. ]]

local MorphVfxTint = {}

local JEAN_97_BLUE = Color3.fromRGB(65, 81, 253)
local MARVEL_GIRL_PINK = Color3.fromRGB(255, 90, 185)

function MorphVfxTint.paintFx(root: Instance, color: Color3)
	local seq = ColorSequence.new(color)
	local function paint(inst: Instance)
		if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
			inst.Color = seq
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") then
			inst.Color = color
		elseif inst:IsA("Highlight") then
			inst.FillColor = color
			inst.OutlineColor = color
		end
	end
	paint(root)
	for _, desc in root:GetDescendants() do
		paint(desc)
	end
end

--[[ X-Men '97 = blue. Marvel Girl = pink. Phoenix: leave authored. ]]
function MorphVfxTint.applyForSkin(model: Model, heroId: string?, skinId: string?, morphName: string?)
	if not model then
		return
	end
	if morphName == "JeanGreyPhoenix" or skinId == "phoenix" then
		return
	end
	if morphName == "JeanGreyMarvelGirl" or skinId == "marvel_girl" then
		MorphVfxTint.paintFx(model, MARVEL_GIRL_PINK)
		return
	end
	if heroId == "jean_grey" or morphName == "JeanGrey" then
		MorphVfxTint.paintFx(model, JEAN_97_BLUE)
	end
end

function MorphVfxTint.applyToTemplateName(model: Model, morphName: string?)
	if morphName == "JeanGreyMarvelGirl" then
		MorphVfxTint.paintFx(model, MARVEL_GIRL_PINK)
		return
	end
	if morphName == "JeanGrey" then
		MorphVfxTint.paintFx(model, JEAN_97_BLUE)
	end
end

return MorphVfxTint
