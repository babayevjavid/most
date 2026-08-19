local Util = {}

-- Top surface of the baseplate (baseplate center Y=-0.5, height 1).
Util.GROUND_Y = 0

function Util.groundCenterY(partHeight: number): number
	return Util.GROUND_Y + partHeight / 2
end

function Util.groundPosition(x: number, partHeight: number, z: number): Vector3
	return Vector3.new(x, Util.groundCenterY(partHeight), z)
end

function Util.onTopOf(baseCenter: Vector3, baseHeight: number, partHeight: number, gap: number?): Vector3
	local topY = baseCenter.Y + baseHeight / 2 + (gap or 0)
	return Vector3.new(baseCenter.X, topY + partHeight / 2, baseCenter.Z)
end

function Util.createPart(props: {
	name: string?,
	size: Vector3?,
	position: Vector3?,
	color: Color3?,
	material: Enum.Material?,
	anchored: boolean?,
	parent: Instance?,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name or "Part"
	part.Size = props.size or Vector3.new(4, 1, 4)
	part.Position = props.position or Vector3.zero
	part.Color = props.color or Color3.fromRGB(255, 255, 255)
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Anchored = if props.anchored == nil then true else props.anchored
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = props.canCollide == true
	part.CanTouch = part.CanCollide
	if props.transparency then
		part.Transparency = props.transparency
	end
	if props.shape then
		part.Shape = props.shape
	end
	if props.parent then
		part.Parent = props.parent
	end
	return part
end

function Util.prepareInteractive(part: BasePart, triggerRadius: number?)
	part.CanCollide = true
	part.CanTouch = true
	if triggerRadius then
		part:SetAttribute("TriggerRadius", triggerRadius)
	end
end

function Util.tagInteractive(part: BasePart, activityType: string, elementId: string, stationName: string)
	part:SetAttribute("ActivityType", activityType)
	part:SetAttribute("ElementId", elementId)
	part:SetAttribute("StationName", stationName)
	Util.prepareInteractive(part)
end

function Util.addWalkZone(station: Model, platformSize: Vector3, platformPosition: Vector3)
	local zone = Util.createPart({
		name = "WalkZone",
		size = platformSize + Vector3.new(6, 14, 6),
		position = platformPosition + Vector3.new(0, 7.5, 0),
		color = Color3.fromRGB(255, 255, 255),
		parent = station,
		canCollide = false,
	})
	zone.Transparency = 1
	zone.CanTouch = false
	zone:SetAttribute("ZoneType", "Station")
	zone:SetAttribute("StationName", station.Name)
end

return Util
