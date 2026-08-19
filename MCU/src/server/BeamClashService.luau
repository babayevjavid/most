--!strict
--[[ Archived: full Beam Clash lives in src/archive/BeamClashService.luau ]]

local BeamClashService = {}

export type BeamSegment = {
	id: string,
	kind: "player" | "dummy",
	player: Player?,
}

function BeamClashService.registerSegmentProvider(_provider: () -> { BeamSegment }) end

function BeamClashService.isCharacterClashing(_character: Model): boolean
	return false
end

function BeamClashService.shouldKeepBeamAlive(_character: Model): boolean
	return false
end

function BeamClashService.getForcedBeamTip(_character: Model): Vector3?
	return nil
end

function BeamClashService.handlePromptHit(_player: Player, _clashId: string?, _promptId: string?) end

function BeamClashService.update(_dt: number) end

function BeamClashService.init() end

return BeamClashService
