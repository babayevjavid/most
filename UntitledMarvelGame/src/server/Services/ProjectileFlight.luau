--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AbilityConstants = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("AbilityConstants"))

local STEER_TURN_RATE = math.rad(AbilityConstants.PROJECTILE_STEER_TURN_RATE_DEG)
local STEER_EXPIRE_SEC = 8

type SteerState = {
	targetPos: Vector3,
	ownerUserId: number,
	expiresAt: number,
}

local steerByToken: { [string]: SteerState } = {}

export type FlightOpts = {
	part: BasePart,
	projectileModel: Model?,
	spawnPos: Vector3,
	initialDir: Vector3,
	maxRange: number,
	speed: number,
	casterChar: Model,
	steerToken: string?,
	curveArcHeight: number?,
	fixedOrientation: CFrame?,
	excludeInstances: { Instance }?,
	faceMovement: boolean?,
	spinRadiansPerSec: number?,
	onStepHit: ((hitPos: Vector3, hitPart: BasePart?) -> boolean)?,
	onEnd: (endPos: Vector3) -> (),
}

local function applyProjectileCFrame(opts: FlightOpts, cf: CFrame, smooth: boolean, dt: number)
	if opts.projectileModel and opts.projectileModel.Parent then
		if smooth then
			opts.projectileModel:PivotTo(opts.projectileModel:GetPivot():Lerp(cf, math.min(1, dt * 22)))
		else
			opts.projectileModel:PivotTo(cf)
		end
	elseif smooth then
		opts.part.CFrame = opts.part.CFrame:Lerp(cf, math.min(1, dt * 22))
	else
		opts.part.CFrame = cf
	end
end

local function buildProjectileCFrame(
	displayPos: Vector3,
	dir: Vector3,
	fixedOri: CFrame?,
	faceMovement: boolean,
	spinAngle: number
): CFrame
	local baseCf: CFrame
	if fixedOri then
		baseCf = CFrame.new(displayPos) * fixedOri
	elseif faceMovement then
		baseCf = CFrame.lookAt(displayPos, displayPos + dir)
	else
		baseCf = CFrame.new(displayPos)
	end
	if spinAngle ~= 0 then
		baseCf *= CFrame.Angles(spinAngle, spinAngle * 0.65, spinAngle * 0.35)
	end
	return baseCf
end

local function rotateDirToward(current: Vector3, target: Vector3, maxRadians: number): Vector3
	local cur = current.Unit
	local tgt = target.Unit
	local dot = math.clamp(cur:Dot(tgt), -1, 1)
	if dot > 0.9999 then
		return tgt
	end
	local angle = math.acos(dot)
	if angle <= maxRadians then
		return tgt
	end
	local axis = cur:Cross(tgt)
	if axis.Magnitude < 1e-5 then
		return cur
	end
	axis = axis.Unit
	return (CFrame.fromAxisAngle(axis, maxRadians):VectorToWorldSpace(cur)).Unit
end

local function clearSteerToken(token: string?)
	if not token or token == "" then
		return
	end
	steerByToken[token] = nil
end

local function registerSteerToken(token: string, ownerUserId: number, initialTarget: Vector3?)
	if type(token) ~= "string" or token == "" then
		return
	end
	steerByToken[token] = {
		targetPos = initialTarget or Vector3.zero,
		ownerUserId = ownerUserId,
		expiresAt = os.clock() + STEER_EXPIRE_SEC,
	}
end

local function updateSteerTarget(plr: Player, token: string, targetPos: Vector3): boolean
	if typeof(targetPos) ~= "Vector3" then
		return false
	end
	local st = steerByToken[token]
	if not st or st.ownerUserId ~= plr.UserId then
		return false
	end
	if os.clock() > st.expiresAt then
		steerByToken[token] = nil
		return false
	end
	st.targetPos = targetPos
	st.expiresAt = os.clock() + STEER_EXPIRE_SEC
	return true
end

local function runProjectileFlight(opts: FlightOpts): RBXScriptConnection?
	local part = opts.part
	if not part.Parent then
		return nil
	end

	local dir = if opts.initialDir.Magnitude > 0.01 then opts.initialDir.Unit else Vector3.new(0, 0, -1)
	local steerToken = opts.steerToken
	local arcHeight = opts.curveArcHeight or 0
	local fixedOri = opts.fixedOrientation
	local spawnPos = opts.spawnPos
	local distanceTraveled = 0
	local currentPos = spawnPos

	local faceMovement = opts.faceMovement ~= false
	local spinRate = opts.spinRadiansPerSec or 0
	local spinAngle = 0
	local initialCf = buildProjectileCFrame(spawnPos, dir, fixedOri, faceMovement, spinAngle)
	applyProjectileCFrame(opts, initialCf, false, 0)

	local conn: RBXScriptConnection?
	conn = RunService.Heartbeat:Connect(function(dt: number)
		if not part.Parent or (opts.projectileModel and not opts.projectileModel.Parent) then
			if conn then
				conn:Disconnect()
			end
			clearSteerToken(steerToken)
			return
		end

		if steerToken and steerByToken[steerToken] then
			local st = steerByToken[steerToken]
			local desired = st.targetPos - currentPos
			if desired.Magnitude > 0.05 then
				dir = rotateDirToward(dir, desired, STEER_TURN_RATE * dt)
			end
		end

		local step = opts.speed * dt
		local moveVec = dir * step

		if opts.onStepHit then
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = opts.excludeInstances or {}
			rayParams.IgnoreWater = true
			local ray = Workspace:Raycast(currentPos, moveVec, rayParams)
			if ray then
				if opts.onStepHit(ray.Position, ray.Instance :: BasePart?) then
					if conn then
						conn:Disconnect()
					end
					clearSteerToken(steerToken)
					opts.onEnd(ray.Position)
					return
				end
			end
		end

		distanceTraveled += step
		if distanceTraveled >= opts.maxRange then
			if conn then
				conn:Disconnect()
			end
			clearSteerToken(steerToken)
			local endPos = currentPos + dir * math.max(0, opts.maxRange - (distanceTraveled - step))
			applyProjectileCFrame(
				opts,
				buildProjectileCFrame(endPos, dir, fixedOri, faceMovement, spinAngle),
				false,
				dt
			)
			opts.onEnd(endPos)
			return
		end

		currentPos += moveVec
		spinAngle += spinRate * dt
		local tNorm = math.clamp(distanceTraveled / math.max(opts.maxRange, 0.01), 0, 1)
		local displayPos = currentPos
		if arcHeight ~= 0 then
			displayPos += Vector3.new(0, math.sin(math.pi * tNorm) * arcHeight, 0)
		end

		local targetCf = buildProjectileCFrame(displayPos, dir, fixedOri, faceMovement, spinAngle)
		applyProjectileCFrame(opts, targetCf, true, dt)
	end)

	return conn
end

local function setupSteerRemote(projectileSteerUpdate: RemoteEvent)
	projectileSteerUpdate.OnServerEvent:Connect(function(plr: Player, token: unknown, targetPos: unknown)
		if type(token) ~= "string" or token == "" then
			return
		end
		if typeof(targetPos) ~= "Vector3" then
			return
		end
		updateSteerTarget(plr, token, targetPos)
	end)
end

return {
	runProjectileFlight = runProjectileFlight,
	registerSteerToken = registerSteerToken,
	updateSteerTarget = updateSteerTarget,
	clearSteerToken = clearSteerToken,
	setupSteerRemote = setupSteerRemote,
}
