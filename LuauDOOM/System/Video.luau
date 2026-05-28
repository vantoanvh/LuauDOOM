--!native
--!optimize 2

-- Port of v_video.c, v_video.h
-- Gamma correction LUT stuff.
-- Functions to draw patches (by post) directly to screen.
-- Functions to blit a block to the screen.

const Definitions = require("../Engine/Definitions")
const BoundingBox = require("../Miscellaneous/BoundingBox")
const VideoMode = require("./VideoMode")

const EMPTY_BUFFER = buffer.create(0)
const State = VideoMode.State
const MapLogicalRect = VideoMode.MapLogicalRect
const MapLogicalXRange = VideoMode.MapLogicalXRange
const MapLogicalYRange = VideoMode.MapLogicalYRange
const MapScreenRect = VideoMode.MapScreenRect
const MapScreenXRange = VideoMode.MapScreenXRange
const MapScreenYRange = VideoMode.MapScreenYRange

const function Warn(...: unknown)
	warn(...)
end

const screens = {
	[0] = EMPTY_BUFFER,
	[1] = EMPTY_BUFFER,
	[2] = EMPTY_BUFFER,
	[3] = EMPTY_BUFFER,
	[4] = EMPTY_BUFFER,
}

const dirtybox = BoundingBox.Create()
local exports
local Video

const function SyncExports()
	if exports == nil then
		return
	end

	exports.CENTERX = Video.CENTERX
	exports.CENTERY = Video.CENTERY
	exports.LogicalWidth = State.LogicalWidth
	exports.LogicalHeight = State.LogicalHeight
	exports.LogicalHalfWidth = State.LogicalHalfWidth
	exports.LogicalHalfHeight = State.LogicalHalfHeight
	exports.Width = State.Width
	exports.Height = State.Height
	exports.HalfWidth = State.HalfWidth
	exports.HalfHeight = State.HalfHeight
	exports.PixelCount = State.PixelCount
	exports.ScreenSize = State.PixelCount
	exports.ViewportX = State.ViewportX
	exports.ViewportY = State.ViewportY
	exports.ViewportWidth = State.ViewportWidth
	exports.ViewportHeight = State.ViewportHeight
end

const function CreateGammaRow(values: { number })
	const row = buffer.create(256)

	for index = 0, 255 do
		buffer.writeu8(row, index, values[index + 1])
	end

	return row
end

-- Now where did these came from?
const gammatable = {
	[0] = CreateGammaRow({
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
		33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
		49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64,
		65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
		81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96,
		97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
		113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128,
		128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143,
		144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159,
		160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
		176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191,
		192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207,
		208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223,
		224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
		240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255,
	}),
	[1] = CreateGammaRow({
		2, 4, 5, 7, 8, 10, 11, 12, 14, 15, 16, 18, 19, 20, 21, 23, 24, 25, 26, 27, 29, 30, 31,
		32, 33, 34, 36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 54, 55,
		56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 69, 70, 71, 72, 73, 74, 75, 76, 77,
		78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98,
		99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114,
		115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 129,
		130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145,
		146, 147, 148, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160,
		161, 162, 163, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
		175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 186, 187, 188, 189,
		190, 191, 192, 193, 194, 195, 196, 196, 197, 198, 199, 200, 201, 202, 203, 204,
		205, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 214, 215, 216, 217, 218,
		219, 220, 221, 222, 222, 223, 224, 225, 226, 227, 228, 229, 230, 230, 231, 232,
		233, 234, 235, 236, 237, 237, 238, 239, 240, 241, 242, 243, 244, 245, 245, 246,
		247, 248, 249, 250, 251, 252, 252, 253, 254, 255,
	}),
	[2] = CreateGammaRow({
		4, 7, 9, 11, 13, 15, 17, 19, 21, 22, 24, 26, 27, 29, 30, 32, 33, 35, 36, 38, 39, 40, 42,
		43, 45, 46, 47, 48, 50, 51, 52, 54, 55, 56, 57, 59, 60, 61, 62, 63, 65, 66, 67, 68, 69,
		70, 72, 73, 74, 75, 76, 77, 78, 79, 80, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
		94, 95, 96, 97, 98, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
		113, 114, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128,
		129, 130, 131, 132, 133, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144,
		144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 153, 154, 155, 156, 157, 158, 159,
		160, 160, 161, 162, 163, 164, 165, 166, 166, 167, 168, 169, 170, 171, 172, 172, 173,
		174, 175, 176, 177, 178, 178, 179, 180, 181, 182, 183, 183, 184, 185, 186, 187, 188,
		188, 189, 190, 191, 192, 193, 193, 194, 195, 196, 197, 197, 198, 199, 200, 201, 201,
		202, 203, 204, 205, 206, 206, 207, 208, 209, 210, 210, 211, 212, 213, 213, 214, 215,
		216, 217, 217, 218, 219, 220, 221, 221, 222, 223, 224, 224, 225, 226, 227, 228, 228,
		229, 230, 231, 231, 232, 233, 234, 235, 235, 236, 237, 238, 238, 239, 240, 241, 241,
		242, 243, 244, 244, 245, 246, 247, 247, 248, 249, 250, 251, 251, 252, 253, 254, 254,
		255,
	}),
	[3] = CreateGammaRow({
		8, 12, 16, 19, 22, 24, 27, 29, 31, 34, 36, 38, 40, 41, 43, 45, 47, 49, 50, 52, 53, 55,
		57, 58, 60, 61, 63, 64, 65, 67, 68, 70, 71, 72, 74, 75, 76, 77, 79, 80, 81, 82, 84, 85,
		86, 87, 88, 90, 91, 92, 93, 94, 95, 96, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107,
		108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124,
		125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 135, 136, 137, 138, 139, 140,
		141, 142, 143, 143, 144, 145, 146, 147, 148, 149, 150, 150, 151, 152, 153, 154, 155,
		155, 156, 157, 158, 159, 160, 160, 161, 162, 163, 164, 165, 165, 166, 167, 168, 169,
		169, 170, 171, 172, 173, 173, 174, 175, 176, 176, 177, 178, 179, 180, 180, 181, 182,
		183, 183, 184, 185, 186, 186, 187, 188, 189, 189, 190, 191, 192, 192, 193, 194, 195,
		195, 196, 197, 197, 198, 199, 200, 200, 201, 202, 202, 203, 204, 205, 205, 206, 207,
		207, 208, 209, 210, 210, 211, 212, 212, 213, 214, 214, 215, 216, 216, 217, 218, 219,
		219, 220, 221, 221, 222, 223, 223, 224, 225, 225, 226, 227, 227, 228, 229, 229, 230,
		231, 231, 232, 233, 233, 234, 235, 235, 236, 237, 237, 238, 238, 239, 240, 240, 241,
		242, 242, 243, 244, 244, 245, 246, 246, 247, 247, 248, 249, 249, 250, 251, 251, 252,
		253, 253, 254, 254, 255,
	}),
	[4] = CreateGammaRow({
		16, 23, 28, 32, 36, 39, 42, 45, 48, 50, 53, 55, 57, 60, 62, 64, 66, 68, 69, 71, 73, 75, 76,
		78, 80, 81, 83, 84, 86, 87, 89, 90, 92, 93, 94, 96, 97, 98, 100, 101, 102, 103, 105, 106,
		107, 108, 109, 110, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124,
		125, 126, 128, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141,
		142, 143, 143, 144, 145, 146, 147, 148, 149, 150, 150, 151, 152, 153, 154, 155, 155,
		156, 157, 158, 159, 159, 160, 161, 162, 163, 163, 164, 165, 166, 166, 167, 168, 169,
		169, 170, 171, 172, 172, 173, 174, 175, 175, 176, 177, 177, 178, 179, 180, 180, 181,
		182, 182, 183, 184, 184, 185, 186, 187, 187, 188, 189, 189, 190, 191, 191, 192, 193,
		193, 194, 195, 195, 196, 196, 197, 198, 198, 199, 200, 200, 201, 202, 202, 203, 203,
		204, 205, 205, 206, 207, 207, 208, 208, 209, 210, 210, 211, 211, 212, 213, 213, 214,
		214, 215, 216, 216, 217, 217, 218, 219, 219, 220, 220, 221, 221, 222, 223, 223, 224,
		224, 225, 225, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231, 232, 232, 233, 233,
		234, 234, 235, 235, 236, 236, 237, 237, 238, 239, 239, 240, 240, 241, 241, 242, 242,
		243, 243, 244, 244, 245, 245, 246, 246, 247, 247, 248, 248, 249, 249, 250, 250, 251,
		251, 252, 252, 253, 254, 254, 255, 255,
	}),
}

Video = {
	CENTERX = State.HalfWidth,
	CENTERY = State.HalfHeight,
	State = State,
	screens = screens,
	dirtybox = dirtybox,
	gammatable = gammatable,
	usegamma = 0,
}

const function GetScreenWidth(): number
	return State.Width
end

const function GetScreenHeight(): number
	return State.Height
end

const function GetScreenSize(): number
	return State.PixelCount
end

const function GetLogicalWidth(): number
	return State.LogicalWidth
end

const function GetLogicalHeight(): number
	return State.LogicalHeight
end

const function GetViewportX(): number
	return State.ViewportX
end

const function GetViewportY(): number
	return State.ViewportY
end

const function GetViewportWidth(): number
	return State.ViewportWidth
end

const function GetViewportHeight(): number
	return State.ViewportHeight
end

const function SetScreenBuffer(index: number, image: buffer)
	screens[index] = image
end

const function GetScreenBuffer(index: number): buffer
	return screens[index]
end

const function SetUseGamma(level: number)

	Video.usegamma = level
end

const function GetUseGamma(): number
	return Video.usegamma
end

const function ClearDirtyBox()
	BoundingBox.ClearBox(dirtybox)
end

-- MarkRect
const function MarkRectRender(x: number, y: number, width: number, height: number)
	BoundingBox.AddToBox(dirtybox, x, y)
	BoundingBox.AddToBox(dirtybox, x + width - 1, y + height - 1)
end

const function MarkRect(x: number, y: number, width: number, height: number)
	if State.Width == State.LogicalWidth and State.Height == State.LogicalHeight then
		MarkRectRender(x, y, width, height)
		return
	end

	const renderX, renderY, renderWidth, renderHeight = MapLogicalRect(x, y, width, height)
	MarkRectRender(renderX, renderY, renderWidth, renderHeight)
end

const function ClearScreen(scrn: number, color: number)
	const screen = screens[scrn]
	const screenSize = State.PixelCount

	buffer.fill(screen, 0, color, screenSize)

	if scrn == 0 then
		MarkRectRender(0, 0, State.Width, State.Height)
	end
end

-- CopyRect
const function CopyRect(
	srcx: number,
	srcy: number,
	srcscrn: number,
	width: number,
	height: number,
	destx: number,
	desty: number,
	destscrn: number
)
	const src = screens[srcscrn]
	const dest = screens[destscrn]

	const screenWidth = State.Width

	if State.Width == State.LogicalWidth and State.Height == State.LogicalHeight then
		MarkRectRender(destx, desty, width, height)

		for row = 0, height - 1 do
			const srcOffset = (srcy + row) * screenWidth + srcx
			const destOffset = (desty + row) * screenWidth + destx
			buffer.copy(dest, destOffset, src, srcOffset, width)
		end

		return
	end

	MarkRect(destx, desty, width, height)
	const srcRenderX0, srcRenderX1 = MapLogicalXRange(srcx, width)
	const destRenderX0, _destRenderX1 = MapLogicalXRange(destx, width)
	const renderWidth = srcRenderX1 - srcRenderX0

	for row = 0, height - 1 do
		const srcRenderY0, srcRenderY1 = MapLogicalYRange(srcy + row, 1)
		const destRenderY0, _destRenderY1 = MapLogicalYRange(desty + row, 1)

		for renderRow = 0, srcRenderY1 - srcRenderY0 - 1 do
			const srcOffset = (srcRenderY0 + renderRow) * screenWidth + srcRenderX0
			const destOffset = (destRenderY0 + renderRow) * screenWidth + destRenderX0
			buffer.copy(dest, destOffset, src, srcOffset, renderWidth)
		end
	end
end

const function DrawPatchColumns(x: number, y: number, scrn: number, patch: buffer, flipped: boolean, context: string)
	const width = buffer.readi16(patch, 0)
	const height = buffer.readi16(patch, 2)
	const leftoffset = buffer.readi16(patch, 4)
	const topoffset = buffer.readi16(patch, 6)

	y -= topoffset
	x -= leftoffset

	if Definitions.RANGECHECK then
		const logicalWidth = State.LogicalWidth
		const logicalHeight = State.LogicalHeight

		if x < 0
			or x + width > logicalWidth
			or y < 0
			or y + height > logicalHeight
			or scrn // 1 ~= scrn
			or scrn < 0
			or scrn > 4
		then
			if context == "DrawPatch" then
				Warn(`Patch at {x},{y} exceeds LFB`)
				Warn("DrawPatch: bad patch (ignored)")
				return
			end


			error(`Bad {context}`)
		end
	end

	const screen = screens[scrn]

	if scrn == 0 then
		MarkRect(x, y, width, height)
	end

	const screenWidth = State.Width

	if State.Width == State.LogicalWidth and State.Height == State.LogicalHeight then
		for col = 0, width - 1 do
			const sourceColumn = if flipped then width - 1 - col else col
			local columnOffset = buffer.readi32(patch, 8 + sourceColumn * 4)
			const renderX = x + col

			while true do
				const topdelta = buffer.readu8(patch, columnOffset)

				if topdelta == 0xFF then
					break
				end

				const count = buffer.readu8(patch, columnOffset + 1)
				local sourceOffset = columnOffset + 3
				local dest = (y + topdelta) * screenWidth + renderX

				for _ = 0, count - 1 do
					buffer.writeu8(screen, dest, buffer.readu8(patch, sourceOffset))
					sourceOffset += 1
					dest += screenWidth
				end

				columnOffset += count + 4
			end
		end

		return
	end

	for col = 0, width - 1 do
		const sourceColumn = if flipped then width - 1 - col else col
		local columnOffset = buffer.readi32(patch, 8 + sourceColumn * 4)
		const renderX0, renderX1 = MapLogicalXRange(x + col, 1)

		-- step through the posts in a column
		while true do
			const topdelta = buffer.readu8(patch, columnOffset)

			if topdelta == 0xFF then
				break
			end

			const count = buffer.readu8(patch, columnOffset + 1)
			const sourceOffset = columnOffset + 3

			for row = 0, count - 1 do
				const color = buffer.readu8(patch, sourceOffset + row)
				const renderY0, renderY1 = MapLogicalYRange(y + topdelta + row, 1)

				for renderY = renderY0, renderY1 - 1 do
					const destStart = renderY * screenWidth + renderX0

					for dest = destStart, destStart + renderX1 - renderX0 - 1 do
						buffer.writeu8(screen, dest, color)
					end
				end
			end

			columnOffset += count + 4
		end
	end
end

const function DrawPatchColumnsRender(x: number, y: number, scrn: number, patch: buffer, flipped: boolean, context: string)
	const width = buffer.readi16(patch, 0)
	const height = buffer.readi16(patch, 2)
	const leftoffset = buffer.readi16(patch, 4)
	const topoffset = buffer.readi16(patch, 6)

	y -= topoffset
	x -= leftoffset

	if Definitions.RANGECHECK then
		const screenWidth = State.Width
		const screenHeight = State.Height

		if x < 0
			or x + width > screenWidth
			or y < 0
			or y + height > screenHeight
			or scrn // 1 ~= scrn
			or scrn < 0
			or scrn > 4
		then
			error(`Bad {context}`)
		end
	end

	const screen = screens[scrn]

	if scrn == 0 then
		MarkRectRender(x, y, width, height)
	end

	const screenWidth = State.Width

	for col = 0, width - 1 do
		const sourceColumn = if flipped then width - 1 - col else col
		local columnOffset = buffer.readi32(patch, 8 + sourceColumn * 4)
		const renderX = x + col

		while true do
			const topdelta = buffer.readu8(patch, columnOffset)

			if topdelta == 0xFF then
				break
			end

			const count = buffer.readu8(patch, columnOffset + 1)
			local sourceOffset = columnOffset + 3
			local dest = (y + topdelta) * screenWidth + renderX

			for _ = 0, count - 1 do
				buffer.writeu8(screen, dest, buffer.readu8(patch, sourceOffset))
				sourceOffset += 1
				dest += screenWidth
			end

			columnOffset += count + 4
		end
	end
end

const function DrawPatchColumnsScreen(x: number, y: number, scrn: number, patch: buffer, flipped: boolean, context: string)
	const width = buffer.readi16(patch, 0)
	const height = buffer.readi16(patch, 2)
	const leftoffset = buffer.readi16(patch, 4)
	const topoffset = buffer.readi16(patch, 6)

	y -= topoffset
	x -= leftoffset

	if Definitions.RANGECHECK then
		const logicalWidth = State.LogicalWidth
		const logicalHeight = State.LogicalHeight

		if x < 0
			or x + width > logicalWidth
			or y < 0
			or y + height > logicalHeight
			or scrn // 1 ~= scrn
			or scrn < 0
			or scrn > 4
		then
			error(`Bad {context}`)
		end
	end

	const screen = screens[scrn]

	if scrn == 0 then
		const renderX, renderY, renderWidth, renderHeight = MapScreenRect(x, y, width, height)
		MarkRectRender(renderX, renderY, renderWidth, renderHeight)
	end

	const screenWidth = State.Width

	if State.Width == State.LogicalWidth and State.Height == State.LogicalHeight then
		for col = 0, width - 1 do
			const sourceColumn = if flipped then width - 1 - col else col
			local columnOffset = buffer.readi32(patch, 8 + sourceColumn * 4)
			const renderX = x + col

			while true do
				const topdelta = buffer.readu8(patch, columnOffset)

				if topdelta == 0xFF then
					break
				end

				const count = buffer.readu8(patch, columnOffset + 1)
				local sourceOffset = columnOffset + 3
				local dest = (y + topdelta) * screenWidth + renderX

				for _ = 0, count - 1 do
					buffer.writeu8(screen, dest, buffer.readu8(patch, sourceOffset))
					sourceOffset += 1
					dest += screenWidth
				end

				columnOffset += count + 4
			end
		end

		return
	end

	for col = 0, width - 1 do
		const sourceColumn = if flipped then width - 1 - col else col
		local columnOffset = buffer.readi32(patch, 8 + sourceColumn * 4)
		const renderX0, renderX1 = MapScreenXRange(x + col, 1)

		while true do
			const topdelta = buffer.readu8(patch, columnOffset)

			if topdelta == 0xFF then
				break
			end

			const count = buffer.readu8(patch, columnOffset + 1)
			const sourceOffset = columnOffset + 3

			for row = 0, count - 1 do
				const color = buffer.readu8(patch, sourceOffset + row)
				const renderY0, renderY1 = MapScreenYRange(y + topdelta + row, 1)

				for renderY = renderY0, renderY1 - 1 do
					const destStart = renderY * screenWidth + renderX0

					for dest = destStart, destStart + renderX1 - renderX0 - 1 do
						buffer.writeu8(screen, dest, color)
					end
				end
			end

			columnOffset += count + 4
		end
	end
end

-- DrawPatch
-- Masks a column based masked pic to the screen.
const function DrawPatch(x: number, y: number, scrn: number, patch: buffer)
	DrawPatchColumns(x, y, scrn, patch, false, "DrawPatch")
end

-- DrawPatchFlipped
-- Masks a column based masked pic to the screen.
-- Flips horizontally, e.g. to mirror face.
const function DrawPatchFlipped(x: number, y: number, scrn: number, patch: buffer)
	DrawPatchColumns(x, y, scrn, patch, true, "DrawPatchFlipped")
end

-- DrawPatchDirect
-- Draws directly to the screen on the pc.
const function DrawPatchRender(x: number, y: number, scrn: number, patch: buffer)
	DrawPatchColumnsRender(x, y, scrn, patch, false, "DrawPatchRender")
end

const function DrawPatchFlippedRender(x: number, y: number, scrn: number, patch: buffer)
	DrawPatchColumnsRender(x, y, scrn, patch, true, "DrawPatchFlippedRender")
end

const function DrawPatchScreen(x: number, y: number, scrn: number, patch: buffer)
	DrawPatchColumnsScreen(x, y, scrn, patch, false, "DrawPatchScreen")
end

const function DrawPatchFlippedScreen(x: number, y: number, scrn: number, patch: buffer)
	DrawPatchColumnsScreen(x, y, scrn, patch, true, "DrawPatchFlippedScreen")
end

-- DrawBlock
-- Draw a linear block of pixels into the view buffer.
const function DrawBlock(x: number, y: number, scrn: number, width: number, height: number, src: buffer)
	const screen = screens[scrn]

	MarkRectRender(x, y, width, height)

	const screenWidth = State.Width
	local destOffset = y * screenWidth + x
	local srcOffset = 0

	while height > 0 do
		buffer.copy(screen, destOffset, src, srcOffset, width)
		srcOffset += width
		destOffset += screenWidth
		height -= 1
	end
end

-- GetBlock
-- Gets a linear block of pixels from the view buffer.
const function GetBlock(x: number, y: number, scrn: number, width: number, height: number, dest: buffer)
	const screen = screens[scrn]

	const screenWidth = State.Width
	local srcOffset = y * screenWidth + x
	local destOffset = 0

	while height > 0 do
		buffer.copy(dest, destOffset, screen, srcOffset, width)
		srcOffset += screenWidth
		destOffset += width
		height -= 1
	end
end

-- Init
const function Init()
	-- stick these in low dos memory on PCs
	const screenSize = State.PixelCount

	for index = 0, 4 do
		screens[index] = buffer.create(screenSize)
	end

	Video.CENTERX = State.HalfWidth
	Video.CENTERY = State.HalfHeight
	SyncExports()
	ClearDirtyBox()
end

exports = {
	State = State,
	CENTERX = Video.CENTERX,
	CENTERY = Video.CENTERY,
	LogicalWidth = State.LogicalWidth,
	LogicalHeight = State.LogicalHeight,
	LogicalHalfWidth = State.LogicalHalfWidth,
	LogicalHalfHeight = State.LogicalHalfHeight,
	Width = State.Width,
	Height = State.Height,
	HalfWidth = State.HalfWidth,
	HalfHeight = State.HalfHeight,
	PixelCount = State.PixelCount,
	ScreenSize = State.PixelCount,
	ViewportX = State.ViewportX,
	ViewportY = State.ViewportY,
	ViewportWidth = State.ViewportWidth,
	ViewportHeight = State.ViewportHeight,
	screens = screens,
	dirtybox = dirtybox,
	gammatable = gammatable,

	GetUseGamma = GetUseGamma,
	GetScreenWidth = GetScreenWidth,
	GetScreenHeight = GetScreenHeight,
	GetScreenSize = GetScreenSize,
	GetLogicalWidth = GetLogicalWidth,
	GetLogicalHeight = GetLogicalHeight,
	GetViewportX = GetViewportX,
	GetViewportY = GetViewportY,
	GetViewportWidth = GetViewportWidth,
	GetViewportHeight = GetViewportHeight,
	SetUseGamma = SetUseGamma,
	SetScreenBuffer = SetScreenBuffer,
	GetScreenBuffer = GetScreenBuffer,
	ClearDirtyBox = ClearDirtyBox,
	SyncState = SyncExports,

	MarkRect = MarkRect,
	MarkRectRender = MarkRectRender,
	CopyRect = CopyRect,
	DrawPatch = DrawPatch,
	DrawPatchFlipped = DrawPatchFlipped,
	DrawPatchDirect = DrawPatch,
	DrawPatchRender = DrawPatchRender,
	DrawPatchFlippedRender = DrawPatchFlippedRender,
	DrawPatchDirectRender = DrawPatchRender,
	DrawPatchScreen = DrawPatchScreen,
	DrawPatchFlippedScreen = DrawPatchFlippedScreen,
	DrawPatchDirectScreen = DrawPatchScreen,
	DrawBlock = DrawBlock,
	GetBlock = GetBlock,
	ClearScreen = ClearScreen,
	Init = Init,
}

return exports
