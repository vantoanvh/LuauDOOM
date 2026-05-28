--!native
--!optimize 2

-- Port of Doors.c, p_spec.h
-- Door animation code (opening/closing)
-- Thinker registration/removal, plane motion, and sound playback come from
-- the shared play runtime.
-- Note: `getNextSector`, `FindSectorFromLineTag`, and
-- `FindLowestCeilingSurrounding` are implemented locally here because
-- `Doors.c` depends on those `p_spec.c` helpers directly.

const Definitions = require("../Engine/Definitions")
const English = require("../Doom/English")
const Fixed = require("../Miscellaneous/Fixed")
const French = require("../Doom/French")
const State = require("../Renderer/State")
const Runtime = require("./Runtime")

const TWOSIDED = 4

const normal = 0
const close30ThenOpen = 1
const close = 2
const open = 3
const raiseIn5Mins = 4
const blazeRaise = 5
const blazeOpen = 6
const blazeClose = 7

const VDOORSPEED = Fixed.FRACUNIT * 2
const VDOORWAIT = 150

const ok = 0
const crushed = 1
const pastdest = 2

const sfx_doropn = 20
const sfx_dorcls = 21
const sfx_oof = 34
const sfx_bdopn = 88
const sfx_bdcls = 89

type Line = typeof(State.lines[0])
type Sector = typeof(State.sectors[0])
type Player = {
	cards: { [number]: boolean? },
	message: string?,
}
type Thing = {
	player: Player? | false,
}
type Thinker = {
	owner: unknown,
	["function"]: {
		acp1: unknown,
	},
}
type Door = {
	direction: number,
	sector: Sector,
	speed: number,
	thinker: Thinker,
	topcountdown: number,
	topheight: number,
	topwait: number,
	type: number,
}

const activeDoors: { Door } = {}
local language = Definitions.english
local strings = English

const function NewThinker(owner: unknown, thinkerFunction: unknown): Thinker
	return {
		owner = owner,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function RegisterDoor(door: Door)
	activeDoors[#activeDoors + 1] = door
	Runtime.addThinker(door.thinker)
end

const function RemoveDoor(door: Door)
	for index = 1, #activeDoors do
		if activeDoors[index] == door then
			table.remove(activeDoors, index)
			break
		end
	end

	Runtime.removeThinker(door.thinker)
end

const function Reset()
	for _, door in activeDoors do
		if door.sector.specialdata == door then
			door.sector.specialdata = false
		end
	end

	table.clear(activeDoors)
end

const function SetLanguage(value: number)
	language = value
	strings = if value == Definitions.french then French else English
end

const function GetString(name: string): string
	const value = strings[name]


	return value
end

-- getNextSector()
-- Return sector_t * of sector next to current.
-- NULL if not two-sided line
const function getNextSector(line: Line, sec: Sector): Sector | false
	if bit32.band(line.flags or 0, TWOSIDED) == 0 then
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

-- FIND LOWEST CEILING IN THE SURROUNDING SECTORS
const function FindLowestCeilingSurrounding(sec: Sector)
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

const function IsPastDest(result: unknown): boolean
	return result == pastdest or result == "pastdest"
end

const function IsCrushed(result: unknown): boolean
	return result == crushed or result == "crushed"
end

const function StartSound(origin: unknown, sound: number)
	Runtime.startSound(origin, sound)
end

const function GetManualDoorSector(line: Line): StudioDeviceSimulatorService
	const side = State.sides[line.sidenum[1]]
	return side.sector
end

-- VerticalDoor
const function VerticalDoor(door: Door)
	local res

	if door.direction == 0 then
		-- WAITING
		door.topcountdown -= 1

		if door.topcountdown == 0 then
			if door.type == blazeRaise then
				door.direction = -1
				StartSound(door.sector.soundorg, sfx_bdcls)
			elseif door.type == normal then
				door.direction = -1
				StartSound(door.sector.soundorg, sfx_dorcls)
			elseif door.type == close30ThenOpen then
				door.direction = 1
				StartSound(door.sector.soundorg, sfx_doropn)
			end
		end
	elseif door.direction == 2 then
		-- INITIAL WAIT
		door.topcountdown -= 1

		if door.topcountdown == 0 and door.type == raiseIn5Mins then
			door.direction = 1
			door.type = normal
			StartSound(door.sector.soundorg, sfx_doropn)
		end
	elseif door.direction == -1 then
		-- DOWN
		res = Runtime.movePlane(
			door.sector,
			door.speed,
			door.sector.floorheight,
			false,
			1,
			door.direction
		)

		if IsPastDest(res) then
			if door.type == blazeRaise or door.type == blazeClose then
				door.sector.specialdata = false
				RemoveDoor(door)
				StartSound(door.sector.soundorg, sfx_bdcls)
			elseif door.type == normal or door.type == close then
				door.sector.specialdata = false
				RemoveDoor(door)
			elseif door.type == close30ThenOpen then
				door.direction = 0
				door.topcountdown = 35 * 30
			end
		elseif IsCrushed(res) then
			if door.type ~= blazeClose and door.type ~= close then
				door.direction = 1
				StartSound(door.sector.soundorg, sfx_doropn)
			end
		end
	elseif door.direction == 1 then
		-- UP
		res = Runtime.movePlane(
			door.sector,
			door.speed,
			door.topheight,
			false,
			1,
			door.direction
		)

		if IsPastDest(res) then
			if door.type == blazeRaise or door.type == normal then
				door.direction = 0
				door.topcountdown = door.topwait
			elseif door.type == close30ThenOpen or door.type == blazeOpen or door.type == open then
				door.sector.specialdata = false
				RemoveDoor(door)
			end
		end
	end
end

const function NewDoor(): Door
	const door = ({
		type = normal,
		sector = false,
		topheight = 0,
		speed = 0,
		direction = 0,
		topwait = 0,
		topcountdown = 0,
	} :: unknown) :: Door

	door.thinker = NewThinker(door, VerticalDoor)

	return door
end

const function DoDoor(line: Line, type_: number): number
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

		const door = NewDoor()
		RegisterDoor(door)

		sec.specialdata = door
		door.sector = sec
		door.type = type_
		door.topwait = VDOORWAIT
		door.speed = VDOORSPEED

		if type_ == blazeClose then
			door.topheight = FindLowestCeilingSurrounding(sec) - 4 * Fixed.FRACUNIT
			door.direction = -1
			door.speed = VDOORSPEED * 4
			StartSound(door.sector.soundorg, sfx_bdcls)
		elseif type_ == close then
			door.topheight = FindLowestCeilingSurrounding(sec) - 4 * Fixed.FRACUNIT
			door.direction = -1
			StartSound(door.sector.soundorg, sfx_dorcls)
		elseif type_ == close30ThenOpen then
			door.topheight = sec.ceilingheight
			door.direction = -1
			StartSound(door.sector.soundorg, sfx_dorcls)
		elseif type_ == blazeRaise or type_ == blazeOpen then
			door.direction = 1
			door.topheight = FindLowestCeilingSurrounding(sec) - 4 * Fixed.FRACUNIT
			door.speed = VDOORSPEED * 4

			if door.topheight ~= sec.ceilingheight then
				StartSound(door.sector.soundorg, sfx_bdopn)
			end
		elseif type_ == normal or type_ == open then
			door.direction = 1
			door.topheight = FindLowestCeilingSurrounding(sec) - 4 * Fixed.FRACUNIT

			if door.topheight ~= sec.ceilingheight then
				StartSound(door.sector.soundorg, sfx_doropn)
			end
		end
	end

	return rtn
end

-- DoLockedDoor
-- Move a locked door up/down
const function DoLockedDoor(line: Line, type_: number, thing: Thing): number
	const player = thing.player

	if not player then
		return 0
	end

	const cards = player.cards

	if line.special == 99 or line.special == 133 then
		if not cards[Definitions.it_bluecard] and not cards[Definitions.it_blueskull] then
			player.message = GetString("BLUEO")
			StartSound(nil, sfx_oof)
			return 0
		end
	elseif line.special == 134 or line.special == 135 then
		if not cards[Definitions.it_redcard] and not cards[Definitions.it_redskull] then
			player.message = GetString("REDO")
			StartSound(nil, sfx_oof)
			return 0
		end
	elseif line.special == 136 or line.special == 137 then
		if not cards[Definitions.it_yellowcard] and not cards[Definitions.it_yellowskull] then
			player.message = GetString("YELLOWO")
			StartSound(nil, sfx_oof)
			return 0
		end
	end

	return DoDoor(line, type_)
end

-- ActivateVerticalDoor : open a door manually, no tag value
const function ActivateVerticalDoor(line: Line, thing: Thing)
	const player = thing.player

	if line.special == 26 or line.special == 32 then
		if not player then
			return
		end

		const cards = player.cards

		if not cards[Definitions.it_bluecard] and not cards[Definitions.it_blueskull] then
			player.message = GetString("BLUEK")
			StartSound(nil, sfx_oof)
			return
		end
	elseif line.special == 27 or line.special == 34 then
		if not player then
			return
		end

		const cards = player.cards

		if not cards[Definitions.it_yellowcard] and not cards[Definitions.it_yellowskull] then
			player.message = GetString("YELLOWK")
			StartSound(nil, sfx_oof)
			return
		end
	elseif line.special == 28 or line.special == 33 then
		if not player then
			return
		end

		const cards = player.cards

		if not cards[Definitions.it_redcard] and not cards[Definitions.it_redskull] then
			player.message = GetString("REDK")
			StartSound(nil, sfx_oof)
			return
		end
	end

	const sec = GetManualDoorSector(line)

	if sec.specialdata then
		const door = sec.specialdata

		if line.special == 1
			or line.special == 26
			or line.special == 27
			or line.special == 28
			or line.special == 117 then
			if door.direction == -1 then
				door.direction = 1
			else
				if not thing.player then
					return
				end

				door.direction = -1
			end

			return
		end
	end

	if line.special == 117 or line.special == 118 then
		StartSound(sec.soundorg, sfx_bdopn)
	elseif line.special == 1 or line.special == 31 then
		StartSound(sec.soundorg, sfx_doropn)
	else
		StartSound(sec.soundorg, sfx_doropn)
	end

	const door = NewDoor()
	RegisterDoor(door)

	sec.specialdata = door
	door.sector = sec
	door.direction = 1
	door.speed = VDOORSPEED
	door.topwait = VDOORWAIT

	if line.special == 1 or line.special == 26 or line.special == 27 or line.special == 28 then
		door.type = normal
	elseif line.special == 31 or line.special == 32 or line.special == 33 or line.special == 34 then
		door.type = open
		line.special = 0
	elseif line.special == 117 then
		door.type = blazeRaise
		door.speed = VDOORSPEED * 4
	elseif line.special == 118 then
		door.type = blazeOpen
		line.special = 0
		door.speed = VDOORSPEED * 4
	end

	door.topheight = FindLowestCeilingSurrounding(sec) - 4 * Fixed.FRACUNIT
end

-- Spawn a door that closes after 30 seconds
const function SpawnDoorCloseIn30(sec: Sector): Door
	const door = NewDoor()
	RegisterDoor(door)

	sec.specialdata = door
	sec.special = 0

	door.sector = sec
	door.direction = 0
	door.type = normal
	door.speed = VDOORSPEED
	door.topcountdown = 30 * 35

	return door
end

-- Spawn a door that opens after 5 minutes
const function SpawnDoorRaiseIn5Mins(sec: Sector, _secnum: number): Door
	const door = NewDoor()
	RegisterDoor(door)

	sec.specialdata = door
	sec.special = 0

	door.sector = sec
	door.direction = 2
	door.type = raiseIn5Mins
	door.speed = VDOORSPEED
	door.topheight = FindLowestCeilingSurrounding(sec) - 4 * Fixed.FRACUNIT
	door.topwait = VDOORWAIT
	door.topcountdown = 5 * 60 * 35

	return door
end

const function GetLanguage(): number
	return language
end

const function GetStrings()
	return strings
end

const function GetActiveDoors(): { Door }
	return activeDoors
end

SetLanguage(language)

return {
	normal = normal,
	close30ThenOpen = close30ThenOpen,
	close = close,
	open = open,
	raiseIn5Mins = raiseIn5Mins,
	blazeRaise = blazeRaise,
	blazeOpen = blazeOpen,
	blazeClose = blazeClose,

	VDOORSPEED = VDOORSPEED,
	VDOORWAIT = VDOORWAIT,

	ok = ok,
	crushed = crushed,
	pastdest = pastdest,

	Reset = Reset,
	SetLanguage = SetLanguage,
	GetLanguage = GetLanguage,
	GetStrings = GetStrings,
	GetActiveDoors = GetActiveDoors,

	getNextSector = getNextSector,
	FindSectorFromLineTag = FindSectorFromLineTag,
	FindLowestCeilingSurrounding = FindLowestCeilingSurrounding,
	VerticalDoor = VerticalDoor,
	DoLockedDoor = DoLockedDoor,
	DoDoor = DoDoor,
	ActivateVerticalDoor = ActivateVerticalDoor,
	SpawnDoorCloseIn30 = SpawnDoorCloseIn30,
	SpawnDoorRaiseIn5Mins = SpawnDoorRaiseIn5Mins,
}
