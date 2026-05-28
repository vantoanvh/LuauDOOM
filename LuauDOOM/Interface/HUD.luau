--!native
--!optimize 2

-- Port of hu_stuff.c, hu_stuff.h
-- Visible single-player heads-up text path:
-- pickup/door messages and map title on automap.
-- Chat/multiplayer input remains minimal for now.

const Automap = require("./Automap")
const Definitions = require("../Engine/Definitions")
const English = require("../Doom/English")
const French = require("../Doom/French")
const Setup = require("../Play/Setup")
const Draw = require("../Renderer/Draw")
const State = require("../Renderer/State")
const Video = require("../System/Video")
const VideoMode = require("../System/VideoMode")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const FontStart = 33
const FontEnd = 95
const FontSize = FontEnd - FontStart + 1

const MessageRefreshKey = Definitions.KEY_ENTER
const MessageX = 0
const MessageY = 0
const MessageWidth = 64
const MessageHeight = 1
const MessageTimeout = 4 * Definitions.TICRATE
const CharEraseKey = Definitions.KEY_BACKSPACE
const MaxLines = 4
const MaxLineLength = 80
const BG = 1
const FG = 0

type LanguageStrings = typeof(English)
type Font = { [number]: buffer }
type Event = {
	type: number,
	data1: number?,
}
type HUDPlayer = {
	[string]: unknown,
	message: string | boolean,
}
type TextLine = {
	[string]: unknown,
	x: number,
	y: number,
	f: Font,
	sc: number,
	len: number,
	l: string,
	needsupdate: number,
}
type ScrollingText = {
	[string]: unknown,
	h: number,
	on: () -> boolean,
	laston: boolean,
	cl: number,
	l: { [number]: TextLine },
}

local language = Definitions.english
local strings = English
local showMessages = true

local plr: HUDPlayer? = nil
const hu_font: Font = {}
local w_title: TextLine = {} :: TextLine
local w_message: ScrollingText = {} :: ScrollingText
local message_on = false
local message_dontfuckwithme = false
local message_nottobefuckedwith = false
local message_counter = 0
local headsupactive = false
local loaded = false

const function BuildDoom1MapNames(source: LanguageStrings)
	return {
		[0] = source.HUSTR_E1M1,
		source.HUSTR_E1M2,
		source.HUSTR_E1M3,
		source.HUSTR_E1M4,
		source.HUSTR_E1M5,
		source.HUSTR_E1M6,
		source.HUSTR_E1M7,
		source.HUSTR_E1M8,
		source.HUSTR_E1M9,
		source.HUSTR_E2M1,
		source.HUSTR_E2M2,
		source.HUSTR_E2M3,
		source.HUSTR_E2M4,
		source.HUSTR_E2M5,
		source.HUSTR_E2M6,
		source.HUSTR_E2M7,
		source.HUSTR_E2M8,
		source.HUSTR_E2M9,
		source.HUSTR_E3M1,
		source.HUSTR_E3M2,
		source.HUSTR_E3M3,
		source.HUSTR_E3M4,
		source.HUSTR_E3M5,
		source.HUSTR_E3M6,
		source.HUSTR_E3M7,
		source.HUSTR_E3M8,
		source.HUSTR_E3M9,
		source.HUSTR_E4M1,
		source.HUSTR_E4M2,
		source.HUSTR_E4M3,
		source.HUSTR_E4M4,
		source.HUSTR_E4M5,
		source.HUSTR_E4M6,
		source.HUSTR_E4M7,
		source.HUSTR_E4M8,
		source.HUSTR_E4M9,
	}
end

const function BuildDoom2MapNames(source: LanguageStrings)
	return {
		[0] = source.HUSTR_1,
		source.HUSTR_2,
		source.HUSTR_3,
		source.HUSTR_4,
		source.HUSTR_5,
		source.HUSTR_6,
		source.HUSTR_7,
		source.HUSTR_8,
		source.HUSTR_9,
		source.HUSTR_10,
		source.HUSTR_11,
		source.HUSTR_12,
		source.HUSTR_13,
		source.HUSTR_14,
		source.HUSTR_15,
		source.HUSTR_16,
		source.HUSTR_17,
		source.HUSTR_18,
		source.HUSTR_19,
		source.HUSTR_20,
		source.HUSTR_21,
		source.HUSTR_22,
		source.HUSTR_23,
		source.HUSTR_24,
		source.HUSTR_25,
		source.HUSTR_26,
		source.HUSTR_27,
		source.HUSTR_28,
		source.HUSTR_29,
		source.HUSTR_30,
		source.HUSTR_31,
		source.HUSTR_32,
	}
end

local mapnames = BuildDoom1MapNames(strings)
local mapnames2 = BuildDoom2MapNames(strings)

const function SetLanguage(value: number)
	language = value
	strings = if value == Definitions.french then French else English
	mapnames = BuildDoom1MapNames(strings)
	mapnames2 = BuildDoom2MapNames(strings)
end

const function GetPrimaryPlayer()
	const players = Setup.GetPlayers()
	local player = players[0]

	if player == nil then
		player = players[1]
	end

	return player :: HUDPlayer?
end

const function InitTextLibrary()
end

const function PatchWidth(patch: buffer): number
	return buffer.readi16(patch, 0)
end

const function PatchHeight(patch: buffer): number
	return buffer.readi16(patch, 2)
end

const function ClearTextLine(t: TextLine)
	t.len = 0
	t.l = ""
	t.needsupdate = 4
end

const function InitTextLine(t: TextLine, x: number, y: number, font: Font, sc: number)
	t.x = x
	t.y = y
	t.f = font
	t.sc = sc
	ClearTextLine(t)
end

const function AddCharToTextLine(t: TextLine, ch: string | number): boolean
	if typeof(ch) == "number" then
		ch = string.char(ch)
	end

	if typeof(ch) ~= "string" or #ch == 0 then
		return false
	end

	if t.len == MaxLineLength then
		return false
	end

	t.l ..= string.sub(ch, 1, 1)
	t.len += 1
	t.needsupdate = 4
	return true
end

const function DrawTextLine(l: TextLine, drawcursor: boolean)
	local x = l.x

	for index = 1, l.len do
		const c = string.byte(string.upper(string.sub(l.l, index, index)))

		if c ~= 32 and c ~= nil and c >= l.sc and c <= 95 then
			const patch = l.f[c - l.sc]

			if typeof(patch) ~= "buffer" then
				continue
			end

			const width = PatchWidth(patch)

			if x + width > Definitions.SCREENWIDTH then
				break
			end

			Video.DrawPatchDirectScreen(x, l.y, FG, patch)
			x += width
		else
			x += 4

			if x >= Definitions.SCREENWIDTH then
				break
			end
		end
	end

	if drawcursor then
		const cursor = l.f[95 - l.sc]

		if typeof(cursor) == "buffer" and x + PatchWidth(cursor) <= Definitions.SCREENWIDTH then
			Video.DrawPatchDirectScreen(x, l.y, FG, cursor)
		end
	end
end

const function EraseTextLine(l: TextLine)
	if not Automap.IsActive() and State.viewwindowx ~= 0 and l.needsupdate ~= 0 then
		const font0 = l.f[0]
		const lh = PatchHeight(font0) + 1
		const renderWidth = Video.GetScreenWidth()

		for y = l.y, l.y + lh - 1 do
			const renderY0, renderY1 = VideoMode.MapScreenYRange(y, 1)

			for renderY = renderY0, renderY1 - 1 do
				const yoffset = renderY * renderWidth

				if renderY < State.viewwindowy or renderY >= State.viewwindowy + State.viewheight then
					Draw.VideoErase(yoffset, renderWidth)
				else
					const rightBorderStart = State.viewwindowx + State.scaledviewwidth
					const rightBorderWidth = renderWidth - rightBorderStart

					Draw.VideoErase(yoffset, State.viewwindowx)

					if rightBorderWidth > 0 then
						Draw.VideoErase(yoffset + rightBorderStart, rightBorderWidth)
					end
				end
			end
		end
	end

	if l.needsupdate ~= 0 then
		l.needsupdate -= 1
	end
end

const function InitScrollingText(
	s: ScrollingText,
	x: number,
	y: number,
	h: number,
	font: Font,
	startchar: number,
	on: () -> boolean
)
	s.h = h
	s.on = on
	s.laston = true
	s.cl = 0
	s.l = {}

	for index = 0, h - 1 do
		const line: TextLine = {} :: TextLine
		InitTextLine(line, x, y - index * (PatchHeight(font[0]) + 1), font, startchar)
		s.l[index] = line
	end
end

const function AddLineToScrollingText(s: ScrollingText)
	s.cl += 1

	if s.cl == s.h then
		s.cl = 0
	end

	ClearTextLine(s.l[s.cl])

	for index = 0, s.h - 1 do
		s.l[index].needsupdate = 4
	end
end

const function AddMessageToScrollingText(s: ScrollingText, prefix: string?, msg: string)
	AddLineToScrollingText(s)

	if prefix ~= nil then
		for index = 1, #prefix do
			AddCharToTextLine(s.l[s.cl], string.sub(prefix, index, index))
		end
	end

	for index = 1, #msg do
		AddCharToTextLine(s.l[s.cl], string.sub(msg, index, index))
	end
end

const function DrawScrollingText(s: ScrollingText)
	if not s.on() then
		return
	end

	for index = 0, s.h - 1 do
		local lineIndex = s.cl - index

		if lineIndex < 0 then
			lineIndex += s.h
		end

		DrawTextLine(s.l[lineIndex], false)
	end
end

const function EraseScrollingText(s: ScrollingText)
	for index = 0, s.h - 1 do
		if s.laston and not s.on() then
			s.l[index].needsupdate = 4
		end

		EraseTextLine(s.l[index])
	end

	s.laston = s.on()
end

const function GetMapTitle(): string
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()
	const gamemode = Setup.GetGameMode()

	if gamemode == Definitions.commercial then
		return mapnames2[map - 1] or "NEWLEVEL"
	end

	const index = (episode - 1) * 9 + map - 1
	return mapnames[index] or "NEWLEVEL"
end

const function ResetTitle()
	ClearTextLine(w_title)

	const title = GetMapTitle()

	for index = 1, #title do
		AddCharToTextLine(w_title, string.sub(title, index, index))
	end
end

const function Init()
	if loaded then
		return
	end

	InitTextLibrary()

	local codepoint = FontStart

	for index = 0, FontSize - 1 do
		hu_font[index] = Wad.CacheLumpName(string.format("STCFN%03d", codepoint), Zone.STATIC)
		codepoint += 1
	end

	loaded = true
end

const function Stop()
	headsupactive = false
end

const function Start()
	if not loaded then
		Init()
	end

	if headsupactive then
		Stop()
	end

	plr = GetPrimaryPlayer()
	message_on = false
	message_dontfuckwithme = false
	message_nottobefuckedwith = false

	InitScrollingText(w_message, MessageX, MessageY, MessageHeight, hu_font, FontStart, function(): boolean
		return message_on
	end)

	InitTextLine(
		w_title,
		0,
		167 - PatchHeight(hu_font[0]),
		hu_font,
		FontStart
	)

	ResetTitle()
	headsupactive = true
end

const function Drawer()
	if not headsupactive then
		return
	end

	DrawScrollingText(w_message)

	if Automap.IsActive() then
		DrawTextLine(w_title, false)
	end
end

const function Erase()
	if not headsupactive then
		return
	end

	EraseScrollingText(w_message)
	EraseTextLine(w_title)
end

const function Ticker()
	if not headsupactive or plr == nil then
		return
	end

	if message_counter ~= 0 then
		message_counter -= 1

		if message_counter == 0 then
			message_on = false
			message_nottobefuckedwith = false
		end
	end

	if showMessages or message_dontfuckwithme then
		const message = plr.message

		if typeof(message) == "string" and ((not message_nottobefuckedwith) or message_dontfuckwithme) then
			AddMessageToScrollingText(w_message, nil, message)
			plr.message = false
			message_on = true
			message_counter = MessageTimeout
			message_nottobefuckedwith = message_dontfuckwithme
			message_dontfuckwithme = false
		end
	end
end

const function DequeueChatChar(): number
	return 0
end

const function Responder(ev: Event): boolean

	if ev.type ~= 0 then
		return false
	end

	if ev.data1 == MessageRefreshKey then
		message_on = true
		message_counter = MessageTimeout
		return true
	end

	return false
end

const function Reset()
	plr = nil
	w_title = {} :: TextLine
	w_message = {} :: ScrollingText
	message_on = false
	message_dontfuckwithme = false
	message_nottobefuckedwith = false
	message_counter = 0
	headsupactive = false
	loaded = false
	table.clear(hu_font)
end

const function GetLanguage(): number
	return language
end

const function SetShowMessages(value: boolean)
	showMessages = value
end

const function GetShowMessages(): boolean
	return showMessages
end

const function SetMessageDontFuckWithMe(value: boolean)
	message_dontfuckwithme = value
end

const function GetHeadsupActive(): boolean
	return headsupactive
end

SetLanguage(language)

return {
	FontStart = FontStart,
	FontEnd = FontEnd,
	FontSize = FontSize,
	MessageRefreshKey = MessageRefreshKey,
	MessageX = MessageX,
	MessageY = MessageY,
	MessageWidth = MessageWidth,
	MessageHeight = MessageHeight,
	MessageTimeout = MessageTimeout,
	CharEraseKey = CharEraseKey,
	MaxLines = MaxLines,
	MaxLineLength = MaxLineLength,
	BG = BG,
	FG = FG,
	hu_font = hu_font,

	Reset = Reset,
	SetLanguage = SetLanguage,
	GetLanguage = GetLanguage,
	SetShowMessages = SetShowMessages,
	GetShowMessages = GetShowMessages,
	SetMessageDontFuckWithMe = SetMessageDontFuckWithMe,
	GetHeadsupActive = GetHeadsupActive,

	Init = Init,
	Start = Start,
	Stop = Stop,
	Responder = Responder,
	Ticker = Ticker,
	Drawer = Drawer,
	Erase = Erase,
	DequeueChatChar = DequeueChatChar,
}
