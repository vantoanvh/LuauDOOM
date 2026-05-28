--!native
--!optimize 2

-- Port of f_finale.c, f_finale.h.
-- Doom end-of-episode text/art flow and Doom II cast sequence.
-- Intentional Luau difference: game-state transitions are host-driven
-- instead of global `gameaction`/`gamestate`.

const Definitions = require("../Engine/Definitions")
const English = require("../Doom/English")
const Host = require("../Engine/Shared").Finale
const French = require("../Doom/French")
const HUD = require("./HUD")
const Info = require("../Doom/Info")
const Setup = require("../Play/Setup")
const Sounds = require("../Doom/Sounds")
const State = require("../Renderer/State")
const Video = require("../System/Video")
const VideoMode = require("../System/VideoMode")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const SCREENWIDTH = Definitions.SCREENWIDTH
const SCREENHEIGHT = Definitions.SCREENHEIGHT
const TEXTSPEED = 3
const TEXTWAIT = 250
const FRAMEMASK = 0x7FFF
const KeyDownEvent = 0

type Event = {
	type: number,
	data1: number?,
	data2: number?,
	data3: number?,
}

local language = Definitions.english
local strings = English

const castorder = {
	[0] = { nameKey = "ZOMBIE", type = Info.POSSESSED },
	{ nameKey = "SHOTGUN", type = Info.SHOTGUY },
	{ nameKey = "HEAVY", type = Info.CHAINGUY },
	{ nameKey = "IMP", type = Info.TROOP },
	{ nameKey = "DEMON", type = Info.SERGEANT },
	{ nameKey = "LOST", type = Info.SKULL },
	{ nameKey = "CACO", type = Info.HEAD },
	{ nameKey = "HELL", type = Info.KNIGHT },
	{ nameKey = "BARON", type = Info.BRUISER },
	{ nameKey = "ARACH", type = Info.BABY },
	{ nameKey = "PAIN", type = Info.PAIN },
	{ nameKey = "REVEN", type = Info.UNDEAD },
	{ nameKey = "MANCU", type = Info.FATSO },
	{ nameKey = "ARCH", type = Info.VILE },
	{ nameKey = "SPIDER", type = Info.SPIDER },
	{ nameKey = "CYBER", type = Info.CYBORG },
	{ nameKey = "HERO", type = Info.PLAYER },
	{ nameKey = false, type = 0 },
}

local active = false
local finalestage = 0
local finalecount = 0
local finaletext = ""
local finaleflat = "F_SKY1"
local lastbunnystage = 0

local castnum = 0
local casttics = 0
local caststate = false
local castdeath = false
local castframes = 0
local castonmelee = 0
local castattacking = false

const function SetLanguage(value: number)
	language = value
	strings = if value == Definitions.french then French else English
end

const function GetString(name: string): string
	const value = strings[name]

	if typeof(value) == "string" then
		return value
	end

	const fallback = English[name]

	if typeof(fallback) == "string" then
		return fallback
	end

	return name
end

const function RequireState(index: number, context: string)
	const state = Info.states[index]


	return state
end

const function RequireMobjInfo(index: number, context: string)
	const info = Info.mobjinfo[index]


	return info
end

const function RequireFontPatch(index: number, context: string): buffer
	const patch = HUD.hu_font[index]


	return patch
end

const function PatchWidth(patch: buffer, context: string): number

	return buffer.readi16(patch, 0)
end

const function StartSound(origin: unknown, sound: unknown)
	const callback = Host.startSound

	if callback ~= nil and typeof(sound) == "number" and sound ~= 0 then
		callback(origin, sound)
	end
end

const function ChangeMusic(music: number, looping: boolean)
	const callback = Host.changeMusic

	if callback ~= nil then
		callback(music, looping)
	end
end

const function CallWorldDone()
	const callback = Host.worldDone

	if callback ~= nil then
		callback()
	end
end

const function RequestWipe()
	const callback = Host.requestWipe

	if callback ~= nil then
		callback()
	end
end

const function GetPrimaryPlayer()
	const players = Setup.GetPlayers()
	local player = players[0]

	if player == nil then
		player = players[1]
	end

	return player
end

const function ReadPatchColumnOffset(patch: buffer, column: number, context: string): number
	const offset = buffer.readi32(patch, 8 + column * 4)


	return offset
end

const function ReadPatchPost(patch: buffer, columnOffset: number, context: string): (number, number, number)

	const topdelta = buffer.readu8(patch, columnOffset)

	if topdelta == 0xFF then
		return topdelta, 0, columnOffset + 1
	end


	const count = buffer.readu8(patch, columnOffset + 1)
	const sourceOffset = columnOffset + 3


	return topdelta, count, sourceOffset
end

const function MapLogicalXRange(x: number, width: number): (number, number)
	return VideoMode.MapLogicalXRange(x, width)
end

const function MapLogicalYRange(y: number, height: number): (number, number)
	return VideoMode.MapLogicalYRange(y, height)
end

const function FillBackgroundFlat(name: string)
	const flat = Wad.CacheLumpName(name, Zone.CACHE)
	const screen = Video.GetScreenBuffer(0)
	const renderWidth = Video.GetScreenWidth()


	for y = 0, SCREENHEIGHT - 1 do
		const renderY0, renderY1 = MapLogicalYRange(y, 1)
		const sourceOffset = bit32.band(y, 63) * 64

		for x = 0, SCREENWIDTH - 1 do
			const color = buffer.readu8(flat, sourceOffset + bit32.band(x, 63))
			const renderX0, renderX1 = MapLogicalXRange(x, 1)

			for renderY = renderY0, renderY1 - 1 do
				const dest = renderY * renderWidth + renderX0

				for renderX = renderX0, renderX1 - 1 do
					buffer.writeu8(screen, dest + (renderX - renderX0), color)
				end
			end
		end
	end

	Video.MarkRect(0, 0, SCREENWIDTH, SCREENHEIGHT)
end

const function SelectFinaleContent(secretExit: boolean): (string, string, number)
	const gamemode = Setup.GetGameMode()
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()

	if gamemode == Definitions.shareware or gamemode == Definitions.registered or gamemode == Definitions.retail then
		if episode == 1 then
			return "FLOOR4_8", GetString("E1TEXT"), Sounds.mus_victor
		end

		if episode == 2 then
			return "SFLR6_1", GetString("E2TEXT"), Sounds.mus_victor
		end

		if episode == 3 then
			return "MFLR8_4", GetString("E3TEXT"), Sounds.mus_victor
		end

		if episode == 4 then
			return "MFLR8_3", GetString("E4TEXT"), Sounds.mus_victor
		end
	end

	if gamemode == Definitions.commercial then
		if map == 15 and secretExit then
			return "RROCK13", GetString("C5TEXT"), Sounds.mus_read_m
		end

		if map == 31 and secretExit then
			return "RROCK19", GetString("C6TEXT"), Sounds.mus_read_m
		end

		if map == 6 then
			return "SLIME16", GetString("C1TEXT"), Sounds.mus_read_m
		end

		if map == 11 then
			return "RROCK14", GetString("C2TEXT"), Sounds.mus_read_m
		end

		if map == 20 then
			return "RROCK07", GetString("C3TEXT"), Sounds.mus_read_m
		end

		if map == 30 then
			return "RROCK17", GetString("C4TEXT"), Sounds.mus_read_m
		end
	end

	return "F_SKY1", GetString("C1TEXT"), Sounds.mus_read_m
end

const function StartCast()
	castnum = 0

	const info = RequireMobjInfo(castorder[castnum].type, "StartCast")

	RequestWipe()
	caststate = RequireState(info.seestate, "StartCast")
	casttics = caststate.tics
	castdeath = false
	castframes = 0
	castonmelee = 0
	castattacking = false
	finalestage = 2
	ChangeMusic(Sounds.mus_evil, true)
end

const function StartFinale(secretExit: boolean?)
	const flat, text, music = SelectFinaleContent(secretExit == true)

	active = true
	finalestage = 0
	finalecount = 0
	finaleflat = flat
	finaletext = text
	lastbunnystage = 0
	castnum = 0
	casttics = 0
	caststate = false
	castdeath = false
	castframes = 0
	castonmelee = 0
	castattacking = false
	ChangeMusic(music, true)
end

const function CastTicker()
	local st = 0
	local sfx = 0

	casttics -= 1

	if casttics > 0 then
		return
	end


	if caststate.tics == -1 or caststate.nextstate == Info.NULL then
		castnum += 1
		castdeath = false

		if castorder[castnum] == nil or castorder[castnum].nameKey == false then
			castnum = 0
		end

		const info = RequireMobjInfo(castorder[castnum].type, "CastTicker")

		if typeof(info.seesound) == "number" and info.seesound ~= 0 then
			StartSound(nil, info.seesound)
		end

		caststate = RequireState(info.seestate, "CastTicker")
		castframes = 0
	else
		if caststate == Info.states[Info.PLAY_ATK1] then
			castattacking = false
			castframes = 0
			caststate = RequireState(RequireMobjInfo(castorder[castnum].type, "CastTicker").seestate, "CastTicker")
		else
			st = caststate.nextstate
			caststate = RequireState(st, "CastTicker")
			castframes += 1

			if st == Info.PLAY_ATK1 then
				sfx = Sounds.sfx_dshtgn
			elseif st == Info.POSS_ATK2 then
				sfx = Sounds.sfx_pistol
			elseif st == Info.SPOS_ATK2 then
				sfx = Sounds.sfx_shotgn
			elseif st == Info.VILE_ATK2 then
				sfx = Sounds.sfx_vilatk
			elseif st == Info.SKEL_FIST2 then
				sfx = Sounds.sfx_skeswg
			elseif st == Info.SKEL_FIST4 then
				sfx = Sounds.sfx_skepch
			elseif st == Info.SKEL_MISS2 then
				sfx = Sounds.sfx_skeatk
			elseif st == Info.FATT_ATK8 or st == Info.FATT_ATK5 or st == Info.FATT_ATK2 then
				sfx = Sounds.sfx_firsht
			elseif st == Info.CPOS_ATK2 or st == Info.CPOS_ATK3 or st == Info.CPOS_ATK4 then
				sfx = Sounds.sfx_shotgn
			elseif st == Info.TROO_ATK3 then
				sfx = Sounds.sfx_claw
			elseif st == Info.SARG_ATK2 then
				sfx = Sounds.sfx_sgtatk
			elseif st == Info.BOSS_ATK2 or st == Info.BOS2_ATK2 or st == Info.HEAD_ATK2 then
				sfx = Sounds.sfx_firsht
			elseif st == Info.SKULL_ATK2 then
				sfx = Sounds.sfx_sklatk
			elseif st == Info.SPID_ATK2 or st == Info.SPID_ATK3 then
				sfx = Sounds.sfx_shotgn
			elseif st == Info.BSPI_ATK2 then
				sfx = Sounds.sfx_plasma
			elseif st == Info.CYBER_ATK2 or st == Info.CYBER_ATK4 or st == Info.CYBER_ATK6 then
				sfx = Sounds.sfx_rlaunc
			elseif st == Info.PAIN_ATK3 then
				sfx = Sounds.sfx_sklatk
			end

			if sfx ~= 0 then
				StartSound(nil, sfx)
			end
		end
	end

	if castframes == 12 then
		const info = RequireMobjInfo(castorder[castnum].type, "CastTicker")

		castattacking = true

		if castonmelee ~= 0 then
			caststate = RequireState(info.meleestate, "CastTicker")
		else
			caststate = RequireState(info.missilestate, "CastTicker")
		end

		castonmelee = bit32.bxor(castonmelee, 1)

		if caststate == Info.states[Info.NULL] then
			if castonmelee ~= 0 then
				caststate = RequireState(info.meleestate, "CastTicker")
			else
				caststate = RequireState(info.missilestate, "CastTicker")
			end
		end
	end

	if castattacking then
		const info = RequireMobjInfo(castorder[castnum].type, "CastTicker")

		if castframes == 24 or caststate == Info.states[info.seestate] then
			castattacking = false
			castframes = 0
			caststate = RequireState(info.seestate, "CastTicker")
		end
	end

	casttics = caststate.tics

	if casttics == -1 then
		casttics = 15
	end
end

const function CastResponder(ev: Event): boolean
	if typeof(ev) ~= "table" or ev.type ~= KeyDownEvent then
		return false
	end

	if castdeath then
		return true
	end

	const info = RequireMobjInfo(castorder[castnum].type, "CastResponder")

	castdeath = true
	caststate = RequireState(info.deathstate, "CastResponder")
	casttics = caststate.tics
	castframes = 0
	castattacking = false

	if typeof(info.deathsound) == "number" and info.deathsound ~= 0 then
		StartSound(nil, info.deathsound)
	end

	return true
end

const function Responder(ev: Event): boolean
	if not active then
		return false
	end

	if finalestage == 2 then
		return CastResponder(ev)
	end

	return false
end

const function TextWrite()
	FillBackgroundFlat(finaleflat)

	local cx = 10
	local cy = 10
	local count = (finalecount - 10) // TEXTSPEED

	if count < 0 then
		count = 0
	end

	local index = 1

	while count > 0 do
		const ch = string.sub(finaletext, index, index)

		if ch == "" then
			break
		end

		index += 1
		count -= 1

		if ch == "\n" then
			cx = 10
			cy += 11
		else
			const upper = string.upper(ch)
			const codepoint = string.byte(upper)

			if codepoint == nil then
				break
			end

			const fontIndex = codepoint - HUD.FontStart

			if fontIndex < 0 or fontIndex >= HUD.FontSize then
				cx += 4
			else
				const patch = RequireFontPatch(fontIndex, "TextWrite")
				const width = PatchWidth(patch, "TextWrite")

				if cx + width > SCREENWIDTH then
					break
				end

				Video.DrawPatch(cx, cy, 0, patch)
				cx += width
			end
		end
	end
end

const function CastPrint(text: string)
	local width = 0

	for index = 1, #text do
		const ch = string.sub(text, index, index)
		const codepoint = string.byte(string.upper(ch))

		if codepoint == nil then
			break
		end

		const fontIndex = codepoint - HUD.FontStart

		if fontIndex < 0 or fontIndex >= HUD.FontSize then
			width += 4
		else
			width += PatchWidth(RequireFontPatch(fontIndex, "CastPrint"), "CastPrint")
		end
	end

	local cx = 160 - width // 2

	for index = 1, #text do
		const ch = string.sub(text, index, index)
		const codepoint = string.byte(string.upper(ch))

		if codepoint == nil then
			break
		end

		const fontIndex = codepoint - HUD.FontStart

		if fontIndex < 0 or fontIndex >= HUD.FontSize then
			cx += 4
		else
			const patch = RequireFontPatch(fontIndex, "CastPrint")
			const widthPart = PatchWidth(patch, "CastPrint")
			Video.DrawPatch(cx, 180, 0, patch)
			cx += widthPart
		end
	end
end

const function CastDrawer()

	Video.DrawPatch(0, 0, 0, Wad.CacheLumpName("BOSSBACK", Zone.CACHE))
	CastPrint(GetString(castorder[castnum].nameKey))

	const sprdef = State.sprites[caststate.sprite]


	const frameIndex = bit32.band(caststate.frame, FRAMEMASK)
	const sprframe = sprdef.spriteframes[frameIndex]


	const lump = sprframe.lump[0]


	const patch = Wad.CacheLumpNum(lump + State.firstspritelump, Zone.CACHE)
	const flip = sprframe.flip[0] == true

	if flip then
		Video.DrawPatchFlipped(160, 170, 0, patch)
	else
		Video.DrawPatch(160, 170, 0, patch)
	end
end

const function DrawPatchColumn(x: number, patch: buffer, col: number)
	local columnOffset = ReadPatchColumnOffset(patch, col, "DrawPatchColumn")
	const screen = Video.GetScreenBuffer(0)
	const renderWidth = Video.GetScreenWidth()
	const renderX0, renderX1 = MapLogicalXRange(x, 1)

	while true do
		const topdelta, count, sourceOffset = ReadPatchPost(patch, columnOffset, "DrawPatchColumn")

		if topdelta == 0xFF then
			break
		end

		for row = 0, count - 1 do
			const color = buffer.readu8(patch, sourceOffset + row)
			const renderY0, renderY1 = MapLogicalYRange(topdelta + row, 1)

			for renderY = renderY0, renderY1 - 1 do
				const dest = renderY * renderWidth + renderX0

				for renderX = renderX0, renderX1 - 1 do
					buffer.writeu8(screen, dest + (renderX - renderX0), color)
				end
			end
		end

		columnOffset += buffer.readu8(patch, columnOffset + 1) + 4
	end
end

const function BunnyScroll()
	const p1 = Wad.CacheLumpName("PFUB2", Zone.LEVEL)
	const p2 = Wad.CacheLumpName("PFUB1", Zone.LEVEL)

	Video.MarkRect(0, 0, SCREENWIDTH, SCREENHEIGHT)

	local scrolled = 320 - (finalecount - 230) // 2

	if scrolled > 320 then
		scrolled = 320
	end

	if scrolled < 0 then
		scrolled = 0
	end

	for x = 0, SCREENWIDTH - 1 do
		if x + scrolled < 320 then
			DrawPatchColumn(x, p1, x + scrolled)
		else
			DrawPatchColumn(x, p2, x + scrolled - 320)
		end
	end

	if finalecount < 1130 then
		return
	end

	const centerX = (SCREENWIDTH - 13 * 8) // 2
	const centerY = (SCREENHEIGHT - 8 * 8) // 2

	if finalecount < 1180 then
		Video.DrawPatch(centerX, centerY, 0, Wad.CacheLumpName("END0", Zone.CACHE))
		lastbunnystage = 0
		return
	end

	local stage = (finalecount - 1180) // 5

	if stage > 6 then
		stage = 6
	end

	if stage > lastbunnystage then
		StartSound(nil, Sounds.sfx_pistol)
		lastbunnystage = stage
	end

	Video.DrawPatch(centerX, centerY, 0, Wad.CacheLumpName(`END{stage}`, Zone.CACHE))
end

const function Ticker()
	if not active then
		return
	end

	const gamemode = Setup.GetGameMode()
	const map = Setup.GetCurrentMap()
	const player = GetPrimaryPlayer()
	local buttons = 0

	if typeof(player) == "table" and typeof(player.cmd) == "table" and typeof(player.cmd.buttons) == "number" then
		buttons = player.cmd.buttons
	end

	if gamemode == Definitions.commercial and finalecount > 50 and buttons ~= 0 then
		if map == 30 then
			StartCast()
		else
			CallWorldDone()
			return
		end
	end

	finalecount += 1

	if finalestage == 2 then
		CastTicker()
		return
	end

	if gamemode == Definitions.commercial then
		return
	end

	if finalestage == 0 and finalecount > #finaletext * TEXTSPEED + TEXTWAIT then
		finalecount = 0
		finalestage = 1
		RequestWipe()

		if Setup.GetCurrentEpisode() == 3 then
			ChangeMusic(Sounds.mus_bunny, true)
		end
	end
end

const function Drawer()
	if not active then
		return
	end

	Video.ClearScreen(0, 0)

	if finalestage == 2 then
		CastDrawer()
		return
	end

	if finalestage == 0 then
		TextWrite()
		return
	end

	const gamemode = Setup.GetGameMode()
	const episode = Setup.GetCurrentEpisode()

	if episode == 1 then
		if gamemode == Definitions.retail then
			Video.DrawPatch(0, 0, 0, Wad.CacheLumpName("CREDIT", Zone.CACHE))
		else
			Video.DrawPatch(0, 0, 0, Wad.CacheLumpName("HELP2", Zone.CACHE))
		end

		return
	end

	if episode == 2 then
		Video.DrawPatch(0, 0, 0, Wad.CacheLumpName("VICTORY2", Zone.CACHE))
		return
	end

	if episode == 3 then
		BunnyScroll()
		return
	end

	if episode == 4 then
		Video.DrawPatch(0, 0, 0, Wad.CacheLumpName("ENDPIC", Zone.CACHE))
	end
end

const function Reset()
	active = false
	finalestage = 0
	finalecount = 0
	finaletext = ""
	finaleflat = "F_SKY1"
	lastbunnystage = 0
	castnum = 0
	casttics = 0
	caststate = false
	castdeath = false
	castframes = 0
	castonmelee = 0
	castattacking = false
end

const function IsActive(): boolean
	return active
end

const function GetStage(): number
	return finalestage
end

const function GetCount(): number
	return finalecount
end

const function GetText(): string
	return finaletext
end

const function GetFlat(): string
	return finaleflat
end

SetLanguage(language)

return {
	TEXTSPEED = TEXTSPEED,
	TEXTWAIT = TEXTWAIT,

	Reset = Reset,
	SetLanguage = SetLanguage,
	IsActive = IsActive,
	GetStage = GetStage,
	GetCount = GetCount,
	GetText = GetText,
	GetFlat = GetFlat,
	StartFinale = StartFinale,
	StartCast = StartCast,
	Responder = Responder,
	Ticker = Ticker,
	Drawer = Drawer,
}
