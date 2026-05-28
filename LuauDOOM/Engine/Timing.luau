--!optimize 2
--!native

--[[
	Timing.luau

	Tracks fixed-timestep frame timing, pending simulation tics, interpolation alpha, and host time.
]]

const Definitions = require("./Definitions")

const SIMULATION_HZ = Definitions.TICRATE
const SECONDS_PER_TIC = 1 / SIMULATION_HZ
const EXTERNAL_MAX_CATCH_UP_TICS = 0

local accumulatorSeconds = 0
local pendingTics = 0
local interpolationAlpha = 0
local currentHostTime = 0
local totalSimTics = 0

const function RebuildPendingTics(catchUpCap: number)
	local availableTics = accumulatorSeconds / SECONDS_PER_TIC // 1

	if catchUpCap > 0 and availableTics > catchUpCap then
		availableTics = catchUpCap
	end

	pendingTics = availableTics
	accumulatorSeconds -= pendingTics * SECONDS_PER_TIC
	interpolationAlpha = math.clamp(accumulatorSeconds / SECONDS_PER_TIC, 0, 1)
end

const function Reset()
	accumulatorSeconds = 0
	pendingTics = 0
	interpolationAlpha = 0
	currentHostTime = 0
	totalSimTics = 0
end

const function BeginFrame(realDt: number?)
	currentHostTime += realDt

	if realDt > 0 then
		accumulatorSeconds += realDt
	end

	RebuildPendingTics(EXTERNAL_MAX_CATCH_UP_TICS)

	return pendingTics
end

const function BeginExactTicFrame(ticCount: number)

	accumulatorSeconds = 0
	interpolationAlpha = 0
	pendingTics = ticCount
	currentHostTime += ticCount * SECONDS_PER_TIC
	return pendingTics
end

const function ConsumePendingTic(): boolean
	if pendingTics <= 0 then
		return false
	end

	pendingTics -= 1
	return true
end

const function AdvanceGameTic(): number
	totalSimTics += 1
	return totalSimTics
end

const function GetInterpolationAlpha(): number
	return interpolationAlpha
end

const function GetGameTic(): number
	return totalSimTics
end

const function GetHostTime(): number
	return currentHostTime
end

return {
	Reset = Reset,
	BeginFrame = BeginFrame,
	BeginExactTicFrame = BeginExactTicFrame,
	ConsumePendingTic = ConsumePendingTic,
	AdvanceGameTic = AdvanceGameTic,
	GetInterpolationAlpha = GetInterpolationAlpha,
	GetGameTic = GetGameTic,
	GetHostTime = GetHostTime,
}
