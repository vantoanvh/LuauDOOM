--!native
--!optimize 2

-- Port of r_main.c, r_main.h
-- Rendering main loop and setup functions,
-- utility functions (BSP, geometry, trigonometry).
-- See tables.c, too.
-- Geometry helpers shared by renderer and play code.

const BoundingBox = require("../Miscellaneous/BoundingBox")
const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const State = require("./State")

const tantoangle = Tables.tantoangle
const finesine = Tables.finesine
const SlopeDiv = Tables.SlopeDiv
const FixedMul = Fixed.FixedMul
const FixedDiv = Fixed.FixedDiv
const SIGNBIT = 0x80000000

type Vertex = {
	x: number,
	y: number,
}

type Node = {
	x: number,
	y: number,
	dx: number,
	dy: number,
}

type SegLine = {
	v1: Vertex,
	v2: Vertex,
}

const function ToSigned32(value: number): number
	value = bit32.band(value, 0xFFFFFFFF)
	return if value >= SIGNBIT then value - 0x100000000 else value
end

const function SetViewPoint(x: number, y: number)
	State.viewx = x
	State.viewy = y
end

const function GetViewPoint(): (number, number)
	return State.viewx, State.viewy
end

-- R_AddPointToBox
-- Expand a given bbox
-- so that it encloses a given point.
const function AddPointToBox(x: number, y: number, box: buffer)
	BoundingBox.AddToBox(box, x, y)
end

-- R_PointOnSide
-- Traverse BSP (sub) tree,
--  check point against partition plane.
-- Returns side 0 (front) or 1 (back).
const function PointOnSide(x: number, y: number, node: Node): number
	const nodeX = node.x
	const nodeY = node.y
	local nodeDx = node.dx
	local nodeDy = node.dy


	nodeDx = ToSigned32(nodeDx)
	nodeDy = ToSigned32(nodeDy)

	if nodeDx == 0 then
		if x <= nodeX then
			return if nodeDy > 0 then 1 else 0
		end

		return if nodeDy < 0 then 1 else 0
	end

	if nodeDy == 0 then
		if y <= nodeY then
			return if nodeDx < 0 then 1 else 0
		end

		return if nodeDx > 0 then 1 else 0
	end

	const dx = ToSigned32(x - nodeX)
	const dy = ToSigned32(y - nodeY)

	-- Try to quickly decide by looking at sign bits.
	if bit32.btest(bit32.bxor(nodeDy, nodeDx, dx, dy), 0x80000000) then
		if bit32.btest(bit32.bxor(nodeDy, dx), 0x80000000) then
			-- (left is negative)
			return 1
		end

		return 0
	end

	const left = FixedMul(ToSigned32(bit32.arshift(nodeDy, 16)), dx)
	const right = FixedMul(dy, ToSigned32(bit32.arshift(nodeDx, 16)))

	if right < left then
		-- front side
		return 0
	end

	-- back side
	return 1
end

-- R_PointOnSegSide
const function PointOnSegSide(x: number, y: number, line: SegLine): number
	const v1 = line.v1
	const v2 = line.v2


	const lx = v1.x
	const ly = v1.y
	const ldx = ToSigned32(v2.x - lx)
	const ldy = ToSigned32(v2.y - ly)

	if ldx == 0 then
		if x <= lx then
			return if ldy > 0 then 1 else 0
		end

		return if ldy < 0 then 1 else 0
	end

	if ldy == 0 then
		if y <= ly then
			return if ldx < 0 then 1 else 0
		end

		return if ldx > 0 then 1 else 0
	end

	const dx = ToSigned32(x - lx)
	const dy = ToSigned32(y - ly)

	-- Try to quickly decide by looking at sign bits.
	if bit32.btest(bit32.bxor(ldy, ldx, dx, dy), 0x80000000) then
		if bit32.btest(bit32.bxor(ldy, dx), 0x80000000) then
			-- (left is negative)
			return 1
		end

		return 0
	end

	const left = FixedMul(ToSigned32(bit32.arshift(ldy, 16)), dx)
	const right = FixedMul(dy, ToSigned32(bit32.arshift(ldx, 16)))

	if right < left then
		-- front side
		return 0
	end

	-- back side
	return 1
end

const function PointToAngleFromView(originX: number, originY: number, x: number, y: number): number
	x = ToSigned32(x - originX)
	y = ToSigned32(y - originY)

	if x == 0 and y == 0 then
		return 0
	end

	if x >= 0 then
		-- x >=0
		if y >= 0 then
			-- y>= 0
			if x > y then
				-- octant 0
				return tantoangle[SlopeDiv(y, x)]
			else
				-- octant 1
				return 0x40000000 - 1 - tantoangle[SlopeDiv(x, y)]
			end
		else
			-- y<0
			y = -y

			if x > y then
				-- octant 8
				return bit32.band(-tantoangle[SlopeDiv(y, x)], 0xFFFFFFFF)
			else
				-- octant 7
				return 0xC0000000 + tantoangle[SlopeDiv(x, y)]
			end
		end
	else
		-- x<0
		x = -x

		if y >= 0 then
			-- y>= 0
			if x > y then
				-- octant 3
				return 0x80000000 - 1 - tantoangle[SlopeDiv(y, x)]
			else
				-- octant 2
				return 0x40000000 + tantoangle[SlopeDiv(x, y)]
			end
		else
			-- y<0
			y = -y

			if x > y then
				-- octant 4
				return 0x80000000 + tantoangle[SlopeDiv(y, x)]
			else
				-- octant 5
				return 0xC0000000 - 1 - tantoangle[SlopeDiv(x, y)]
			end
		end
	end
end

-- R_PointToAngle
-- To get a global angle from cartesian coordinates,
--  the coordinates are flipped until they are in
--  the first octant of the coordinate system, then
--  the y (<=x) is scaled and divided by x to get a
--  tangent (slope) value which is looked up in the
--  tantoangle[] table.
const function PointToAngle(x: number, y: number): number
	return PointToAngleFromView(State.viewx, State.viewy, x, y)
end

const function PointToAngle2(x1: number, y1: number, x2: number, y2: number): number
	return PointToAngleFromView(x1, y1, x2, y2)
end

const function PointToDist(x: number, y: number): number
	local dx = ToSigned32(x - State.viewx)
	local dy = ToSigned32(y - State.viewy)

	if dx < 0 then
		dx = -dx
	end

	if dy < 0 then
		dy = -dy
	end

	if dx == 0 and dy == 0 then
		return 0
	end

	if dy > dx then
		const temp = dx
		dx = dy
		dy = temp
	end

	const angle = bit32.rshift(tantoangle[bit32.rshift(FixedDiv(dy, dx), 5)] + 0x40000000, 19)

	-- use as cosine
	return FixedDiv(dx, finesine[angle])
end

return {
	SetViewPoint = SetViewPoint,
	GetViewPoint = GetViewPoint,

	AddPointToBox = AddPointToBox,
	PointOnSide = PointOnSide,
	PointOnSegSide = PointOnSegSide,
	PointToAngle = PointToAngle,
	PointToAngle2 = PointToAngle2,
	PointToDist = PointToDist,
}
