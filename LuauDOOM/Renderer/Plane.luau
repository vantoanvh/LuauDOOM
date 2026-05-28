--!native
--!optimize 2

-- Port of r_plane.c, r_plane.h
-- Refresh, visplane stuff (floor, ceilings).
-- `Bsp.luau` / `Segs.luau` populate visplanes before `DrawPlanes`.

const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const Video = require("../System/Video")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")
const Data = require("./Data")
const Draw = require("./Draw")
const Sky = require("./Sky")
const State = require("./State")

const LIGHTLEVELS = 16
const LIGHTSEGSHIFT = 4
const MAXLIGHTZ = 128
const LIGHTZSHIFT = 20
const PLANE = 0x7FFFFFFF
const EMPTY_BUFFER = buffer.create(0)
const UINT32_MASK = 0xFFFFFFFF
const SIGNBIT = 0x80000000
const ANGLETOSKYSHIFT = Sky.ANGLETOSKYSHIFT

const finecosine = Tables.finecosine
const finesine = Tables.finesine

const FixedMul = Fixed.FixedMul
const DrawSetColumnSourceSetup = Draw.SetColumnSourceSetup
const DrawSetColumnBoundsPositionSource = Draw.SetColumnBoundsPositionSource
const DrawSetSpanDraw = Draw.SetSpanDraw
const DrawSetSpanSource = Draw.SetSpanSource
const SkyGetSkyFlatNum = Sky.GetSkyFlatNum
const SkyGetSkyTexture = Sky.GetSkyTexture
const SkyGetSkyTextureMid = Sky.GetSkyTextureMid
const DataGetLinearColumnSource = Data.GetLinearColumnSource
const CacheLumpNum = Wad.CacheLumpNum
const STATIC = Zone.STATIC

const function ToSigned32(value: number): number
	value = bit32.band(value, UINT32_MASK)

	return if value >= SIGNBIT then value - 0x100000000 else value
end

type PlaneLimits = { [number]: number }
type Visplane = {
	height: number,
	picnum: number,
	lightlevel: number,
	minx: number,
	maxx: number,
	top: PlaneLimits,
	bottom: PlaneLimits,
}

-- Clip values are the solid pixel bounding the range.
--  floorclip starts out SCREENHEIGHT
--  ceilingclip starts out -1
local floorclip = EMPTY_BUFFER
local ceilingclip = EMPTY_BUFFER
local floorclipclear = EMPTY_BUFFER
local floorclipclearwidth = 0
local floorclipclearheight = 0

-- spanstart holds the start of a plane span
-- initialized to 0 at start
local spanstart = EMPTY_BUFFER
local renderWidthCached = 0

-- texture mapping
local planezlight: { [number]: number } = {}
local planeheight = 0

local basexscale = 0
local baseyscale = 0

local cachedheight = EMPTY_BUFFER
local cacheddistance = EMPTY_BUFFER
local cachedxstep = EMPTY_BUFFER
local cachedystep = EMPTY_BUFFER

const visplanes: { Visplane } = {}
local lastvisplane = 0

const function EnsureFloorClipClear(width: number, height: number)
	if floorclipclearwidth == width and floorclipclearheight == height then
		return
	end

	const byteWidth = width * 4
	floorclipclear = buffer.create(byteWidth)

	for byteOffset = 0, byteWidth - 4, 4 do
		buffer.writei32(floorclipclear, byteOffset, height)
	end

	floorclipclearwidth = width
	floorclipclearheight = height
end

const function InitializeVisplaneSentinels(plane: Visplane)
	const renderWidth = renderWidthCached
	const top = plane.top
	const bottom = plane.bottom

	-- leave pads for [minx-1]/[maxx+1]
	top[-1] = PLANE
	top[renderWidth] = PLANE
	bottom[-1] = 0
	bottom[renderWidth] = 0
end

const function ClearVisplaneColumns(plane: Visplane)
	const renderWidth = renderWidthCached
	const top = plane.top
	const bottom = plane.bottom
	local minx = plane.minx
	local maxx = plane.maxx

	top[-1] = PLANE
	top[renderWidth] = PLANE
	bottom[-1] = 0
	bottom[renderWidth] = 0

	if minx < 0 then
		minx = 0
	end

	if maxx >= renderWidth then
		maxx = renderWidth - 1
	end

	for x = minx, maxx do
		top[x] = PLANE
		bottom[x] = 0
	end
end

const function AcquireVisplane(index: number)
	local plane = visplanes[index]

	if plane == nil then
		const renderWidth = renderWidthCached

		plane = {
			height = 0,
			picnum = 0,
			lightlevel = 0,
			minx = renderWidth,
			maxx = -1,
			top = {},
			bottom = {},
		}

		const top = plane.top
		const bottom = plane.bottom

		for x = 0, renderWidth - 1 do
			top[x] = PLANE
			bottom[x] = 0
		end

		InitializeVisplaneSentinels(plane)

		visplanes[index] = plane
	end

	ClearVisplaneColumns(plane)
	return plane
end

const function Reset()
	const renderWidth = Video.Width
	const renderHeight = Video.Height

	renderWidthCached = renderWidth
	table.clear(visplanes)

	lastvisplane = 0
	planeheight = 0
	basexscale = 0
	baseyscale = 0
	planezlight = {}
	State.floorplane = nil
	State.ceilingplane = nil

	floorclip = buffer.create(renderWidth * 4)
	ceilingclip = buffer.create(renderWidth * 4)
	const renderWidthBytes = renderWidth * 4
	buffer.fill(ceilingclip, 0, 0xFF, renderWidth * 4)
	EnsureFloorClipClear(renderWidth, renderHeight)
	buffer.copy(floorclip, 0, floorclipclear, 0, renderWidthBytes)

	spanstart = buffer.create(renderHeight * 4)

	cachedheight = buffer.create(renderHeight * 4)
	cacheddistance = buffer.create(renderHeight * 4)
	cachedxstep = buffer.create(renderHeight * 4)
	cachedystep = buffer.create(renderHeight * 4)
end

-- MapPlane
-- Uses global vars:
--  planeheight
--  ds_source
--  basexscale
--  baseyscale
--  viewx
--  viewy
-- BASIC PRIMITIVE
const function MapPlane(y: number, x1: number, x2: number)
	if Definitions.RANGECHECK then
	end

	const yslope = State.yslope
	const distscale = State.distscale
	const xtoviewangle = State.xtoviewangle
	const viewangle = State.viewangle
	const viewx = State.viewx
	const viewy = State.viewy
	const colormaps = State.colormaps
	const spanfunc = State.spanfunc
	const fixedcolormap = State.fixedcolormap
	local distance
	local dsXStep
	local dsYStep
	const yByteOffset = y * 4

	if planeheight ~= buffer.readi32(cachedheight, yByteOffset) then
		buffer.writei32(cachedheight, yByteOffset, planeheight)
		distance = FixedMul(planeheight, buffer.readi32(yslope, yByteOffset))
		buffer.writei32(cacheddistance, yByteOffset, distance)
		dsXStep = FixedMul(distance, basexscale)
		dsYStep = FixedMul(distance, baseyscale)
		buffer.writei32(cachedxstep, yByteOffset, dsXStep)
		buffer.writei32(cachedystep, yByteOffset, dsYStep)
	else
		distance = buffer.readi32(cacheddistance, yByteOffset)
		dsXStep = buffer.readi32(cachedxstep, yByteOffset)
		dsYStep = buffer.readi32(cachedystep, yByteOffset)
	end

	const xByteOffset = x1 * 4
	const length = FixedMul(distance, buffer.readi32(distscale, xByteOffset))

	const fineAngle = bit32.band(
		bit32.rshift(bit32.band(viewangle + buffer.readu32(xtoviewangle, xByteOffset), UINT32_MASK), 19),
		8191
	)

	const dsXFrac = ToSigned32(viewx + FixedMul(finecosine[fineAngle], length))
	const dsYFrac = ToSigned32(-viewy - FixedMul(finesine[fineAngle], length))

	local dsColormapOffset = fixedcolormap

	if not dsColormapOffset then
		const index = bit32.rshift(distance, LIGHTZSHIFT)
		dsColormapOffset = planezlight[if index >= MAXLIGHTZ then MAXLIGHTZ - 1 else index]
	end

	DrawSetSpanDraw(y, x1, x2, colormaps, dsColormapOffset, dsXFrac, dsYFrac, dsXStep, dsYStep)

	spanfunc()
end

-- ClearPlanes
-- At begining of frame.
const function ClearPlanes()
	const viewwidth = State.viewwidth
	const viewheight = State.viewheight
	const viewWidthBytes = viewwidth * 4
	buffer.fill(ceilingclip, 0, 0xFF, viewWidthBytes)
	EnsureFloorClipClear(viewwidth, viewheight)
	buffer.copy(floorclip, 0, floorclipclear, 0, viewWidthBytes)

	lastvisplane = 0

	buffer.fill(cachedheight, 0, 0)

	const angle = bit32.band(
		bit32.rshift(bit32.band(State.viewangle - 0x40000000, UINT32_MASK), 19),
		8191
	)

	const centerxfrac = State.centerxfrac

	basexscale = ToSigned32((math.modf(finecosine[angle] / centerxfrac * 65536)))
	baseyscale = ToSigned32(-(math.modf(finesine[angle] / centerxfrac * 65536)))
end

-- FindPlane
const function FindPlane(height: number, picnum: number, lightlevel: number)
	if picnum == SkyGetSkyFlatNum() then
		height = 0
		lightlevel = 0
	end

	for index = 1, lastvisplane do
		const plane = visplanes[index]

		if height == plane.height and picnum == plane.picnum and lightlevel == plane.lightlevel then
			return plane
		end
	end

	lastvisplane += 1

	const plane = AcquireVisplane(lastvisplane)
	plane.height = height
	plane.picnum = picnum
	plane.lightlevel = lightlevel
	plane.minx = renderWidthCached
	plane.maxx = -1

	return plane
end

-- CheckPlane
const function CheckPlane(pl: Visplane, start: number, stop: number)
	local intrl
	local intrh
	local unionl
	local unionh

	if start < pl.minx then
		intrl = pl.minx
		unionl = start
	else
		unionl = pl.minx
		intrl = start
	end

	if stop > pl.maxx then
		intrh = pl.maxx
		unionh = stop
	else
		unionh = pl.maxx
		intrh = stop
	end

	const top = pl.top
	local clear = true

	for x = intrl, intrh do
		if top[x] ~= PLANE then
			clear = false
			break
		end
	end

	if clear then
		pl.minx = unionl
		pl.maxx = unionh
		return pl
	end

	lastvisplane += 1

	const newPlane = AcquireVisplane(lastvisplane)
	newPlane.height = pl.height
	newPlane.picnum = pl.picnum
	newPlane.lightlevel = pl.lightlevel
	newPlane.minx = start
	newPlane.maxx = stop

	return newPlane
end

-- MakeSpans
const function MakeSpans(x: number, t1: number, b1: number, t2: number, b2: number)
	const stopX = x - 1
	const spanstartLocal = spanstart

	if t1 < t2 and t1 <= b1 then
		const endY = if t2 - 1 < b1 then t2 - 1 else b1
		local byteOffset = t1 * 4

		for y = t1, endY do
			MapPlane(y, buffer.readi32(spanstartLocal, byteOffset), stopX)
			byteOffset += 4
		end

		t1 = endY + 1
	end

	if b1 > b2 and b1 >= t1 then
		const endY = if b2 + 1 > t1 then b2 + 1 else t1
		local byteOffset = b1 * 4

		for y = b1, endY, -1 do
			MapPlane(y, buffer.readi32(spanstartLocal, byteOffset), stopX)
			byteOffset -= 4
		end

		b1 = endY - 1
	end

	if t2 < t1 and t2 <= b2 then
		const endY = if t1 - 1 < b2 then t1 - 1 else b2
		const endByteOffset = endY * 4

		for byteOffset = t2 * 4, endByteOffset, 4 do
			buffer.writei32(spanstartLocal, byteOffset, x)
		end

		t2 = endY + 1
	end

	if b2 > b1 and b2 >= t2 then
		const endY = if b1 + 1 > t2 then b1 + 1 else t2
		const endByteOffset = endY * 4

		for byteOffset = b2 * 4, endByteOffset, -4 do
			buffer.writei32(spanstartLocal, byteOffset, x)
		end
	end
end

const function DrawPlanes()
	if Definitions.RANGECHECK then
	end

	const skyFlatNum = SkyGetSkyFlatNum()
	const xtoviewangle = State.xtoviewangle
	const viewangle = State.viewangle
	const colormaps = State.colormaps
	const colfunc = State.colfunc
	const flattranslation = State.flattranslation
	const firstflat = State.firstflat
	const viewz = State.viewz
	const zlight = State.zlight
	const extralight = State.extralight
	const skyColumnScale = bit32.arshift(State.pspriteiscale, State.detailshift)
	local skyPrepared = false
	local skySource = EMPTY_BUFFER
	local skyWidthMask = 0
	local skySourceHeight = 0
	local lastFlatTranslation = -1
	local lastLight = -1
	local lastPlaneZLight = false

	for index = 1, lastvisplane do
		const pl = visplanes[index]

		if pl.minx > pl.maxx then
			continue
		end

		-- sky flat
		if pl.picnum == skyFlatNum then
			if not skyPrepared then
				const skyTexture = SkyGetSkyTexture()
				skySource, skyWidthMask, skySourceHeight = DataGetLinearColumnSource(skyTexture)
				DrawSetColumnSourceSetup(skyColumnScale, colormaps, 0, SkyGetSkyTextureMid(), skySource, 0)
				skyPrepared = true
			end

			local x = pl.minx
			const planeTop = pl.top
			const planeBottom = pl.bottom
			const xByteEnd = pl.maxx * 4

			for xByteOffset = pl.minx * 4, xByteEnd, 4 do
				const dcYl = planeTop[x]
				const dcYh = planeBottom[x]

				if dcYl <= dcYh then
					DrawSetColumnBoundsPositionSource(dcYl, dcYh, x, bit32.band(bit32.rshift(
						bit32.band(viewangle + buffer.readu32(xtoviewangle, xByteOffset), UINT32_MASK),
						ANGLETOSKYSHIFT
					), 1023, skyWidthMask) * skySourceHeight)

					colfunc()
				end

				x += 1
			end

			continue
		end

		-- regular flat
		const flatTranslation = flattranslation[pl.picnum]

		if flatTranslation ~= lastFlatTranslation then
			const dsSource = CacheLumpNum(firstflat + flatTranslation, STATIC)
			lastFlatTranslation = flatTranslation
			DrawSetSpanSource(dsSource, 0)
		end

		const heightDelta = ToSigned32(pl.height - viewz)
		planeheight = if heightDelta < 0 then -heightDelta else heightDelta

		local light = bit32.arshift(pl.lightlevel, LIGHTSEGSHIFT) + extralight

		if light >= LIGHTLEVELS then
			light = LIGHTLEVELS - 1
		end

		if light < 0 then
			light = 0
		end

		if light ~= lastLight then
			lastPlaneZLight = zlight[light]
			lastLight = light
		end

		planezlight = lastPlaneZLight


		const planeTop = pl.top
		const planeBottom = pl.bottom

		const maxx = pl.maxx + 1
		const minx = pl.minx - 1

		planeTop[maxx] = PLANE
		planeTop[minx] = PLANE
		planeBottom[maxx] = 0
		planeBottom[minx] = 0

		local previousTop = PLANE
		local previousBottom = 0

		for x = minx + 1, maxx do
			const currentTop = planeTop[x]
			const currentBottom = planeBottom[x]
			MakeSpans(x, previousTop, previousBottom, currentTop, currentBottom)
			previousTop = currentTop
			previousBottom = currentBottom
		end

		-- Wad cache buffers are not zone-owned in this port,
		--  so the original tag change is intentionally omitted.
	end
end

const function GetFloorClip(): buffer
	return floorclip
end

const function GetCeilingClip(): buffer
	return ceilingclip
end

Reset()

return {
	Reset = Reset,

	ClearPlanes = ClearPlanes,
	DrawPlanes = DrawPlanes,
	FindPlane = FindPlane,
	CheckPlane = CheckPlane,

	GetFloorClip = GetFloorClip,
	GetCeilingClip = GetCeilingClip,
}
