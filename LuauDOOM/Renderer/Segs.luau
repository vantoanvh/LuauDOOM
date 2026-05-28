--!native
--!optimize 2

-- Port of r_segs.c, r_segs.h
-- All the clipping: columns, horizontal spans, sky columns.
-- Note: `screenheightarray` and `negonearray` are owned by `r_things.c`.
-- This port keeps compatible fallback arrays so it can still run before or
-- without `Things.luau`; when `Things` is installed it populates the shared
-- sprite bridge state.
-- Note: clip refs stored in drawsegs are packed buffers with explicit x bases.

const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const Bsp = require("./Bsp")
const Data = require("./Data")
const Draw = require("./Draw")
const Geometry = require("./Geometry")
const Plane = require("./Plane")
const Runtime = require("./Runtime")
const ScaleFromGlobalAngle = require("./Shared")
const Sky = require("./Sky")
const State = require("./State")
const SpriteState = require("./SpriteState")
const Video = require("../System/Video")

const LIGHTLEVELS = 16
const LIGHTSEGSHIFT = 4
const MAXLIGHTSCALE = 48
const LIGHTSCALESHIFT = 12
const WALL_COLUMN_HEIGHT = 128

const HEIGHTBITS = 12
const HEIGHTUNIT = 4096

const SIL_NONE = 0
const SIL_BOTTOM = 1
const SIL_TOP = 2
const SIL_BOTH = 3

const DONTPEGTOP = 8
const DONTPEGBOTTOM = 16
const MAPPED = 256

const MAXINT = 0x7FFFFFFF
const MININT = -0x80000000
const MAXSHORT = 0x7FFF
const UINT32_MASK = 0xFFFFFFFF
const SIGNBIT = 0x80000000
const FixedMul = Fixed.FixedMul

type BufferCache = { [number]: buffer? }

local segtextured = false
local markfloor = false
local markceiling = false

local maskedtexture = false
local toptexture = 0
local bottomtexture = 0
local midtexture = 0

local rw_x = 0
local rw_stopx = 0
local rw_centerangle = 0
local rw_offset = 0
local rw_scale = 0
local rw_scalestep = 0
local rw_midtexturemid = 0
local rw_toptexturemid = 0
local rw_bottomtexturemid = 0

local worldtop = 0
local worldbottom = 0
local worldhigh = 0
local worldlow = 0

local pixhigh = 0
local pixlow = 0
local pixhighstep = 0
local pixlowstep = 0

local topfrac = 0
local topstep = 0
local bottomfrac = 0
local bottomstep = 0

local maskedtexturecol: buffer? = nil
const maskedPostColumn = buffer.create(WALL_COLUMN_HEIGHT)

local mfloorclip: buffer? = nil
local mceilingclip: buffer? = nil

local maskedtexturebase = 0
local mfloorclipbase = 0
local mceilingclipbase = 0
local spryscale = 0
local sprtopscreen = 0

local internalNegOneArray = buffer.create(math.max(Video.Width, 1) * 4)
local internalScreenHeightArray = buffer.create(math.max(Video.Width, 1) * 4)
local internalScreenHeightClear = buffer.create(0)
local internalSpriteClipWidth = 0
local internalScreenHeightClearWidth = 0
local internalScreenHeightClearHeight = 0
const drawsegStore = Bsp.GetDrawSegStore()
const BspMaxDrawSegs = Bsp.MAXDRAWSEGS

const BspGetDrawSegIndex = Bsp.GetDrawSegIndex
const BspSetDrawSegIndex = Bsp.SetDrawSegIndex
const BspGetCurrentLine = Bsp.GetCurrentLine
const BspGetFrontSector = Bsp.GetFrontSector
const BspGetBackSector = Bsp.GetBackSector
const BspSetCurrentState = Bsp.SetCurrentState

const drawsegX1 = drawsegStore.x1
const drawsegX2 = drawsegStore.x2
const drawsegScale1 = drawsegStore.scale1
const drawsegScale2 = drawsegStore.scale2
const drawsegScaleStep = drawsegStore.scalestep
const drawsegSilhouette = drawsegStore.silhouette
const drawsegBSilHeight = drawsegStore.bsilheight
const drawsegTSilHeight = drawsegStore.tsilheight
const drawsegCurline = drawsegStore.curline
const drawsegSprTopClip = drawsegStore.sprtopclip
const drawsegSprBottomClip = drawsegStore.sprbottomclip
const drawsegMaskedTextureCol = drawsegStore.maskedtexturecol
const reusableSprTopClipBuffers: BufferCache = table.create(BspMaxDrawSegs + 1)
const reusableSprBottomClipBuffers: BufferCache = table.create(BspMaxDrawSegs + 1)
const reusableMaskedTextureColBuffers: BufferCache = table.create(BspMaxDrawSegs + 1)

const DrawSetColumnRenderBase = Draw.SetColumnRenderBase
const DrawSetColumnTextureSource = Draw.SetColumnTextureSource
const DrawColumn = Draw.DrawColumn
const DrawColumnLow = Draw.DrawColumnLow
const GetColumn = Data.GetColumn
const GetMaskedColumn = Data.GetMaskedColumn
const PointToDist = Geometry.PointToDist
const SkyGetSkyFlatNum = Sky.GetSkyFlatNum
const PlaneGetCeilingClip = Plane.GetCeilingClip
const PlaneGetFloorClip = Plane.GetFloorClip
const PlaneCheckPlane = Plane.CheckPlane

const function ToSigned32(value: number): number
	value = bit32.band(value, UINT32_MASK)
	return if value >= SIGNBIT then value - 0x100000000 else value
end

const function SignedRightShift(value: number, shift: number): number
	return ToSigned32(bit32.arshift(value, shift))
end

const function EnsureInternalScreenHeightClear(width: number, height: number)
	if internalScreenHeightClearWidth == width and internalScreenHeightClearHeight == height then
		return
	end

	const byteWidth = width * 4
	internalScreenHeightClear = buffer.create(byteWidth)

	for byteOffset = 0, byteWidth - 4, 4 do
		buffer.writei32(internalScreenHeightClear, byteOffset, height)
	end

	internalScreenHeightClearWidth = width
	internalScreenHeightClearHeight = height
end

const function SyncInternalSpriteClipArrays()
	const width = Video.Width
	const byteWidth = width * 4

	if internalSpriteClipWidth ~= width then
		const allocByteWidth = math.max(byteWidth, 4)
		internalNegOneArray = buffer.create(allocByteWidth)
		internalScreenHeightArray = buffer.create(allocByteWidth)
		internalSpriteClipWidth = width
	end

	buffer.fill(internalNegOneArray, 0, 0xFF)
	const viewheight = State.viewheight

	EnsureInternalScreenHeightClear(width, viewheight)
	buffer.copy(internalScreenHeightArray, 0, internalScreenHeightClear, 0, byteWidth)
end

const function GetNegOneArray()
	const negonearray = SpriteState.negonearray

	if negonearray then
		return negonearray
	end

	SyncInternalSpriteClipArrays()
	return internalNegOneArray
end

const function GetScreenHeightArray()
	const screenheightarray = SpriteState.screenheightarray

	if screenheightarray then
		return screenheightarray
	end

	SyncInternalSpriteClipArrays()
	return internalScreenHeightArray
end

const function GetDrawSegBuffer(cache: BufferCache, index: number, byteCount: number): buffer
	local cached = cache[index]

	if cached == nil or buffer.len(cached) < byteCount then
		cached = buffer.create(byteCount)
		cache[index] = cached
	end

	return cached
end

const function CopyClipRange(source: buffer, start: number, stop: number, cache: BufferCache, index: number): buffer
	const count = stop - start + 1
	const byteCount = count * 4
	const copy = GetDrawSegBuffer(cache, index, byteCount)

	buffer.copy(copy, 0, source, start * 4, byteCount)

	return copy
end

const function DrawMaskedColumn(data: buffer, columnOffset: number)
	const basetexturemid = SpriteState.spriteTextureMid
	const colfunc = State.colfunc or if State.detailshift ~= 0 then DrawColumnLow else DrawColumn
	local currentOffset = columnOffset
	const dc_x = SpriteState.spriteColumnX
	const floorClipX = buffer.readi32(mfloorclip :: buffer, (dc_x - mfloorclipbase) * 4)
	const ceilingClipX = buffer.readi32(mceilingclip :: buffer, (dc_x - mceilingclipbase) * 4)
	const dataLength = buffer.len(data)

	while true do
		const topdelta = buffer.readu8(data, currentOffset)

		if topdelta == 0xFF then
			break
		end

		const length = buffer.readu8(data, currentOffset + 1)
		const topscreen = sprtopscreen + spryscale * topdelta
		const bottomscreen = topscreen + spryscale * length

		local dc_yl = ToSigned32(bit32.arshift(topscreen + 65536 - 1, 16))
		local dc_yh = ToSigned32(bit32.arshift(bottomscreen - 1, 16))

		if dc_yh >= floorClipX then
			dc_yh = floorClipX - 1
		end

		if dc_yl <= ceilingClipX then
			dc_yl = ceilingClipX + 1
		end

		if dc_yl <= dc_yh then
			const sourceOffset = currentOffset + 3

			if sourceOffset + WALL_COLUMN_HEIGHT <= dataLength then
				DrawSetColumnTextureSource(dc_yl, dc_yh, basetexturemid - topdelta * 65536, data, sourceOffset)
			else
				local copyCount = length
				const available = dataLength - sourceOffset

				if copyCount > WALL_COLUMN_HEIGHT then
					copyCount = WALL_COLUMN_HEIGHT
				end

				if copyCount > available then
					copyCount = available
				end

				if copyCount >= WALL_COLUMN_HEIGHT then
					buffer.copy(maskedPostColumn, 0, data, sourceOffset, WALL_COLUMN_HEIGHT)
				elseif copyCount > 0 then
					buffer.copy(maskedPostColumn, 0, data, sourceOffset, copyCount)
					buffer.fill(maskedPostColumn, copyCount, 0, WALL_COLUMN_HEIGHT - copyCount)
				else
					buffer.fill(maskedPostColumn, 0, 0, WALL_COLUMN_HEIGHT)
				end

				DrawSetColumnTextureSource(dc_yl, dc_yh, basetexturemid - topdelta * 65536, maskedPostColumn, 0)
			end

			colfunc()
		end

		currentOffset += length + 4
	end
end

const function Reset()
	segtextured = false
	markfloor = false
	markceiling = false

	maskedtexture = false
	toptexture = 0
	bottomtexture = 0
	midtexture = 0

	rw_x = 0
	rw_stopx = 0
	rw_centerangle = 0
	rw_offset = 0
	rw_scale = 0
	rw_scalestep = 0
	rw_midtexturemid = 0
	rw_toptexturemid = 0
	rw_bottomtexturemid = 0

	worldtop = 0
	worldbottom = 0
	worldhigh = 0
	worldlow = 0

	pixhigh = 0
	pixlow = 0
	pixhighstep = 0
	pixlowstep = 0

	topfrac = 0
	topstep = 0
	bottomfrac = 0
	bottomstep = 0

	maskedtexturecol = nil
	mfloorclip = nil
	mceilingclip = nil
	maskedtexturebase = 0
	mfloorclipbase = 0
	mceilingclipbase = 0
	spryscale = 0
	sprtopscreen = 0

	State.rw_distance = 0
	State.rw_normalangle = 0
	SyncInternalSpriteClipArrays()
end

-- RenderMaskedSegRange
const function RenderMaskedSegRange(drawSegIndex: number, x1: number, x2: number)
	if x2 < x1 then
		return
	end

	const drawSegOffset = drawSegIndex * 4
	const curline = drawsegCurline[drawSegIndex]
	const frontsector = curline.frontsector
	const backsector = curline.backsector
	const sidedef = curline.sidedef
	const linedef = curline.linedef
	const texturetranslation = State.texturetranslation
	const textureheight = State.textureheight
	const viewz = State.viewz
	const texnum = texturetranslation[sidedef.midtexture]
	local lightnum = bit32.arshift(frontsector.lightlevel, LIGHTSEGSHIFT) + State.extralight
	local texturemid = 0
	const frontFloorHeight = frontsector.renderFloorHeight or frontsector.floorheight
	const backFloorHeight = backsector.renderFloorHeight or backsector.floorheight
	const frontCeilingHeight = frontsector.renderCeilingHeight or frontsector.ceilingheight
	const backCeilingHeight = backsector.renderCeilingHeight or backsector.ceilingheight
	const v1 = curline.v1
	const v2 = curline.v2

	BspSetCurrentState(curline, frontsector, backsector)
	if v1.y == v2.y then
		lightnum -= 1
	elseif v1.x == v2.x then
		lightnum += 1
	end

	if lightnum < 0 then
		lightnum = 0
	elseif lightnum >= LIGHTLEVELS then
		lightnum = LIGHTLEVELS - 1
	end

	const walllights = State.scalelight[lightnum]
	State.walllights = walllights

	maskedtexturecol = drawsegMaskedTextureCol[drawSegIndex] or nil
	maskedtexturebase = buffer.readi32(drawsegX1, drawSegOffset)
	rw_scalestep = buffer.readi32(drawsegScaleStep, drawSegOffset)
	spryscale = buffer.readi32(drawsegScale1, drawSegOffset) + (x1 - maskedtexturebase) * rw_scalestep
	mfloorclip = drawsegSprBottomClip[drawSegIndex]
	mceilingclip = drawsegSprTopClip[drawSegIndex]
	mfloorclipbase = maskedtexturebase
	mceilingclipbase = maskedtexturebase
	SpriteState.maskedFloorClip = mfloorclip
	SpriteState.maskedCeilingClip = mceilingclip
	SpriteState.maskedFloorClipBase = mfloorclipbase
	SpriteState.maskedCeilingClipBase = mceilingclipbase

	if bit32.btest(linedef.flags, DONTPEGBOTTOM) then
		const textureHeight = textureheight[texnum]
		texturemid = if frontFloorHeight > backFloorHeight then frontFloorHeight else backFloorHeight
		texturemid += textureHeight - viewz
	else
		texturemid = (if frontCeilingHeight < backCeilingHeight then frontCeilingHeight else backCeilingHeight) - viewz
	end

	texturemid += sidedef.rowoffset

	const maskedColumnDrawer = SpriteState.maskedColumnDrawer or DrawMaskedColumn
	const maskedTextureColumns = maskedtexturecol :: buffer
	const fixedcolormap = State.fixedcolormap
	const colormaps = State.colormaps
	SpriteState.spriteColFunc = State.colfunc or if State.detailshift ~= 0 then DrawColumnLow else DrawColumn

	const centeryfrac = State.centeryfrac
	const rwScaleStep = rw_scalestep
	local spryscaleValue = spryscale
	local x = x1
	const clipStartOffset = (x1 - maskedtexturebase) * 4
	const clipEndOffset = (x2 - maskedtexturebase) * 4
	SpriteState.spriteTextureMid = texturemid

	if fixedcolormap then
		for clipOffset = clipStartOffset, clipEndOffset, 4 do
			const textureColumn = buffer.readi32(maskedTextureColumns, clipOffset)

			if textureColumn ~= MAXSHORT then
				spryscale = spryscaleValue
				sprtopscreen = ToSigned32(centeryfrac - FixedMul(texturemid, spryscaleValue))
				SpriteState.spriteYScale = spryscale
				SpriteState.spriteTopScreen = sprtopscreen
				SpriteState.spriteColumnX = x

				const source, sourceOffset = GetMaskedColumn(texnum, textureColumn)

				DrawSetColumnRenderBase(colormaps, fixedcolormap, x, UINT32_MASK // spryscaleValue)

				maskedColumnDrawer(source, sourceOffset)
				buffer.writei32(maskedTextureColumns, clipOffset, MAXSHORT)
			end

			spryscaleValue = bit32.band(spryscaleValue + rwScaleStep, UINT32_MASK)

			if spryscaleValue >= SIGNBIT then
				spryscaleValue -= 0x100000000
			end

			x += 1
		end
	else
		for clipOffset = clipStartOffset, clipEndOffset, 4 do
			const textureColumn = buffer.readi32(maskedTextureColumns, clipOffset)

			if textureColumn ~= MAXSHORT then
				local index = bit32.arshift(spryscaleValue, LIGHTSCALESHIFT)

				if index >= MAXLIGHTSCALE then
					index = MAXLIGHTSCALE - 1
				end

				spryscale = spryscaleValue
				sprtopscreen = ToSigned32(centeryfrac - FixedMul(texturemid, spryscaleValue))
				SpriteState.spriteYScale = spryscale
				SpriteState.spriteTopScreen = sprtopscreen
				SpriteState.spriteColumnX = x

				const source, sourceOffset = GetMaskedColumn(texnum, textureColumn)

				DrawSetColumnRenderBase(colormaps, walllights[index], x, UINT32_MASK // spryscaleValue)

				maskedColumnDrawer(source, sourceOffset)
				buffer.writei32(maskedTextureColumns, clipOffset, MAXSHORT)
			end

			spryscaleValue = bit32.band(spryscaleValue + rwScaleStep, UINT32_MASK)

			if spryscaleValue >= SIGNBIT then
				spryscaleValue -= 0x100000000
			end

			x += 1
		end
	end

	spryscale = spryscaleValue
end

-- RenderSegLoop
-- Draws zero, one, or two textures (and possibly a masked
--  texture) for walls.
-- Can draw or mark the starting pixel of floor and ceiling
--  textures.
-- CALLED: CORE LOOPING ROUTINE.
const function RenderSegLoop()
	const ceilingclip = PlaneGetCeilingClip()
	const floorclip = PlaneGetFloorClip()
	const ceilingPlane = State.ceilingplane
	const floorPlane = State.floorplane
	const colfunc = State.colfunc or if State.detailshift ~= 0 then DrawColumnLow else DrawColumn
	const finetangent = Tables.finetangent
	const viewheight = State.viewheight
	const walllights = State.walllights
	const xtoviewangle = State.xtoviewangle
	const colormaps = State.colormaps
	const rwDistance = State.rw_distance
	const rwCenterAngle = rw_centerangle
	const rwOffset = rw_offset
	const rwScaleStep = rw_scalestep
	const topStepValue = topstep
	const bottomStepValue = bottomstep
	const midTexture = midtexture
	const topTexture = toptexture
	const bottomTexture = bottomtexture
	const rwMidTextureMid = rw_midtexturemid
	const rwTopTextureMid = rw_toptexturemid
	const rwBottomTextureMid = rw_bottomtexturemid
	local loopcount = State.loopcount
	const maskedTextureBaseOffset = maskedtexturebase * 4
	local ceilingPlaneTop
	local ceilingPlaneBottom
	local floorPlaneTop
	local floorPlaneBottom
	const maskedTextureColumns = maskedtexturecol
	const markCeiling = markceiling
	const markFloor = markfloor
	const segTextured = segtextured
	const maskedTexture = maskedtexture
	local rwX = rw_x
	const rwStopX = rw_stopx
	local rwScale = rw_scale
	local topFrac = topfrac
	local bottomFrac = bottomfrac
	local pixHigh = pixhigh
	local pixLow = pixlow
	const startByteOffset = rwX * 4
	const stopByteOffset = (rwStopX - 1) * 4
	local maskedTextureOffset = startByteOffset - maskedTextureBaseOffset

	if markCeiling then
		ceilingPlaneTop = ceilingPlane.top
		ceilingPlaneBottom = ceilingPlane.bottom
	end

	if markFloor then
		floorPlaneTop = floorPlane.top
		floorPlaneBottom = floorPlane.bottom
	end

	for rwByteOffset = startByteOffset, stopByteOffset, 4 do
		local ceilingClip = buffer.readi32(ceilingclip, rwByteOffset)
		const floorClip = buffer.readi32(floorclip, rwByteOffset)
		const ceilingClipPlusOne = ceilingClip + 1
		const floorClipMinusOne = floorClip - 1
		local yl = bit32.band(bit32.arshift(topFrac + HEIGHTUNIT - 1, HEIGHTBITS), UINT32_MASK)
		if yl >= SIGNBIT then
			yl -= 0x100000000
		end
		local top
		local bottom

		if yl < ceilingClipPlusOne then
			yl = ceilingClipPlusOne
		end

		if markCeiling then
			top = ceilingClipPlusOne
			bottom = yl - 1

			if bottom >= floorClip then
				bottom = floorClipMinusOne
			end

			if top <= bottom then
				ceilingPlaneTop[rwX] = top
				ceilingPlaneBottom[rwX] = bottom
			end
		end

		local yh = bit32.band(bit32.arshift(bottomFrac, HEIGHTBITS), UINT32_MASK)
		if yh >= SIGNBIT then
			yh -= 0x100000000
		end

		if yh >= floorClip then
			yh = floorClipMinusOne
		end

		if markFloor then
			top = yh + 1
			bottom = floorClipMinusOne

			if top <= ceilingClip then
				top = ceilingClipPlusOne
			end

			if top <= bottom then
				floorPlaneTop[rwX] = top
				floorPlaneBottom[rwX] = bottom
			end
		end

		local texturecolumn = 0

		if segTextured then
			const angle = bit32.band(
				bit32.rshift(bit32.band(rwCenterAngle + buffer.readu32(xtoviewangle, rwByteOffset), UINT32_MASK), 19),
				4095
			)

			texturecolumn = bit32.band(bit32.arshift(bit32.band(rwOffset - FixedMul(finetangent[angle], rwDistance), UINT32_MASK), 16), UINT32_MASK)
			if texturecolumn >= SIGNBIT then
				texturecolumn -= 0x100000000
			end

			local lightIndex = bit32.arshift(rwScale, LIGHTSCALESHIFT)

			if lightIndex >= MAXLIGHTSCALE then
				lightIndex = MAXLIGHTSCALE - 1
			end

			DrawSetColumnRenderBase(colormaps, walllights[lightIndex], rwX, UINT32_MASK // rwScale)
		end

		if midTexture ~= 0 then
			const source, sourceOffset = GetColumn(midTexture, texturecolumn)

			DrawSetColumnTextureSource(yl, yh, rwMidTextureMid, source, sourceOffset)
			colfunc()
			buffer.writei32(ceilingclip, rwByteOffset, viewheight)
			buffer.writei32(floorclip, rwByteOffset, -1)
		else
			if topTexture ~= 0 then
				local mid = bit32.band(bit32.arshift(pixHigh, HEIGHTBITS), UINT32_MASK)
				if mid >= SIGNBIT then
					mid -= 0x100000000
				end
				pixHigh = bit32.band(pixHigh + pixhighstep, UINT32_MASK)

				if pixHigh >= SIGNBIT then
					pixHigh -= 0x100000000
				end

				if mid >= floorClip then
					mid = floorClipMinusOne
				end

				if mid >= yl then
					const source, sourceOffset = GetColumn(topTexture, texturecolumn)

					DrawSetColumnTextureSource(yl, mid, rwTopTextureMid, source, sourceOffset)
					colfunc()
					buffer.writei32(ceilingclip, rwByteOffset, mid)
					ceilingClip = mid
				else
					ceilingClip = yl - 1
					buffer.writei32(ceilingclip, rwByteOffset, ceilingClip)
				end
			elseif markCeiling then
				ceilingClip = yl - 1
				buffer.writei32(ceilingclip, rwByteOffset, ceilingClip)
			end

			if bottomTexture ~= 0 then
				local mid = bit32.band(bit32.arshift(pixLow + HEIGHTUNIT - 1, HEIGHTBITS), UINT32_MASK)
				if mid >= SIGNBIT then
					mid -= 0x100000000
				end
				pixLow = bit32.band(pixLow + pixlowstep, UINT32_MASK)

				if pixLow >= SIGNBIT then
					pixLow -= 0x100000000
				end

				if mid <= ceilingClip then
					mid = ceilingClip + 1
				end

				if mid <= yh then
					const source, sourceOffset = GetColumn(bottomTexture, texturecolumn)

					DrawSetColumnTextureSource(mid, yh, rwBottomTextureMid, source, sourceOffset)
					colfunc()
					buffer.writei32(floorclip, rwByteOffset, mid)
				else
					buffer.writei32(floorclip, rwByteOffset, yh + 1)
				end
			elseif markFloor then
				buffer.writei32(floorclip, rwByteOffset, yh + 1)
			end

			if maskedTexture then
				buffer.writei32(maskedTextureColumns :: buffer, maskedTextureOffset, texturecolumn)
			end
		end

		rwScale = bit32.band(rwScale + rwScaleStep, UINT32_MASK)

		if rwScale >= SIGNBIT then
			rwScale -= 0x100000000
		end

		topFrac = bit32.band(topFrac + topStepValue, UINT32_MASK)

		if topFrac >= SIGNBIT then
			topFrac -= 0x100000000
		end

		bottomFrac = bit32.band(bottomFrac + bottomStepValue, UINT32_MASK)

		if bottomFrac >= SIGNBIT then
			bottomFrac -= 0x100000000
		end

		rwX += 1
		maskedTextureOffset += 4
		loopcount += 1
	end

	rw_x = rwX
	rw_scale = rwScale
	topfrac = topFrac
	bottomfrac = bottomFrac
	pixhigh = pixHigh
	pixlow = pixLow
	State.loopcount = loopcount
end

-- StoreWallRange
-- A wall segment will be drawn
--  between start and stop pixels (inclusive).
const function StoreWallRange(start: number, stop: number)
	const drawSegIndex = BspGetDrawSegIndex()

	if drawSegIndex > BspMaxDrawSegs then
		return
	end

	const curline = BspGetCurrentLine()
	const sidedef = curline.sidedef
	const linedef = curline.linedef
	const frontsector = BspGetFrontSector()
	const backsector = BspGetBackSector()
	const drawSegOffset = drawSegIndex * 4
	const rowoffset = sidedef.rowoffset
	const v1 = curline.v1
	const frontFloorHeight = frontsector.renderFloorHeight or frontsector.floorheight
	const frontCeilingHeight = frontsector.renderCeilingHeight or frontsector.ceilingheight
	const texturetranslation = State.texturetranslation
	const textureheight = State.textureheight
	const viewz = State.viewz
	const viewangle = State.viewangle
	const rwAngle1 = State.rw_angle1
	const finesine = Tables.finesine
	local backFloorHeight
	local backCeilingHeight
	const xtoviewangle = State.xtoviewangle

	linedef.flags = bit32.bor(linedef.flags, MAPPED)

	State.rw_normalangle = bit32.band(curline.angle + 0x40000000, UINT32_MASK)
	const rwNormalAngle = State.rw_normalangle

	local offsetangle = ToSigned32(rwNormalAngle - rwAngle1)

	if offsetangle < 0 then
		offsetangle = -offsetangle
	end

	if offsetangle > 0x40000000 then
		offsetangle = 0x40000000
	end

	const distangle = 0x40000000 - offsetangle
	const hyp = PointToDist(v1.x, v1.y)
	local sineval = finesine[bit32.rshift(distangle, 19)]

	State.rw_distance = FixedMul(hyp, sineval)

	buffer.writei32(drawsegX1, drawSegOffset, start)
	buffer.writei32(drawsegX2, drawSegOffset, stop)
	drawsegCurline[drawSegIndex] = curline
	rw_x = start
	rw_stopx = stop + 1

	const startByteOffset = start * 4
	rw_scale = ScaleFromGlobalAngle(viewangle + buffer.readu32(xtoviewangle, startByteOffset))
	buffer.writei32(drawsegScale1, drawSegOffset, rw_scale)

	if stop > start then
		const stopByteOffset = stop * 4
		const scale2 = ScaleFromGlobalAngle(viewangle + buffer.readu32(xtoviewangle, stopByteOffset))
		rw_scalestep = math.modf((scale2 - rw_scale) / (stop - start))
		buffer.writei32(drawsegScale2, drawSegOffset, scale2)
		buffer.writei32(drawsegScaleStep, drawSegOffset, rw_scalestep)
	else
		buffer.writei32(drawsegScale2, drawSegOffset, rw_scale)
		buffer.writei32(drawsegScaleStep, drawSegOffset, 0)
		rw_scalestep = 0
	end

	worldtop = frontCeilingHeight - viewz
	worldbottom = frontFloorHeight - viewz

	midtexture = 0
	toptexture = 0
	bottomtexture = 0
	maskedtexture = false
	maskedtexturecol = nil
	drawsegMaskedTextureCol[drawSegIndex] = false
	const skyFlatNum = SkyGetSkyFlatNum()

	if not backsector then
		midtexture = texturetranslation[sidedef.midtexture]
		markfloor = true
		markceiling = true

		if bit32.btest(linedef.flags, DONTPEGBOTTOM) then
			const vtop = frontFloorHeight + textureheight[sidedef.midtexture]
			rw_midtexturemid = vtop - viewz
		else
			rw_midtexturemid = worldtop
		end

		rw_midtexturemid += rowoffset

		buffer.writei32(drawsegSilhouette, drawSegOffset, SIL_BOTH)
		drawsegSprTopClip[drawSegIndex] = GetScreenHeightArray()
		drawsegSprBottomClip[drawSegIndex] = GetNegOneArray()
		buffer.writei32(drawsegBSilHeight, drawSegOffset, MAXINT)
		buffer.writei32(drawsegTSilHeight, drawSegOffset, MININT)
	else
		backFloorHeight = backsector.renderFloorHeight or backsector.floorheight
		backCeilingHeight = backsector.renderCeilingHeight or backsector.ceilingheight
		drawsegSprTopClip[drawSegIndex] = false
		drawsegSprBottomClip[drawSegIndex] = false
		local silhouetteValue = SIL_NONE
		local bSilHeight = 0
		local tSilHeight = 0

		if frontFloorHeight > backFloorHeight then
			silhouetteValue = SIL_BOTTOM
			bSilHeight = frontFloorHeight
		elseif backFloorHeight > viewz then
			silhouetteValue = SIL_BOTTOM
			bSilHeight = MAXINT
		end

		if frontCeilingHeight < backCeilingHeight then
			silhouetteValue = bit32.bor(silhouetteValue, SIL_TOP)
			tSilHeight = frontCeilingHeight
		elseif backCeilingHeight < viewz then
			silhouetteValue = bit32.bor(silhouetteValue, SIL_TOP)
			tSilHeight = MININT
		end

		if backCeilingHeight <= frontFloorHeight then
			drawsegSprBottomClip[drawSegIndex] = GetNegOneArray()
			bSilHeight = MAXINT
			silhouetteValue = bit32.bor(silhouetteValue, SIL_BOTTOM)
		end

		if backFloorHeight >= frontCeilingHeight then
			drawsegSprTopClip[drawSegIndex] = GetScreenHeightArray()
			tSilHeight = MININT
			silhouetteValue = bit32.bor(silhouetteValue, SIL_TOP)
		end

		buffer.writei32(drawsegSilhouette, drawSegOffset, silhouetteValue)
		buffer.writei32(drawsegBSilHeight, drawSegOffset, bSilHeight)
		buffer.writei32(drawsegTSilHeight, drawSegOffset, tSilHeight)

		worldhigh = backCeilingHeight - viewz
		worldlow = backFloorHeight - viewz

		if frontsector.ceilingpic == skyFlatNum and backsector.ceilingpic == skyFlatNum then
			worldtop = worldhigh
		end

		markfloor = worldlow ~= worldbottom
			or backsector.floorpic ~= frontsector.floorpic
			or backsector.lightlevel ~= frontsector.lightlevel

		markceiling = worldhigh ~= worldtop
			or backsector.ceilingpic ~= frontsector.ceilingpic
			or backsector.lightlevel ~= frontsector.lightlevel

		if backCeilingHeight <= frontFloorHeight
			or backFloorHeight >= frontCeilingHeight then
			markceiling = true
			markfloor = true
		end

		if worldhigh < worldtop then
			toptexture = texturetranslation[sidedef.toptexture]

			if bit32.btest(linedef.flags, DONTPEGTOP) then
				rw_toptexturemid = worldtop
			else
				const vtop = backCeilingHeight + textureheight[sidedef.toptexture]
				rw_toptexturemid = vtop - viewz
			end
		end

		if worldlow > worldbottom then
			bottomtexture = texturetranslation[sidedef.bottomtexture]

			if bit32.btest(linedef.flags, DONTPEGBOTTOM) then
				rw_bottomtexturemid = worldtop
			else
				rw_bottomtexturemid = worldlow
			end
		end

		rw_toptexturemid += rowoffset
		rw_bottomtexturemid += rowoffset

		if sidedef.midtexture ~= 0 then
			maskedtexture = true
			maskedtexturebase = rw_x
			const maskedTextureByteCount = (rw_stopx - rw_x) * 4
			maskedtexturecol = GetDrawSegBuffer(reusableMaskedTextureColBuffers, drawSegIndex, maskedTextureByteCount)

			for maskedClipOffset = 0, maskedTextureByteCount - 4, 4 do
				buffer.writei32(maskedtexturecol :: buffer, maskedClipOffset, MAXSHORT)
			end

			drawsegMaskedTextureCol[drawSegIndex] = maskedtexturecol
		end
	end

	segtextured = midtexture ~= 0 or toptexture ~= 0 or bottomtexture ~= 0 or maskedtexture

	if segtextured then
		const normalAngleDelta = bit32.band(rwNormalAngle - rwAngle1, UINT32_MASK)
		offsetangle = normalAngleDelta

		if offsetangle > 0x80000000 then
			offsetangle = bit32.band(-offsetangle, UINT32_MASK)
		end

		if offsetangle > 0x40000000 then
			offsetangle = 0x40000000
		end

		sineval = finesine[bit32.rshift(offsetangle, 19)]

		rw_offset = FixedMul(hyp, sineval)

		if normalAngleDelta < 0x80000000 then
			rw_offset = -rw_offset
		end

		rw_offset = ToSigned32(rw_offset + sidedef.textureoffset + curline.offset)
		rw_centerangle = 0x40000000 + viewangle - rwNormalAngle

		if not State.fixedcolormap then
			local lightnum = bit32.arshift(frontsector.lightlevel, LIGHTSEGSHIFT) + State.extralight
			const v2 = curline.v2

			if v1.y == v2.y then
				lightnum -= 1
			elseif v1.x == v2.x then
				lightnum += 1
			end

			if lightnum < 0 then
				lightnum = 0
			elseif lightnum >= LIGHTLEVELS then
				lightnum = LIGHTLEVELS - 1
			end

			State.walllights = State.scalelight[lightnum]
		end
	end

	if frontFloorHeight >= viewz then
		markfloor = false
	end

	if frontCeilingHeight <= viewz and frontsector.ceilingpic ~= skyFlatNum then
		markceiling = false
	end

	const centeryfracShifted = bit32.arshift(State.centeryfrac, 4)

	worldtop = SignedRightShift(worldtop, 4)
	worldbottom = SignedRightShift(worldbottom, 4)

	topstep = ToSigned32(-FixedMul(rw_scalestep, worldtop))
	topfrac = ToSigned32(centeryfracShifted - FixedMul(worldtop, rw_scale))

	bottomstep = ToSigned32(-FixedMul(rw_scalestep, worldbottom))
	bottomfrac = ToSigned32(centeryfracShifted - FixedMul(worldbottom, rw_scale))

	if backsector then
		worldhigh = SignedRightShift(worldhigh, 4)
		worldlow = SignedRightShift(worldlow, 4)

		if worldhigh < worldtop then
			pixhigh = ToSigned32(centeryfracShifted - FixedMul(worldhigh, rw_scale))
			pixhighstep = ToSigned32(-FixedMul(rw_scalestep, worldhigh))
		end

		if worldlow > worldbottom then
			pixlow = ToSigned32(centeryfracShifted - FixedMul(worldlow, rw_scale))
			pixlowstep = ToSigned32(-FixedMul(rw_scalestep, worldlow))
		end
	end

	if markceiling then
		State.ceilingplane = PlaneCheckPlane(State.ceilingplane, rw_x, rw_stopx - 1)
	end

	if markfloor then
		State.floorplane = PlaneCheckPlane(State.floorplane, rw_x, rw_stopx - 1)
	end

	RenderSegLoop()

	local silhouetteValue = buffer.readi32(drawsegSilhouette, drawSegOffset)

	if (bit32.btest(silhouetteValue, SIL_TOP) or maskedtexture)
		and not drawsegSprTopClip[drawSegIndex] then
		drawsegSprTopClip[drawSegIndex] = CopyClipRange(
			PlaneGetCeilingClip(),
			start,
			rw_stopx - 1,
			reusableSprTopClipBuffers,
			drawSegIndex
		)
	end

	if (bit32.btest(silhouetteValue, SIL_BOTTOM) or maskedtexture)
		and not drawsegSprBottomClip[drawSegIndex] then
		drawsegSprBottomClip[drawSegIndex] = CopyClipRange(
			PlaneGetFloorClip(),
			start,
			rw_stopx - 1,
			reusableSprBottomClipBuffers,
			drawSegIndex
		)
	end

	if maskedtexture and bit32.band(silhouetteValue, SIL_TOP) == 0 then
		silhouetteValue = bit32.bor(silhouetteValue, SIL_TOP)
		buffer.writei32(drawsegSilhouette, drawSegOffset, silhouetteValue)
		buffer.writei32(drawsegTSilHeight, drawSegOffset, MININT)
	end

	if maskedtexture and bit32.band(silhouetteValue, SIL_BOTTOM) == 0 then
		silhouetteValue = bit32.bor(silhouetteValue, SIL_BOTTOM)
		buffer.writei32(drawsegSilhouette, drawSegOffset, silhouetteValue)
		buffer.writei32(drawsegBSilHeight, drawSegOffset, MAXINT)
	end

	BspSetDrawSegIndex(drawSegIndex + 1)
end

const function Install()
	Runtime.storeWallRange = StoreWallRange
end

Reset()

return {
	SIL_NONE = SIL_NONE,
	SIL_BOTTOM = SIL_BOTTOM,
	SIL_TOP = SIL_TOP,
	SIL_BOTH = SIL_BOTH,

	Reset = Reset,
	Install = Install,

	RenderMaskedSegRange = RenderMaskedSegRange,
}
