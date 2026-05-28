--!native
--!optimize 2

-- Port of p_map.c
-- Movement, collision handling, use traces, attack traces, and slide motion.

const Fixed = require("../Miscellaneous/Fixed")
const Info = require("../Doom/Info")
const Geometry = require("../Renderer/Geometry")
const MapUtil = require("./MapUtil")
const Random = require("../Miscellaneous/Random")
const Runtime = require("./Runtime")
const Sky = require("../Renderer/Sky")
const State = require("../Renderer/State")
const Tables = require("../Engine/Tables")

const SPECIAL = 1
const SOLID = 2
const SHOOTABLE = 4
const DROPOFF = 0x400
const PICKUP = 0x800
const NOCLIP = 0x1000
const FLOAT = 0x4000
const TELEPORT = 0x8000
const MISSILE = 0x10000
const DROPPED = 0x20000
const NOBLOOD = Info.NOBLOOD
const SKULLFLY = 0x1000000

const BLOCKING = 1
const BLOCKMONSTERS = 2
const TWOSIDED = 4
const SlopeHorizontal = 0
const SlopeVertical = 1

const BOXTOP = 0
const BOXBOTTOM = 1
const BOXLEFT = 2
const BOXRIGHT = 3
const FRACBITS = 16
const FRACUNIT = 65536
const UINT32_MASK = 0xFFFFFFFF
const SIGNBIT = 0x80000000
const ANG180 = 0x80000000
const ANGLETOFINESHIFT = 19
const FINEMASK = 8191
const finecosine = Tables.finecosine
const finesine = Tables.finesine
const FixedMul = Fixed.FixedMul
const FixedDiv = Fixed.FixedDiv
const SkyGetSkyFlatNum = Sky.GetSkyFlatNum
const RandomValue = Random.PlayRandom

const MAXRADIUS = 32 * FRACUNIT
const MAXSPECIALCROSS = 8
const USERANGE = 64 * FRACUNIT

const GIBS = 895
const sfx_noway = 81
const PLAYER = 0
const BRUISER = 15
const BLOOD = 38
const KNIGHT = 17

type NumberList = { [number]: number }
type Sector = {
	blockbox: NumberList,
	ceilingheight: number,
	ceilingpic: number,
	floorheight: number,
}
type Vertex = {
	x: number,
	y: number,
}
type Line = {
	backsector: Sector,
	bbox: NumberList,
	dx: number,
	dy: number,
	flags: number,
	frontsector: Sector,
	index: number,
	slopetype: number,
	special: number,
	v1: Vertex,
}
type MobjInfo = {
	damage: number,
	spawnstate: number,
}
type Mobj = {
	angle: number,
	ceilingz: number,
	flags: number,
	floorz: number,
	health: number,
	height: number,
	info: MobjInfo,
	momx: number,
	momy: number,
	momz: number,
	player: unknown?,
	radius: number,
	target: Mobj?,
	type: number,
	x: number,
	y: number,
	z: number,
}
type Player = {
	mo: Mobj,
}
type LineIntercept = {
	d: {
		line: Line,
	},
	frac: number,
	isaline: true,
}
type ThingIntercept = {
	d: {
		thing: Mobj,
	},
	frac: number,
	isaline: false,
}
type Intercept = LineIntercept | ThingIntercept

local crushchange = false
local nofit = false
const tmbbox = {
	[BOXTOP] = 0,
	[BOXBOTTOM] = 0,
	[BOXRIGHT] = 0,
	[BOXLEFT] = 0,
}
local tmthing = false
local tmflags = 0
local tmx = 0
local tmy = 0
local floatok = false
local tmfloorz = 0
local tmceilingz = 0
local tmdropoffz = 0
local ceilingline = false
const spechit: { [number]: Line } = {}
local numspechit = 0
local usething = false
local linetarget = false
local shootthing = false
local shootz = 0
local la_damage = 0
local attackrange = 0
local aimslope = 0
local topslope = 0
local bottomslope = 0
local bombsource = false
local bombspot = false
local bombdamage = 0
local bestslidefrac = 0
local bestslideline = false
local slidemo = false
local tmxmove = 0
local tmymove = 0

const BlockThingsIterator = MapUtil.BlockThingsIterator
const BlockLinesIterator = MapUtil.BlockLinesIterator
const PathTraverse = MapUtil.PathTraverse
const LineOpening = MapUtil.LineOpening
const PointOnLineSide = MapUtil.PointOnLineSide
const AproxDistance = MapUtil.ApproximateDistance
const GetOpenTop = MapUtil.GetOpenTop
const GetOpenBottom = MapUtil.GetOpenBottom
const GetOpenRange = MapUtil.GetOpenRange
const GetLowFloor = MapUtil.GetLowFloor
const GetBMapOrgX = MapUtil.GetBMapOrgX
const GetBMapOrgY = MapUtil.GetBMapOrgY

const ADDLINES = MapUtil.ADDLINES
const ADDTHINGS = MapUtil.ADDTHINGS
const MAPBLOCKSHIFT = MapUtil.MAPBLOCKSHIFT

const function SignedRightShift(value: number, shift: number): number
	value = bit32.band(bit32.arshift(value, shift), UINT32_MASK)
	return if value >= SIGNBIT then value - 0x100000000 else value
end

const function ToSigned32(value: number): number
	value = bit32.band(value, UINT32_MASK)
	return if value >= SIGNBIT then value - 0x100000000 else value
end

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function GetMapNumber(): number
	const callback = Runtime.getMapNumber

	if callback == nil then
		return 0
	end

	return callback()
end

-- CheckLineIterator
-- Adjusts tmfloorz and tmceilingz as lines are contacted
const function CheckLineIterator(ld: Line)
	if tmbbox[BOXRIGHT] <= ld.bbox[BOXLEFT]
		or tmbbox[BOXLEFT] >= ld.bbox[BOXRIGHT]
		or tmbbox[BOXTOP] <= ld.bbox[BOXBOTTOM]
		or tmbbox[BOXBOTTOM] >= ld.bbox[BOXTOP] then
		return true
	end

	if MapUtil.BoxOnLineSide(tmbbox, ld) ~= -1 then
		return true
	end

	const thing = tmthing

	if not ld.backsector then
		return false
	end

	if bit32.band(thing.flags, MISSILE) == 0 then
		if bit32.btest(ld.flags, BLOCKING) then
			return false
		end

		if not thing.player and bit32.btest(ld.flags, BLOCKMONSTERS) then
			return false
		end
	end

	LineOpening(ld)

	const openTop = GetOpenTop()
	const openBottom = GetOpenBottom()
	const lowFloor = GetLowFloor()

	if openTop < tmceilingz then
		tmceilingz = openTop
		ceilingline = ld
	end

	if openBottom > tmfloorz then
		tmfloorz = openBottom
	end

	if lowFloor < tmdropoffz then
		tmdropoffz = lowFloor
	end

	if ld.special ~= 0 then
		if numspechit < MAXSPECIALCROSS then
			spechit[numspechit] = ld
			numspechit += 1
		end
	end

	return true
end

-- CheckThingIterator
const function CheckThingIterator(thing: Mobj)
	if bit32.band(thing.flags, bit32.bor(SOLID, SPECIAL, SHOOTABLE)) == 0 then
		return true
	end

	const mover = tmthing

	const blockdist = thing.radius + mover.radius

	if math.abs(thing.x - tmx) >= blockdist or math.abs(thing.y - tmy) >= blockdist then
		return true
	end

	if thing == mover then
		return true
	end

	if bit32.btest(mover.flags, SKULLFLY) then
		const damage = (bit32.band(RandomValue(), 7) + 1) * mover.info.damage

		Runtime.damageMobj(thing, mover, mover, damage)

		mover.flags = bit32.band(mover.flags, bit32.bnot(SKULLFLY))
		mover.momx = 0
		mover.momy = 0
		mover.momz = 0

		Runtime.setMobjState(mover, mover.info.spawnstate)

		return false
	end

	if bit32.btest(mover.flags, MISSILE) then
		if mover.z > thing.z + thing.height then
			return true
		end

		if mover.z + mover.height < thing.z then
			return true
		end

		if mover.target
			and (
				mover.target.type == thing.type
				or (mover.target.type == KNIGHT and thing.type == BRUISER)
				or (mover.target.type == BRUISER and thing.type == KNIGHT)
			) then
			if thing == mover.target then
				return true
			end

			if thing.type ~= PLAYER then
				return false
			end
		end

		if bit32.band(thing.flags, SHOOTABLE) == 0 then
			return bit32.band(thing.flags, SOLID) == 0
		end

		const damage = (bit32.band(RandomValue(), 7) + 1) * mover.info.damage
		Runtime.damageMobj(thing, mover, mover.target, damage)

		return false
	end

	if bit32.btest(thing.flags, SPECIAL) then
		const solid = bit32.btest(thing.flags, SOLID)

		if bit32.btest(tmflags, PICKUP) then
			Runtime.touchSpecialThing(thing, mover)
		end

		return not solid
	end

	return bit32.band(thing.flags, SOLID) == 0
end

-- CheckPosition
-- This is purely informative, nothing is modified
-- (except things picked up).
const function CheckPosition(thing: Mobj, x: number, y: number): boolean
	tmthing = thing
	tmflags = thing.flags
	tmx = x
	tmy = y

	tmbbox[BOXTOP] = y + thing.radius
	tmbbox[BOXBOTTOM] = y - thing.radius
	tmbbox[BOXRIGHT] = x + thing.radius
	tmbbox[BOXLEFT] = x - thing.radius

	const newsubsec = MapUtil.PointInSubsector(x, y)

	ceilingline = false

	tmfloorz = newsubsec.sector.floorheight
	tmdropoffz = newsubsec.sector.floorheight
	tmceilingz = newsubsec.sector.ceilingheight

	State.validcount = State.validcount + 1
	numspechit = 0

	if bit32.btest(tmflags, NOCLIP) then
		return true
	end

	const bmaporgx = GetBMapOrgX()
	const bmaporgy = GetBMapOrgY()
	local xl = SignedRightShift(tmbbox[BOXLEFT] - bmaporgx - MAXRADIUS, MAPBLOCKSHIFT)
	local xh = SignedRightShift(tmbbox[BOXRIGHT] - bmaporgx + MAXRADIUS, MAPBLOCKSHIFT)
	local yl = SignedRightShift(tmbbox[BOXBOTTOM] - bmaporgy - MAXRADIUS, MAPBLOCKSHIFT)
	local yh = SignedRightShift(tmbbox[BOXTOP] - bmaporgy + MAXRADIUS, MAPBLOCKSHIFT)

	for bx = xl, xh do
		for by = yl, yh do
			if not BlockThingsIterator(bx, by, CheckThingIterator) then
				return false
			end
		end
	end

	xl = SignedRightShift(tmbbox[BOXLEFT] - bmaporgx, MAPBLOCKSHIFT)
	xh = SignedRightShift(tmbbox[BOXRIGHT] - bmaporgx, MAPBLOCKSHIFT)
	yl = SignedRightShift(tmbbox[BOXBOTTOM] - bmaporgy, MAPBLOCKSHIFT)
	yh = SignedRightShift(tmbbox[BOXTOP] - bmaporgy, MAPBLOCKSHIFT)

	for bx = xl, xh do
		for by = yl, yh do
			if not BlockLinesIterator(bx, by, CheckLineIterator) then
				return false
			end
		end
	end

	return true
end

-- ThingHeightClip
-- Takes a valid thing and adjusts the thing->floorz,
-- thing->ceilingz, and possibly thing->z.
const function ThingHeightClip(thing: Mobj): boolean
	const onfloor = thing.z == thing.floorz

	CheckPosition(thing, thing.x, thing.y)

	thing.floorz = tmfloorz
	thing.ceilingz = tmceilingz

	if onfloor then
		thing.z = thing.floorz
	else
		if thing.z + thing.height > thing.ceilingz then
			thing.z = thing.ceilingz - thing.height
		end
	end

	if thing.ceilingz - thing.floorz < thing.height then
		return false
	end

	return true
end

-- StompThingIterator
const function StompThingIterator(thing: Mobj)
	if bit32.band(thing.flags, SHOOTABLE) == 0 then
		return true
	end

	const mover = tmthing

	const blockdist = thing.radius + mover.radius

	if math.abs(thing.x - tmx) >= blockdist or math.abs(thing.y - tmy) >= blockdist then
		return true
	end

	if thing == mover then
		return true
	end

	if not mover.player and GetMapNumber() ~= 30 then
		return false
	end

	Runtime.damageMobj(thing, mover, mover, 10000)

	return true
end

-- AimLineAttack
const function AimTraverseIterator(intercept: Intercept)
	if intercept.isaline then
		const li = intercept.d.line

		if bit32.band(li.flags, TWOSIDED) == 0 then
			return false
		end

		LineOpening(li)

		if GetOpenBottom() >= GetOpenTop() then
			return false
		end

		const dist = FixedMul(attackrange, intercept.frac)

		if li.frontsector.floorheight ~= li.backsector.floorheight then
			const slope = FixedDiv(GetOpenBottom() - shootz, dist)

			if slope > bottomslope then
				bottomslope = slope
			end
		end

		if li.frontsector.ceilingheight ~= li.backsector.ceilingheight then
			const slope = FixedDiv(GetOpenTop() - shootz, dist)

			if slope < topslope then
				topslope = slope
			end
		end

		if topslope <= bottomslope then
			return false
		end

		return true
	end

	const thing = intercept.d.thing

	if thing == shootthing then
		return true
	end

	if bit32.band(thing.flags, SHOOTABLE) == 0 then
		return true
	end

	const dist = FixedMul(attackrange, intercept.frac)
	local thingtopslope = FixedDiv(thing.z + thing.height - shootz, dist)

	if thingtopslope < bottomslope then
		return true
	end

	local thingbottomslope = FixedDiv(thing.z - shootz, dist)

	if thingbottomslope > topslope then
		return true
	end

	if thingtopslope > topslope then
		thingtopslope = topslope
	end

	if thingbottomslope < bottomslope then
		thingbottomslope = bottomslope
	end

	aimslope = math.modf((thingtopslope + thingbottomslope) / 2)
	linetarget = thing

	return false
end

const function ShootTraverseIterator(intercept: Intercept)
	const trace = MapUtil.GetTrace()

	if intercept.isaline then
		const li = intercept.d.line

		if li.special ~= 0 then
			Runtime.shootSpecialLine(shootthing, li)
		end

		if bit32.band(li.flags, TWOSIDED) == 0 then
			const frac = intercept.frac - FixedDiv(4 * FRACUNIT, attackrange)
			const x = trace.x + FixedMul(trace.dx, frac)
			const y = trace.y + FixedMul(trace.dy, frac)
			const z = shootz + FixedMul(aimslope, FixedMul(frac, attackrange))

			if li.frontsector.ceilingpic == SkyGetSkyFlatNum() then
				if z > li.frontsector.ceilingheight then
					return false
				end

				if li.backsector and li.backsector.ceilingpic == SkyGetSkyFlatNum() then
					return false
				end
			end

			Runtime.spawnPuff(x, y, z)
			return false
		end

		LineOpening(li)

		const dist = FixedMul(attackrange, intercept.frac)

		if li.frontsector.floorheight ~= li.backsector.floorheight then
			const slope = FixedDiv(GetOpenBottom() - shootz, dist)

			if slope > aimslope then
				const frac = intercept.frac - FixedDiv(4 * FRACUNIT, attackrange)
				const x = trace.x + FixedMul(trace.dx, frac)
				const y = trace.y + FixedMul(trace.dy, frac)
				const z = shootz + FixedMul(aimslope, FixedMul(frac, attackrange))

				if li.frontsector.ceilingpic == SkyGetSkyFlatNum() then
					if z > li.frontsector.ceilingheight then
						return false
					end

					if li.backsector and li.backsector.ceilingpic == SkyGetSkyFlatNum() then
						return false
					end
				end

				Runtime.spawnPuff(x, y, z)
				return false
			end
		end

		if li.frontsector.ceilingheight ~= li.backsector.ceilingheight then
			const slope = FixedDiv(GetOpenTop() - shootz, dist)

			if slope < aimslope then
				const frac = intercept.frac - FixedDiv(4 * FRACUNIT, attackrange)
				const x = trace.x + FixedMul(trace.dx, frac)
				const y = trace.y + FixedMul(trace.dy, frac)
				const z = shootz + FixedMul(aimslope, FixedMul(frac, attackrange))

				if li.frontsector.ceilingpic == SkyGetSkyFlatNum() then
					if z > li.frontsector.ceilingheight then
						return false
					end

					if li.backsector and li.backsector.ceilingpic == SkyGetSkyFlatNum() then
						return false
					end
				end

				Runtime.spawnPuff(x, y, z)
				return false
			end
		end

		return true
	end

	const thing = intercept.d.thing

	if thing == shootthing then
		return true
	end

	if bit32.band(thing.flags, SHOOTABLE) == 0 then
		return true
	end

	const dist = FixedMul(attackrange, intercept.frac)
	const thingtopslope = FixedDiv(thing.z + thing.height - shootz, dist)

	if thingtopslope < aimslope then
		return true
	end

	const thingbottomslope = FixedDiv(thing.z - shootz, dist)

	if thingbottomslope > aimslope then
		return true
	end

	const frac = intercept.frac - FixedDiv(10 * FRACUNIT, attackrange)
	const x = trace.x + FixedMul(trace.dx, frac)
	const y = trace.y + FixedMul(trace.dy, frac)
	const z = shootz + FixedMul(aimslope, FixedMul(frac, attackrange))

	if bit32.btest(thing.flags, NOBLOOD) then
		Runtime.spawnPuff(x, y, z)
	else
		Runtime.spawnBlood(x, y, z, la_damage)
	end

	if la_damage ~= 0 then
		Runtime.damageMobj(thing, shootthing, shootthing, la_damage)
	end

	return false
end

const function AimLineAttack(t1: Mobj, angle: number, distance: number): number
	angle = bit32.rshift(bit32.band(angle, UINT32_MASK), ANGLETOFINESHIFT)
	shootthing = t1

	const x2 = ToSigned32(t1.x + bit32.arshift(distance, FRACBITS) * finecosine[angle])
	const y2 = ToSigned32(t1.y + bit32.arshift(distance, FRACBITS) * finesine[angle])

	shootz = ToSigned32(t1.z + t1.height // 2 + 8 * FRACUNIT)
	topslope = math.modf(100 * FRACUNIT / 160)
	bottomslope = math.modf(-100 * FRACUNIT / 160)
	attackrange = distance
	linetarget = false

	PathTraverse(t1.x, t1.y, x2, y2, bit32.bor(ADDLINES, ADDTHINGS), AimTraverseIterator)

	if linetarget then
		return aimslope
	end

	return 0
end

const function LineAttack(t1: Mobj, angle: number, distance: number, slope: number, damage: number)
	angle = bit32.rshift(bit32.band(angle, UINT32_MASK), ANGLETOFINESHIFT)
	shootthing = t1
	la_damage = damage

	const x2 = ToSigned32(t1.x + bit32.arshift(distance, FRACBITS) * finecosine[angle])
	const y2 = ToSigned32(t1.y + bit32.arshift(distance, FRACBITS) * finesine[angle])

	shootz = ToSigned32(t1.z + t1.height // 2 + 8 * FRACUNIT)
	attackrange = distance
	aimslope = slope

	PathTraverse(t1.x, t1.y, x2, y2, bit32.bor(ADDLINES, ADDTHINGS), ShootTraverseIterator)
end

const function UseTraverseIterator(intercept: LineIntercept)
	const line = intercept.d.line

	if line.special == 0 then
		LineOpening(line)

		if GetOpenRange() <= 0 then
			const startSound = Runtime.startSound

			if startSound ~= nil then
				startSound(usething, sfx_noway)
			end

			return false
		end

		return true
	end

	local side = 0

	if PointOnLineSide(usething.x, usething.y, line) == 1 then
		side = 1
	end

	Runtime.useSpecialLine(usething, line, side)
	return false
end

-- UseLines
-- Looks for special lines in front of the player to activate.
const function UseLines(player: Player)
	usething = player.mo

	const angle = bit32.rshift(bit32.band(player.mo.angle, UINT32_MASK), ANGLETOFINESHIFT)
	const x1 = player.mo.x
	const y1 = player.mo.y
	const x2 = ToSigned32(x1 + bit32.arshift(USERANGE, FRACBITS) * finecosine[angle])
	const y2 = ToSigned32(y1 + bit32.arshift(USERANGE, FRACBITS) * finesine[angle])

	PathTraverse(x1, y1, x2, y2, ADDLINES, UseTraverseIterator)
end

-- RADIUS ATTACK
const function RadiusAttackIterator(thing: Mobj)
	if bit32.band(thing.flags, SHOOTABLE) == 0 then
		return true
	end

	if thing.type == Info.CYBORG or thing.type == Info.SPIDER then
		return true
	end

	const dx = math.abs(thing.x - bombspot.x)
	const dy = math.abs(thing.y - bombspot.y)
	local dist = math.max(dx, dy)

	dist = SignedRightShift(dist - thing.radius, FRACBITS)

	if dist < 0 then
		dist = 0
	end

	if dist >= bombdamage then
		return true
	end

	if Runtime.checkSight(thing, bombspot) then
		Runtime.damageMobj(thing, bombspot, bombsource, bombdamage - dist)
	end

	return true
end

const function RadiusAttack(spot: Mobj, source: Mobj?, damage: number)
	const dist = (damage + MAXRADIUS) * FRACUNIT
	const bmaporgx = GetBMapOrgX()
	const bmaporgy = GetBMapOrgY()
	const yh = SignedRightShift(spot.y + dist - bmaporgy, MAPBLOCKSHIFT)
	const yl = SignedRightShift(spot.y - dist - bmaporgy, MAPBLOCKSHIFT)
	const xh = SignedRightShift(spot.x + dist - bmaporgx, MAPBLOCKSHIFT)
	const xl = SignedRightShift(spot.x - dist - bmaporgx, MAPBLOCKSHIFT)

	bombspot = spot
	bombsource = source
	bombdamage = damage

	for y = yl, yh do
		for x = xl, xh do
			BlockThingsIterator(x, y, RadiusAttackIterator)
		end
	end
end

-- TeleportMove
const function TeleportMove(thing: Mobj, x: number, y: number): boolean
	tmthing = thing
	tmflags = thing.flags
	tmx = x
	tmy = y

	tmbbox[BOXTOP] = y + thing.radius
	tmbbox[BOXBOTTOM] = y - thing.radius
	tmbbox[BOXRIGHT] = x + thing.radius
	tmbbox[BOXLEFT] = x - thing.radius

	const newsubsec = MapUtil.PointInSubsector(x, y)

	ceilingline = false

	tmfloorz = newsubsec.sector.floorheight
	tmdropoffz = newsubsec.sector.floorheight
	tmceilingz = newsubsec.sector.ceilingheight

	State.validcount = State.validcount + 1
	numspechit = 0

	const bmaporgx = GetBMapOrgX()
	const bmaporgy = GetBMapOrgY()
	const xl = SignedRightShift(tmbbox[BOXLEFT] - bmaporgx - MAXRADIUS, MAPBLOCKSHIFT)
	const xh = SignedRightShift(tmbbox[BOXRIGHT] - bmaporgx + MAXRADIUS, MAPBLOCKSHIFT)
	const yl = SignedRightShift(tmbbox[BOXBOTTOM] - bmaporgy - MAXRADIUS, MAPBLOCKSHIFT)
	const yh = SignedRightShift(tmbbox[BOXTOP] - bmaporgy + MAXRADIUS, MAPBLOCKSHIFT)

	for bx = xl, xh do
		for by = yl, yh do
			if not BlockThingsIterator(bx, by, StompThingIterator) then
				return false
			end
		end
	end

	MapUtil.UnsetThingPosition(thing)

	thing.floorz = tmfloorz
	thing.ceilingz = tmceilingz
	thing.x = x
	thing.y = y

	MapUtil.SetThingPosition(thing)

	return true
end

-- TryMove
-- Attempt to move to a new position,
-- crossing special lines unless TELEPORT is set.
const function TryMove(thing: Mobj, x: number, y: number): boolean
	local oldx
	local oldy

	floatok = false

	if not CheckPosition(thing, x, y) then
		return false
	end

	if bit32.band(thing.flags, NOCLIP) == 0 then
		if tmceilingz - tmfloorz < thing.height then
			return false
		end

		floatok = true

		if bit32.band(thing.flags, TELEPORT) == 0 and tmceilingz - thing.z < thing.height then
			return false
		end

		if bit32.band(thing.flags, TELEPORT) == 0 and tmfloorz - thing.z > 24 * FRACUNIT then
			return false
		end

		if bit32.band(thing.flags, bit32.bor(DROPOFF, FLOAT)) == 0
			and tmfloorz - tmdropoffz > 24 * FRACUNIT then
			return false
		end
	end

	MapUtil.UnsetThingPosition(thing)

	oldx = thing.x
	oldy = thing.y
	thing.floorz = tmfloorz
	thing.ceilingz = tmceilingz
	thing.x = x
	thing.y = y

	MapUtil.SetThingPosition(thing)

	if bit32.band(thing.flags, bit32.bor(TELEPORT, NOCLIP)) == 0 then
		while numspechit > 0 do
			numspechit -= 1

			const ld = spechit[numspechit]
			const side = PointOnLineSide(thing.x, thing.y, ld)
			const oldside = PointOnLineSide(oldx, oldy, ld)

			if side ~= oldside and ld.special ~= 0 then

				Runtime.crossSpecialLine(ld.index, oldside, thing)
			end
		end
	end

	return true
end

-- SLIDE MOVE
-- Allows the player to slide along any angled walls.
const function HitSlideLine(ld: Line)
	if ld.slopetype == SlopeHorizontal then
		tmymove = 0
		return
	end

	if ld.slopetype == SlopeVertical then
		tmxmove = 0
		return
	end

	const side = PointOnLineSide(slidemo.x, slidemo.y, ld)
	local lineangle = Geometry.PointToAngle2(0, 0, ld.dx, ld.dy)

	if side == 1 then
		lineangle = bit32.band(lineangle + ANG180, UINT32_MASK)
	end

	const moveangle = Geometry.PointToAngle2(0, 0, tmxmove, tmymove)
	local deltaangle = bit32.band(moveangle - lineangle, UINT32_MASK)

	if deltaangle > ANG180 then
		deltaangle = bit32.band(deltaangle + ANG180, UINT32_MASK)
	end

	lineangle = bit32.band(bit32.rshift(lineangle, ANGLETOFINESHIFT), FINEMASK)
	deltaangle = bit32.band(bit32.rshift(deltaangle, ANGLETOFINESHIFT), FINEMASK)

	const movelen = AproxDistance(tmxmove, tmymove)
	const newlen = FixedMul(movelen, finecosine[deltaangle])

	tmxmove = FixedMul(newlen, finecosine[lineangle])
	tmymove = FixedMul(newlen, finesine[lineangle])
end

const function SlideTraverseIterator(intercept: LineIntercept)

	const li = intercept.d.line

	if bit32.band(li.flags, TWOSIDED) == 0 then
		if PointOnLineSide(slidemo.x, slidemo.y, li) == 1 then
			return true
		end
	else
		LineOpening(li)

		if GetOpenRange() >= slidemo.height
			and GetOpenTop() - slidemo.z >= slidemo.height
			and GetOpenBottom() - slidemo.z <= 24 * FRACUNIT then
			return true
		end
	end

	if intercept.frac < bestslidefrac then
		bestslidefrac = intercept.frac
		bestslideline = li
	end

	return false
end

const function SlideMove(mo: Mobj)
	slidemo = mo

	local hitcount = 0

	while true do
		hitcount += 1

		if hitcount == 3 then
			if not TryMove(mo, mo.x, mo.y + mo.momy) then
				TryMove(mo, mo.x + mo.momx, mo.y)
			end

			return
		end

		local leadx
		local leady
		local trailx
		local traily

		if mo.momx > 0 then
			leadx = mo.x + mo.radius
			trailx = mo.x - mo.radius
		else
			leadx = mo.x - mo.radius
			trailx = mo.x + mo.radius
		end

		if mo.momy > 0 then
			leady = mo.y + mo.radius
			traily = mo.y - mo.radius
		else
			leady = mo.y - mo.radius
			traily = mo.y + mo.radius
		end

		bestslidefrac = FRACUNIT + 1
		bestslideline = false

		PathTraverse(leadx, leady, leadx + mo.momx, leady + mo.momy, ADDLINES, SlideTraverseIterator)
		PathTraverse(trailx, leady, trailx + mo.momx, leady + mo.momy, ADDLINES, SlideTraverseIterator)
		PathTraverse(leadx, traily, leadx + mo.momx, traily + mo.momy, ADDLINES, SlideTraverseIterator)

		if bestslidefrac == FRACUNIT + 1 then
			if not TryMove(mo, mo.x, mo.y + mo.momy) then
				TryMove(mo, mo.x + mo.momx, mo.y)
			end

			return
		end

		bestslidefrac -= 0x800

		if bestslidefrac > 0 then
			const newx = FixedMul(mo.momx, bestslidefrac)
			const newy = FixedMul(mo.momy, bestslidefrac)

			if not TryMove(mo, mo.x + newx, mo.y + newy) then
				if not TryMove(mo, mo.x, mo.y + mo.momy) then
					TryMove(mo, mo.x + mo.momx, mo.y)
				end

				return
			end
		end

		bestslidefrac = FRACUNIT - (bestslidefrac + 0x800)

		if bestslidefrac > FRACUNIT then
			bestslidefrac = FRACUNIT
		end

		if bestslidefrac <= 0 then
			return
		end

		tmxmove = FixedMul(mo.momx, bestslidefrac)
		tmymove = FixedMul(mo.momy, bestslidefrac)

		if not bestslideline then
			return
		end

		HitSlideLine(bestslideline)

		mo.momx = tmxmove
		mo.momy = tmymove

		if TryMove(mo, mo.x + tmxmove, mo.y + tmymove) then
			return
		end
	end
end

-- ChangeSectorIterator
const function ChangeSectorIterator(thing: Mobj)
	if ThingHeightClip(thing) then
		-- keep checking
		return true
	end

	-- crunch bodies to giblets
	if thing.health <= 0 then
		Runtime.setMobjState(thing, GIBS)

		thing.flags = bit32.band(thing.flags, bit32.bnot(SOLID))
		thing.height = 0
		thing.radius = 0

		-- keep checking
		return true
	end

	-- crunch dropped items
	if bit32.btest(thing.flags, DROPPED) then
		Runtime.removeMobj(thing)

		-- keep checking
		return true
	end

	if bit32.band(thing.flags, SHOOTABLE) == 0 then
		-- assume it is bloody gibs or something
		return true
	end

	nofit = true

	if crushchange and bit32.band(GetLevelTime(), 3) == 0 then
		Runtime.damageMobj(thing, nil, nil, 10)

		-- spray blood in a random direction
		const mo = Runtime.spawnMobj(thing.x, thing.y, thing.z + thing.height // 2, BLOOD)

		mo.momx = (RandomValue() - RandomValue()) * 4096
		mo.momy = (RandomValue() - RandomValue()) * 4096
	end

	-- keep checking (crush other things)
	return true
end

-- ChangeSector
const function ChangeSector(sector: Sector, crunch: boolean): boolean
	const left = sector.blockbox[BOXLEFT]
	const right = sector.blockbox[BOXRIGHT]
	const bottom = sector.blockbox[BOXBOTTOM]
	const top = sector.blockbox[BOXTOP]

	nofit = false
	crushchange = crunch

	-- re-check heights for all things near the moving sector
	for x = left, right do
		for y = bottom, top do
			BlockThingsIterator(x, y, ChangeSectorIterator)
		end
	end

	return nofit
end

const function Reset()
	crushchange = false
	nofit = false
	tmthing = false
	tmflags = 0
	tmx = 0
	tmy = 0
	floatok = false
	tmfloorz = 0
	tmceilingz = 0
	tmdropoffz = 0
	ceilingline = false
	numspechit = 0
	usething = false
	linetarget = false
	shootthing = false
	shootz = 0
	la_damage = 0
	attackrange = 0
	aimslope = 0
	topslope = 0
	bottomslope = 0
	bombsource = false
	bombspot = false
	bombdamage = 0
	bestslidefrac = 0
	bestslideline = false
	slidemo = false
	tmxmove = 0
	tmymove = 0
end

const function GetFloatOK(): boolean
	return floatok
end

const function GetTMFloorZ(): number
	return tmfloorz
end

const function GetCeilingLine()
	return ceilingline
end

const function GetNumSpecialHits(): number
	return numspechit
end

const function GetSpecialHits()
	return spechit
end

const function GetLineTarget()
	return linetarget
end

const function GetShootThing()
	return shootthing
end

const function GetShootZ(): number
	return shootz
end

const function GetLADamage(): number
	return la_damage
end

const function GetAttackRange(): number
	return attackrange
end

return {
	MISSILE = MISSILE,
	MAXRADIUS = MAXRADIUS,

	Reset = Reset,
	GetFloatOK = GetFloatOK,
	GetTMFloorZ = GetTMFloorZ,
	GetCeilingLine = GetCeilingLine,
	GetNumSpecialHits = GetNumSpecialHits,
	GetSpecialHits = GetSpecialHits,
	GetLineTarget = GetLineTarget,
	GetShootThing = GetShootThing,
	GetShootZ = GetShootZ,
	GetLADamage = GetLADamage,
	GetAttackRange = GetAttackRange,

	CheckPosition = CheckPosition,
	TeleportMove = TeleportMove,
	TryMove = TryMove,
	SlideMove = SlideMove,
	AimLineAttack = AimLineAttack,
	LineAttack = LineAttack,
	RadiusAttack = RadiusAttack,
	ChangeSector = ChangeSector,
	UseLines = UseLines,
}
