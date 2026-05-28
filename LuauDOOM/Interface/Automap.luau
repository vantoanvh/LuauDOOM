--!native
--!optimize 2

-- Port of am_map.c, am_map.h
-- Main automap runtime.
-- Intentional Luau difference: input is fed by the public input API instead of
-- the original global event queue.

const Definitions = require("../Engine/Definitions")
const English = require("../Doom/English")
const French = require("../Doom/French")
const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const Setup = require("../Play/Setup")
const State = require("../Renderer/State")
const Status = require("./Status")
const Video = require("../System/Video")
const VideoMode = require("../System/VideoMode")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const FB = 0
const FRACUNIT = Fixed.FRACUNIT
const FRACBITS = Fixed.FRACBITS
const MAXINT = 2147483647
const PLAYERRADIUS = 16 * FRACUNIT
const MAPBLOCKUNITS = 128

const REDS = 256 - 5 * 16
const REDRANGE = 16
const GREENS = 7 * 16
const GRAYS = 6 * 16
const GRAYSRANGE = 16
const BROWNS = 4 * 16
const YELLOWS = 256 - 32 + 7
const BLACK = 0
const WHITE = 256 - 47

const BACKGROUND = BLACK
const WALLCOLORS = REDS
const TSWALLCOLORS = GRAYS
const FDWALLCOLORS = BROWNS
const CDWALLCOLORS = YELLOWS
const THINGCOLORS = GREENS
const SECRETWALLCOLORS = WALLCOLORS
const GRIDCOLORS = GRAYS + GRAYSRANGE // 2
const XHAIRCOLORS = GRAYS

const SECRET = 32
const DONTDRAW = 128
const MAPPED = 256
const LINE_NEVERSEE = DONTDRAW

const AutomapPanDownKey = Definitions.KEY_DOWNARROW
const AutomapPanUpKey = Definitions.KEY_UPARROW
const AutomapPanRightKey = Definitions.KEY_RIGHTARROW
const AutomapPanLeftKey = Definitions.KEY_LEFTARROW
const AutomapZoomInKey = 61
const AutomapZoomOutKey = 45
const AutomapStartKey = Definitions.KEY_TAB
const AutomapEndKey = Definitions.KEY_TAB
const AutomapGoBigKey = 48
const AutomapFollowKey = 70
const AutomapGridKey = 71
const AutomapMarkKey = 77
const AutomapClearMarkKey = 67
const AutomapMessageHeader = bit32.bor(97 * 16777216, 109 * 65536)
const AutomapMessageEntered = bit32.bor(AutomapMessageHeader, 101 * 256)
const AutomapMessageExited = bit32.bor(AutomapMessageHeader, 120 * 256)

const MaxMarkPoints = 10
const INITSCALEMTOF = math.modf(0.2 * FRACUNIT)
const PanIncrement = 4
const MapZoomIn = math.modf(1.02 * FRACUNIT)
const MapZoomOut = math.modf(FRACUNIT / 1.02)

const NUMPLYRLINES = 7
const NUMCHEATPLYRLINES = 16
const NUMTHINTRIANGLEGUYLINES = 3

type MapPoint = {
	x: number,
	y: number,
}

type MapLine = {
	a: MapPoint,
	b: MapPoint,
}

type MapEvent = {
	type: number,
	data1: number,
}

type AutomapPlayer = {
	mo: {
		x: number,
		y: number,
		angle: number,
	},
	powers: { [number]: number },
	message: string | boolean,
}

local language = Definitions.english
local strings = English
const cheat_xlate_table = table.create(256, 0)
local cheat_xlate_initialized = false
const cheat_amap = {
	sequence = { 0xB2, 0x26, 0x26, 0x2E, 0xFF },
	p = 0,
}

const function SignedRightShift(value: number, shift: number): number
	return Fixed.ToSigned32(bit32.arshift(value, shift))
end

const function CMod(a: number, b: number): number
	return a - math.modf(a / b) * b
end

const function FTOM(x: number, scale_ftom: number): number
	return Fixed.FixedMul(x * FRACUNIT, scale_ftom)
end

const function MTOF(x: number, scale_mtof: number): number
	return SignedRightShift(Fixed.FixedMul(x, scale_mtof), FRACBITS)
end

const function CXMTOF(x: number, m_x: number, scale_mtof: number): number
	return MTOF(x - m_x, scale_mtof)
end

const function CYMTOF(y: number, f_h: number, m_y: number, scale_mtof: number): number
	return f_h - MTOF(y - m_y, scale_mtof)
end

const function GetString(name: string): string
	const value = strings[name]

	if typeof(value) ~= "string" then
		return name
	end

	return value
end

const function SCRAMBLE(value: number): number
	return bit32.band(value, 1) * 128
		+ bit32.band(value, 2) * 32
		+ bit32.band(value, 4)
		+ bit32.band(value, 8) * 2
		+ bit32.rshift(bit32.band(value, 16), 1)
		+ bit32.band(value, 32)
		+ bit32.rshift(bit32.band(value, 64), 5)
		+ bit32.rshift(bit32.band(value, 128), 7)
end

const function CheckAutomapCheat(key: number): boolean
	if not cheat_xlate_initialized then
		cheat_xlate_initialized = true

		for index = 0, 255 do
			cheat_xlate_table[index + 1] = SCRAMBLE(index)
		end
	end

	if cheat_amap.p == 0 then
		cheat_amap.p = 1
	end

	if cheat_xlate_table[key + 1] == cheat_amap.sequence[cheat_amap.p] then
		cheat_amap.p += 1
	else
		cheat_amap.p = 1
	end

	if cheat_amap.sequence[cheat_amap.p] == 0xFF then
		cheat_amap.p = 1
		return true
	end

	return false
end

const function MakeMLine(ax: number, ay: number, bx: number, by: number): MapLine
	return {
		a = { x = ax, y = ay },
		b = { x = bx, y = by },
	}
end

local R = math.modf(8 * PLAYERRADIUS / 7)
const player_arrow = {
	MakeMLine(-R + math.modf(R / 8), 0, R, 0),
	MakeMLine(R, 0, R - math.modf(R / 2), (math.modf(R / 4))),
	MakeMLine(R, 0, R - math.modf(R / 2), -math.modf(R / 4)),
	MakeMLine(-R + math.modf(R / 8), 0, -R - math.modf(R / 8), (math.modf(R / 4))),
	MakeMLine(-R + math.modf(R / 8), 0, -R - math.modf(R / 8), -math.modf(R / 4)),
	MakeMLine(-R + math.modf(3 * R / 8), 0, -R + math.modf(R / 8), (math.modf(R / 4))),
	MakeMLine(-R + math.modf(3 * R / 8), 0, -R + math.modf(R / 8), -math.modf(R / 4)),
}

const cheat_player_arrow = {
	MakeMLine(-R + math.modf(R / 8), 0, R, 0),
	MakeMLine(R, 0, R - math.modf(R / 2), (math.modf(R / 6))),
	MakeMLine(R, 0, R - math.modf(R / 2), -math.modf(R / 6)),
	MakeMLine(-R + math.modf(R / 8), 0, -R - math.modf(R / 8), (math.modf(R / 6))),
	MakeMLine(-R + math.modf(R / 8), 0, -R - math.modf(R / 8), -math.modf(R / 6)),
	MakeMLine(-R + math.modf(3 * R / 8), 0, -R + math.modf(R / 8), (math.modf(R / 6))),
	MakeMLine(-R + math.modf(3 * R / 8), 0, -R + math.modf(R / 8), -math.modf(R / 6)),
	MakeMLine(-math.modf(R / 2), 0, -math.modf(R / 2), -math.modf(R / 6)),
	MakeMLine(-math.modf(R / 2), -math.modf(R / 6), -math.modf(R / 2) + math.modf(R / 6), -math.modf(R / 6)),
	MakeMLine(
		-math.modf(R / 2) + math.modf(R / 6),
		-math.modf(R / 6),
		-math.modf(R / 2) + math.modf(R / 6),
		(math.modf(R / 4))
	),
	MakeMLine(-math.modf(R / 6), 0, -math.modf(R / 6), -math.modf(R / 6)),
	MakeMLine(-math.modf(R / 6), -math.modf(R / 6), 0, -math.modf(R / 6)),
	MakeMLine(0, -math.modf(R / 6), 0, (math.modf(R / 4))),
	MakeMLine(math.modf(R / 6), math.modf(R / 4), math.modf(R / 6), -math.modf(R / 7)),
	MakeMLine(math.modf(R / 6), -math.modf(R / 7), math.modf(R / 6) + math.modf(R / 32), -math.modf(R / 7) - math.modf(R / 32)),
	MakeMLine(math.modf(R / 6) + math.modf(R / 32), -math.modf(R / 7) - math.modf(R / 32), math.modf(R / 6) + math.modf(R / 10), -math.modf(R / 7)),
}

R = FRACUNIT
const thintriangle_guy = {
	MakeMLine(-math.modf(R / 2), -math.modf(0.7 * R), R, 0),
	MakeMLine(R, 0, -math.modf(R / 2), (math.modf(0.7 * R))),
	MakeMLine(-math.modf(R / 2), math.modf(0.7 * R), -math.modf(R / 2), -math.modf(0.7 * R)),
}

local cheating = 0
local grid = 0
local leveljuststarted = 1
local automapactive = false
local finit_width = 0
local finit_height = 0
local f_x = 0
local f_y = 0
local f_w = 0
local f_h = 0
local lightlev = 0
local amclock = 0
const m_paninc = { x = 0, y = 0 }
local mtof_zoommul = FRACUNIT
local ftom_zoommul = FRACUNIT
local m_x = 0
local m_y = 0
local m_x2 = 0
local m_y2 = 0
local m_w = 0
local m_h = 0
local min_x = 0
local min_y = 0
local max_x = 0
local max_y = 0
local max_w = 0
local max_h = 0
local min_scale_mtof = 0
local max_scale_mtof = 0
local old_m_w = 0
local old_m_h = 0
local old_m_x = 0
local old_m_y = 0
const f_oldloc = { x = MAXINT, y = 0 }
local scale_mtof = INITSCALEMTOF
local scale_ftom = FRACUNIT
local plr: AutomapPlayer? = nil
local marknums: { [number]: buffer } = {}
local markpoints: { [number]: MapPoint } = {}
local markpointnum = 0
local followplayer = 1
local stopped = true
local bigstate = 0
local lastlevel = -1
local lastepisode = -1

const function SetLanguage(value: number)
	language = value
	strings = if value == Definitions.french then French else English
end

const function GetPlayer()
	const players = Setup.GetPlayers()
	local player = players[0]

	if player == nil then
		player = players[1]
	end

	return player
end

const function GetScreen0(context: string): buffer
	const screen = Video.GetScreenBuffer(0)
	return screen
end

const function RefreshFrameBounds()
	finit_width = Video.GetViewportWidth()
	finit_height = math.max(Video.GetViewportHeight() - VideoMode.GetStatusBarHeight(), 0)
end

const function FillRenderRect(fb: buffer, x: number, y: number, width: number, height: number, color: number)
	const screenWidth = Video.GetScreenWidth()

	for renderY = y, y + height - 1 do
		const rowOffset = renderY * screenWidth + x

		for renderX = 0, width - 1 do
			buffer.writeu8(fb, rowOffset + renderX, color)
		end
	end
end

const function FillRenderPixel(fb: buffer, x: number, y: number, color: number)
	buffer.writeu8(fb, y * Video.GetScreenWidth() + x, color)
end

const function NotifyStatus(message: number)
	Status.Responder({
		type = 1,
		data1 = message,
		data2 = 0,
		data3 = 0,
	})
end

const function UnloadPics()
	for index = 0, 9 do
		const patch = marknums[index]

		if typeof(patch) == "buffer" then
			Zone.ChangeTag(patch, Zone.CACHE)
		end
	end

	marknums = {}
end

const function ClearMarks()
	markpoints = {}

	for index = 0, MaxMarkPoints - 1 do
		markpoints[index] = { x = -1, y = 0 }
	end

	markpointnum = 0
end

const function ActivateNewScale()
	m_x += m_w // 2
	m_y += m_h // 2
	m_w = FTOM(f_w, scale_ftom)
	m_h = FTOM(f_h, scale_ftom)
	m_x -= m_w // 2
	m_y -= m_h // 2
	m_x2 = m_x + m_w
	m_y2 = m_y + m_h
end

const function SaveScaleAndLoc()
	old_m_x = m_x
	old_m_y = m_y
	old_m_w = m_w
	old_m_h = m_h
end

const function RestoreScaleAndLoc()
	m_w = old_m_w
	m_h = old_m_h

	if followplayer == 0 then
		m_x = old_m_x
		m_y = old_m_y
	else
		const player = plr

		if typeof(player) ~= "table" or typeof(player.mo) ~= "table" then
			return
		end

		m_x = player.mo.x - m_w // 2
		m_y = player.mo.y - m_h // 2
	end

	m_x2 = m_x + m_w
	m_y2 = m_y + m_h
	scale_mtof = Fixed.FixedDiv(f_w * FRACUNIT, m_w)
	scale_ftom = Fixed.FixedDiv(FRACUNIT, scale_mtof)
end

const function AddMark()
	markpoints[markpointnum].x = m_x + m_w // 2
	markpoints[markpointnum].y = m_y + m_h // 2
	markpointnum = (markpointnum + 1) % MaxMarkPoints
end

const function FindMinMaxBoundaries()
	min_x = MAXINT
	min_y = MAXINT
	max_x = -MAXINT
	max_y = -MAXINT

	for index = 0, State.numvertexes - 1 do
		const vertex = State.vertexes[index]

		if typeof(vertex) ~= "table" then
			continue
		end

		if vertex.x < min_x then
			min_x = vertex.x
		elseif vertex.x > max_x then
			max_x = vertex.x
		end

		if vertex.y < min_y then
			min_y = vertex.y
		elseif vertex.y > max_y then
			max_y = vertex.y
		end
	end

	max_w = max_x - min_x
	max_h = max_y - min_y

	const a = Fixed.FixedDiv(f_w * FRACUNIT, max_w)
	const b = Fixed.FixedDiv(f_h * FRACUNIT, max_h)
	min_scale_mtof = if a < b then a else b
	max_scale_mtof = Fixed.FixedDiv(f_h * FRACUNIT, 2 * PLAYERRADIUS)
end

const function ChangeWindowLoc()
	if m_paninc.x ~= 0 or m_paninc.y ~= 0 then
		followplayer = 0
		f_oldloc.x = MAXINT
	end

	m_x += m_paninc.x
	m_y += m_paninc.y

	if m_x + m_w // 2 > max_x then
		m_x = max_x - m_w // 2
	elseif m_x + m_w // 2 < min_x then
		m_x = min_x - m_w // 2
	end

	if m_y + m_h // 2 > max_y then
		m_y = max_y - m_h // 2
	elseif m_y + m_h // 2 < min_y then
		m_y = min_y - m_h // 2
	end

	m_x2 = m_x + m_w
	m_y2 = m_y + m_h
end

const function InitVariables()
	automapactive = true
	NotifyStatus(AutomapMessageEntered)
	f_oldloc.x = MAXINT
	f_oldloc.y = 0
	amclock = 0
	lightlev = 0
	m_paninc.x = 0
	m_paninc.y = 0
	ftom_zoommul = FRACUNIT
	mtof_zoommul = FRACUNIT
	m_w = FTOM(f_w, scale_ftom)
	m_h = FTOM(f_h, scale_ftom)
	plr = GetPlayer()


	m_x = plr.mo.x - m_w // 2
	m_y = plr.mo.y - m_h // 2
	ChangeWindowLoc()
	old_m_x = m_x
	old_m_y = m_y
	old_m_w = m_w
	old_m_h = m_h
end

const function LoadPics()
	for index = 0, 9 do
		marknums[index] = Wad.CacheLumpName(`AMMNUM{index}`, Zone.STATIC)
	end
end

const function LevelInit()
	RefreshFrameBounds()
	leveljuststarted = 0
	f_x = 0
	f_y = 0
	f_w = finit_width
	f_h = finit_height
	ClearMarks()
	FindMinMaxBoundaries()
	scale_mtof = Fixed.FixedDiv(min_scale_mtof, (math.modf(0.7 * FRACUNIT)))

	if scale_mtof > max_scale_mtof then
		scale_mtof = min_scale_mtof
	end

	scale_ftom = Fixed.FixedDiv(FRACUNIT, scale_mtof)
end

const function Stop()
	if stopped then
		return
	end

	UnloadPics()
	automapactive = false
	NotifyStatus(AutomapMessageExited)
	stopped = true
end

const function Start()
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()
	const frameWidth = finit_width
	const frameHeight = finit_height

	RefreshFrameBounds()

	if not stopped then
		Stop()
	end

	stopped = false

	if lastlevel ~= map
		or lastepisode ~= episode
		or leveljuststarted ~= 0
		or frameWidth ~= finit_width
		or frameHeight ~= finit_height
	then
		LevelInit()
		lastlevel = map
		lastepisode = episode
	end

	InitVariables()
	LoadPics()
end

const function MinOutWindowScale()
	scale_mtof = min_scale_mtof
	scale_ftom = Fixed.FixedDiv(FRACUNIT, scale_mtof)
	ActivateNewScale()
end

const function MaxOutWindowScale()
	scale_mtof = max_scale_mtof
	scale_ftom = Fixed.FixedDiv(FRACUNIT, scale_mtof)
	ActivateNewScale()
end

const function CycleCheat()
	if automapactive then
		cheating = (cheating + 1) % 3
	end
end

const function Responder(ev: MapEvent): boolean

	const evType = ev.type
	const data1 = ev.data1
	local rc = false

	if not automapactive then
		if evType == 0 and data1 == AutomapStartKey then
			Start()
			rc = true
		end
	elseif evType == 0 then
		rc = true

		if data1 == AutomapPanRightKey then
			if followplayer == 0 then
				m_paninc.x = FTOM(PanIncrement, scale_ftom)
			else
				rc = false
			end
		elseif data1 == AutomapPanLeftKey then
			if followplayer == 0 then
				m_paninc.x = -FTOM(PanIncrement, scale_ftom)
			else
				rc = false
			end
		elseif data1 == AutomapPanUpKey then
			if followplayer == 0 then
				m_paninc.y = FTOM(PanIncrement, scale_ftom)
			else
				rc = false
			end
		elseif data1 == AutomapPanDownKey then
			if followplayer == 0 then
				m_paninc.y = -FTOM(PanIncrement, scale_ftom)
			else
				rc = false
			end
		elseif data1 == AutomapZoomOutKey then
			mtof_zoommul = MapZoomOut
			ftom_zoommul = MapZoomIn
		elseif data1 == AutomapZoomInKey then
			mtof_zoommul = MapZoomIn
			ftom_zoommul = MapZoomOut
		elseif data1 == AutomapEndKey then
			bigstate = 0
			Stop()
		elseif data1 == AutomapGoBigKey then
			bigstate = if bigstate == 0 then 1 else 0

			if bigstate ~= 0 then
				SaveScaleAndLoc()
				MinOutWindowScale()
			else
				RestoreScaleAndLoc()
			end
		elseif data1 == AutomapFollowKey then
			followplayer = if followplayer == 0 then 1 else 0
			f_oldloc.x = MAXINT
			plr.message = if followplayer ~= 0 then GetString("AMSTR_FOLLOWON") else GetString("AMSTR_FOLLOWOFF")
		elseif data1 == AutomapGridKey then
			grid = if grid == 0 then 1 else 0
			plr.message = if grid ~= 0 then GetString("AMSTR_GRIDON") else GetString("AMSTR_GRIDOFF")
		elseif data1 == AutomapMarkKey then
			plr.message = `{GetString("AMSTR_MARKEDSPOT")} {markpointnum}`
			AddMark()
		elseif data1 == AutomapClearMarkKey then
			ClearMarks()
			plr.message = GetString("AMSTR_MARKSCLEARED")
		else
			rc = false
		end

		if typeof(data1) == "number" then
			local key = bit32.band(data1, 0xFF)

			if key >= 65 and key <= 90 then
				key += 32
			end

			if CheckAutomapCheat(key) then
				CycleCheat()
				rc = false
			end
		end
	elseif evType == 1 then
		if data1 == AutomapPanRightKey or data1 == AutomapPanLeftKey then
			if followplayer == 0 then
				m_paninc.x = 0
			end
		elseif data1 == AutomapPanUpKey or data1 == AutomapPanDownKey then
			if followplayer == 0 then
				m_paninc.y = 0
			end
		elseif data1 == AutomapZoomOutKey or data1 == AutomapZoomInKey then
			mtof_zoommul = FRACUNIT
			ftom_zoommul = FRACUNIT
		end
	end

	return rc
end

const function ChangeWindowScale()
	scale_mtof = Fixed.FixedMul(scale_mtof, mtof_zoommul)
	scale_ftom = Fixed.FixedDiv(FRACUNIT, scale_mtof)

	if scale_mtof < min_scale_mtof then
		MinOutWindowScale()
	elseif scale_mtof > max_scale_mtof then
		MaxOutWindowScale()
	else
		ActivateNewScale()
	end
end

const function DoFollowPlayer()
	if typeof(plr) ~= "table" or typeof(plr.mo) ~= "table" then
		return
	end

	if f_oldloc.x ~= plr.mo.x or f_oldloc.y ~= plr.mo.y then
		m_x = plr.mo.x - m_w // 2
		m_y = plr.mo.y - m_h // 2
		m_x2 = m_x + m_w
		m_y2 = m_y + m_h
		f_oldloc.x = plr.mo.x
		f_oldloc.y = plr.mo.y
	end
end

const function Ticker()
	if not automapactive then
		return
	end

	amclock += 1

	if followplayer ~= 0 then
		DoFollowPlayer()
	end

	if ftom_zoommul ~= FRACUNIT then
		ChangeWindowScale()
	end

	if m_paninc.x ~= 0 or m_paninc.y ~= 0 then
		ChangeWindowLoc()
	end
end

const function ClearFB(color: number)
	const fb = GetScreen0("AutomapDrawer")
	FillRenderRect(fb, f_x, f_y, f_w, f_h, color)
end

const function DoOutCode(mx: number, my: number): number
	local outcode = 0

	if my < 0 then
		outcode = bit32.bor(outcode, 8)
	elseif my >= f_h then
		outcode = bit32.bor(outcode, 4)
	end

	if mx < 0 then
		outcode = bit32.bor(outcode, 1)
	elseif mx >= f_w then
		outcode = bit32.bor(outcode, 2)
	end

	return outcode
end
	
const function ClipMLine(ml: MapLine, fl: MapLine): boolean
	const LEFT = 1
	const RIGHT = 2
	const BOTTOM = 4
	const TOP = 8
	local outcode1 = 0
	local outcode2 = 0
	local outside = 0
	const tmp = { x = 0, y = 0 }
	local dx = 0
	local dy = 0

	if ml.a.y > m_y2 then
		outcode1 = TOP
	elseif ml.a.y < m_y then
		outcode1 = BOTTOM
	end

	if ml.b.y > m_y2 then
		outcode2 = TOP
	elseif ml.b.y < m_y then
		outcode2 = BOTTOM
	end

	if bit32.btest(outcode1, outcode2) then
		return false
	end

	if ml.a.x < m_x then
		outcode1 = bit32.bor(outcode1, LEFT)
	elseif ml.a.x > m_x2 then
		outcode1 = bit32.bor(outcode1, RIGHT)
	end

	if ml.b.x < m_x then
		outcode2 = bit32.bor(outcode2, LEFT)
	elseif ml.b.x > m_x2 then
		outcode2 = bit32.bor(outcode2, RIGHT)
	end

	if bit32.btest(outcode1, outcode2) then
		return false
	end

	fl.a.x = CXMTOF(ml.a.x, m_x, scale_mtof)
	fl.a.y = CYMTOF(ml.a.y, f_h, m_y, scale_mtof)
	fl.b.x = CXMTOF(ml.b.x, m_x, scale_mtof)
	fl.b.y = CYMTOF(ml.b.y, f_h, m_y, scale_mtof)

	outcode1 = DoOutCode(fl.a.x, fl.a.y)
	outcode2 = DoOutCode(fl.b.x, fl.b.y)

	if bit32.btest(outcode1, outcode2) then
		return false
	end

	while bit32.bor(outcode1, outcode2) ~= 0 do
		if outcode1 ~= 0 then
			outside = outcode1
		else
			outside = outcode2
		end

		if bit32.btest(outside, TOP) then
			dy = fl.a.y - fl.b.y
			dx = fl.b.x - fl.a.x
			tmp.x = fl.a.x + math.modf(dx * fl.a.y / dy)
			tmp.y = 0
		elseif bit32.btest(outside, BOTTOM) then
			dy = fl.a.y - fl.b.y
			dx = fl.b.x - fl.a.x
			tmp.x = fl.a.x + math.modf(dx * (fl.a.y - f_h) / dy)
			tmp.y = f_h - 1
		elseif bit32.btest(outside, RIGHT) then
			dy = fl.b.y - fl.a.y
			dx = fl.b.x - fl.a.x
			tmp.y = fl.a.y + math.modf(dy * (f_w - 1 - fl.a.x) / dx)
			tmp.x = f_w - 1
		else
			dy = fl.b.y - fl.a.y
			dx = fl.b.x - fl.a.x
			tmp.y = fl.a.y + math.modf(dy * (-fl.a.x) / dx)
			tmp.x = 0
		end

		if outside == outcode1 then
			fl.a.x = tmp.x
			fl.a.y = tmp.y
			outcode1 = DoOutCode(fl.a.x, fl.a.y)
		else
			fl.b.x = tmp.x
			fl.b.y = tmp.y
			outcode2 = DoOutCode(fl.b.x, fl.b.y)
		end

		if bit32.btest(outcode1, outcode2) then
			return false
		end
	end

	return true
end

const function DrawFLine(fl: MapLine, color: number)
	const dx = fl.b.x - fl.a.x
	const ax = 2 * math.abs(dx)
	const sx = if dx < 0 then -1 else 1
	const dy = fl.b.y - fl.a.y
	const ay = 2 * math.abs(dy)
	const sy = if dy < 0 then -1 else 1
	local x = fl.a.x
	local y = fl.a.y
	const fb = GetScreen0("AutomapDrawLine")
	local d = 0

	const function PutDot(xx: number, yy: number)
		FillRenderPixel(fb, f_x + xx, f_y + yy, color)
	end

	if ax > ay then
		d = ay - ax // 2

		while true do
			PutDot(x, y)

			if x == fl.b.x then
				return
			end

			if d >= 0 then
				y += sy
				d -= ax
			end

			x += sx
			d += ay
		end
	else
		d = ax - ay // 2

		while true do
			PutDot(x, y)

			if y == fl.b.y then
				return
			end

			if d >= 0 then
				x += sx
				d -= ay
			end

			y += sy
			d += ax
		end
	end
end

const function DrawMLine(ml: MapLine, color: number)
	const fl = {
		a = { x = 0, y = 0 },
		b = { x = 0, y = 0 },
	}

	if ClipMLine(ml, fl) then
		DrawFLine(fl, color)
	end
end

const function DrawGrid(color: number)
	local start = m_x
	const step = MAPBLOCKUNITS * FRACUNIT
	local offset = CMod(start - Setup.GetBlockMapOriginX(), step)

	if offset ~= 0 then
		start += step - offset
	end

	const line = {
		a = { x = 0, y = m_y },
		b = { x = 0, y = m_y + m_h },
	}

	for x = start, m_x + m_w - 1, step do
		line.a.x = x
		line.b.x = x
		DrawMLine(line, color)
	end

	start = m_y
	offset = CMod(start - Setup.GetBlockMapOriginY(), step)

	if offset ~= 0 then
		start += step - offset
	end

	line.a.x = m_x
	line.b.x = m_x + m_w

	for y = start, m_y + m_h - 1, step do
		line.a.y = y
		line.b.y = y
		DrawMLine(line, color)
	end
end

const function DrawWalls()
	const line = {
		a = { x = 0, y = 0 },
		b = { x = 0, y = 0 },
	}

	for index = 0, State.numlines - 1 do
		const worldLine = State.lines[index]

		if typeof(worldLine) ~= "table" or typeof(worldLine.v1) ~= "table" or typeof(worldLine.v2) ~= "table" then
			continue
		end

		line.a.x = worldLine.v1.x
		line.a.y = worldLine.v1.y
		line.b.x = worldLine.v2.x
		line.b.y = worldLine.v2.y

		const frontsector = worldLine.frontsector
		const backsector = worldLine.backsector
		const hasFrontSector = typeof(frontsector) == "table"
		const hasBackSector = typeof(backsector) == "table"

		if cheating ~= 0 or bit32.btest(worldLine.flags, MAPPED) then
			if bit32.btest(worldLine.flags, LINE_NEVERSEE) and cheating == 0 then
				continue
			end

			if not hasBackSector then
				DrawMLine(line, WALLCOLORS + lightlev)
			else
				if worldLine.special == 39 then
					DrawMLine(line, WALLCOLORS + REDRANGE // 2)
				elseif bit32.btest(worldLine.flags, SECRET) then
					if cheating ~= 0 then
						DrawMLine(line, SECRETWALLCOLORS + lightlev)
					else
						DrawMLine(line, WALLCOLORS + lightlev)
					end
				elseif not hasFrontSector then
					DrawMLine(line, WALLCOLORS + lightlev)
				elseif backsector.floorheight ~= frontsector.floorheight then
					DrawMLine(line, FDWALLCOLORS + lightlev)
				elseif backsector.ceilingheight ~= frontsector.ceilingheight then
					DrawMLine(line, CDWALLCOLORS + lightlev)
				elseif cheating ~= 0 then
					DrawMLine(line, TSWALLCOLORS + lightlev)
				end
			end
		elseif typeof(plr) == "table"
			and typeof(plr.powers) == "table"
			and typeof(plr.powers[Definitions.pw_allmap]) == "number"
			and plr.powers[Definitions.pw_allmap] ~= 0
		then
			if bit32.band(worldLine.flags, LINE_NEVERSEE) == 0 then
				DrawMLine(line, GRAYS + 3)
			end
		end
	end
end

const function Rotate(x: number, y: number, angle: number): (number, number)
	const fineIndex = bit32.band(bit32.rshift(angle, Tables.ANGLETOFINESHIFT), Tables.FINEANGLES - 1)
	const cos = Tables.finecosine[fineIndex]
	const sin = Tables.finesine[fineIndex]
	const rotatedX = Fixed.FixedMul(x, cos) - Fixed.FixedMul(y, sin)
	const rotatedY = Fixed.FixedMul(x, sin) + Fixed.FixedMul(y, cos)
	return rotatedX, rotatedY
end

const function DrawLineCharacter(lineguy: { [number]: MapLine }, lineCount: number, scale: number, angle: number, color: number, x: number, y: number)
	const line = {
		a = { x = 0, y = 0 },
		b = { x = 0, y = 0 },
	}

	for index = 1, lineCount do
		const source = lineguy[index]
		line.a.x = source.a.x
		line.a.y = source.a.y

		if scale ~= 0 then
			line.a.x = Fixed.FixedMul(scale, line.a.x)
			line.a.y = Fixed.FixedMul(scale, line.a.y)
		end

		if angle ~= 0 then
			line.a.x, line.a.y = Rotate(line.a.x, line.a.y, angle)
		end

		line.a.x += x
		line.a.y += y
		line.b.x = source.b.x
		line.b.y = source.b.y

		if scale ~= 0 then
			line.b.x = Fixed.FixedMul(scale, line.b.x)
			line.b.y = Fixed.FixedMul(scale, line.b.y)
		end

		if angle ~= 0 then
			line.b.x, line.b.y = Rotate(line.b.x, line.b.y, angle)
		end

		line.b.x += x
		line.b.y += y
		DrawMLine(line, color)
	end
end

const function DrawPlayers()
	if typeof(plr) ~= "table" or typeof(plr.mo) ~= "table" then
		return
	end

	if cheating ~= 0 then
		DrawLineCharacter(cheat_player_arrow, NUMCHEATPLYRLINES, 0, plr.mo.angle, WHITE, plr.mo.x, plr.mo.y)
	else
		DrawLineCharacter(player_arrow, NUMPLYRLINES, 0, plr.mo.angle, WHITE, plr.mo.x, plr.mo.y)
	end
end

const function DrawThings(colors: number)
	for index = 0, State.numsectors - 1 do
		const sector = State.sectors[index]
		local thing = if typeof(sector) == "table" then sector.thinglist else nil

		while thing ~= nil and thing ~= false do
			DrawLineCharacter(thintriangle_guy, NUMTHINTRIANGLEGUYLINES, 16 * FRACUNIT, thing.angle, colors + lightlev, thing.x, thing.y)
			thing = thing.snext
		end
	end
end

const function DrawMarks()
	for index = 0, MaxMarkPoints - 1 do
		const point = markpoints[index]

		if typeof(point) ~= "table" or point.x == -1 then
			continue
		end

		const fx = CXMTOF(point.x, m_x, scale_mtof)
		const fy = CYMTOF(point.y, f_h, m_y, scale_mtof)

		if fx >= 0 and fx <= f_w - 5 and fy >= 0 and fy <= f_h - 6 then
			const patch = marknums[index]

			if typeof(patch) == "buffer" and buffer.len(patch) > 0 then
				Video.DrawPatchRender(f_x + fx, f_y + fy, FB, patch)
			end
		end
	end
end

const function DrawCrosshair(color: number)
	const fb = GetScreen0("AutomapDrawer")
	const x = f_x + f_w // 2
	const y = f_y + f_h // 2
	FillRenderPixel(fb, x, y, color)
end

const function Drawer()
	if not automapactive then
		return
	end

	ClearFB(BACKGROUND)

	if grid ~= 0 then
		DrawGrid(GRIDCOLORS)
	end

	DrawWalls()
	DrawPlayers()

	if cheating == 2 then
	DrawThings(THINGCOLORS)
	end

	DrawCrosshair(XHAIRCOLORS)
	DrawMarks()
	Video.MarkRectRender(f_x, f_y, f_w, f_h)
end

const function Reset()
	Stop()
	cheating = 0
	grid = 0
	leveljuststarted = 1
	automapactive = false
	RefreshFrameBounds()
	f_x = 0
	f_y = 0
	f_w = 0
	f_h = 0
	lightlev = 0
	amclock = 0
	m_paninc.x = 0
	m_paninc.y = 0
	mtof_zoommul = FRACUNIT
	ftom_zoommul = FRACUNIT
	m_x = 0
	m_y = 0
	m_x2 = 0
	m_y2 = 0
	m_w = 0
	m_h = 0
	min_x = 0
	min_y = 0
	max_x = 0
	max_y = 0
	max_w = 0
	max_h = 0
	min_scale_mtof = 0
	max_scale_mtof = 0
	old_m_w = 0
	old_m_h = 0
	old_m_x = 0
	old_m_y = 0
	f_oldloc.x = MAXINT
	f_oldloc.y = 0
	scale_mtof = INITSCALEMTOF
	scale_ftom = FRACUNIT
	plr = nil
	ClearMarks()
	cheat_xlate_initialized = false
	cheat_amap.p = 0
	followplayer = 1
	stopped = true
	bigstate = 0
	lastlevel = -1
	lastepisode = -1
end

Reset()
SetLanguage(language)

const function GetLanguage(): number
	return language
end

const function IsActive(): boolean
	return automapactive
end

const function IsFollowingPlayer(): boolean
	return followplayer ~= 0
end

return {
	Reset = Reset,
	SetLanguage = SetLanguage,
	GetLanguage = GetLanguage,
	IsActive = IsActive,
	IsFollowingPlayer = IsFollowingPlayer,
	Responder = Responder,
	Ticker = Ticker,
	Drawer = Drawer,
	Start = Start,
	Stop = Stop,
}
