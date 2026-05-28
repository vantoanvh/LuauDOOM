--!native
--!optimize 2

-- Port of p_sight.c
-- LineOfSight/Visibility checks, uses REJECT lookup table.

const Fixed = require("../Miscellaneous/Fixed")
const MapUtil = require("./MapUtil")
const State = require("../Renderer/State")
const WorldState = require("./WorldState")

const TWOSIDED = 4
const SUBSECTOR = 0x8000

type NumberMap = { [number]: number }
type Divline = {
	x: number,
	y: number,
	dx: number,
	dy: number,
}
type Sector = {
	index: number?,
	floorheight: number,
	ceilingheight: number,
}
type SightThing = {
	x: number,
	y: number,
	z: number,
	height: number,
	subsector: {
		sector: Sector,
	},
}

local sightzstart = 0
local topslope = 0
local bottomslope = 0
const strace: Divline = {
	x = 0,
	y = 0,
	dx = 0,
	dy = 0,
}
local t2x = 0
local t2y = 0
const sightcounts: NumberMap = {
	[0] = 0,
	[1] = 0,
}

const ToSigned32 = Fixed.ToSigned32

const function SignedRightShift(value: number, shift: number): number
	return ToSigned32(bit32.arshift(value, shift))
end

const function IsSubsectorRef(value: number): boolean
	return bit32.btest(value, SUBSECTOR)
end

const function ResolveSubsectorRef(value: number): number
	if value == -1 or value == 0xFFFF then
		return 0
	end

	return bit32.band(value, SUBSECTOR - 1)
end

const function GetRejectMatrix(): buffer
	return WorldState.rejectmatrix
end

const function CheckSubsectorIndex(index: number, context: string)
end

const function CheckNodeIndex(index: number, context: string)
end

const function GetSectorIndex(sector: unknown, context: string): number
	const sectorValue = sector :: Sector
	const index = sectorValue.index

	if index ~= nil then
		return index
	end

	for i = 0, State.numsectors - 1 do
		if State.sectors[i] == sectorValue then
			return i
		end
	end

	error(`{context}: sector is not present in State.sectors`)
end

-- DivlineSide
-- Returns side 0 (front), 1 (back), or 2 (on).
const function DivlineSide(x: number, y: number, node: unknown): number
	local dx
	local dy
	local left
	local right
	const divline = node :: Divline
	const nodeDx = ToSigned32(divline.dx)
	const nodeDy = ToSigned32(divline.dy)

	if nodeDx == 0 then
		if x == divline.x then
			return 2
		end

		if x <= divline.x then
			return if nodeDy > 0 then 1 else 0
		end

		return if nodeDy < 0 then 1 else 0
	end

	if nodeDy == 0 then
		if x == divline.y then
			return 2
		end

		if y <= divline.y then
			return if nodeDx < 0 then 1 else 0
		end

		return if nodeDx > 0 then 1 else 0
	end

	dx = ToSigned32(x - divline.x)
	dy = ToSigned32(y - divline.y)

	left = ToSigned32(SignedRightShift(nodeDy, Fixed.FRACBITS) * SignedRightShift(dx, Fixed.FRACBITS))
	right = ToSigned32(SignedRightShift(dy, Fixed.FRACBITS) * SignedRightShift(nodeDx, Fixed.FRACBITS))

	if right < left then
		return 0
	end

	if left == right then
		return 2
	end

	return 1
end

-- InterceptVector2
-- Returns the fractional intercept point
-- along the first divline.
const function InterceptVector2(v2: unknown, v1: unknown): number
	return MapUtil.InterceptVector(v2 :: Divline, v1 :: Divline)
end

-- CrossSubsector
-- Returns true if strace crosses the given subsector successfully.
const function CrossSubsector(num: number): boolean
	CheckSubsectorIndex(num, "CrossSubsector")

	const sub = State.subsectors[num]

	const count = sub.numlines
	const segIndex = sub.firstline

	for offset = 0, count - 1 do
		const seg = State.segs[segIndex + offset]


		const line = seg.linedef

		if line.validcount == State.validcount then
			continue
		end

		line.validcount = State.validcount

		const v1 = line.v1
		const v2 = line.v2

		local s1 = DivlineSide(v1.x, v1.y, strace)
		local s2 = DivlineSide(v2.x, v2.y, strace)

		if s1 == s2 then
			continue
		end

		const divl = {
			x = ToSigned32(v1.x),
			y = ToSigned32(v1.y),
			dx = ToSigned32(v2.x - v1.x),
			dy = ToSigned32(v2.y - v1.y),
		}

		s1 = DivlineSide(strace.x, strace.y, divl)
		s2 = DivlineSide(t2x, t2y, divl)

		if s1 == s2 then
			continue
		end

		if bit32.band(line.flags, TWOSIDED) == 0 then
			return false
		end

		const front = seg.frontsector
		const back = seg.backsector

		if front.floorheight == back.floorheight and front.ceilingheight == back.ceilingheight then
			continue
		end

		const opentop = if front.ceilingheight < back.ceilingheight then front.ceilingheight else back.ceilingheight
		const openbottom = if front.floorheight > back.floorheight then front.floorheight else back.floorheight

		if openbottom >= opentop then
			return false
		end

		const frac = InterceptVector2(strace, divl)
		local slope

		if front.floorheight ~= back.floorheight then
			slope = Fixed.FixedDiv(openbottom - sightzstart, frac)

			if slope > bottomslope then
				bottomslope = slope
			end
		end

		if front.ceilingheight ~= back.ceilingheight then
			slope = Fixed.FixedDiv(opentop - sightzstart, frac)

			if slope < topslope then
				topslope = slope
			end
		end

		if topslope <= bottomslope then
			return false
		end
	end

	return true
end

-- CrossBSPNode
-- Returns true if strace crosses the given node successfully.
const function CrossBSPNode(bspnum: number): boolean
	if IsSubsectorRef(bspnum) then
		return CrossSubsector(ResolveSubsectorRef(bspnum))
	end

	CheckNodeIndex(bspnum, "CrossBSPNode")

	const bsp = State.nodes[bspnum]

	local side = DivlineSide(strace.x, strace.y, bsp)

	if side == 2 then
		side = 0
	end

	if not CrossBSPNode(bsp.children[side]) then
		return false
	end

	if side == DivlineSide(t2x, t2y, bsp) then
		return true
	end

	return CrossBSPNode(bsp.children[bit32.bxor(side, 1)])
end

-- CheckSight
-- Returns true if a straight line between t1 and t2 is unobstructed.
-- Uses REJECT.
const function CheckSight(t1: unknown, t2: unknown): boolean
	const source = t1 :: SightThing
	const target = t2 :: SightThing
	const s1 = GetSectorIndex(source.subsector.sector, "CheckSight t1 sector")
	const s2 = GetSectorIndex(target.subsector.sector, "CheckSight t2 sector")
	const rejectmatrix = GetRejectMatrix()
	const pnum = s1 * State.numsectors + s2
	const bytenum = bit32.rshift(pnum, 3)
	const bitnum = bit32.lshift(1, bit32.band(pnum, 7))

	if bit32.btest(buffer.readu8(rejectmatrix, bytenum), bitnum) then
		sightcounts[0] += 1
		return false
	end

	sightcounts[1] += 1
	State.validcount += 1

	sightzstart = ToSigned32(source.z + source.height - source.height // 4)
	topslope = ToSigned32(target.z + target.height - sightzstart)
	bottomslope = ToSigned32(target.z - sightzstart)

	strace.x = ToSigned32(source.x)
	strace.y = ToSigned32(source.y)
	t2x = ToSigned32(target.x)
	t2y = ToSigned32(target.y)
	strace.dx = ToSigned32(target.x - source.x)
	strace.dy = ToSigned32(target.y - source.y)

	return CrossBSPNode(State.numnodes - 1)
end

const function Reset()
	sightzstart = 0
	topslope = 0
	bottomslope = 0
	strace.x = 0
	strace.y = 0
	strace.dx = 0
	strace.dy = 0
	t2x = 0
	t2y = 0
	sightcounts[0] = 0
	sightcounts[1] = 0
end

const function GetSightZStart(): number
	return sightzstart
end

const function GetTopSlope(): number
	return topslope
end

const function GetBottomSlope(): number
	return bottomslope
end

const function GetTrace(): Divline
	return strace
end

const function GetTargetX(): number
	return t2x
end

const function GetTargetY(): number
	return t2y
end

const function GetSightCounts(): NumberMap
	return sightcounts
end

Reset()

return {
	TWOSIDED = TWOSIDED,
	SUBSECTOR = SUBSECTOR,

	Reset = Reset,
	GetSightZStart = GetSightZStart,
	GetTopSlope = GetTopSlope,
	GetBottomSlope = GetBottomSlope,
	GetTrace = GetTrace,
	GetTargetX = GetTargetX,
	GetTargetY = GetTargetY,
	GetSightCounts = GetSightCounts,
	DivlineSide = DivlineSide,
	InterceptVector2 = InterceptVector2,
	CrossSubsector = CrossSubsector,
	CrossBSPNode = CrossBSPNode,
	CheckSight = CheckSight,
}
