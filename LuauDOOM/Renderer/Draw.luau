--!native
--!optimize 2

-- Port of r_draw.c, r_draw.h
-- The actual span/column drawing functions.
-- Here find the main potential for optimization,
--  e.g. inline assembly, different algorithms.

const Definitions = require("../Engine/Definitions")
const State = require("./State")
const Video = require("../System/Video")
const Zone = require("../System/Zone")
const Wad = require("../System/Wad")

const DrawPatchRender = Video.DrawPatchRender
const CacheLumpName = Wad.CacheLumpName
const CACHE = Zone.CACHE

-- status bar height at bottom of screen
const SBARHEIGHT = 32

const FUZZTABLE = 50
const FRACBITS = 16
const COLUMN_HEIGHT_MASK = 127
const FUZZ_COLORMAP_OFFSET = 6 * 256
const LOW_DETAIL_REPEAT = 257
const FUZZSIGNS = {
	[0] = 1, -1, 1, -1, 1, 1, -1,
	1, 1, -1, 1, 1, 1, -1,
	1, 1, 1, -1, -1, -1, -1,
	1, -1, -1, 1, 1, 1, 1, -1,
	1, -1, 1, 1, -1, -1, 1,
	1, -1, -1, -1, -1, 1, 1,
	1, 1, -1, 1, 1, -1, 1,
}

const EMPTY_BUFFER = buffer.create(0)

-- All drawing to the view buffer is accomplished in this file.
-- The other refresh files only know about coordinates,
--  not the architecture of the frame buffer.
-- This Luau port stores row/column lookup offsets instead of raw pointers.

local viewimage = EMPTY_BUFFER
local screen0 = EMPTY_BUFFER
local screen1 = EMPTY_BUFFER
local ylookup = EMPTY_BUFFER
local columnofs = EMPTY_BUFFER
local markRect = Video.MarkRect
local gamemode = Definitions.indetermined
local screen0Size = 0
local screen1Size = 0
local viewimageSize = 0
local drawRenderWidth = Video.Width
local drawCentery = State.centery
local drawViewHeight = State.viewheight
local drawGameplayAvailableHeight = Video.Height - Video.ViewportHeight * SBARHEIGHT // Video.LogicalHeight

-- DrawColumn
-- Source is the top of the column to scale.
local dc_colormap = EMPTY_BUFFER
local dc_colormap_offset = 0
local dc_x = 0
local dc_yl = 0
local dc_yh = 0
local dc_iscale = 0
local dc_texturemid = 0

-- first pixel in a column (possibly virtual)
local dc_source = EMPTY_BUFFER
local dc_source_offset = 0

local ds_y = 0
local ds_x1 = 0
local ds_x2 = 0

local ds_colormap = EMPTY_BUFFER
local ds_colormap_offset = 0

local ds_xfrac = 0
local ds_yfrac = 0
local ds_xstep = 0
local ds_ystep = 0

-- start of a 64*64 tile image
local ds_source = EMPTY_BUFFER
local ds_source_offset = 0

local dc_translation = EMPTY_BUFFER
local dc_translation_offset = 0
local translationtables = EMPTY_BUFFER
local translationtablesAllocated = false

local fuzzoffset = EMPTY_BUFFER

local fuzzpos = 0
local fuzzBorder = 1

const function ResolveScreenBuffer(index: number): buffer
	const image = if index == 0 then screen0 else screen1
	const screenBufferSize = Video.ScreenSize
	const cachedSize = if index == 0 then screen0Size else screen1Size

	if cachedSize == screenBufferSize then
		return image
	end

	const adopted = Video.GetScreenBuffer(index)

	if index == 0 then
		screen0 = adopted
		screen0Size = screenBufferSize
	else
		screen1 = adopted
		screen1Size = screenBufferSize
	end

	return adopted
end

const function RebuildFuzzOffsets()
	const renderWidth = Video.Width
	const renderHeight = Video.Height
	const logicalScaleY = renderHeight // Video.LogicalHeight
	const offsetCount = FUZZTABLE + renderHeight
	const offsets = buffer.create(offsetCount * 4)
	local index = 0
	const offsetByteEnd = offsetCount * 4 - 4
	fuzzBorder = logicalScaleY

	for byteOffset = 0, offsetByteEnd, 4 do
		buffer.writei32(offsets, byteOffset, FUZZSIGNS[index % FUZZTABLE] * renderWidth * logicalScaleY)
		index += 1
	end

	fuzzoffset = offsets
end

const function Reset()
	if translationtablesAllocated then
		Zone.Free(translationtables)
	end

	viewimage = EMPTY_BUFFER
	screen0 = EMPTY_BUFFER
	screen1 = EMPTY_BUFFER
	ylookup = EMPTY_BUFFER
	columnofs = EMPTY_BUFFER
	markRect = Video.MarkRect
	gamemode = Definitions.indetermined
	screen0Size = 0
	screen1Size = 0
	viewimageSize = 0
	drawRenderWidth = Video.Width
	drawCentery = State.centery
	drawViewHeight = State.viewheight
	drawGameplayAvailableHeight = Video.Height - Video.ViewportHeight * SBARHEIGHT // Video.LogicalHeight

	dc_colormap = EMPTY_BUFFER
	dc_colormap_offset = 0
	dc_x = 0
	dc_yl = 0
	dc_yh = 0
	dc_iscale = 0
	dc_texturemid = 0
	dc_source = EMPTY_BUFFER
	dc_source_offset = 0
	ds_y = 0
	ds_x1 = 0
	ds_x2 = 0
	ds_colormap = EMPTY_BUFFER
	ds_colormap_offset = 0
	ds_xfrac = 0
	ds_yfrac = 0
	ds_xstep = 0
	ds_ystep = 0
	ds_source = EMPTY_BUFFER
	ds_source_offset = 0
	dc_translation = EMPTY_BUFFER
	dc_translation_offset = 0
	translationtables = EMPTY_BUFFER
	translationtablesAllocated = false

	fuzzpos = 0
	RebuildFuzzOffsets()
end

const function SetColumnPosition(x: number)
	dc_x = x
end

const function SetColumnScale(iscale: number)
	dc_iscale = iscale
end

const function SetColumnRenderBase(colormap: buffer, colormapOffset: number, x: number, iscale: number)
	dc_colormap = colormap
	dc_colormap_offset = colormapOffset
	dc_x = x
	dc_iscale = iscale
end

const function SetColumnSourceSetup(iscale: number, colormap: buffer, colormapOffset: number, texturemid: number, source: buffer, sourceOffset: number)
	dc_iscale = iscale
	dc_colormap = colormap
	dc_colormap_offset = colormapOffset
	dc_texturemid = texturemid
	dc_source = source
	dc_source_offset = sourceOffset
end

const function SetColumnTextureSource(yl: number, yh: number, texturemid: number, source: buffer, sourceOffset: number)
	dc_yl = yl
	dc_yh = yh
	dc_texturemid = texturemid
	dc_source = source
	dc_source_offset = sourceOffset
end

const function SetColumnBoundsPositionSource(yl: number, yh: number, x: number, sourceOffset: number)
	dc_yl = yl
	dc_yh = yh
	dc_x = x
	dc_source_offset = sourceOffset
end

const function SetColumnTranslation(translation: buffer, offset: number)
	dc_translation = translation
	dc_translation_offset = offset
end

const function SetSpanDraw(
	y: number,
	x1: number,
	x2: number,
	colormap: buffer,
	colormapOffset: number,
	xfrac: number,
	yfrac: number,
	xstep: number,
	ystep: number
)
	ds_y = y
	ds_x1 = x1
	ds_x2 = x2
	ds_colormap = colormap
	ds_colormap_offset = colormapOffset
	ds_xfrac = xfrac
	ds_yfrac = yfrac
	ds_xstep = xstep
	ds_ystep = ystep
end

const function SetSpanSource(source: buffer, offset: number)
	ds_source = source
	ds_source_offset = offset
end

-- A column is a vertical slice/span from a wall texture that,
--  given the DOOM style restrictions on the view orientation,
--  will always have constant z depth.
-- Thus a special case loop for very fast rendering can
--  be used. It has also been used with Wolfenstein 3D.
const function DrawColumn()
	const count = dc_yh - dc_yl

	-- Zero length, column does not exceed a pixel.
	if count < 0 then
		return
	end

	const image = viewimage

	-- Framebuffer destination address.
	-- Use ylookup LUT to avoid multiply with ScreenWidth.
	-- Use columnofs LUT for subwindows?
	const dest = buffer.readi32(ylookup, dc_yl * 4) + buffer.readi32(columnofs, dc_x * 4)
	const renderWidth = drawRenderWidth

	-- Determine scaling,
	--  which is the only mapping to be done.
	const fracstep = dc_iscale
	const source = dc_source
	const sourceOffset = dc_source_offset
	const colormap = dc_colormap
	const colormapOffset = dc_colormap_offset
	const centery = drawCentery
	local frac = dc_texturemid + (dc_yl - centery) * fracstep

	for destOffset = dest, dest + count * renderWidth, renderWidth do
		buffer.writeu8(image, destOffset, buffer.readu8(
			colormap,
			colormapOffset + buffer.readu8(source, sourceOffset + bit32.band(bit32.rshift(frac, FRACBITS), COLUMN_HEIGHT_MASK))
		))

		frac += fracstep
	end
end

const function DrawColumnLow()
	const count = dc_yh - dc_yl

	if count < 0 then
		return
	end

	const image = viewimage

	const rowOffset = buffer.readi32(ylookup, dc_yl * 4)
	const dest = rowOffset + buffer.readi32(columnofs, dc_x * 8)
	const renderWidth = drawRenderWidth
	const fracstep = dc_iscale
	const source = dc_source
	const sourceOffset = dc_source_offset
	const colormap = dc_colormap
	const colormapOffset = dc_colormap_offset
	const centery = drawCentery
	local frac = dc_texturemid + (dc_yl - centery) * fracstep

	for destOffset = dest, dest + count * renderWidth, renderWidth do
		buffer.writeu16(image, destOffset,
			buffer.readu8(colormap, colormapOffset + buffer.readu8(source, sourceOffset + bit32.band(bit32.rshift(frac, FRACBITS), COLUMN_HEIGHT_MASK))) * LOW_DETAIL_REPEAT
		)

		frac += fracstep
	end
end

-- Framebuffer postprocessing.
-- Creates a fuzzy image by copying pixels
--  from adjacent ones to left and right.
-- Used with an all black colormap, this
--  could create the SHADOW effect,
--  i.e. spectres and invisible players.
const function DrawFuzzColumn()
	const border = fuzzBorder
	const highBorder = drawViewHeight - 1 - border

	-- The fuzz offset samples one scaled row above or below the current pixel.
	if dc_yl < border then
		dc_yl = border
	end

	if dc_yh > highBorder then
		dc_yh = highBorder
	end

	const yl = dc_yl
	const yh = dc_yh
	const count = yh - yl

	if count < 0 then
		return
	end

	const image = viewimage

	const dest = buffer.readi32(ylookup, yl * 4) + buffer.readi32(columnofs, dc_x * 4)
	const renderWidth = drawRenderWidth
	const colormaps = State.colormaps
	const fuzz = fuzzoffset
	local fuzzByteOffset = fuzzpos * 4

	for destOffset = dest, dest + count * renderWidth, renderWidth do
		buffer.writeu8(image, destOffset, buffer.readu8(
			colormaps, FUZZ_COLORMAP_OFFSET + buffer.readu8(image, destOffset + buffer.readi32(fuzz, fuzzByteOffset))
		))

		fuzzByteOffset += 4
	end

	fuzzpos = (fuzzpos + count + 1) % FUZZTABLE
end

const function DrawFuzzColumnLow()
	const border = fuzzBorder
	const highBorder = drawViewHeight - 1 - border

	if dc_yl < border then
		dc_yl = border
	end

	if dc_yh > highBorder then
		dc_yh = highBorder
	end

	const yl = dc_yl
	const yh = dc_yh
	const count = yh - yl

	if count < 0 then
		return
	end

	const image = viewimage

	const rowOffset = buffer.readi32(ylookup, yl * 4)
	const dest = rowOffset + buffer.readi32(columnofs, dc_x * 8)
	const renderWidth = drawRenderWidth
	const colormaps = State.colormaps
	const fuzz = fuzzoffset
	local fuzzByteOffset = fuzzpos * 4

	for destOffset = dest, dest + count * renderWidth, renderWidth do
		buffer.writeu16(image, destOffset, buffer.readu8(colormaps,
			FUZZ_COLORMAP_OFFSET + buffer.readu8(image, destOffset + buffer.readi32(fuzz, fuzzByteOffset))
		) * LOW_DETAIL_REPEAT)

		fuzzByteOffset += 4
	end

	fuzzpos = (fuzzpos + count + 1) % FUZZTABLE
end

-- R_DrawTranslatedColumn
-- Used to draw player sprites
--  with the green colorramp mapped to others.
const function DrawTranslatedColumn()
	const count = dc_yh - dc_yl

	if count < 0 then
		return
	end

	const image = viewimage

	const dest = buffer.readi32(ylookup, dc_yl * 4) + buffer.readi32(columnofs, dc_x * 4)
	const renderWidth = drawRenderWidth
	const fracstep = dc_iscale
	const source = dc_source
	const sourceOffset = dc_source_offset
	const colormap = dc_colormap
	const colormapOffset = dc_colormap_offset
	const translation = dc_translation
	const translationOffset = dc_translation_offset
	const centery = drawCentery
	local frac = dc_texturemid + (dc_yl - centery) * fracstep

	for destOffset = dest, dest + count * renderWidth, renderWidth do
		buffer.writeu8(image, destOffset, buffer.readu8(
			colormap,
			colormapOffset + buffer.readu8(translation, translationOffset + buffer.readu8(source, sourceOffset + bit32.arshift(frac, FRACBITS)))
		))

		frac += fracstep
	end
end

const function DrawTranslatedColumnLow()
	const count = dc_yh - dc_yl

	if count < 0 then
		return
	end

	const image = viewimage

	const rowOffset = buffer.readi32(ylookup, dc_yl * 4)
	const dest = rowOffset + buffer.readi32(columnofs, dc_x * 8)
	const renderWidth = drawRenderWidth
	const fracstep = dc_iscale
	const source = dc_source
	const sourceOffset = dc_source_offset
	const colormap = dc_colormap
	const colormapOffset = dc_colormap_offset
	const translation = dc_translation
	const translationOffset = dc_translation_offset
	const centery = drawCentery
	local frac = dc_texturemid + (dc_yl - centery) * fracstep

	for destOffset = dest, dest + count * renderWidth, renderWidth do
		buffer.writeu16(image, destOffset, buffer.readu8(
			colormap,
			colormapOffset + buffer.readu8(translation, translationOffset + buffer.readu8(source, sourceOffset + bit32.arshift(frac, FRACBITS)))
		) * LOW_DETAIL_REPEAT)

		frac += fracstep
	end
end

-- DrawSpan
-- With DOOM style restrictions on view orientation,
--  the floors and ceilings consist of horizontal slices
--  or spans with constant z depth.
const function DrawSpan()
	const image = viewimage
	local xfrac = ds_xfrac
	local yfrac = ds_yfrac
	const colormap = ds_colormap
	const source = ds_source
	const colormapOffset = ds_colormap_offset
	const sourceOffset = ds_source_offset
	const xstep = ds_xstep
	const ystep = ds_ystep
	const dest = buffer.readi32(ylookup, ds_y * 4) + buffer.readi32(columnofs, ds_x1 * 4)
	const count = ds_x2 - ds_x1

	for destOffset = dest, dest + count do
		buffer.writeu8(image, destOffset, buffer.readu8(colormap, colormapOffset
			+ buffer.readu8(source, sourceOffset
			+ bit32.band(bit32.rshift(yfrac, 10), 4032)
			+ bit32.band(bit32.rshift(xfrac, 16), 63)))
		)

		xfrac += xstep
		yfrac += ystep
	end
end

const function DrawSpanLow()
	const image = viewimage
	local xfrac = ds_xfrac
	local yfrac = ds_yfrac
	const colormap = ds_colormap
	const source = ds_source
	const colormapOffset = ds_colormap_offset
	const sourceOffset = ds_source_offset
	const xstep = ds_xstep
	const ystep = ds_ystep
	const dest = buffer.readi32(ylookup, ds_y * 4) + buffer.readi32(columnofs, ds_x1 * 8)
	const count = ds_x2 - ds_x1

	for destOffset = dest, dest + count * 2, 2 do
		buffer.writeu16(image, destOffset, buffer.readu8(colormap, colormapOffset
			+ buffer.readu8(source, sourceOffset
			+ bit32.band(bit32.rshift(yfrac, 10), 4032)
			+ bit32.band(bit32.rshift(xfrac, 16), 63))
		) * LOW_DETAIL_REPEAT)
		
		xfrac += xstep
		yfrac += ystep
	end
end

-- R_InitBuffer
-- Creats lookup tables that avoid
--  multiplies and other hazzles
--  for getting the framebuffer address
--  of a pixel to draw.
const function InitBuffer(width: number, height: number)
	const renderWidth = Video.Width

	drawRenderWidth = renderWidth
	drawCentery = State.centery
	drawViewHeight = height
	drawGameplayAvailableHeight = Video.Height - Video.ViewportHeight * SBARHEIGHT // Video.LogicalHeight

	columnofs = buffer.create(width * 4)
	ylookup = buffer.create(height * 4)
	State.scaledviewwidth = width
	State.viewheight = height

	-- Handle resize,
	--  e.g. smaller view windows
	--  with border and/or status bar.
	State.viewwindowx = (renderWidth - width) // 2
	const viewwindowx = State.viewwindowx

	-- Column offset. For windows.
	const widthByteEnd = width * 4 - 4
	local columnOffset = viewwindowx

	for byteOffset = 0, widthByteEnd, 4 do
		buffer.writei32(columnofs, byteOffset, columnOffset)
		columnOffset += 1
	end

	-- Same with base row offset.
	if width == renderWidth then
		State.viewwindowy = 0
	else
		State.viewwindowy = (drawGameplayAvailableHeight - height) // 2
	end

	-- Precalculate all row offsets.
	const viewwindowy = State.viewwindowy
	local rowOffset = viewwindowy * renderWidth
	const heightByteEnd = height * 4 - 4

	for byteOffset = 0, heightByteEnd, 4 do
		buffer.writei32(ylookup, byteOffset, rowOffset)
		rowOffset += renderWidth
	end
end

-- InitTranslationTables
-- Creates the translation tables to map
--  the green color ramp to gray, brown, red.
-- Assumes a given structure of the PLAYPAL.
-- Could be read from a lump instead.
const function InitTranslationTables()
	if translationtablesAllocated then
		Zone.Free(translationtables)
	end

	translationtables = Zone.Malloc(256 * 3, Zone.STATIC)
	translationtablesAllocated = true

	-- translate just the 16 green colors
	for index = 0, 255 do
		if index >= 0x70 and index <= 0x7F then
			const lowNibble = bit32.band(index, 0xF)
			-- map green ramp to gray, brown, red
			buffer.writeu8(translationtables, index, 0x60 + lowNibble)
			buffer.writeu8(translationtables, index + 256, 0x40 + lowNibble)
			buffer.writeu8(translationtables, index + 512, 0x20 + lowNibble)
		else
			-- Keep all other colors as is.
			buffer.writeu8(translationtables, index, index)
			buffer.writeu8(translationtables, index + 256, index)
			buffer.writeu8(translationtables, index + 512, index)
		end
	end

	dc_translation = translationtables
	dc_translation_offset = 0
end

const function SetViewImage(image: buffer)
	viewimage = image
	screen0 = image
	const screenSize = Video.ScreenSize
	viewimageSize = screenSize
	screen0Size = screenSize
	Video.SetScreenBuffer(0, image)
end

const function GetViewImage(): buffer
	if viewimageSize == Video.ScreenSize then
		return viewimage
	end

	viewimage = ResolveScreenBuffer(0)
	viewimageSize = screen0Size
	return viewimage
end

const function SetScreenBuffer(index: number, image: buffer)
	Video.SetScreenBuffer(index, image)

	if index == 0 then
		screen0 = image
		viewimage = image
		screen0Size = Video.ScreenSize
		viewimageSize = screen0Size
	elseif index == 1 then
		screen1 = image
		screen1Size = Video.ScreenSize
	end
end

const function GetScreenBuffer(index: number): buffer
	return ResolveScreenBuffer(index)
end

-- Copy a screen buffer.
const function VideoErase(ofs: number, count: number)
	buffer.copy(ResolveScreenBuffer(0), ofs, ResolveScreenBuffer(1), ofs, count)
end

-- DrawViewBorder
-- Draws the border around the view
--  for different size windows?
const function DrawViewBorder()
	const renderWidth = Video.Width
	const gameplayHeight = drawGameplayAvailableHeight

	if State.scaledviewwidth == renderWidth then
		return
	end

	const frontscreen = ResolveScreenBuffer(0)
	const backscreen = ResolveScreenBuffer(1)
	const top = (gameplayHeight - State.viewheight) // 2
	local side = (renderWidth - State.scaledviewwidth) // 2

	buffer.copy(frontscreen, 0, backscreen, 0, top * renderWidth + side)

	local ofs = (State.viewheight + top) * renderWidth - side
	buffer.copy(frontscreen, ofs, backscreen, ofs, top * renderWidth + side)

	ofs = top * renderWidth + renderWidth - side
	side *= 2

	for sideOffset = ofs, ofs + (State.viewheight - 2) * renderWidth, renderWidth do
		buffer.copy(frontscreen, sideOffset, backscreen, sideOffset, side)
	end

	markRect(0, 0, renderWidth, gameplayHeight)
end

const function FillBackScreen()
	const renderWidth = Video.Width
	const gameplayHeight = drawGameplayAvailableHeight

	if State.scaledviewwidth == renderWidth then
		return
	end

	const backscreen = ResolveScreenBuffer(1)
	const scaledviewwidth = State.scaledviewwidth
	const viewwindowx = State.viewwindowx
	const viewwindowy = State.viewwindowy
	const viewheight = State.viewheight

	const name = if gamemode == Definitions.commercial then "GRNROCK" else "FLOOR7_2"
	const src = CacheLumpName(name, CACHE)
	const topPatch = CacheLumpName("brdr_t", CACHE)
	const bottomPatch = CacheLumpName("brdr_b", CACHE)
	const leftPatch = CacheLumpName("brdr_l", CACHE)
	const rightPatch = CacheLumpName("brdr_r", CACHE)
	const topLeftPatch = CacheLumpName("brdr_tl", CACHE)
	const topRightPatch = CacheLumpName("brdr_tr", CACHE)
	const bottomLeftPatch = CacheLumpName("brdr_bl", CACHE)
	const bottomRightPatch = CacheLumpName("brdr_br", CACHE)

	local srcOffset = 0
	const tileRemainder = bit32.band(renderWidth, 63)
	const wholeTiles = renderWidth // 64
	const wholeTileBytes = wholeTiles * 64

	for destRowOffset = 0, gameplayHeight * renderWidth - renderWidth, renderWidth do
		for tileOffset = 0, wholeTileBytes - 64, 64 do
			buffer.copy(backscreen, destRowOffset + tileOffset, src, srcOffset, 64)
		end

		if tileRemainder ~= 0 then
			buffer.copy(backscreen, destRowOffset + wholeTileBytes, src, srcOffset, tileRemainder)
		end

		srcOffset += 64
		if srcOffset == 4096 then
			srcOffset = 0
		end
	end

	for x = 0, scaledviewwidth - 1, 8 do
		DrawPatchRender(viewwindowx + x, viewwindowy - 8, 1, topPatch)
	end

	for x = 0, scaledviewwidth - 1, 8 do
		DrawPatchRender(viewwindowx + x, viewwindowy + viewheight, 1, bottomPatch)
	end

	for y = 0, viewheight - 1, 8 do
		DrawPatchRender(viewwindowx - 8, viewwindowy + y, 1, leftPatch)
	end

	for y = 0, viewheight - 1, 8 do
		DrawPatchRender(viewwindowx + scaledviewwidth, viewwindowy + y, 1, rightPatch)
	end

	DrawPatchRender(viewwindowx - 8, viewwindowy - 8, 1, topLeftPatch)
	DrawPatchRender(
		viewwindowx + scaledviewwidth,
		viewwindowy - 8,
		1,
		topRightPatch
	)
	DrawPatchRender(
		viewwindowx - 8,
		viewwindowy + viewheight,
		1,
		bottomLeftPatch
	)
	DrawPatchRender(
		viewwindowx + scaledviewwidth,
		viewwindowy + viewheight,
		1,
		bottomRightPatch
	)
end

Reset()

const function SetGameMode(value: number)
	gamemode = value
end

const function GetTranslationTables(): buffer
	return translationtables
end

return {
	SBARHEIGHT = SBARHEIGHT,

	Reset = Reset,
	SetColumnPosition = SetColumnPosition,
	SetColumnScale = SetColumnScale,
	SetColumnRenderBase = SetColumnRenderBase,
	SetColumnSourceSetup = SetColumnSourceSetup,
	SetColumnTextureSource = SetColumnTextureSource,
	SetColumnBoundsPositionSource = SetColumnBoundsPositionSource,
	SetColumnTranslation = SetColumnTranslation,
	SetSpanDraw = SetSpanDraw,
	SetSpanSource = SetSpanSource,
	InitBuffer = InitBuffer,
	InitTranslationTables = InitTranslationTables,
	SetViewImage = SetViewImage,
	GetViewImage = GetViewImage,
	SetScreenBuffer = SetScreenBuffer,
	GetScreenBuffer = GetScreenBuffer,

	SetGameMode = SetGameMode,
	GetTranslationTables = GetTranslationTables,

	DrawColumn = DrawColumn,
	DrawColumnLow = DrawColumnLow,
	DrawFuzzColumn = DrawFuzzColumn,
	DrawFuzzColumnLow = DrawFuzzColumnLow,
	DrawTranslatedColumn = DrawTranslatedColumn,
	DrawTranslatedColumnLow = DrawTranslatedColumnLow,
	DrawSpan = DrawSpan,
	DrawSpanLow = DrawSpanLow,
	VideoErase = VideoErase,
	FillBackScreen = FillBackScreen,
	DrawViewBorder = DrawViewBorder,
}
