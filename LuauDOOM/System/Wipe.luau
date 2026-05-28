--!native
--!optimize 2

-- Port of f_wipe.c, f_wipe.h
-- DESCRIPTION:
--	Mission begin melt/wipe screen special effect.
--	Mission start screen wipe/melt, special effects.

const Random = require("../Miscellaneous/Random")
const Video = require("./Video")


-- simple gradual pixel change for 8-bit only
const wipe_ColorXForm = 0

-- weird screen melt
const wipe_Melt = 1

const wipe_NUMWIPES = 2

-- when zero, stop the wipe
local go = false
local wipe_scr_start = buffer.create(0)
local wipe_scr_end = buffer.create(0)
local wipe_scr = buffer.create(0)
local y = table.create(0)

const function wipe_shittyColMajorXform(array: buffer, width: number, height: number)
	const pixelCount = width * height
	const byteCount = pixelCount * 2
	const dest = buffer.create(byteCount)

	for iy = 0, height - 1 do
		for ix = 0, width - 1 do
			buffer.writeu16(dest, (ix * height + iy) * 2, buffer.readu16(array, (iy * width + ix) * 2))
		end
	end

	buffer.copy(array, 0, dest, 0, byteCount)
end

const function GetWipeTickScale(width: number, height: number): number
	const logicalWidth = Video.LogicalWidth
	const logicalHeight = Video.LogicalHeight
	const scaleX = width // logicalWidth
	const scaleY = height // logicalHeight
	local scale = scaleX

	if scaleY > scale then
		scale = scaleY
	end

	if scale < 1 then
		return 1
	end

	return scale
end

const function ScaleWipeTicks(width: number, height: number, ticks: number): number
	if ticks <= 0 then
		return ticks
	end

	return ticks * GetWipeTickScale(width, height)
end

const function wipe_initColorXForm(width: number, height: number, _ticks: number): number
	buffer.copy(wipe_scr, 0, wipe_scr_start, 0, width * height)
	return 0
end

const function wipe_doColorXForm(width: number, height: number, ticks: number): number
	local changed = false
	const total = width * height

	for offset = 0, total - 1 do
		const w = buffer.readu8(wipe_scr, offset)
		const e = buffer.readu8(wipe_scr_end, offset)

		if w ~= e then
			local newval

			if w > e then
				newval = w - ticks

				if newval < e then
					buffer.writeu8(wipe_scr, offset, e)
				else
					buffer.writeu8(wipe_scr, offset, newval)
				end

				changed = true
			elseif w < e then
				newval = w + ticks

				if newval > e then
					buffer.writeu8(wipe_scr, offset, e)
				else
					buffer.writeu8(wipe_scr, offset, newval)
				end

				changed = true
			end
		end
	end

	return if changed then 0 else 1
end

const function wipe_exitColorXForm(_width: number, _height: number, _ticks: number): number
	return 0
end

const function wipe_initMelt(width: number, height: number, _ticks: number): number
	-- copy start screen to main screen
	buffer.copy(wipe_scr, 0, wipe_scr_start, 0, width * height)

	-- makes this wipe faster (in theory)
	-- to have stuff in column-major format
	wipe_shittyColMajorXform(wipe_scr_start, width // 2, height)
	wipe_shittyColMajorXform(wipe_scr_end, width // 2, height)

	-- setup initial column positions
	-- (y<0 => not ready to scroll yet)
	y = table.create(width, 0)
	y[1] = -bit32.band(Random.MenuRandom(), 15)

	for index = 2, width do
		const r = (Random.MenuRandom() % 3) - 1
		y[index] = y[index - 1] + r

		if y[index] > 0 then
			y[index] = 0
		elseif y[index] == -16 then
			y[index] = -15
		end
	end

	return 0
end

const function wipe_doMelt(width: number, height: number, ticks: number): number
	local done = true
	const halfwidth = width // 2

	while ticks > 0 do
		ticks -= 1

		for index = 1, halfwidth do
			local columnY = y[index]

			if columnY < 0 then
				y[index] = columnY + 1
				done = false
			elseif columnY < height then
				local dy = if columnY < 16 then columnY + 1 else 8

				if columnY + dy >= height then
					dy = height - columnY
				end

				local sourceOffset = ((index - 1) * height + columnY) * 2
				local destOffset = (columnY * halfwidth + (index - 1)) * 2

				for _ = 1, dy do
					buffer.writeu16(wipe_scr, destOffset, buffer.readu16(wipe_scr_end, sourceOffset))
					sourceOffset += 2
					destOffset += halfwidth * 2
				end

				columnY += dy
				y[index] = columnY
				sourceOffset = ((index - 1) * height) * 2
				destOffset = (columnY * halfwidth + (index - 1)) * 2

				for _ = 1, height - columnY do
					buffer.writeu16(wipe_scr, destOffset, buffer.readu16(wipe_scr_start, sourceOffset))
					sourceOffset += 2
					destOffset += halfwidth * 2
				end

				done = false
			end
		end
	end

	return if done then 1 else 0
end

const function wipe_exitMelt(_width: number, _height: number, _ticks: number): number
	table.clear(y)
	return 0
end

const function StartScreen(_x: number, _y: number, _width: number, _height: number): number
	const screenSize = Video.GetScreenSize()

	wipe_scr_start = buffer.create(screenSize)
	buffer.copy(wipe_scr_start, 0, Video.GetScreenBuffer(0), 0, screenSize)
	return 0
end

const function EndScreen(x: number, y0: number, width: number, height: number): number
	const screenSize = Video.GetScreenSize()

	wipe_scr_end = buffer.create(screenSize)
	buffer.copy(wipe_scr_end, 0, Video.GetScreenBuffer(0), 0, screenSize)
	Video.DrawBlock(x, y0, 0, width, height, wipe_scr_start) -- restore start scr.
	return 0
end

const function SetStartScreenBuffer(source: buffer)
	const screenSize = Video.GetScreenSize()


	wipe_scr_start = buffer.create(screenSize)
	buffer.copy(wipe_scr_start, 0, source, 0, screenSize)
end

const function SetEndScreenBuffer(source: buffer)
	const screenSize = Video.GetScreenSize()


	wipe_scr_end = buffer.create(screenSize)
	buffer.copy(wipe_scr_end, 0, source, 0, screenSize)
end

const function RestoreStartScreen(x: number, y0: number, width: number, height: number): number
	if buffer.len(wipe_scr_start) ~= Video.GetScreenSize() then
		return 0
	end

	Video.DrawBlock(x, y0, 0, width, height, wipe_scr_start)
	return 0
end

const wipes = {
	[0] = wipe_initColorXForm,
	[1] = wipe_doColorXForm,
	[2] = wipe_exitColorXForm,
	[3] = wipe_initMelt,
	[4] = wipe_doMelt,
	[5] = wipe_exitMelt,
}

const function ScreenWipe(wipeno: number, _x: number, _y: number, width: number, height: number, ticks: number): number

	const scaledTicks = ScaleWipeTicks(width, height, ticks)

	-- initial stuff
	if not go then
		go = true
		wipe_scr = Video.GetScreenBuffer(0)
		wipes[wipeno * 3](width, height, scaledTicks)
	end

	-- do a piece of wipe-in
	Video.MarkRectRender(0, 0, width, height)

	const rc = wipes[wipeno * 3 + 1](width, height, scaledTicks)

	-- final stuff
	if rc ~= 0 then
		go = false
		wipes[wipeno * 3 + 2](width, height, scaledTicks)
	end

	return if go then 0 else 1
end

const function Reset()
	go = false
	wipe_scr_start = buffer.create(0)
	wipe_scr_end = buffer.create(0)
	wipe_scr = buffer.create(0)
	table.clear(y)
end

return {
	wipe_ColorXForm = wipe_ColorXForm,
	wipe_Melt = wipe_Melt,
	wipe_NUMWIPES = wipe_NUMWIPES,
	Reset = Reset,
	StartScreen = StartScreen,
	EndScreen = EndScreen,
	ScreenWipe = ScreenWipe,
	SetStartScreenBuffer = SetStartScreenBuffer,
	SetEndScreenBuffer = SetEndScreenBuffer,
	RestoreStartScreen = RestoreStartScreen,
}
