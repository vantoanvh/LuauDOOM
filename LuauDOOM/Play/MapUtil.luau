--!native
--!optimize 2

-- Port of p_maputl.c, p_local.h
-- Movement/collision utility functions.
-- This file ports the block/sector thing-link routines, block iterators,
-- line/divline helpers, and `LineOpening`.
-- Note: blockmap state is shared through `WorldState.luau`.

const Fixed = require("../Miscellaneous/Fixed")
const Main = require("../Renderer/Main")
const State = require("../Renderer/State")
const WorldState = require("./WorldState")

const NOSECTOR = 8
const NOBLOCKMAP = 16

const BOXTOP = 0
const BOXBOTTOM = 1
const BOXLEFT = 2
const BOXRIGHT = 3
const FRACBITS = 16
const FRACUNIT = 65536
const MAPBLOCKSIZE = 128 * FRACUNIT
const MAPBLOCKSHIFT = FRACBITS + 7
const MAPBTOFRAC = MAPBLOCKSHIFT - FRACBITS

const SlopeHorizontal = 0
const SlopeVertical = 1
const SlopePositive = 2
const SlopeNegative = 3

const ADDLINES = 1
const ADDTHINGS = 2
const EARLYOUT = 4

const MAXINT = 2147483647
const UINT32_MASK = 0xFFFFFFFF
const SIGNBIT = 0x80000000
const FixedMul = Fixed.FixedMul
const FixedDiv = Fixed.FixedDiv

type Vertex = {
	x: number,
	y: number,
}

type Divline = {
	x: number,
	y: number,
	dx: number,
	dy: number,
}

type Sector = {
	ceilingheight: number,
	floorheight: number,
	thinglist: Thing? | false,
}

type Subsector = {
	sector: Sector,
}

type Thing = {
	x: number,
	y: number,
	radius: number,
	flags: number,
	subsector: Subsector,
	snext: Thing? | false,
	sprev: Thing? | false,
	bnext: Thing? | false,
	bprev: Thing? | false,
}

type Line = {
	dx: number,
	dy: number,
	v1: Vertex,
	v2: Vertex,
	slopetype: number,
	sidenum: { [number]: number },
	frontsector: Sector,
	backsector: Sector? | false,
	validcount: number,
}

type Box = { [number]: number }

type Intercept = {
	frac: number,
	isaline: boolean,
	d: {
		line: Line?,
		thing: Thing?,
	},
}

local opentop = 0
local openbottom = 0
local openrange = 0
local lowfloor = 0
const intercepts: { [number]: Intercept } = {}
local interceptCount = 0
const trace: Divline = {
	x = 0,
	y = 0,
	dx = 0,
	dy = 0,
}
const lineDivlineScratch: Divline = {
	x = 0,
	y = 0,
	dx = 0,
	dy = 0,
}
const thingDivlineScratch: Divline = {
	x = 0,
	y = 0,
	dx = 0,
	dy = 0,
}
local earlyout = false

const function TruthyC(result: unknown): boolean
	return result ~= nil and result ~= false and result ~= 0
end

const function SignedRightShift(value: number, shift: number): number
	value = bit32.band(bit32.arshift(value, shift), UINT32_MASK)

	return if value >= SIGNBIT then value - 0x100000000 else value
end

const function ToSigned32(value: number): number
	value = bit32.band(value, UINT32_MASK)
	return if value >= SIGNBIT then value - 0x100000000 else value
end

const function MapBlockCoord(value: number, origin: number): number
	return SignedRightShift(value - origin, MAPBLOCKSHIFT)
end

const function GetBMapWidth(): number
	return WorldState.bmapwidth
end

const function GetBMapHeight(): number
	return WorldState.bmapheight
end

const function GetBMapOrgX(): number
	return WorldState.bmaporgx
end

const function GetBMapOrgY(): number
	return WorldState.bmaporgy
end

const function AddIntercept(intercept: Intercept)
	intercepts[interceptCount] = intercept
	interceptCount += 1
end

const function PointInSubsector(x: number, y: number): Subsector
	return Main.PointInSubsector(x, y)
end

-- ApproximateDistance
-- Gives an estimation of distance (not exact)
const function ApproximateDistance(dx: number, dy: number): number
	dx = ToSigned32(dx)
	dy = ToSigned32(dy)

	dx = math.abs(dx)
	dy = math.abs(dy)

	if dx < dy then
		return ToSigned32(dx + dy - dx // 2)
	end

	return ToSigned32(dx + dy - dy // 2)
end

-- PointOnLineSide
-- Returns 0 or 1
const function PointOnLineSide(x: number, y: number, line: Line): number
	local dx
	local dy
	local left
	local right
	const lineDx = ToSigned32(line.dx)
	const lineDy = ToSigned32(line.dy)

	if lineDx == 0 then
		if x <= line.v1.x then
			return if lineDy > 0 then 1 else 0
		end

		return if lineDy < 0 then 1 else 0
	end

	if lineDy == 0 then
		if y <= line.v1.y then
			return if lineDx < 0 then 1 else 0
		end

		return if lineDx > 0 then 1 else 0
	end

	dx = ToSigned32(x - line.v1.x)
	dy = ToSigned32(y - line.v1.y)

	left = FixedMul(SignedRightShift(lineDy, FRACBITS), dx)
	right = FixedMul(dy, SignedRightShift(lineDx, FRACBITS))

	if right < left then
		return 0
	end

	return 1
end

-- BoxOnLineSide
-- Considers the line to be infinite
-- Returns side 0 or 1, -1 if box crosses the line.
const function BoxOnLineSide(tmbox: Box, ld: Line): number
	local p1
	local p2

	if ld.slopetype == SlopeHorizontal then
		p1 = tmbox[BOXTOP] > ld.v1.y and 1 or 0
		p2 = tmbox[BOXBOTTOM] > ld.v1.y and 1 or 0

		if ld.dx < 0 then
			p1 = bit32.bxor(p1, 1)
			p2 = bit32.bxor(p2, 1)
		end
	elseif ld.slopetype == SlopeVertical then
		p1 = tmbox[BOXRIGHT] < ld.v1.x and 1 or 0
		p2 = tmbox[BOXLEFT] < ld.v1.x and 1 or 0

		if ld.dy < 0 then
			p1 = bit32.bxor(p1, 1)
			p2 = bit32.bxor(p2, 1)
		end
	elseif ld.slopetype == SlopePositive then
		p1 = PointOnLineSide(tmbox[BOXLEFT], tmbox[BOXTOP], ld)
		p2 = PointOnLineSide(tmbox[BOXRIGHT], tmbox[BOXBOTTOM], ld)
	elseif ld.slopetype == SlopeNegative then
		p1 = PointOnLineSide(tmbox[BOXRIGHT], tmbox[BOXTOP], ld)
		p2 = PointOnLineSide(tmbox[BOXLEFT], tmbox[BOXBOTTOM], ld)
	else
		error(`BoxOnLineSide: bad slopetype {ld.slopetype}`)
	end

	if p1 == p2 then
		return p1
	end

	return -1
end

-- PointOnDivlineSide
-- Returns 0 or 1.
const function PointOnDivlineSide(x: number, y: number, line: Divline): number
	local dx
	local dy
	local left
	local right
	const lineDx = ToSigned32(line.dx)
	const lineDy = ToSigned32(line.dy)

	if lineDx == 0 then
		if x <= line.x then
			return if lineDy > 0 then 1 else 0
		end

		return if lineDy < 0 then 1 else 0
	end

	if lineDy == 0 then
		if y <= line.y then
			return if lineDx < 0 then 1 else 0
		end

		return if lineDx > 0 then 1 else 0
	end

	dx = ToSigned32(x - line.x)
	dy = ToSigned32(y - line.y)

	if bit32.btest(bit32.bxor(lineDy, lineDx, dx, dy), 0x80000000) then
		if bit32.btest(bit32.bxor(lineDy, dx), 0x80000000) then
			return 1
		end

		return 0
	end

	left = FixedMul(SignedRightShift(lineDy, 8), SignedRightShift(dx, 8))
	right = FixedMul(SignedRightShift(dy, 8), SignedRightShift(lineDx, 8))

	if right < left then
		return 0
	end

	return 1
end

-- MakeDivline
const function MakeDivline(li: Line, dl: Divline)
	dl.x = li.v1.x
	dl.y = li.v1.y
	dl.dx = li.dx
	dl.dy = li.dy
end

-- InterceptVector
-- Returns the fractional intercept point
-- along the first divline.
-- This is only called by the addthings
-- and addlines traversers.
const function InterceptVector(v2: Divline, v1: Divline): number
	const den = FixedMul(SignedRightShift(v1.dy, 8), v2.dx) - FixedMul(SignedRightShift(v1.dx, 8), v2.dy)

	if den == 0 then
		return 0
	end

	const num = FixedMul(SignedRightShift(v1.x - v2.x, 8), v1.dy)
		+ FixedMul(SignedRightShift(v2.y - v1.y, 8), v1.dx)

	return FixedDiv(num, den)
end

-- LineOpening
-- Sets opentop and openbottom to the window
-- through a two sided line.
-- OPTIMIZE: keep this precalculated
const function LineOpening(linedef: Line)
	if linedef.sidenum[1] == -1 then
		-- single sided line
		openrange = 0
		return
	end

	const front = linedef.frontsector
	const back = linedef.backsector

	if front.ceilingheight < back.ceilingheight then
		opentop = front.ceilingheight
	else
		opentop = back.ceilingheight
	end

	if front.floorheight > back.floorheight then
		openbottom = front.floorheight
		lowfloor = back.floorheight
	else
		openbottom = back.floorheight
		lowfloor = front.floorheight
	end

	openrange = opentop - openbottom
end

-- UnsetThingPosition
-- Unlinks a thing from block map and sectors.
const function UnsetThingPosition(thing: Thing)
	local blockx
	local blocky

	if bit32.band(thing.flags, NOSECTOR) == 0 then
		-- unlink from subsector
		if thing.snext then
			thing.snext.sprev = thing.sprev
		end

		if thing.sprev then
			thing.sprev.snext = thing.snext
		else

			thing.subsector.sector.thinglist = thing.snext
		end
	end

	if bit32.band(thing.flags, NOBLOCKMAP) == 0 then
		-- unlink from block map
		if thing.bnext then
			thing.bnext.bprev = thing.bprev
		end

		if thing.bprev then
			thing.bprev.bnext = thing.bnext
		else
			const bmaporgx = WorldState.bmaporgx
			const bmaporgy = WorldState.bmaporgy
			const bmapwidth = WorldState.bmapwidth
			const bmapheight = WorldState.bmapheight

			blockx = MapBlockCoord(thing.x, bmaporgx)
			blocky = MapBlockCoord(thing.y, bmaporgy)

			if blockx >= 0 and blockx < bmapwidth and blocky >= 0 and blocky < bmapheight then
				WorldState.blocklinks[blocky * bmapwidth + blockx] = thing.bnext
			end
		end
	end

	thing.snext = false
	thing.sprev = false
	thing.bnext = false
	thing.bprev = false
end

-- SetThingPosition
-- Links a thing into both a block and a subsector based on it's x y.
-- Sets thing->subsector properly
const function SetThingPosition(thing: Thing)
	const ss = PointInSubsector(thing.x, thing.y)
	thing.subsector = ss

	if bit32.band(thing.flags, NOSECTOR) == 0 then

		const sec = ss.sector

		thing.sprev = false
		thing.snext = sec.thinglist

		if sec.thinglist then
			sec.thinglist.sprev = thing
		end

		sec.thinglist = thing
	end

	if bit32.band(thing.flags, NOBLOCKMAP) == 0 then
		const bmaporgx = WorldState.bmaporgx
		const bmaporgy = WorldState.bmaporgy
		const bmapwidth = WorldState.bmapwidth
		const bmapheight = WorldState.bmapheight
		const blockx = MapBlockCoord(thing.x, bmaporgx)
		const blocky = MapBlockCoord(thing.y, bmaporgy)

		if blockx >= 0 and blockx < bmapwidth and blocky >= 0 and blocky < bmapheight then
			const blocklinks = WorldState.blocklinks
			const index = blocky * bmapwidth + blockx
			const link = blocklinks[index]

			thing.bprev = false
			thing.bnext = link

			if link then
				link.bprev = thing
			end

			blocklinks[index] = thing
		else
			thing.bnext = false
			thing.bprev = false
		end
	end
end

-- BlockLinesIterator
-- The validcount flags are used to avoid checking lines
-- that are marked in multiple mapblocks,
-- so increment validcount before the first call
-- to BlockLinesIterator, then make one or more calls
-- to it.
const function BlockLinesIterator(x: number, y: number, func: (Line) -> unknown): boolean
	const bmapwidth = WorldState.bmapwidth
	const bmapheight = WorldState.bmapheight

	if x < 0 or y < 0 or x >= bmapwidth or y >= bmapheight then
		return true
	end

	local offset = y * bmapwidth + x
	offset = WorldState.blockmap[offset]


	const blockmaplump = WorldState.blockmaplump
	local listIndex = offset
	const lines = State.lines
	const validcount = State.validcount

	while true do
		const lineIndex = blockmaplump[listIndex]


		if lineIndex == -1 then
			break
		end

		const ld = lines[lineIndex]


		if ld.validcount == validcount then
			listIndex += 1
			continue
		end

		ld.validcount = validcount

		if not TruthyC(func(ld)) then
			return false
		end

		listIndex += 1
	end

	return true
end

-- BlockThingsIterator
const function BlockThingsIterator(x: number, y: number, func: (Thing) -> unknown): boolean
	const bmapwidth = WorldState.bmapwidth
	const bmapheight = WorldState.bmapheight

	if x < 0 or y < 0 or x >= bmapwidth or y >= bmapheight then
		return true
	end

	local mobj = WorldState.blocklinks[y * bmapwidth + x]

	while mobj do
		const nextThing = mobj.bnext


		if not TruthyC(func(mobj)) then
			return false
		end

		mobj = nextThing
	end

	return true
end

-- AddLineInterceptsIterator.
-- Looks for lines in the given block
-- that intercept the given trace
-- to add to the intercepts list.
-- A line is crossed if its endpoints
-- are on opposite sides of the trace.
-- Returns true if earlyout and a solid line hit.
const function AddLineInterceptsIterator(ld: Line): boolean
	local s1
	local s2

	if trace.dx > FRACUNIT * 16
		or trace.dy > FRACUNIT * 16
		or trace.dx < -FRACUNIT * 16
		or trace.dy < -FRACUNIT * 16 then
		s1 = PointOnDivlineSide(ld.v1.x, ld.v1.y, trace)
		s2 = PointOnDivlineSide(ld.v2.x, ld.v2.y, trace)
	else
		s1 = PointOnLineSide(trace.x, trace.y, ld)
		s2 = PointOnLineSide(trace.x + trace.dx, trace.y + trace.dy, ld)
	end

	if s1 == s2 then
		return true
	end

	const dl = lineDivlineScratch
	MakeDivline(ld, dl)

	const frac = InterceptVector(trace, dl)

	if frac < 0 then
		return true
	end

	if earlyout and frac < FRACUNIT and not ld.backsector then
		return false
	end

	AddIntercept({
		frac = frac,
		isaline = true,
		d = {
			line = ld,
		},
	})

	return true
end

-- AddThingInterceptsIterator
const function AddThingInterceptsIterator(thing: Thing): boolean
	local x1
	local y1
	local x2
	local y2
	const tracepositive = ToSigned32(bit32.bxor(trace.dx, trace.dy)) > 0

	if tracepositive then
		x1 = thing.x - thing.radius
		y1 = thing.y + thing.radius
		x2 = thing.x + thing.radius
		y2 = thing.y - thing.radius
	else
		x1 = thing.x - thing.radius
		y1 = thing.y - thing.radius
		x2 = thing.x + thing.radius
		y2 = thing.y + thing.radius
	end

	const s1 = PointOnDivlineSide(x1, y1, trace)
	const s2 = PointOnDivlineSide(x2, y2, trace)

	if s1 == s2 then
		return true
	end

	const dl = thingDivlineScratch
	dl.x = x1
	dl.y = y1
	dl.dx = x2 - x1
	dl.dy = y2 - y1

	const frac = InterceptVector(trace, dl)

	if frac < 0 then
		return true
	end

	AddIntercept({
		frac = frac,
		isaline = false,
		d = {
			thing = thing,
		},
	})

	return true
end

-- TraverseIntercepts
-- Returns true if the traverser function returns true
-- for all lines.
const function TraverseIntercepts(func: (Intercept) -> unknown, maxfrac: number): boolean
	local count = interceptCount

	while count > 0 do
		count -= 1

		local dist = MAXINT
		local bestIndex = -1

		for index = 0, interceptCount - 1 do
			const scan = intercepts[index]

			if scan and scan.frac < dist then
				dist = scan.frac
				bestIndex = index
			end
		end

		if dist > maxfrac then
			return true
		end

		const intercept = intercepts[bestIndex]


		if not TruthyC(func(intercept)) then
			return false
		end

		intercept.frac = MAXINT
	end

	return true
end

-- PathTraverse
-- Traces a line from x1,y1 to x2,y2,
-- calling the traverser function for each.
-- Returns true if the traverser function returns true
-- for all lines.
const function PathTraverse(
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	flags: number,
	trav: (Intercept) -> unknown
): boolean
	earlyout = bit32.btest(flags, EARLYOUT)


	State.validcount += 1
	table.clear(intercepts)
	interceptCount = 0
	const bmaporgx = WorldState.bmaporgx
	const bmaporgy = WorldState.bmaporgy

	if bit32.band(x1 - bmaporgx, MAPBLOCKSIZE - 1) == 0 then
		x1 = ToSigned32(x1 + FRACUNIT)
	end

	if bit32.band(y1 - bmaporgy, MAPBLOCKSIZE - 1) == 0 then
		y1 = ToSigned32(y1 + FRACUNIT)
	end

	trace.x = ToSigned32(x1)
	trace.y = ToSigned32(y1)
	trace.dx = ToSigned32(x2 - x1)
	trace.dy = ToSigned32(y2 - y1)

	x1 = ToSigned32(x1 - bmaporgx)
	y1 = ToSigned32(y1 - bmaporgy)
	const xt1 = SignedRightShift(x1, MAPBLOCKSHIFT)
	const yt1 = SignedRightShift(y1, MAPBLOCKSHIFT)

	x2 = ToSigned32(x2 - bmaporgx)
	y2 = ToSigned32(y2 - bmaporgy)
	const xt2 = SignedRightShift(x2, MAPBLOCKSHIFT)
	const yt2 = SignedRightShift(y2, MAPBLOCKSHIFT)

	local mapxstep
	local partial
	local ystep

	if xt2 > xt1 then
		mapxstep = 1
		partial = FRACUNIT - bit32.band(SignedRightShift(x1, MAPBTOFRAC), FRACUNIT - 1)
		ystep = FixedDiv(y2 - y1, math.abs(x2 - x1))
	elseif xt2 < xt1 then
		mapxstep = -1
		partial = bit32.band(SignedRightShift(x1, MAPBTOFRAC), FRACUNIT - 1)
		ystep = FixedDiv(y2 - y1, math.abs(x2 - x1))
	else
		mapxstep = 0
		partial = FRACUNIT
		ystep = 256 * FRACUNIT
	end

	local yintercept = ToSigned32(SignedRightShift(y1, MAPBTOFRAC) + FixedMul(partial, ystep))

	local mapystep
	local xstep

	if yt2 > yt1 then
		mapystep = 1
		partial = FRACUNIT - bit32.band(SignedRightShift(y1, MAPBTOFRAC), FRACUNIT - 1)
		xstep = FixedDiv(x2 - x1, math.abs(y2 - y1))
	elseif yt2 < yt1 then
		mapystep = -1
		partial = bit32.band(SignedRightShift(y1, MAPBTOFRAC), FRACUNIT - 1)
		xstep = FixedDiv(x2 - x1, math.abs(y2 - y1))
	else
		mapystep = 0
		partial = FRACUNIT
		xstep = 256 * FRACUNIT
	end

	local xintercept = ToSigned32(SignedRightShift(x1, MAPBTOFRAC) + FixedMul(partial, xstep))
	local mapx = xt1
	local mapy = yt1

	for _ = 0, 63 do
		if bit32.btest(flags, ADDLINES) then
			if not TruthyC(BlockLinesIterator(mapx, mapy, AddLineInterceptsIterator)) then
				return false
			end
		end

		if bit32.btest(flags, ADDTHINGS) then
			if not TruthyC(BlockThingsIterator(mapx, mapy, AddThingInterceptsIterator)) then
				return false
			end
		end

		if mapx == xt2 and mapy == yt2 then
			break
		end

		if SignedRightShift(yintercept, FRACBITS) == mapy then
			yintercept = ToSigned32(yintercept + ystep)
			mapx += mapxstep
		elseif SignedRightShift(xintercept, FRACBITS) == mapx then
			xintercept = ToSigned32(xintercept + xstep)
			mapy += mapystep
		end
	end

	return TraverseIntercepts(trav, FRACUNIT)
end

const function GetOpenTop(): number
	return opentop
end

const function GetOpenBottom(): number
	return openbottom
end

const function GetOpenRange(): number
	return openrange
end

const function GetLowFloor(): number
	return lowfloor
end

const function GetIntercepts(): { [number]: Intercept }
	return intercepts
end

const function GetInterceptCount(): number
	return interceptCount
end

const function GetTrace(): Divline
	return trace
end

const MapUtil = {
	NOSECTOR = NOSECTOR,
	NOBLOCKMAP = NOBLOCKMAP,
	MAPBLOCKSIZE = MAPBLOCKSIZE,
	MAPBLOCKSHIFT = MAPBLOCKSHIFT,
	MAPBTOFRAC = MAPBTOFRAC,
	SlopeHorizontal = SlopeHorizontal,
	SlopeVertical = SlopeVertical,
	SlopePositive = SlopePositive,
	SlopeNegative = SlopeNegative,
	ADDLINES = ADDLINES,
	ADDTHINGS = ADDTHINGS,
	EARLYOUT = EARLYOUT,
	GetBMapWidth = GetBMapWidth,
	GetBMapHeight = GetBMapHeight,
	GetBMapOrgX = GetBMapOrgX,
	GetBMapOrgY = GetBMapOrgY,
	PointInSubsector = PointInSubsector,
	GetOpenTop = GetOpenTop,
	GetOpenBottom = GetOpenBottom,
	GetOpenRange = GetOpenRange,
	GetLowFloor = GetLowFloor,
	AddLineInterceptsIterator = AddLineInterceptsIterator,
	AddThingInterceptsIterator = AddThingInterceptsIterator,
	GetIntercepts = GetIntercepts,
	GetInterceptCount = GetInterceptCount,
	GetTrace = GetTrace,
}

MapUtil.ApproximateDistance = ApproximateDistance
MapUtil.PointOnLineSide = PointOnLineSide
MapUtil.BoxOnLineSide = BoxOnLineSide
MapUtil.PointOnDivlineSide = PointOnDivlineSide
MapUtil.MakeDivline = MakeDivline
MapUtil.InterceptVector = InterceptVector
MapUtil.LineOpening = LineOpening
MapUtil.UnsetThingPosition = UnsetThingPosition
MapUtil.SetThingPosition = SetThingPosition
MapUtil.BlockLinesIterator = BlockLinesIterator
MapUtil.BlockThingsIterator = BlockThingsIterator
MapUtil.TraverseIntercepts = TraverseIntercepts
MapUtil.PathTraverse = PathTraverse

return MapUtil
