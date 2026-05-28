--!native
--!optimize 2

-- Port of p_floor.c, p_spec.h
-- Floor animation: raising stairs.
-- Thinker registration/removal, sector collision updates, and sound playback
-- are provided by the shared play runtime.
-- Note: `twoSided`, `getSide`, `getSector`, `getNextSector`,
-- `FindSectorFromLineTag`, and surrounding-height helpers are implemented
-- locally here because `p_floor.c` depends on those `p_spec.c` helpers.

const Fixed = require("../Miscellaneous/Fixed")
const State = require("../Renderer/State")
const Runtime = require("./Runtime")

const function Warn(...: unknown)
	warn(...)
end

const TWOSIDED = 4

const lowerFloor = 0
const lowerFloorToLowest = 1
const turboLower = 2
const raiseFloor = 3
const raiseFloorToNearest = 4
const raiseToTexture = 5
const lowerAndChange = 6
const raiseFloor24 = 7
const raiseFloor24AndChange = 8
const raiseFloorCrush = 9
const raiseFloorTurbo = 10
const donutRaise = 11
const raiseFloor512 = 12

const build8 = 0
const turbo16 = 1

const FLOORSPEED = Fixed.FRACUNIT

const ok = 0
const crushed = 1
const pastdest = 2

const sfx_pstop = 19
const sfx_stnmov = 22

const MAX_ADJOINING_SECTORS = 20

type NumberMap = { [number]: number }
type Sector = {
	[string]: unknown,
	floorheight: number,
	ceilingheight: number,
	floorpic: number,
	special: number,
	tag: number,
	specialdata: unknown,
	soundorg: unknown,
	lines: { [number]: Line },
	linecount: number,
}
type Line = {
	flags: number,
	tag: number,
	sidenum: NumberMap,
	frontsector: Sector,
	backsector: Sector | false,
}
type Side = {
	sector: Sector,
	bottomtexture: number,
}
type Thinker = {
	owner: unknown,
	["function"]: {
		acp1: unknown?,
	},
}
type FloorMover = {
	type: number,
	crush: boolean,
	sector: Sector,
	direction: number,
	newspecial: number,
	texture: number,
	floordestheight: number,
	speed: number,
	thinker: Thinker,
}
type FloorMoveConfig = {
	type: number?,
	crush: boolean?,
	sector: Sector,
	direction: number?,
	newspecial: number?,
	texture: number?,
	floordestheight: number?,
	speed: number?,
}

const activeFloors: { FloorMover } = {}

const function NewThinker(owner: unknown, thinkerFunction: unknown?): Thinker
	return {
		owner = owner,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function RemoveFloor(floor: FloorMover)
	for index = 1, #activeFloors do
		if activeFloors[index] == floor then
			table.remove(activeFloors, index)
			break
		end
	end

	Runtime.removeThinker(floor.thinker)
end

const function Reset()
	for _, floor in activeFloors do
		if floor.sector.specialdata == floor then
			floor.sector.specialdata = false
		end
	end

	table.clear(activeFloors)
end

const function StartSound(origin: unknown, sound: number)
	Runtime.startSound(origin, sound)
end

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function ChangeSector(sector: Sector, crushFlag: boolean): boolean
	const result = Runtime.changeSector(sector, crushFlag)

	return result ~= nil and result ~= false and result ~= 0
end

const function FindSectorIndex(target: Sector | false): number
	for index = 0, State.numsectors - 1 do
		if State.sectors[index] == target then
			return index
		end
	end

	return -1
end

-- getSide()
-- Will return a side_t*
-- given the number of the current sector,
-- the line number, and the side (0/1) that you want.
const function getSide(currentSector: number, line: number, side: number): Side
	const sector = State.sectors[currentSector]
	const mapLine = sector.lines[line]
	const sideIndex = mapLine.sidenum[side]


	return State.sides[sideIndex]
end

-- getSector()
-- Will return a sector_t*
-- given the number of the current sector,
-- the line number and the side (0/1) that you want.
const function getSector(currentSector: number, line: number, side: number): Sector
	return getSide(currentSector, line, side).sector
end

-- twoSided()
-- Given the sector number and the line number,
-- it will tell you whether the line is two-sided or not.
const function twoSided(sector: number, line: number): boolean
	const mapSector = State.sectors[sector]
	const mapLine = mapSector.lines[line]

	return bit32.btest(mapLine.flags, TWOSIDED)
end

-- getNextSector()
-- Return sector_t * of sector next to current.
-- NULL if not two-sided line
const function getNextSector(line: Line, sec: Sector): Sector | false
	if bit32.band(line.flags, TWOSIDED) == 0 then
		return false
	end

	if line.frontsector == sec then
		return line.backsector or false
	end

	return line.frontsector or false
end

-- RETURN NEXT SECTOR # THAT LINE TAG REFERS TO
const function FindSectorFromLineTag(line: Line, start: number): number
	for index = start + 1, State.numsectors - 1 do
		const sector = State.sectors[index]

		if sector.tag == line.tag then
			return index
		end
	end

	return -1
end

-- FindLowestFloorSurrounding()
-- FIND LOWEST FLOOR HEIGHT IN SURROUNDING SECTORS
const function FindLowestFloorSurrounding(sec: Sector): number
	local floor = sec.floorheight

	for index = 0, sec.linecount - 1 do
		const check = sec.lines[index]


		const other = getNextSector(check, sec)

		if other and other.floorheight < floor then
			floor = other.floorheight
		end
	end

	return floor
end

-- FindHighestFloorSurrounding()
-- FIND HIGHEST FLOOR HEIGHT IN SURROUNDING SECTORS
const function FindHighestFloorSurrounding(sec: Sector): number
	local floor = -500 * Fixed.FRACUNIT

	for index = 0, sec.linecount - 1 do
		const check = sec.lines[index]


		const other = getNextSector(check, sec)

		if other and other.floorheight > floor then
			floor = other.floorheight
		end
	end

	return floor
end

-- FindNextHighestFloor
-- FIND NEXT HIGHEST FLOOR IN SURROUNDING SECTORS
const function FindNextHighestFloor(sec: Sector, currentheight: number): number
	const height = currentheight
	const heightlist = table.create(MAX_ADJOINING_SECTORS)
	local h = 0

	for index = 0, sec.linecount - 1 do
		const check = sec.lines[index]


		const other = getNextSector(check, sec)

		if other then
			if other.floorheight > height then
				heightlist[h] = other.floorheight
				h += 1

				if h >= MAX_ADJOINING_SECTORS then
					Warn("FindNextHighestFloor: sector with more than 20 adjoining sectors")
					break
				end
			end
		end
	end

	if h == 0 then
		return currentheight
	end

	local min = heightlist[0]

	for index = 1, h - 1 do
		if heightlist[index] < min then
			min = heightlist[index]
		end
	end

	return min
end

-- FIND LOWEST CEILING IN THE SURROUNDING SECTORS
const function FindLowestCeilingSurrounding(sec: Sector): number
	local height = 0x7fffffff

	for index = 0, sec.linecount - 1 do
		const check = sec.lines[index]


		const other = getNextSector(check, sec)

		if other and other.ceilingheight < height then
			height = other.ceilingheight
		end
	end

	return height
end

-- Move a plane (floor or ceiling) and check for crushing
const function MovePlane(sector: Sector, speed: number, dest: number, crushFlag: boolean, floorOrCeiling: number, direction: number): number
	local flag
	local lastpos

	if floorOrCeiling == 0 then
		-- FLOOR
		if direction == -1 then
			-- DOWN
			if sector.floorheight - speed < dest then
				lastpos = sector.floorheight
				sector.floorheight = dest
				flag = ChangeSector(sector, crushFlag)

				if flag then
					sector.floorheight = lastpos
					ChangeSector(sector, crushFlag)
				end

				return pastdest
			else
				lastpos = sector.floorheight
				sector.floorheight -= speed
				flag = ChangeSector(sector, crushFlag)

				if flag then
					sector.floorheight = lastpos
					ChangeSector(sector, crushFlag)
					return crushed
				end
			end
		elseif direction == 1 then
			-- UP
			if sector.floorheight + speed > dest then
				lastpos = sector.floorheight
				sector.floorheight = dest
				flag = ChangeSector(sector, crushFlag)

				if flag then
					sector.floorheight = lastpos
					ChangeSector(sector, crushFlag)
				end

				return pastdest
			else
				lastpos = sector.floorheight
				sector.floorheight += speed
				flag = ChangeSector(sector, crushFlag)

				if flag then
					if crushFlag then
						return crushed
					end

					sector.floorheight = lastpos
					ChangeSector(sector, crushFlag)
					return crushed
				end
			end
		end
	elseif floorOrCeiling == 1 then
		-- CEILING
		if direction == -1 then
			-- DOWN
			if sector.ceilingheight - speed < dest then
				lastpos = sector.ceilingheight
				sector.ceilingheight = dest
				flag = ChangeSector(sector, crushFlag)

				if flag then
					sector.ceilingheight = lastpos
					ChangeSector(sector, crushFlag)
				end

				return pastdest
			else
				lastpos = sector.ceilingheight
				sector.ceilingheight -= speed
				flag = ChangeSector(sector, crushFlag)

				if flag then
					if crushFlag then
						return crushed
					end

					sector.ceilingheight = lastpos
					ChangeSector(sector, crushFlag)
					return crushed
				end
			end
		elseif direction == 1 then
			-- UP
			if sector.ceilingheight + speed > dest then
				lastpos = sector.ceilingheight
				sector.ceilingheight = dest
				flag = ChangeSector(sector, crushFlag)

				if flag then
					sector.ceilingheight = lastpos
					ChangeSector(sector, crushFlag)
				end

				return pastdest
			else
				lastpos = sector.ceilingheight
				sector.ceilingheight += speed
				ChangeSector(sector, crushFlag)
			end
		end
	end

	return ok
end

-- MOVE A FLOOR TO IT'S DESTINATION (UP OR DOWN)
const function MoveFloor(floor: FloorMover)
	const res = MovePlane(
		floor.sector,
		floor.speed,
		floor.floordestheight,
		floor.crush,
		0,
		floor.direction
	)

	if bit32.band(GetLevelTime(), 7) == 0 then
		StartSound(floor.sector.soundorg, sfx_stnmov)
	end

	if res == pastdest then
		floor.sector.specialdata = false

		if floor.direction == 1 then
			if floor.type == donutRaise then
				floor.sector.special = floor.newspecial
				floor.sector.floorpic = floor.texture
			end
		elseif floor.direction == -1 then
			if floor.type == lowerAndChange then
				floor.sector.special = floor.newspecial
				floor.sector.floorpic = floor.texture
			end
		end

		RemoveFloor(floor)
		StartSound(floor.sector.soundorg, sfx_pstop)
	end
end

const function NewFloor(): FloorMover
	const floor = {
		type = lowerFloor,
		crush = false,
		sector = (false :: unknown) :: Sector,
		direction = 0,
		newspecial = 0,
		texture = 0,
		floordestheight = 0,
		speed = 0,
		thinker = (nil :: unknown) :: Thinker,
	}

	floor.thinker = NewThinker(floor, MoveFloor)

	return floor
end

const function RegisterFloor(floor: FloorMover)
	activeFloors[#activeFloors + 1] = floor
	Runtime.addThinker(floor.thinker)
end

const function SpawnFloorMove(config: FloorMoveConfig): FloorMover
	const sector = config.sector
	const floor = NewFloor()

	floor.type = config.type or lowerFloor
	floor.crush = config.crush == true
	floor.sector = sector
	floor.direction = config.direction or 0
	floor.newspecial = config.newspecial or 0
	floor.texture = config.texture or 0
	floor.floordestheight = config.floordestheight or 0
	floor.speed = config.speed or 0

	RegisterFloor(floor)
	sector.specialdata = floor

	return floor
end

-- HANDLE FLOOR TYPES
const function DoFloor(line: Line, floortype: number): number
	local secnum = -1
	local rtn = 0

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

		const floor = NewFloor()
		RegisterFloor(floor)

		sec.specialdata = floor
		floor.type = floortype
		floor.crush = false

		if floortype == lowerFloor then
			floor.direction = -1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = FindHighestFloorSurrounding(sec)
		elseif floortype == lowerFloorToLowest then
			floor.direction = -1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = FindLowestFloorSurrounding(sec)
		elseif floortype == turboLower then
			floor.direction = -1
			floor.sector = sec
			floor.speed = FLOORSPEED * 4
			floor.floordestheight = FindHighestFloorSurrounding(sec)

			if floor.floordestheight ~= sec.floorheight then
				floor.floordestheight += 8 * Fixed.FRACUNIT
			end
		elseif floortype == raiseFloorCrush or floortype == raiseFloor then
			floor.crush = floortype == raiseFloorCrush
			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = FindLowestCeilingSurrounding(sec)

			if floor.floordestheight > sec.ceilingheight then
				floor.floordestheight = sec.ceilingheight
			end

			floor.floordestheight -= (8 * Fixed.FRACUNIT) * (if floortype == raiseFloorCrush then 1 else 0)
		elseif floortype == raiseFloorTurbo then
			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED * 4
			floor.floordestheight = FindNextHighestFloor(sec, sec.floorheight)
		elseif floortype == raiseFloorToNearest then
			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = FindNextHighestFloor(sec, sec.floorheight)
		elseif floortype == raiseFloor24 then
			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = floor.sector.floorheight + 24 * Fixed.FRACUNIT
		elseif floortype == raiseFloor512 then
			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = floor.sector.floorheight + 512 * Fixed.FRACUNIT
		elseif floortype == raiseFloor24AndChange then
			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = floor.sector.floorheight + 24 * Fixed.FRACUNIT
			sec.floorpic = line.frontsector.floorpic
			sec.special = line.frontsector.special
		elseif floortype == raiseToTexture then
			local minsize = 0x7fffffff

			floor.direction = 1
			floor.sector = sec
			floor.speed = FLOORSPEED

			for index = 0, sec.linecount - 1 do
				if twoSided(secnum, index) then
					local side = getSide(secnum, index, 0)

					if side.bottomtexture >= 0 then
						const height = State.textureheight[side.bottomtexture]

						if height ~= nil and height < minsize then
							minsize = height
						end
					end

					side = getSide(secnum, index, 1)

					if side.bottomtexture >= 0 then
						const height = State.textureheight[side.bottomtexture]

						if height ~= nil and height < minsize then
							minsize = height
						end
					end
				end
			end

			floor.floordestheight = floor.sector.floorheight + minsize
		elseif floortype == lowerAndChange then
			floor.direction = -1
			floor.sector = sec
			floor.speed = FLOORSPEED
			floor.floordestheight = FindLowestFloorSurrounding(sec)
			floor.texture = sec.floorpic

			for index = 0, sec.linecount - 1 do
				if twoSided(secnum, index) then
					local other

					if getSide(secnum, index, 0).sector == State.sectors[secnum] then
						other = getSector(secnum, index, 1)
					else
						other = getSector(secnum, index, 0)
					end

					if other.floorheight == floor.floordestheight then
						floor.texture = other.floorpic
						floor.newspecial = other.special
						break
					end
				end
			end
		end
	end

	return rtn
end

-- BUILD A STAIRCASE!
const function BuildStairs(line: Line, type_: number): number
	local secnum = -1
	local rtn = 0

	while true do
		secnum = FindSectorFromLineTag(line, secnum)

		if secnum < 0 then
			break
		end

		local sec = State.sectors[secnum]

		if sec.specialdata then
			continue
		end

		rtn = 1

		local floor = NewFloor()
		RegisterFloor(floor)

		sec.specialdata = floor
		floor.direction = 1
		floor.sector = sec

		local stairsize
		local speed

		if type_ == build8 then
			speed = FLOORSPEED / 4
			stairsize = 8 * Fixed.FRACUNIT
		else
			speed = FLOORSPEED * 4
			stairsize = 16 * Fixed.FRACUNIT
		end

		floor.speed = speed

		local height = sec.floorheight + stairsize
		floor.floordestheight = height

		const texture = sec.floorpic

		repeat
			local found = false

			for index = 0, sec.linecount - 1 do
				const mapLine = sec.lines[index]

				if bit32.band(mapLine.flags, TWOSIDED) == 0 then
					continue
				end

				local tsec = mapLine.frontsector
				local newsecnum = FindSectorIndex(tsec)

				if secnum ~= newsecnum then
					continue
				end

				tsec = mapLine.backsector
				newsecnum = FindSectorIndex(tsec)

				if newsecnum < 0 or tsec.floorpic ~= texture then
					continue
				end

				height += stairsize

				if tsec.specialdata then
					continue
				end

				sec = tsec
				secnum = newsecnum
				floor = NewFloor()
				RegisterFloor(floor)
				sec.specialdata = floor
				floor.direction = 1
				floor.sector = sec
				floor.speed = speed
				floor.floordestheight = height
				found = true
				break
			end

			if not found then
				break
			end
		until false
	end

	return rtn
end

const function GetActiveFloors(): { FloorMover }
	return activeFloors
end

return {
	lowerFloor = lowerFloor,
	lowerFloorToLowest = lowerFloorToLowest,
	turboLower = turboLower,
	raiseFloor = raiseFloor,
	raiseFloorToNearest = raiseFloorToNearest,
	raiseToTexture = raiseToTexture,
	lowerAndChange = lowerAndChange,
	raiseFloor24 = raiseFloor24,
	raiseFloor24AndChange = raiseFloor24AndChange,
	raiseFloorCrush = raiseFloorCrush,
	raiseFloorTurbo = raiseFloorTurbo,
	donutRaise = donutRaise,
	raiseFloor512 = raiseFloor512,

	build8 = build8,
	turbo16 = turbo16,

	FLOORSPEED = FLOORSPEED,

	ok = ok,
	crushed = crushed,
	pastdest = pastdest,

	Reset = Reset,
	GetActiveFloors = GetActiveFloors,
	SpawnFloorMove = SpawnFloorMove,

	twoSided = twoSided,
	getSide = getSide,
	getSector = getSector,
	getNextSector = getNextSector,
	FindSectorFromLineTag = FindSectorFromLineTag,
	FindLowestFloorSurrounding = FindLowestFloorSurrounding,
	FindHighestFloorSurrounding = FindHighestFloorSurrounding,
	FindNextHighestFloor = FindNextHighestFloor,
	FindLowestCeilingSurrounding = FindLowestCeilingSurrounding,
	MovePlane = MovePlane,
	MoveFloor = MoveFloor,
	DoFloor = DoFloor,
	BuildStairs = BuildStairs,
}
