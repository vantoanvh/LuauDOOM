--!native
--!optimize 2

-- Port of r_things.c, r_things.h
-- Refresh of things, i.e. objects represented by sprites.
-- Note: sprite definition storage lives in `State.sprites` as Luau tables
-- instead of zone allocations.
-- `screenheightarray` is refreshed from `Main.ExecuteSetViewSize()` through
-- shared sprite bridge state, not by taking a direct dependency on `Main`.
const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const Bsp = require("./Bsp")
const Draw = require("./Draw")
const Geometry = require("./Geometry")
const Runtime = require("./Runtime")
const Segs = require("./Segs")
const SpriteState = require("./SpriteState")
const State = require("./State")
const Video = require("../System/Video")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const FRACBITS = 16
const FRACUNIT = 65536
const FixedMul = Fixed.FixedMul
const UINT32_MASK = 0xFFFFFFFF
const SIGNBIT = 0x80000000

const MINZ = FRACUNIT * 4
const BASEYCENTER = 100
const MAXVISSPRITES = 512
const LIGHTLEVELS = 16
const LIGHTSEGSHIFT = 4
const MAXLIGHTSCALE = 48
const LIGHTSCALESHIFT = 12
const FULLBRIGHT = 0x8000
const FRAMEMASK = 0x7FFF
const SHADOW = 0x40000
const TRANSLATION = 0x0C000000
const TRANSSHIFT = 26
const NUMPSPRITES = 2
const SPRITE_COLUMN_HEIGHT = 128

type SpriteFrame = {
	rotate: boolean | number,
	lump: { [number]: number },
	flip: { [number]: number },
}

type SpriteDef = {
	numframes: number,
	spriteframes: { [number]: SpriteFrame },
}

type VisSprite = {
	x1: number,
	x2: number,
	gx: number,
	gy: number,
	gz: number,
	gzt: number,
	startfrac: number,
	scale: number,
	xiscale: number,
	texturemid: number,
	patch: number,
	colormap: boolean | number,
	mobjflags: number,
}

type Thing = {
	flags: number,
	frame: number,
	x: number,
	y: number,
	z: number,
	angle: number,
	renderPrevX: number?,
	renderPrevY: number?,
	renderPrevZ: number?,
	renderPrevAngle: number?,
	sprite: number,
	snext: Thing?,
}

type Sector = {
	validcount: number,
	lightlevel: number,
	thinglist: Thing?,
}

type PlayerSprite = {
	state: {
		sprite: number,
		frame: number,
	},
	sx: number,
	sy: number,
	renderPrevSX: number?,
	renderPrevSY: number?,
}

const sprtemp: { [number]: SpriteFrame } = {}
local maxframe = -1
local spritename = ""

const vissprites: { [number]: VisSprite } = {}
local visspriteCount = 0
local overflowsprite: VisSprite = {} :: VisSprite

local spritelights = false
local negonearray = buffer.create(math.max(Video.Width, 1) * 4)
local screenheightarray = buffer.create(math.max(Video.Width, 1) * 4)
local mfloorclip = false
local mceilingclip = false
local mfloorclipbase = 0
local mceilingclipbase = 0
local spryscale = 0
local sprtopscreen = 0
const maskedPostColumn = buffer.create(SPRITE_COLUMN_HEIGHT)
local clipbot = buffer.create(math.max(Video.Width, 1) * 4)
local cliptop = buffer.create(math.max(Video.Width, 1) * 4)
local nocliparray = buffer.create(math.max(Video.Width, 1) * 4)
local screenheightclear = buffer.create(0)
local clipBufferWidth = 0
local screenheightclearwidth = 0
local screenheightclearheight = 0
local sortedSpriteIndices = buffer.create(MAXVISSPRITES * 2)
local sortedSpriteScratch = buffer.create(MAXVISSPRITES * 2)
const spriteSortCounts = buffer.create(256 * 4)
local sortedSpriteCount = 0
const CLIP = -2
const ANG45_HALF_9 = 0x90000000
const NOT_SIL_BOTTOM = bit32.bnot(Segs.SIL_BOTTOM)
const NOT_SIL_TOP = bit32.bnot(Segs.SIL_TOP)

const drawsegStore = Bsp.GetDrawSegStore()
const drawsegX1 = drawsegStore.x1
const drawsegX2 = drawsegStore.x2
const drawsegScale1 = drawsegStore.scale1
const drawsegScale2 = drawsegStore.scale2
const drawsegSilhouette = drawsegStore.silhouette
const drawsegBSilHeight = drawsegStore.bsilheight
const drawsegTSilHeight = drawsegStore.tsilheight
const drawsegCurline = drawsegStore.curline
const drawsegSprTopClip = drawsegStore.sprtopclip
const drawsegSprBottomClip = drawsegStore.sprbottomclip
const drawsegMaskedTextureCol = drawsegStore.maskedtexturecol
const DrawSetColumnPosition = Draw.SetColumnPosition
const DrawSetColumnScale = Draw.SetColumnScale
const DrawSetColumnRenderBase = Draw.SetColumnRenderBase
const DrawSetColumnTextureSource = Draw.SetColumnTextureSource
const DrawSetColumnTranslation = Draw.SetColumnTranslation
const DrawGetTranslationTables = Draw.GetTranslationTables
const DrawColumn = Draw.DrawColumn
const DrawColumnLow = Draw.DrawColumnLow
const DrawFuzzColumn = Draw.DrawFuzzColumn
const DrawTranslatedColumn = Draw.DrawTranslatedColumn
const BspGetDrawSegIndex = Bsp.GetDrawSegIndex
const SegsRenderMaskedSegRange = Segs.RenderMaskedSegRange
const PointToAngle = Geometry.PointToAngle
const PointOnSegSide = Geometry.PointOnSegSide
const CacheLumpNum = Wad.CacheLumpNum
const CACHE = Zone.CACHE

const function EnsureClipBuffers()
	const width = Video.Width

	if clipBufferWidth ~= width then
		const byteWidth = width * 4
		negonearray = buffer.create(byteWidth)
		screenheightarray = buffer.create(byteWidth)
		clipbot = buffer.create(byteWidth)
		cliptop = buffer.create(byteWidth)
		nocliparray = buffer.create(byteWidth)
		clipBufferWidth = width

		for byteOffset = 0, byteWidth - 4, 4 do
			buffer.writei32(nocliparray, byteOffset, CLIP)
		end

		if SpriteState.negonearray ~= false then
			SpriteState.negonearray = negonearray
			SpriteState.screenheightarray = screenheightarray
		end
	end
end

const function EnsureScreenHeightClear(width: number, height: number)
	if screenheightclearwidth == width and screenheightclearheight == height then
		return
	end

	const byteWidth = width * 4
	screenheightclear = buffer.create(byteWidth)

	for byteOffset = 0, byteWidth - 4, 4 do
		buffer.writei32(screenheightclear, byteOffset, height)
	end

	screenheightclearwidth = width
	screenheightclearheight = height
end

const function CollectSpriteNames(namelist: { [number]: string }?): { string }
	if namelist == nil then
		return {}
	end

	const names: { string } = {}

	if namelist[0] ~= nil then
		local index = 0

		while namelist[index] ~= nil do
			names[#names + 1] = string.upper(namelist[index] :: string)
			index += 1
		end
	else
		for index, name in namelist do
			names[#names + 1] = string.upper(name :: string)
		end
	end

	return names
end

const function NewSpriteFrame(): SpriteFrame
	const frame = {
		rotate = false,
		lump = {},
		flip = {},
	}

	for rotation = 0, 7 do
		frame.lump[rotation] = -1
		frame.flip[rotation] = 0
	end

	return frame
end

const function ResetTempFrames()
	table.clear(sprtemp)

	for frame = 0, 28 do
		const entry = NewSpriteFrame()
		entry.rotate = -1
		sprtemp[frame] = entry
	end
end

const function NewVissprite(): VisSprite
	return {
		x1 = 0,
		x2 = 0,
		gx = 0,
		gy = 0,
		gz = 0,
		gzt = 0,
		startfrac = 0,
		scale = 0,
		xiscale = 0,
		texturemid = 0,
		patch = 0,
		colormap = false,
		mobjflags = 0,
	}
end

const function ResetNegOneArray()
	buffer.fill(negonearray, 0, 0xFF)
end

const function UpdateViewClipArrays()
	EnsureClipBuffers()

	const viewheight = State.viewheight
	const byteWidth = State.viewwidth * 4

	EnsureScreenHeightClear(State.viewwidth, viewheight)
	buffer.copy(screenheightarray, 0, screenheightclear, 0, byteWidth)
end

const function Reset()
	EnsureClipBuffers()
	table.clear(State.sprites)

	State.numsprites = 0
	maxframe = -1
	spritename = ""
	visspriteCount = 0
	sortedSpriteCount = 0
	spritelights = false
	mfloorclip = false
	mceilingclip = false
	spryscale = 0
	sprtopscreen = 0

	for index = 1, MAXVISSPRITES do
		vissprites[index] = NewVissprite()
	end

	overflowsprite = NewVissprite()
	ResetTempFrames()
	ResetNegOneArray()
	UpdateViewClipArrays()
	Runtime.addSprites = nil
	SpriteState.negonearray = false
	SpriteState.screenheightarray = false
	SpriteState.maskedColumnDrawer = nil
end

-- InstallSpriteLump
-- Local function for R_InitSprites.
const function InstallSpriteLump(lump: number, frame: number, rotation: number, flipped: boolean)
	if frame > maxframe then
		maxframe = frame
	end

	const tempFrame = sprtemp[frame]

	if rotation == 0 then
		tempFrame.rotate = 0

		for r = 0, 7 do
			tempFrame.lump[r] = lump - State.firstspritelump
			tempFrame.flip[r] = if flipped then 1 else 0
		end

		return
	end

	tempFrame.rotate = 1
	rotation -= 1

	tempFrame.lump[rotation] = lump - State.firstspritelump
	tempFrame.flip[rotation] = if flipped then 1 else 0
end

-- InitSpriteDefs
const function InitSpriteDefs(namelist: { [number]: string }?)
	const names = CollectSpriteNames(namelist)

	table.clear(State.sprites)
	State.numsprites = #names

	if State.numsprites == 0 then
		return
	end

	const start = State.firstspritelump - 1
	const finish = State.lastspritelump + 1

	for spriteIndex = 0, State.numsprites - 1 do
		spritename = names[spriteIndex + 1]
		ResetTempFrames()
		maxframe = -1

		for lump = start + 1, finish - 1 do
			const lumpName = Wad.GetLumpName(lump)

			if string.sub(lumpName, 1, 4) == spritename then
				const frameByte = string.byte(lumpName, 5)
				const rotationByte = string.byte(lumpName, 6)


				const frame = frameByte - 65
				const rotation = rotationByte - 48
				InstallSpriteLump(lump, frame, rotation, false)

				if string.byte(lumpName, 7) ~= nil then
					const frame2Byte = string.byte(lumpName, 7)
					const rotation2Byte = string.byte(lumpName, 8)


					InstallSpriteLump(
						lump,
						frame2Byte - 65,
						rotation2Byte - 48,
						true
					)
				end
			end
		end

		if maxframe == -1 then
			State.sprites[spriteIndex] = {
				numframes = 0,
				spriteframes = {},
			}
			continue
		end

		maxframe += 1

		const spriteframes: { [number]: SpriteFrame } = {}

		for frame = 0, maxframe - 1 do
			const sourceFrame = sprtemp[frame]
			const spriteframe = NewSpriteFrame()
			spriteframe.rotate = sourceFrame.rotate == 1

			for rotation = 0, 7 do
				spriteframe.lump[rotation] = sourceFrame.lump[rotation]
				spriteframe.flip[rotation] = sourceFrame.flip[rotation]
			end

			spriteframes[frame] = spriteframe
		end

		State.sprites[spriteIndex] = {
			numframes = maxframe,
			spriteframes = spriteframes,
		}
	end
end

-- InitSprites
-- Called at program start.
const function InitSprites(namelist: { [number]: string }?)
	ResetNegOneArray()
	InitSpriteDefs(namelist)
end

-- ClearSprites
-- Called at frame start.
const function ClearSprites()
	visspriteCount = 0
	sortedSpriteCount = 0
end

-- NewVisSprite
const function NewVisSprite()
	if visspriteCount == MAXVISSPRITES then
		overflowsprite = NewVissprite()
		return overflowsprite
	end

	visspriteCount += 1

	const vis = vissprites[visspriteCount]
	vis.x1 = 0
	vis.x2 = 0
	vis.gx = 0
	vis.gy = 0
	vis.gz = 0
	vis.gzt = 0
	vis.startfrac = 0
	vis.scale = 0
	vis.xiscale = 0
	vis.texturemid = 0
	vis.patch = 0
	vis.colormap = false
	vis.mobjflags = 0

	return vis
end

const function DrawMaskedPosts(data: buffer, columnOffset: number, floorclip: buffer, floorClipOffset: number, ceilingclip: buffer, ceilingClipOffset: number, yscale: number, topscreenBase: number, basetexturemid: number, colfunc: () -> ())
	local currentOffset = columnOffset
	const floorClipX = buffer.readi32(floorclip, floorClipOffset)
	const ceilingClipX = buffer.readi32(ceilingclip, ceilingClipOffset)
	const dataLength = buffer.len(data)

	while true do
		const topdelta = buffer.readu8(data, currentOffset)

		if topdelta == 0xFF then
			break
		end

		const length = buffer.readu8(data, currentOffset + 1)
		const topscreen = topscreenBase + yscale * topdelta
		const bottomscreen = topscreen + yscale * length
		local dc_yl = bit32.band(bit32.arshift(topscreen + FRACUNIT - 1, FRACBITS), UINT32_MASK)
		local dc_yh = bit32.band(bit32.arshift(bottomscreen - 1, FRACBITS), UINT32_MASK)

		if dc_yl >= SIGNBIT then
			dc_yl -= 0x100000000
		end

		if dc_yh >= SIGNBIT then
			dc_yh -= 0x100000000
		end

		if dc_yh >= floorClipX then
			dc_yh = floorClipX - 1
		end

		if dc_yl <= ceilingClipX then
			dc_yl = ceilingClipX + 1
		end

		if dc_yl <= dc_yh then
			const sourceOffset = currentOffset + 3

			if sourceOffset + SPRITE_COLUMN_HEIGHT <= dataLength then
				DrawSetColumnTextureSource(dc_yl, dc_yh, basetexturemid - topdelta * FRACUNIT, data, sourceOffset)
			else
				local copyCount = length
				const available = dataLength - sourceOffset

				if copyCount > SPRITE_COLUMN_HEIGHT then
					copyCount = SPRITE_COLUMN_HEIGHT
				end

				if copyCount > available then
					copyCount = available
				end

				if copyCount >= SPRITE_COLUMN_HEIGHT then
					buffer.copy(maskedPostColumn, 0, data, sourceOffset, SPRITE_COLUMN_HEIGHT)
				elseif copyCount > 0 then
					buffer.copy(maskedPostColumn, 0, data, sourceOffset, copyCount)
					buffer.fill(maskedPostColumn, copyCount, 0, SPRITE_COLUMN_HEIGHT - copyCount)
				else
					buffer.fill(maskedPostColumn, 0, 0, SPRITE_COLUMN_HEIGHT)
				end

				DrawSetColumnTextureSource(dc_yl, dc_yh, basetexturemid - topdelta * FRACUNIT, maskedPostColumn, 0)
			end

			colfunc()
		end

		currentOffset += length + 4
	end
end

const function DrawMaskedSegColumn(data: buffer, columnOffset: number)
	const spriteColumnX = SpriteState.spriteColumnX

	DrawMaskedPosts(
		data,
		columnOffset,
		SpriteState.maskedFloorClip,
		(spriteColumnX - SpriteState.maskedFloorClipBase) * 4,
		SpriteState.maskedCeilingClip,
		(spriteColumnX - SpriteState.maskedCeilingClipBase) * 4,
		SpriteState.spriteYScale,
		SpriteState.spriteTopScreen,
		SpriteState.spriteTextureMid,
		SpriteState.spriteColFunc
	)
end

-- DrawVisSprite
-- mfloorclip and mceilingclip should also be set.
const function DrawVisSprite(vis: VisSprite, x1: number, x2: number)
	const baseColFunc = State.basecolfunc or if State.detailshift ~= 0 then DrawColumnLow else DrawColumn
	const patch = CacheLumpNum(vis.patch + State.firstspritelump, CACHE)
	const mobjflags = vis.mobjflags

	if not vis.colormap then
		State.colfunc = State.fuzzcolfunc or DrawFuzzColumn
	else
		const translation = bit32.band(mobjflags, TRANSLATION)

		if translation ~= 0 then
			const translationIndex = bit32.rshift(translation, TRANSSHIFT) - 1

			State.colfunc = State.transcolfunc or DrawTranslatedColumn
			DrawSetColumnTranslation(DrawGetTranslationTables(), translationIndex * 256)
		else
			State.colfunc = baseColFunc
		end

	end

	const xiscale = vis.xiscale
	const absXiscale = if xiscale < 0 then -xiscale else xiscale
	const dc_iscale = bit32.arshift(absXiscale, State.detailshift)
	if vis.colormap then
		DrawSetColumnRenderBase(State.colormaps, vis.colormap, x1, dc_iscale)
	else
		DrawSetColumnScale(dc_iscale)
	end

	local frac = vis.startfrac
	spryscale = vis.scale
	const texturemid = vis.texturemid
	const colfunc = State.colfunc or if State.detailshift ~= 0 then DrawColumnLow else DrawColumn
	sprtopscreen = State.centeryfrac - FixedMul(texturemid, spryscale)
	local floorClipOffset = (x1 - mfloorclipbase) * 4
	local ceilingClipOffset = (x1 - mceilingclipbase) * 4

	for dc_x = x1, x2 do
		DrawSetColumnPosition(dc_x)
		DrawMaskedPosts(
			patch,
			buffer.readi32(patch, 8 + bit32.arshift(frac, FRACBITS) * 4),
			mfloorclip,
			floorClipOffset,
			mceilingclip,
			ceilingClipOffset,
			spryscale,
			sprtopscreen,
			texturemid,
			colfunc
		)
		frac += xiscale
		floorClipOffset += 4
		ceilingClipOffset += 4
	end

	State.colfunc = baseColFunc
end

-- ProjectSprite
const function ProjectSprite(thing: Thing)
	const viewx = State.viewx
	const viewy = State.viewy
	const viewz = State.viewz
	const viewcos = State.viewcos
	const viewsin = State.viewsin
	const projection = State.projection
	const centerxfrac = State.centerxfrac
	const viewwidth = State.viewwidth
	const detailshift = State.detailshift
	const fixedcolormap = State.fixedcolormap
	const spriteoffset = State.spriteoffset
	const spritewidth = State.spritewidth
	const spritetopoffset = State.spritetopoffset
	const sprites = State.sprites
	const alpha = State.interpolationAlpha
	const thingFlags = thing.flags
	const thingFrame = thing.frame
	local thingX = thing.x
	local thingY = thing.y
	local thingZ = thing.z
	local thingAngle = thing.angle

	if alpha > 0 then
		const prevX = thing.renderPrevX
		const prevY = thing.renderPrevY
		const prevZ = thing.renderPrevZ
		const prevAngle = thing.renderPrevAngle

		if prevX ~= nil then
			thingX = math.modf(prevX + (thingX - prevX) * alpha)
		end

		if prevY ~= nil then
			thingY = math.modf(prevY + (thingY - prevY) * alpha)
		end

		if prevZ ~= nil then
			thingZ = math.modf(prevZ + (thingZ - prevZ) * alpha)
		end

		if prevAngle ~= nil then
			local delta = thingAngle - prevAngle

			if delta > 0x80000000 then
				delta -= 0x100000000
			elseif delta < -0x80000000 then
				delta += 0x100000000
			end

			thingAngle = bit32.band(math.modf(prevAngle + delta * alpha), 0xFFFFFFFF)
		end
	end
	const tr_x = thingX - viewx
	const tr_y = thingY - viewy
	local gxt = FixedMul(tr_x, viewcos)
	local gyt = -FixedMul(tr_y, viewsin)
	const tz = gxt - gyt

	if tz < MINZ then
		return
	end

	local xscale = math.modf(projection / tz * FRACUNIT)
	if xscale >= SIGNBIT then
		xscale -= 0x100000000
	end

	gxt = -FixedMul(tr_x, viewsin)
	gyt = FixedMul(tr_y, viewcos)
	local tx = -(gyt + gxt)

	if (if tx < 0 then -tx else tx) > tz * 4 then
		return
	end

	const sprdef = sprites[thing.sprite]
	const frameIndex = bit32.band(thingFrame, FRAMEMASK)
	const sprframe = sprdef.spriteframes[frameIndex]

	local lump
	local flip

	if sprframe.rotate then
		const ang = PointToAngle(thingX, thingY)
		const rot = bit32.rshift(ang - thingAngle + ANG45_HALF_9, 29)

		lump = sprframe.lump[rot]
		flip = sprframe.flip[rot] ~= 0
	else
		lump = sprframe.lump[0]
		flip = sprframe.flip[0] ~= 0
	end

	const width = spritewidth[lump]

	tx -= spriteoffset[lump]
	local x1 = bit32.band(bit32.arshift(centerxfrac + FixedMul(tx, xscale), FRACBITS), UINT32_MASK)
	if x1 >= SIGNBIT then
		x1 -= 0x100000000
	end

	if x1 > viewwidth then
		return
	end

	tx += width
	local x2 = bit32.band(bit32.arshift(centerxfrac + FixedMul(tx, xscale), FRACBITS), UINT32_MASK)
	if x2 >= SIGNBIT then
		x2 -= 0x100000000
	end
	x2 -= 1

	if x2 < 0 then
		return
	end

	const vis = NewVisSprite()
	vis.mobjflags = thingFlags
	vis.scale = if detailshift == 0 then xscale else xscale * 2
	vis.gx = thingX
	vis.gy = thingY
	vis.gz = thingZ
	vis.gzt = thingZ + spritetopoffset[lump]
	vis.texturemid = vis.gzt - viewz
	vis.x1 = if x1 < 0 then 0 else x1
	vis.x2 = if x2 >= viewwidth then viewwidth - 1 else x2
	const iscale = if xscale <= 4 then 0x7FFFFFFF else math.modf(0x100000000 / xscale)

	if flip then
		vis.startfrac = width - 1
		vis.xiscale = -iscale
	else
		vis.startfrac = 0
		vis.xiscale = iscale
	end

	if vis.x1 > x1 then
		vis.startfrac += vis.xiscale * (vis.x1 - x1)
	end

	vis.patch = lump

	if bit32.btest(thingFlags, SHADOW) then
		vis.colormap = false
	elseif fixedcolormap then
		vis.colormap = fixedcolormap
	elseif bit32.btest(thingFrame, FULLBRIGHT) then
		vis.colormap = 0
	else
		local index = bit32.arshift(xscale, LIGHTSCALESHIFT - detailshift)

		if index >= MAXLIGHTSCALE then
			index = MAXLIGHTSCALE - 1
		end

		vis.colormap = spritelights[index]
	end
end

-- AddSprites
-- During BSP traversal, this adds sprites by sector.
const function AddSprites(sec: Sector)
	if sec.validcount == State.validcount then
		return
	end

	sec.validcount = State.validcount
	const lightnum = bit32.arshift(sec.lightlevel, LIGHTSEGSHIFT) + State.extralight

	if lightnum < 0 then
		spritelights = State.scalelight[0]
	elseif lightnum >= LIGHTLEVELS then
		spritelights = State.scalelight[LIGHTLEVELS - 1]
	else
		spritelights = State.scalelight[lightnum]
	end

	local thing = sec.thinglist

	while thing do
		ProjectSprite(thing)
		thing = thing.snext
	end
end

const function DrawPlayerSprite(psp: PlayerSprite)
	const sprites = State.sprites
	const spriteoffset = State.spriteoffset
	const spritewidth = State.spritewidth
	const spritetopoffset = State.spritetopoffset
	const centerxfrac = State.centerxfrac
	const viewwidth = State.viewwidth
	const pspritescale = State.pspritescale
	const pspriteiscale = State.pspriteiscale
	const detailshift = State.detailshift
	const fixedcolormap = State.fixedcolormap
	const state = psp.state
	const sprdef = sprites[state.sprite]
	const stateFrame = state.frame
	const sprframe = sprdef.spriteframes[bit32.band(stateFrame, FRAMEMASK)]

	const lump = sprframe.lump[0]
	const flip = sprframe.flip[0] ~= 0
	const width = spritewidth[lump]
	local pspSx = psp.sx
	local pspSy = psp.sy
	const alpha = State.interpolationAlpha

	if alpha > 0 then
		const prevSX = psp.renderPrevSX
		const prevSY = psp.renderPrevSY

		if prevSX ~= nil then
			pspSx = math.modf(prevSX + (pspSx - prevSX) * alpha)
		end

		if prevSY ~= nil then
			pspSy = math.modf(prevSY + (pspSy - prevSY) * alpha)
		end
	end

	local tx = pspSx - 160 * FRACUNIT

	tx -= spriteoffset[lump]
	local x1 = bit32.band(bit32.arshift(centerxfrac + FixedMul(tx, pspritescale), FRACBITS), UINT32_MASK)
	if x1 >= SIGNBIT then
		x1 -= 0x100000000
	end

	if x1 > viewwidth then
		return
	end

	tx += width
	local x2 = bit32.band(bit32.arshift(centerxfrac + FixedMul(tx, pspritescale), FRACBITS), UINT32_MASK)
	if x2 >= SIGNBIT then
		x2 -= 0x100000000
	end
	x2 -= 1

	if x2 < 0 then
		return
	end

	const vis = NewVissprite()
	vis.mobjflags = 0
	vis.texturemid = BASEYCENTER * FRACUNIT + FRACUNIT // 2 - (pspSy - spritetopoffset[lump])
	vis.x1 = if x1 < 0 then 0 else x1
	vis.x2 = if x2 >= viewwidth then viewwidth - 1 else x2
	vis.scale = if detailshift == 0 then pspritescale else pspritescale * 2

	if flip then
		vis.xiscale = -pspriteiscale
		vis.startfrac = width - 1
	else
		vis.xiscale = pspriteiscale
		vis.startfrac = 0
	end

	if vis.x1 > x1 then
		vis.startfrac += vis.xiscale * (vis.x1 - x1)
	end

	vis.patch = lump

	const playerPowers = State.viewplayer.powers
	local invisibility = playerPowers[Definitions.pw_invisibility]

	if invisibility == nil then
		invisibility = playerPowers[Definitions.pw_invisibility + 1]
	end

	invisibility = invisibility or 0

	if invisibility > 4 * 32 or bit32.btest(invisibility, 8) then
		vis.colormap = false
	elseif fixedcolormap then
		vis.colormap = fixedcolormap
	elseif bit32.btest(stateFrame, FULLBRIGHT) then
		vis.colormap = 0
	else
		vis.colormap = spritelights[MAXLIGHTSCALE - 1]
	end

	DrawVisSprite(vis, vis.x1, vis.x2)
end

-- DrawPlayerSprites
const function DrawPlayerSprites()
	const player = State.viewplayer
	const sector = player.mo.subsector.sector
	const lightnum = bit32.arshift(sector.lightlevel, LIGHTSEGSHIFT) + State.extralight

	if lightnum < 0 then
		spritelights = State.scalelight[0]
	elseif lightnum >= LIGHTLEVELS then
		spritelights = State.scalelight[LIGHTLEVELS - 1]
	else
		spritelights = State.scalelight[lightnum]
	end

	mfloorclip = screenheightarray
	mceilingclip = negonearray
	mfloorclipbase = 0
	mceilingclipbase = 0

	for index = 0, NUMPSPRITES - 1 do
		local psp = player.psprites[index]

		if psp == nil then
			psp = player.psprites[index + 1]
		elseif psp.state then
			DrawPlayerSprite(psp)
		end
	end
end

-- SortVisSprites
const function SortVisSprites()
	const count = visspriteCount

	if count == 0 then
		sortedSpriteCount = 0
		return
	end

	local maxScale = 0
	const sprites = vissprites
	local seedSpriteIndex = 1
	const lastOrderOffset = count * 2 - 2

	for writeOffset = 0, lastOrderOffset, 2 do
		buffer.writeu16(sortedSpriteIndices, writeOffset, seedSpriteIndex)

		const scale = sprites[seedSpriteIndex].scale

		if scale > maxScale then
			maxScale = scale
		end

		seedSpriteIndex += 1
	end

	sortedSpriteCount = count

	if count > 1 and maxScale ~= 0 then
		local source = sortedSpriteIndices
		local target = sortedSpriteScratch
		const passCount = 4 - bit32.countlz(maxScale) // 8

		for shift = 0, (passCount - 1) * 8, 8 do
			buffer.fill(spriteSortCounts, 0, 0)

			for orderOffset = 0, lastOrderOffset, 2 do
				const countOffset = bit32.band(bit32.rshift(sprites[buffer.readu16(source, orderOffset)].scale, shift), 0xFF) * 4
				buffer.writeu32(spriteSortCounts, countOffset, buffer.readu32(spriteSortCounts, countOffset) + 1)
			end

			local writeOffset = 0

			for countOffset = 0, 255 * 4, 4 do
				const bucketCount = buffer.readu32(spriteSortCounts, countOffset) * 2
				buffer.writeu32(spriteSortCounts, countOffset, writeOffset)
				writeOffset += bucketCount
			end

			for orderOffset = 0, lastOrderOffset, 2 do
				const spriteIndex = buffer.readu16(source, orderOffset)
				const countOffset = bit32.band(bit32.rshift(sprites[spriteIndex].scale, shift), 0xFF) * 4
				const targetOffset = buffer.readu32(spriteSortCounts, countOffset)
				buffer.writeu16(target, targetOffset, spriteIndex)
				buffer.writeu32(spriteSortCounts, countOffset, targetOffset + 2)
			end

			source, target = target, source
		end

		sortedSpriteIndices, sortedSpriteScratch = source, target
	end
end

-- DrawSprite
const function DrawSprite(spr: VisSprite)
	const drawSegIndex = BspGetDrawSegIndex()
	const sprX1 = spr.x1
	const sprX2 = spr.x2
	const sprScale = spr.scale
	const sprGX = spr.gx
	const sprGY = spr.gy
	const sprGZ = spr.gz
	const sprGZT = spr.gzt
	const clipStartOffset = sprX1 * 4
	const clipEndOffset = sprX2 * 4
	const clipByteCount = clipEndOffset - clipStartOffset + 4
	const clipBot = clipbot
	const clipTop = cliptop
	const noClip = CLIP

	buffer.copy(clipBot, clipStartOffset, nocliparray, clipStartOffset, clipByteCount)
	buffer.copy(clipTop, clipStartOffset, nocliparray, clipStartOffset, clipByteCount)

	for drawSegOffset = (drawSegIndex - 1) * 4, 4, -4 do
		const index = drawSegOffset // 4
		const x1 = buffer.readi32(drawsegX1, drawSegOffset)
		const x2 = buffer.readi32(drawsegX2, drawSegOffset)
		local silhouette = buffer.readi32(drawsegSilhouette, drawSegOffset)
		const maskedColumns = drawsegMaskedTextureCol[index]

		if x1 > sprX2
			or x2 < sprX1
			or (silhouette == 0 and not maskedColumns) then
			continue
		end

		const r1 = if x1 < sprX1 then sprX1 else x1
		const r2 = if x2 > sprX2 then sprX2 else x2
		const x1Offset = x1 * 4
		const r1Offset = r1 * 4
		const r2Offset = r2 * 4
		const sourceStartOffset = r1Offset - x1Offset
		local lowscale
		local scale
		const scale1 = buffer.readi32(drawsegScale1, drawSegOffset)
		const scale2 = buffer.readi32(drawsegScale2, drawSegOffset)

		if scale1 > scale2 then
			lowscale = scale2
			scale = scale1
		else
			lowscale = scale1
			scale = scale2
		end

		if scale < sprScale or (lowscale < sprScale and PointOnSegSide(sprGX, sprGY, drawsegCurline[index]) == 0) then
			if maskedColumns then
				SegsRenderMaskedSegRange(index, r1, r2)
			end

			continue
		end

		const bottomSilHeight = buffer.readi32(drawsegBSilHeight, drawSegOffset)
		const topSilHeight = buffer.readi32(drawsegTSilHeight, drawSegOffset)

		if sprGZ >= bottomSilHeight then
			silhouette = bit32.band(silhouette, NOT_SIL_BOTTOM)
		end

		if sprGZT <= topSilHeight then
			silhouette = bit32.band(silhouette, NOT_SIL_TOP)
		end

		if silhouette == Segs.SIL_BOTTOM then
			const sprbottomclip = drawsegSprBottomClip[index]
			local sourceOffset = sourceStartOffset

			for clipOffset = r1Offset, r2Offset, 4 do
				if buffer.readi32(clipBot, clipOffset) == noClip then
					buffer.writei32(clipBot, clipOffset, buffer.readi32(sprbottomclip, sourceOffset))
				end

				sourceOffset += 4
			end
		elseif silhouette == Segs.SIL_TOP then
			const sprtopclip = drawsegSprTopClip[index]
			local sourceOffset = sourceStartOffset

			for clipOffset = r1Offset, r2Offset, 4 do
				if buffer.readi32(clipTop, clipOffset) == noClip then
					buffer.writei32(clipTop, clipOffset, buffer.readi32(sprtopclip, sourceOffset))
				end

				sourceOffset += 4
			end
		elseif silhouette == Segs.SIL_BOTH then
			const sprbottomclip = drawsegSprBottomClip[index]
			const sprtopclip = drawsegSprTopClip[index]
			local sourceOffset = sourceStartOffset

			for clipOffset = r1Offset, r2Offset, 4 do
				if buffer.readi32(clipBot, clipOffset) == noClip then
					buffer.writei32(clipBot, clipOffset, buffer.readi32(sprbottomclip, sourceOffset))
				end

				if buffer.readi32(clipTop, clipOffset) == noClip then
					buffer.writei32(clipTop, clipOffset, buffer.readi32(sprtopclip, sourceOffset))
				end

				sourceOffset += 4
			end
		end
	end

	const viewheight = State.viewheight

	for clipOffset = clipStartOffset, clipEndOffset, 4 do
		if buffer.readi32(clipBot, clipOffset) == noClip then
			buffer.writei32(clipBot, clipOffset, viewheight)
		end

		if buffer.readi32(clipTop, clipOffset) == noClip then
			buffer.writei32(clipTop, clipOffset, -1)
		end
	end

	mfloorclip = clipBot
	mceilingclip = clipTop
	mfloorclipbase = 0
	mceilingclipbase = 0
	DrawVisSprite(spr, sprX1, sprX2)
end

-- DrawMasked
const function DrawMasked()
	const drawSegIndex = BspGetDrawSegIndex()

	SortVisSprites()

	const spriteCount = sortedSpriteCount

	for readOffset = 0, spriteCount * 2 - 2, 2 do
		DrawSprite(vissprites[buffer.readu16(sortedSpriteIndices, readOffset)])
	end

	for drawSegOffset = (drawSegIndex - 1) * 4, 4, -4 do
		const index = drawSegOffset // 4
		const maskedColumns = drawsegMaskedTextureCol[index]

		if maskedColumns then
			SegsRenderMaskedSegRange(
				index,
				buffer.readi32(drawsegX1, drawSegOffset),
				buffer.readi32(drawsegX2, drawSegOffset)
			)
		end
	end

	if State.viewangleoffset == 0 then
		DrawPlayerSprites()
	end
end

const function Install()
	UpdateViewClipArrays()
	Segs.Install()
	Runtime.addSprites = AddSprites
	SpriteState.negonearray = negonearray
	SpriteState.screenheightarray = screenheightarray
	SpriteState.maskedColumnDrawer = DrawMaskedSegColumn
end

Reset()

return {
	Reset = Reset,
	Install = Install,
	UpdateViewClipArrays = UpdateViewClipArrays,

	InitSprites = InitSprites,
	ClearSprites = ClearSprites,
	DrawMasked = DrawMasked,
}
