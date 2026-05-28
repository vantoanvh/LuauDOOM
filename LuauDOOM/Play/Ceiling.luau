--!native
--!optimize 2

-- Port of p_ceilng.c, p_spec.h
-- Ceiling animation (lowering, crushing, raising)
-- Thinker registration/removal, plane motion, and sound playback come from
-- the shared play runtime.
-- Note: `getNextSector`, `FindSectorFromLineTag`, and
-- `FindHighestCeilingSurrounding` are implemented locally here because
-- `p_ceilng.c` depends on those `p_spec.c` helpers directly.

const Fixed = require("../Miscellaneous/Fixed")
const State = require("../Renderer/State")
const Runtime = require("./Runtime")

const TWOSIDED = 4

const lowerToFloor = 0
const raiseToHighest = 1
const lowerAndCrush = 2
const crushAndRaise = 3
const fastCrushAndRaise = 4
const silentCrushAndRaise = 5

const CEILSPEED = Fixed.FRACUNIT
const CEILWAIT = 150
const MAXCEILINGS = 30

const ok = 0
const crushed = 1
const pastdest = 2

const sfx_pstop = 19
const sfx_stnmov = 22

type Sector = {
	ceilingheight: number,
	floorheight: number,
	tag: number,
	linecount: number,
	lines: { [number]: unknown },
	soundorg: unknown,
	specialdata: unknown,
}

type LineDef = {
	flags: number,
	tag: number,
	frontsector: Sector,
	backsector: Sector | false,
}

type ThinkerFunction = (unknown) -> ()

type Thinker = {
	owner: unknown,
	["function"]: {
		acp1: ThinkerFunction?,
	},
}

type Ceiling = {
	type: number,
	sector: Sector,
	bottomheight: number,
	topheight: number,
	speed: number,
	crush: boolean,
	direction: number,
	tag: number,
	olddirection: number,
	thinker: Thinker,
}

const activeceilings: { [number]: Ceiling } = {}

const function NewThinker(owner: unknown, thinkerFunction: ThinkerFunction?): Thinker
	return {
		owner = owner,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function RegisterThinker(ceiling: Ceiling)
	Runtime.addThinker(ceiling.thinker)
end

const function RemoveThinker(ceiling: Ceiling)
	Runtime.removeThinker(ceiling.thinker)
end

const function StartSound(origin: unknown, sound: number)
	Runtime.startSound(origin, sound)
end

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function IsPastDest(result: number | string): boolean
	return result == pastdest or result == "pastdest"
end

const function IsCrushed(result: number | string): boolean
	return result == crushed or result == "crushed"
end

const function Reset()
	for i = 0, MAXCEILINGS - 1 do
		const ceiling = activeceilings[i]

		if ceiling ~= nil and ceiling.sector.specialdata == ceiling then
			ceiling.sector.specialdata = false
		end

		activeceilings[i] = nil
	end
end

-- getNextSector()
-- Return sector_t * of sector next to current.
-- NULL if not two-sided line
const function getNextSector(line: LineDef, sec: Sector): Sector | false
	if bit32.band(line.flags, TWOSIDED) == 0 then
		return false
	end

	if line.frontsector == sec then
		return line.backsector or false
	end

	return line.frontsector or false
end

-- RETURN NEXT SECTOR # THAT LINE TAG REFERS TO
const function FindSectorFromLineTag(line: LineDef, start: number): number
	for index = start + 1, State.numsectors - 1 do
		const sector = State.sectors[index]

		if sector.tag == line.tag then
			return index
		end
	end

	return -1
end

-- FIND HIGHEST CEILING IN THE SURROUNDING SECTORS
const function FindHighestCeilingSurrounding(sec: Sector): number
	local height = 0

	for index = 0, sec.linecount - 1 do
		const check = sec.lines[index] :: LineDef


		const other = getNextSector(check, sec)

		if other and other.ceilingheight > height then
			height = other.ceilingheight
		end
	end

	return height
end

const function AddActiveCeiling(c: Ceiling)
	for i = 0, MAXCEILINGS - 1 do
		if activeceilings[i] == nil then
			activeceilings[i] = c
			return
		end
	end
end

const function RemoveActiveCeiling(c: Ceiling)
	for i = 0, MAXCEILINGS - 1 do
		if activeceilings[i] == c then
			activeceilings[i].sector.specialdata = false
			RemoveThinker(activeceilings[i])
			activeceilings[i] = nil
			return
		end
	end
end

-- MoveCeiling
const function MoveCeiling(ceiling: Ceiling)
	local res

	if ceiling.direction == 0 then
		-- IN STASIS
		return
	elseif ceiling.direction == 1 then
		-- UP
		res = Runtime.movePlane(
			ceiling.sector,
			ceiling.speed,
			ceiling.topheight,
			false,
			1,
			ceiling.direction
		)

		if bit32.band(GetLevelTime(), 7) == 0 then
			if ceiling.type ~= silentCrushAndRaise then
				StartSound(ceiling.sector.soundorg, sfx_stnmov)
			end
		end

		if IsPastDest(res) then
			if ceiling.type == raiseToHighest then
				RemoveActiveCeiling(ceiling)
			elseif ceiling.type == silentCrushAndRaise then
				StartSound(ceiling.sector.soundorg, sfx_pstop)
				ceiling.direction = -1
			elseif ceiling.type == fastCrushAndRaise or ceiling.type == crushAndRaise then
				ceiling.direction = -1
			end
		end
	elseif ceiling.direction == -1 then
		-- DOWN
		res = Runtime.movePlane(
			ceiling.sector,
			ceiling.speed,
			ceiling.bottomheight,
			ceiling.crush,
			1,
			ceiling.direction
		)

		if bit32.band(GetLevelTime(), 7) == 0 then
			if ceiling.type ~= silentCrushAndRaise then
				StartSound(ceiling.sector.soundorg, sfx_stnmov)
			end
		end

		if IsPastDest(res) then
			if ceiling.type == silentCrushAndRaise then
				StartSound(ceiling.sector.soundorg, sfx_pstop)
				ceiling.speed = CEILSPEED
				ceiling.direction = 1
			elseif ceiling.type == crushAndRaise then
				ceiling.speed = CEILSPEED
				ceiling.direction = 1
			elseif ceiling.type == fastCrushAndRaise then
				ceiling.direction = 1
			elseif ceiling.type == lowerAndCrush or ceiling.type == lowerToFloor then
				RemoveActiveCeiling(ceiling)
			end
		elseif IsCrushed(res) then
			if ceiling.type == silentCrushAndRaise
				or ceiling.type == crushAndRaise
				or ceiling.type == lowerAndCrush then
				ceiling.speed = CEILSPEED / 8
			end
		end
	end
end

const function NewCeiling(): Ceiling
	const ceiling = {
		type = lowerToFloor,
		sector = (false :: unknown) :: Sector,
		bottomheight = 0,
		topheight = 0,
		speed = 0,
		crush = false,
		direction = 0,
		tag = 0,
		olddirection = 0,
		thinker = (nil :: unknown) :: Thinker,
	}

	ceiling.thinker = NewThinker(ceiling, MoveCeiling)

	return ceiling
end

const function ActivateInStasisCeiling(line: LineDef)
	for i = 0, MAXCEILINGS - 1 do
		const ceiling = activeceilings[i]

		if ceiling ~= nil and ceiling.tag == line.tag and ceiling.direction == 0 then
			ceiling.direction = ceiling.olddirection
			ceiling.thinker["function"].acp1 = MoveCeiling
		end
	end
end

-- DoCeiling
-- Move a ceiling up/down and all around!
const function DoCeiling(line: LineDef, type_: number): number
	local secnum = -1
	local rtn = 0

	if type_ == fastCrushAndRaise or type_ == silentCrushAndRaise or type_ == crushAndRaise then
		ActivateInStasisCeiling(line)
	end

	while true do
		secnum = FindSectorFromLineTag(line, secnum)

		if secnum < 0 then
			break
		end

		const sec = State.sectors[secnum]

		if sec.specialdata then
			continue
		end

		rtn = 1

		const ceiling = NewCeiling()
		RegisterThinker(ceiling)

		sec.specialdata = ceiling
		ceiling.sector = sec
		ceiling.crush = false

		if type_ == fastCrushAndRaise then
			ceiling.crush = true
			ceiling.topheight = sec.ceilingheight
			ceiling.bottomheight = sec.floorheight + 8 * Fixed.FRACUNIT
			ceiling.direction = -1
			ceiling.speed = CEILSPEED * 2
		elseif type_ == silentCrushAndRaise or type_ == crushAndRaise or type_ == lowerAndCrush or type_ == lowerToFloor then
			if type_ == silentCrushAndRaise or type_ == crushAndRaise then
				ceiling.crush = true
				ceiling.topheight = sec.ceilingheight
			end

			ceiling.bottomheight = sec.floorheight

			if type_ ~= lowerToFloor then
				ceiling.bottomheight += 8 * Fixed.FRACUNIT
			end

			ceiling.direction = -1
			ceiling.speed = CEILSPEED
		elseif type_ == raiseToHighest then
			ceiling.topheight = FindHighestCeilingSurrounding(sec)
			ceiling.direction = 1
			ceiling.speed = CEILSPEED
		end

		ceiling.tag = sec.tag
		ceiling.type = type_
		AddActiveCeiling(ceiling)
	end

	return rtn
end

const function CeilingCrushStop(line: LineDef): number
	local rtn = 0

	for i = 0, MAXCEILINGS - 1 do
		const ceiling = activeceilings[i]

		if ceiling ~= nil and ceiling.tag == line.tag and ceiling.direction ~= 0 then
			ceiling.olddirection = ceiling.direction
			ceiling.thinker["function"].acp1 = nil
			ceiling.direction = 0
			rtn = 1
		end
	end

	return rtn
end

const function GetActiveCeilings(): { [number]: Ceiling }
	return activeceilings
end

const Exports = {
	lowerToFloor = lowerToFloor,
	raiseToHighest = raiseToHighest,
	lowerAndCrush = lowerAndCrush,
	crushAndRaise = crushAndRaise,
	fastCrushAndRaise = fastCrushAndRaise,
	silentCrushAndRaise = silentCrushAndRaise,

	CEILSPEED = CEILSPEED,
	CEILWAIT = CEILWAIT,
	MAXCEILINGS = MAXCEILINGS,

	ok = ok,
	crushed = crushed,
	pastdest = pastdest,

	Reset = Reset,
	GetActiveCeilings = GetActiveCeilings,

	getNextSector = getNextSector,
	FindSectorFromLineTag = FindSectorFromLineTag,
	FindHighestCeilingSurrounding = FindHighestCeilingSurrounding,
	MoveCeiling = MoveCeiling,
	DoCeiling = DoCeiling,
	AddActiveCeiling = AddActiveCeiling,
	RemoveActiveCeiling = RemoveActiveCeiling,
	ActivateInStasisCeiling = ActivateInStasisCeiling,
	CeilingCrushStop = CeilingCrushStop,
}

Exports.FindSectorFromLineTag = FindSectorFromLineTag
Exports.FindHighestCeilingSurrounding = FindHighestCeilingSurrounding
Exports.MoveCeiling = MoveCeiling
Exports.AddActiveCeiling = AddActiveCeiling
Exports.RemoveActiveCeiling = RemoveActiveCeiling
Exports.ActivateInStasisCeiling = ActivateInStasisCeiling

return Exports
