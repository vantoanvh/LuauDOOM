--!native
--!optimize 2

-- Port of r_bsp.c, r_bsp.h
-- BSP traversal, handling of LineSegs for rendering.
-- `StoreWallRange` from `Segs.luau` and sprite submission from
-- `Things.luau` route through the shared renderer runtime so BSP stays acyclic.

const BoundingBox = require("../Miscellaneous/BoundingBox")
const Geometry = require("./Geometry")
const Plane = require("./Plane")
const Runtime = require("./Runtime")
const Sky = require("./Sky")
const State = require("./State")

const MAXDRAWSEGS = 2048
const MAXSEGS = 128
const SUBSECTOR = 0x8000
const ANGLE_MAX = 0x100000000
const PointToAngle2 = Geometry.PointToAngle2
const PointOnSide = Geometry.PointOnSide
const PlaneFindPlane = Plane.FindPlane
const SkyGetSkyFlatNum = Sky.GetSkyFlatNum

type NumberMap = { [number]: number }
type Vertex = {
	x: number,
	y: number,
}
type Sector = {
	[string]: unknown,
	floorheight: number,
	ceilingheight: number,
	floorpic: number,
	ceilingpic: number,
	lightlevel: number,
	renderFloorHeight: number?,
	renderCeilingHeight: number?,
}
type SideDef = {
	midtexture: number,
}
type LineDef = {
	frontsector: Sector,
	backsector: Sector | false,
}
type Seg = {
	v1: Vertex,
	v2: Vertex,
	sidedef: SideDef,
	linedef: LineDef,
	frontsector: Sector,
	backsector: Sector | false,
}
type Node = {
	bbox: { [number]: NumberMap },
	children: NumberMap,
}

local curline = false
local frontsector = false
local backsector = false

const drawsegX1 = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegX2 = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegScale1 = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegScale2 = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegScaleStep = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegSilhouette = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegBSilHeight = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegTSilHeight = buffer.create((MAXDRAWSEGS + 1) * 4)
const drawsegCurline = table.create(MAXDRAWSEGS + 1)
const drawsegSprTopClip = table.create(MAXDRAWSEGS + 1)
const drawsegSprBottomClip = table.create(MAXDRAWSEGS + 1)
const drawsegMaskedTextureCol = table.create(MAXDRAWSEGS + 1)

const solidsegFirst = buffer.create((MAXSEGS + 1) * 4)
const solidsegLast = buffer.create((MAXSEGS + 1) * 4)

const drawsegStore = {
	x1 = drawsegX1,
	x2 = drawsegX2,
	scale1 = drawsegScale1,
	scale2 = drawsegScale2,
	scalestep = drawsegScaleStep,
	silhouette = drawsegSilhouette,
	bsilheight = drawsegBSilHeight,
	tsilheight = drawsegTSilHeight,
	curline = drawsegCurline,
	sprtopclip = drawsegSprTopClip,
	sprbottomclip = drawsegSprBottomClip,
	maskedtexturecol = drawsegMaskedTextureCol,
}

const checkcoord = {
	[0] = 3, 0, 2, 1,
	3, 0, 2, 0,
	3, 1, 2, 0,
	0, 0, 0, 0,
	2, 0, 2, 1,
	0, 0, 0, 0,
	3, 1, 3, 0,
	0, 0, 0, 0,
	2, 0, 3, 1,
	2, 1, 3, 1,
	2, 1, 3, 0,
}
local ds_p = 0
local newend = 0

const function Reset()
	curline = false
	frontsector = false
	backsector = false

	buffer.fill(drawsegX1, 0, 0)
	buffer.fill(drawsegX2, 0, 0)
	buffer.fill(drawsegScale1, 0, 0)
	buffer.fill(drawsegScale2, 0, 0)
	buffer.fill(drawsegScaleStep, 0, 0)
	buffer.fill(drawsegSilhouette, 0, 0)
	buffer.fill(drawsegBSilHeight, 0, 0)
	buffer.fill(drawsegTSilHeight, 0, 0)
	buffer.fill(solidsegFirst, 0, 0)
	buffer.fill(solidsegLast, 0, 0)
	table.clear(drawsegCurline)
	table.clear(drawsegSprTopClip)
	table.clear(drawsegSprBottomClip)
	table.clear(drawsegMaskedTextureCol)

	ds_p = 0
	newend = 0
	State.maxdrawsegs = MAXDRAWSEGS
	State.drawsegindex = 0
end

const function ClearDrawSegs()
	ds_p = 1
	State.drawsegindex = 1
end

const function ClearClipSegs()
	buffer.writei32(solidsegFirst, 4, -0x7FFFFFFF)
	buffer.writei32(solidsegLast, 4, -1)
	buffer.writei32(solidsegFirst, 8, State.viewwidth)
	buffer.writei32(solidsegLast, 8, 0x7FFFFFFF)
	newend = 3
end

const function ClipSolidWallSegment(first: number, last: number)
	const storeWallRange = Runtime.storeWallRange

	local start = 1
	local startOffset = 4
	const touchStart = first - 1
	local startLast = 0
	const newendOffset = newend * 4

	for offset = 4, newendOffset, 4 do
		startLast = buffer.readi32(solidsegLast, offset)

		if startLast >= touchStart then
			start = offset // 4
			startOffset = offset
			break
		end
	end

	const startFirst = buffer.readi32(solidsegFirst, startOffset)

	if first < startFirst then
		if last < startFirst - 1 then
			storeWallRange(first, last)

			for writeOffset = newendOffset, (start + 1) * 4, -4 do
				const readOffset = writeOffset - 4
				buffer.writei32(solidsegFirst, writeOffset, buffer.readi32(solidsegFirst, readOffset))
				buffer.writei32(solidsegLast, writeOffset, buffer.readi32(solidsegLast, readOffset))
			end

			buffer.writei32(solidsegFirst, startOffset, first)
			buffer.writei32(solidsegLast, startOffset, last)
			newend += 1
			return
		end

		storeWallRange(first, startFirst - 1)
		buffer.writei32(solidsegFirst, startOffset, first)
	end

	if last <= startLast then
		return
	end

	local mergedLast = last
	local nextIndex = start
	local nextLast = startLast

	for nextFirstOffset = startOffset + 4, newendOffset, 4 do
		const nextFirst = buffer.readi32(solidsegFirst, nextFirstOffset)

		if last < nextFirst - 1 then
			break
		end

		storeWallRange(nextLast + 1, nextFirst - 1)
		nextIndex += 1
		nextLast = buffer.readi32(solidsegLast, nextFirstOffset)

		if last <= nextLast then
			mergedLast = nextLast
			buffer.writei32(solidsegLast, startOffset, mergedLast)

			if nextIndex == start then
				return
			end

			local writeOffset = (start + 1) * 4

			for readOffset = (nextIndex + 1) * 4, newendOffset, 4 do
				buffer.writei32(solidsegFirst, writeOffset, buffer.readi32(solidsegFirst, readOffset))
				buffer.writei32(solidsegLast, writeOffset, buffer.readi32(solidsegLast, readOffset))

				writeOffset += 4
			end

			newend = writeOffset // 4
			return
		end
	end

	storeWallRange(nextLast + 1, last)

	buffer.writei32(solidsegLast, startOffset, mergedLast)

	if nextIndex == start then
		return
	end

	local writeOffset = (start + 1) * 4

	for readOffset = (nextIndex + 1) * 4, newendOffset, 4 do
		buffer.writei32(solidsegFirst, writeOffset, buffer.readi32(solidsegFirst, readOffset))
		buffer.writei32(solidsegLast, writeOffset, buffer.readi32(solidsegLast, readOffset))

		writeOffset += 4
	end

	newend = writeOffset // 4
end

const function ClipPassWallSegment(first: number, last: number)
	const storeWallRange = Runtime.storeWallRange

	local startOffset = 4
	const touchStart = first - 1
	local startLast = 0
	const newendOffset = newend * 4

	for offset = 4, newendOffset, 4 do
		startLast = buffer.readi32(solidsegLast, offset)

		if startLast >= touchStart then
			startOffset = offset
			break
		end
	end

	const startFirst = buffer.readi32(solidsegFirst, startOffset)

	if first < startFirst then
		if last < startFirst - 1 then
			storeWallRange(first, last)
			return
		end

		storeWallRange(first, startFirst - 1)
	end

	if last <= startLast then
		return
	end

	for nextOffset = startOffset + 4, newendOffset, 4 do
		const nextFirst = buffer.readi32(solidsegFirst, nextOffset)

		if last < nextFirst - 1 then
			break
		end

		storeWallRange(startLast + 1, nextFirst - 1)
		startLast = buffer.readi32(solidsegLast, nextOffset)

		if last <= startLast then
			return
		end
	end

	storeWallRange(startLast + 1, last)
end

const function AddLine(line: Seg)
	curline = line
	State.linecount += 1

	const viewx = State.viewx
	const viewy = State.viewy
	local angle1 = PointToAngle2(viewx, viewy, line.v1.x, line.v1.y)
	local angle2 = PointToAngle2(viewx, viewy, line.v2.x, line.v2.y)
	local span = angle1 - angle2

	if span < 0 then
		span += ANGLE_MAX
	end

	if span >= 0x80000000 then
		return
	end

	State.rw_angle1 = angle1
	const viewangle = State.viewangle
	angle1 -= viewangle
	if angle1 < 0 then
		angle1 += ANGLE_MAX
	elseif angle1 >= ANGLE_MAX then
		angle1 -= ANGLE_MAX
	end

	angle2 -= viewangle
	if angle2 < 0 then
		angle2 += ANGLE_MAX
	elseif angle2 >= ANGLE_MAX then
		angle2 -= ANGLE_MAX
	end

	const clipangle = State.clipangle
	const clipangle2 = clipangle + clipangle
	local tspan = angle1 + clipangle
	if tspan < 0 then
		tspan += ANGLE_MAX
	elseif tspan >= ANGLE_MAX then
		tspan -= ANGLE_MAX
	end

	if tspan > clipangle2 then
		tspan -= clipangle2

		if tspan >= span then
			return
		end

		angle1 = clipangle
	end

	tspan = clipangle - angle2
	if tspan < 0 then
		tspan += ANGLE_MAX
	elseif tspan >= ANGLE_MAX then
		tspan -= ANGLE_MAX
	end

	if tspan > clipangle2 then
		tspan -= clipangle2

		if tspan >= span then
			return
		end

		angle2 = ANGLE_MAX - clipangle
	end

	angle1 += 0x40000000
	if angle1 >= ANGLE_MAX then
		angle1 -= ANGLE_MAX
	end

	angle2 += 0x40000000
	if angle2 >= ANGLE_MAX then
		angle2 -= ANGLE_MAX
	end

	const viewangletox = State.viewangletox
	const x1 = buffer.readi32(viewangletox, bit32.rshift(angle1, 19) * 4)
	const x2 = buffer.readi32(viewangletox, bit32.rshift(angle2, 19) * 4)

	if x1 == x2 then
		return
	end

	const activeBackSector = line.backsector
	backsector = activeBackSector

	const wallLast = x2 - 1

	if not activeBackSector then
		ClipSolidWallSegment(x1, wallLast)
		return
	end

	const activeFrontSector = frontsector
	const backCeilingHeight = activeBackSector.renderCeilingHeight or activeBackSector.ceilingheight
	const backFloorHeight = activeBackSector.renderFloorHeight or activeBackSector.floorheight
	const frontCeilingHeight = activeFrontSector.renderCeilingHeight or activeFrontSector.ceilingheight
	const frontFloorHeight = activeFrontSector.renderFloorHeight or activeFrontSector.floorheight

	if backCeilingHeight <= frontFloorHeight
		or backFloorHeight >= frontCeilingHeight then
		ClipSolidWallSegment(x1, wallLast)
		return
	end

	if backCeilingHeight ~= frontCeilingHeight
		or backFloorHeight ~= frontFloorHeight then
		ClipPassWallSegment(x1, wallLast)
		return
	end

	if activeBackSector.ceilingpic == activeFrontSector.ceilingpic
		and activeBackSector.floorpic == activeFrontSector.floorpic
		and activeBackSector.lightlevel == activeFrontSector.lightlevel
		and (line.sidedef.midtexture or 0) == 0 then
		return
	end

	ClipPassWallSegment(x1, wallLast)
end

const function CheckBBox(
	bspcoord: NumberMap,
	viewx: number,
	viewy: number,
	viewangle: number,
	clipangle: number,
	viewangletox: buffer
)
	local boxx
	local boxy

	if viewx <= bspcoord[BoundingBox.BOXLEFT] then
		boxx = 0
	elseif viewx < bspcoord[BoundingBox.BOXRIGHT] then
		boxx = 1
	else
		boxx = 2
	end

	if viewy >= bspcoord[BoundingBox.BOXTOP] then
		boxy = 0
	elseif viewy > bspcoord[BoundingBox.BOXBOTTOM] then
		boxy = 1
	else
		boxy = 2
	end

	const boxpos = boxy * 4 + boxx

	if boxpos == 5 then
		return true
	end

	const checkcoordOffset = boxpos * 4
	const x1 = bspcoord[checkcoord[checkcoordOffset]]
	const y1 = bspcoord[checkcoord[checkcoordOffset + 1]]
	const x2 = bspcoord[checkcoord[checkcoordOffset + 2]]
	const y2 = bspcoord[checkcoord[checkcoordOffset + 3]]

	local angle1 = PointToAngle2(viewx, viewy, x1, y1) - viewangle
	if angle1 < 0 then
		angle1 += ANGLE_MAX
	elseif angle1 >= ANGLE_MAX then
		angle1 -= ANGLE_MAX
	end

	local angle2 = PointToAngle2(viewx, viewy, x2, y2) - viewangle
	if angle2 < 0 then
		angle2 += ANGLE_MAX
	elseif angle2 >= ANGLE_MAX then
		angle2 -= ANGLE_MAX
	end
	local span = angle1 - angle2

	if span < 0 then
		span += ANGLE_MAX
	end

	if span >= 0x80000000 then
		return true
	end

	const clipangle2 = clipangle + clipangle
	local tspan = angle1 + clipangle
	if tspan < 0 then
		tspan += ANGLE_MAX
	elseif tspan >= ANGLE_MAX then
		tspan -= ANGLE_MAX
	end

	if tspan > clipangle2 then
		tspan -= clipangle2

		if tspan >= span then
			return false
		end

		angle1 = clipangle
	end

	tspan = clipangle - angle2
	if tspan < 0 then
		tspan += ANGLE_MAX
	elseif tspan >= ANGLE_MAX then
		tspan -= ANGLE_MAX
	end

	if tspan > clipangle2 then
		tspan -= clipangle2

		if tspan >= span then
			return false
		end

		angle2 = ANGLE_MAX - clipangle
	end

	angle1 += 0x40000000
	if angle1 >= ANGLE_MAX then
		angle1 -= ANGLE_MAX
	end

	angle2 += 0x40000000
	if angle2 >= ANGLE_MAX then
		angle2 -= ANGLE_MAX
	end

	const sx1 = buffer.readi32(viewangletox, bit32.rshift(angle1, 19) * 4)
	local sx2 = buffer.readi32(viewangletox, bit32.rshift(angle2, 19) * 4)

	if sx1 == sx2 then
		return false
	end

	sx2 -= 1

	local startOffset = 4
	const newendOffset = newend * 4

	for offset = 4, newendOffset, 4 do
		if buffer.readi32(solidsegLast, offset) >= sx2 then
			startOffset = offset
			break
		end
	end

	return sx1 < buffer.readi32(solidsegFirst, startOffset)
		or sx2 > buffer.readi32(solidsegLast, startOffset)
end

const function Subsector(num: number)
	State.sscount += 1

	const sub = State.subsectors[num]
	const activeFrontSector = sub.sector
	frontsector = activeFrontSector

	const frontFloorHeight = activeFrontSector.renderFloorHeight or activeFrontSector.floorheight
	const frontCeilingHeight = activeFrontSector.renderCeilingHeight or activeFrontSector.ceilingheight
	const viewz = State.viewz

	if frontFloorHeight < viewz then
		State.floorplane = PlaneFindPlane(frontFloorHeight, activeFrontSector.floorpic, activeFrontSector.lightlevel)
	else
		State.floorplane = nil
	end

	if frontCeilingHeight > viewz or activeFrontSector.ceilingpic == SkyGetSkyFlatNum() then
		State.ceilingplane = PlaneFindPlane(frontCeilingHeight, activeFrontSector.ceilingpic, activeFrontSector.lightlevel)
	else
		State.ceilingplane = nil
	end

	const addSprites = Runtime.addSprites

	if addSprites ~= nil then
		addSprites(activeFrontSector)
	end

	const firstline = sub.firstline
	const lastline = firstline + sub.numlines - 1
	const segs = State.segs

	for lineIndex = firstline, lastline do
		AddLine(segs[lineIndex])
	end
end

const function TraverseBSPNode(
	bspnum: number,
	viewx: number,
	viewy: number,
	viewangle: number,
	clipangle: number,
	viewangletox: buffer,
	nodes: { [number]: Node }
)
	if bspnum == -1 or bspnum >= SUBSECTOR then
		if bspnum == -1 or bspnum == 0xFFFF then
			Subsector(0)
		else
			Subsector(bspnum - SUBSECTOR)
		end
		return
	end

	const bsp = nodes[bspnum]
	local side = PointOnSide(viewx, viewy, bsp)
	const children = bsp.children
	const bbox = bsp.bbox

	TraverseBSPNode(children[side], viewx, viewy, viewangle, clipangle, viewangletox, nodes)

	side = 1 - side

	if CheckBBox(bbox[side], viewx, viewy, viewangle, clipangle, viewangletox) then
		TraverseBSPNode(children[side], viewx, viewy, viewangle, clipangle, viewangletox, nodes)
	end
end

const function RenderBSPNode(bspnum: number)
	TraverseBSPNode(bspnum, State.viewx, State.viewy, State.viewangle, State.clipangle, State.viewangletox, State.nodes)
end

const function SetCurrentState(newCurline: Seg | false | nil, newFrontSector: Sector | false | nil, newBackSector: Sector | false | nil)
	curline = newCurline or false
	frontsector = newFrontSector or false
	backsector = newBackSector or false
end

const function GetDrawSegStore()
	return drawsegStore
end

const function GetDrawSegIndex(): number
	return ds_p
end

const function SetDrawSegIndex(value: number)
	ds_p = value
	State.drawsegindex = value
end

const function GetCurrentLine()
	return curline
end

const function GetFrontSector()
	return frontsector
end

const function GetBackSector()
	return backsector
end

Reset()

return {
	MAXDRAWSEGS = MAXDRAWSEGS,

	Reset = Reset,
	SetCurrentState = SetCurrentState,

	ClearClipSegs = ClearClipSegs,
	ClearDrawSegs = ClearDrawSegs,
	RenderBSPNode = RenderBSPNode,

	GetDrawSegStore = GetDrawSegStore,
	GetDrawSegIndex = GetDrawSegIndex,
	SetDrawSegIndex = SetDrawSegIndex,
	GetCurrentLine = GetCurrentLine,
	GetFrontSector = GetFrontSector,
	GetBackSector = GetBackSector,
}
