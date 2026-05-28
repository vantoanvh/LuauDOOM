--!native
--!optimize 2

-- Port of p_plats.c, p_spec.h
-- Plats (i.e. elevator platforms) code, raising/lowering.
-- Thinker registration/removal, plane motion, and sound playback come from
-- the shared play runtime.

const Random = require("../Miscellaneous/Random")
const Fixed = require("../Miscellaneous/Fixed")
const Floor = require("./Floor")
const Runtime = require("./Runtime")
const State = require("../Renderer/State")

const up = 0
const down = 1
const waiting = 2
const in_stasis = 3

const perpetualRaise = 0
const downWaitUpStay = 1
const raiseAndChange = 2
const raiseToNearestAndChange = 3
const blazeDWUS = 4

const PLATWAIT = 3
const PLATSPEED = Floor.FLOORSPEED
const MAXPLATS = 30

const crushed = Floor.crushed
const pastdest = Floor.pastdest

const sfx_pstart = 18
const sfx_pstop = 19
const sfx_stnmov = 22

type Line = typeof(State.lines[0])
type Sector = typeof(State.sectors[0])
type Thinker = {
	owner: unknown,
	["function"]: {
		acp1: unknown?,
	},
}
type Plat = {
	sector: Sector,
	speed: number,
	low: number,
	high: number,
	wait: number,
	count: number,
	status: number,
	oldstatus: number,
	crush: boolean,
	tag: number,
	type: number,
	thinker: Thinker,
}

const activeplats: { [number]: Plat? } = {}

const function NewThinker(owner: unknown, thinkerFunction: unknown?): Thinker
	return {
		owner = owner,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function RegisterThinker(plat: Plat)
	Runtime.addThinker(plat.thinker)
end

const function RemoveThinker(plat: Plat)
	Runtime.removeThinker(plat.thinker)
end

const function GetFrontFloorPic(line: Line, context: string)
	const sidenum = line.sidenum[0]


	const side = State.sides[sidenum]

	return side.sector.floorpic
end

const function AddActivePlat(plat: Plat)
	const active = activeplats

	for i = 0, MAXPLATS - 1 do
		if active[i] == nil then
			active[i] = plat
			return
		end
	end

	error("AddActivePlat: no more plats!")
end

const function RemoveActivePlat(plat: Plat)
	const active = activeplats

	for i = 0, MAXPLATS - 1 do
		const activePlat = active[i]

		if activePlat == plat then
			activePlat.sector.specialdata = false
			RemoveThinker(activePlat)
			active[i] = nil
			return
		end
	end

	error("RemoveActivePlat: can't find plat!")
end

-- Move a plat up and down
const function PlatRaise(plat: Plat)
	local res

	if plat.status == up then
		res = Runtime.movePlane(plat.sector, plat.speed, plat.high, plat.crush, 0, 1)

		if plat.type == raiseAndChange or plat.type == raiseToNearestAndChange then
			if bit32.band(Runtime.getLevelTime() :: number, 7) == 0 then
				Runtime.startSound(plat.sector.soundorg, sfx_stnmov)
			end
		end

		if res == crushed and not plat.crush then
			plat.count = plat.wait
			plat.status = down
			Runtime.startSound(plat.sector.soundorg, sfx_pstart)
		elseif res == pastdest then
			plat.count = plat.wait
			plat.status = waiting
			Runtime.startSound(plat.sector.soundorg, sfx_pstop)

			if plat.type == blazeDWUS
				or plat.type == downWaitUpStay
				or plat.type == raiseAndChange
				or plat.type == raiseToNearestAndChange then
				RemoveActivePlat(plat)
			end
		end
	elseif plat.status == down then
		res = Runtime.movePlane(plat.sector, plat.speed, plat.low, false, 0, -1)

		if res == pastdest then
			plat.count = plat.wait
			plat.status = waiting
			Runtime.startSound(plat.sector.soundorg, sfx_pstop)
		end
	elseif plat.status == waiting then
		plat.count -= 1

		if plat.count == 0 then
			if plat.sector.floorheight == plat.low then
				plat.status = up
			else
				plat.status = down
			end

			Runtime.startSound(plat.sector.soundorg, sfx_pstart)
		end
	end
end

const function NewPlat(): Plat
	const plat = {
		sector = (false :: unknown) :: Sector,
		speed = 0,
		low = 0,
		high = 0,
		wait = 0,
		count = 0,
		status = up,
		oldstatus = up,
		crush = false,
		tag = 0,
		type = perpetualRaise,
		thinker = (nil :: unknown) :: Thinker,
	}

	plat.thinker = NewThinker(plat, PlatRaise)

	return plat
end

const function Reset()
	const active = activeplats

	for i = 0, MAXPLATS - 1 do
		const plat = active[i]

		if plat ~= nil and plat.sector.specialdata == plat then
			plat.sector.specialdata = false
		end

		active[i] = nil
	end
end

const function ActivateInStasis(tag: number)
	const active = activeplats

	for i = 0, MAXPLATS - 1 do
		const plat = active[i]

		if plat ~= nil and plat.tag == tag and plat.status == in_stasis then
			plat.status = plat.oldstatus
			plat.thinker["function"].acp1 = PlatRaise
		end
	end
end

const function StopPlat(line: Line)
	const active = activeplats

	for i = 0, MAXPLATS - 1 do
		const plat = active[i]

		if plat ~= nil and plat.status ~= in_stasis and plat.tag == line.tag then
			plat.oldstatus = plat.status
			plat.status = in_stasis
			plat.thinker["function"].acp1 = nil
		end
	end
end

-- Do Platforms
--  "amount" is only used for SOME platforms.
const function DoPlat(line: Line, type_: number, amount: number): number
	local secnum = -1
	local rtn = 0

	if type_ == perpetualRaise then
		ActivateInStasis(line.tag)
	end

	while true do
		secnum = Floor.FindSectorFromLineTag(line, secnum)

		if secnum < 0 then
			break
		end

		const sec = State.sectors[secnum]

		if sec.specialdata then
			continue
		end

		rtn = 1

		const plat = NewPlat()
		RegisterThinker(plat)

		plat.type = type_
		plat.sector = sec
		plat.sector.specialdata = plat
		plat.crush = false
		plat.tag = line.tag

		if type_ == raiseToNearestAndChange then
			plat.speed = PLATSPEED / 2
			sec.floorpic = GetFrontFloorPic(line, "DoPlat")
			plat.high = Floor.FindNextHighestFloor(sec, sec.floorheight)
			plat.wait = 0
			plat.status = up
			sec.special = 0

			Runtime.startSound(sec.soundorg, sfx_stnmov)
		elseif type_ == raiseAndChange then
			plat.speed = PLATSPEED / 2
			sec.floorpic = GetFrontFloorPic(line, "DoPlat")
			plat.high = sec.floorheight + amount * Fixed.FRACUNIT
			plat.wait = 0
			plat.status = up

			Runtime.startSound(sec.soundorg, sfx_stnmov)
		elseif type_ == downWaitUpStay then
			plat.speed = PLATSPEED * 4
			plat.low = Floor.FindLowestFloorSurrounding(sec)

			if plat.low > sec.floorheight then
				plat.low = sec.floorheight
			end

			plat.high = sec.floorheight
			plat.wait = 35 * PLATWAIT
			plat.status = down
			Runtime.startSound(sec.soundorg, sfx_pstart)
		elseif type_ == blazeDWUS then
			plat.speed = PLATSPEED * 8
			plat.low = Floor.FindLowestFloorSurrounding(sec)

			if plat.low > sec.floorheight then
				plat.low = sec.floorheight
			end

			plat.high = sec.floorheight
			plat.wait = 35 * PLATWAIT
			plat.status = down
			Runtime.startSound(sec.soundorg, sfx_pstart)
		elseif type_ == perpetualRaise then
			plat.speed = PLATSPEED
			plat.low = Floor.FindLowestFloorSurrounding(sec)

			if plat.low > sec.floorheight then
				plat.low = sec.floorheight
			end

			plat.high = Floor.FindHighestFloorSurrounding(sec)

			if plat.high < sec.floorheight then
				plat.high = sec.floorheight
			end

			plat.wait = 35 * PLATWAIT
			plat.status = bit32.band(Random.PlayRandom(), 1)

			Runtime.startSound(sec.soundorg, sfx_pstart)
		end

		AddActivePlat(plat)
	end

	return rtn
end

const function GetActivePlats()
	return activeplats
end

return {
	up = up,
	down = down,
	waiting = waiting,
	in_stasis = in_stasis,

	perpetualRaise = perpetualRaise,
	downWaitUpStay = downWaitUpStay,
	raiseAndChange = raiseAndChange,
	raiseToNearestAndChange = raiseToNearestAndChange,
	blazeDWUS = blazeDWUS,

	PLATWAIT = PLATWAIT,
	PLATSPEED = PLATSPEED,
	MAXPLATS = MAXPLATS,

	Reset = Reset,
	GetActivePlats = GetActivePlats,

	PlatRaise = PlatRaise,
	DoPlat = DoPlat,
	AddActivePlat = AddActivePlat,
	RemoveActivePlat = RemoveActivePlat,
	StopPlat = StopPlat,
	ActivateInStasis = ActivateInStasis,
}
