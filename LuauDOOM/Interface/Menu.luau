--!native
--!optimize 2

-- Port of m_menu.c, m_menu.h
-- DESCRIPTION:
--	DOOM selection menu, options, episode etc.
--	Sliders and icons. Kinda widget stuff.
-- Adapted for Luau host wiring instead of DOS file I/O.

const Automap = require("./Automap")
const Definitions = require("../Engine/Definitions")
const English = require("../Doom/English")
const French = require("../Doom/French")
const HUD = require("./HUD")
const Host = require("../Engine/Shared").Menu
const Main = require("../Renderer/Main")
const State = require("../Renderer/State")
const Setup = require("../Play/Setup")
const Sounds = require("../Doom/Sounds")
const Video = require("../System/Video")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const ClearScreen = Video.ClearScreen
const DrawPatchDirect = Video.DrawPatchDirect
const CacheLumpName = Wad.CacheLumpName
const CACHE = Zone.CACHE

const function Warn(...: unknown)
	warn(...)
end

const ev_keydown = 0
const ev_mouse = 2
const ev_joystick = 3

const SAVESTRINGSIZE = 24
const SKULLXOFF = -32
const LINEHEIGHT = 16
const NUM_QUITMESSAGES = 22

type Event = {
	type: number,
	data1: number?,
	data2: number?,
	data3: number?,
}

type MenuRoutine = (choice: number) -> ()
type MessageRoutine = (response: number) -> ()
type DrawRoutine = () -> ()

type MenuItem = {
	status: number,
	name: string,
	routine: MenuRoutine?,
	alphaKey: number?,
}

type MenuDef = {
	numitems: number,
	prevMenu: MenuDef?,
	menuitems: { [number]: MenuItem },
	routine: DrawRoutine?,
	x: number,
	y: number,
	lastOn: number,
}

const quitMessages = {
	[0] = English.QUITMSG,
	"please don't leave, there's more\ndemons to toast!",
	"let's beat it -- this is turning\ninto a bloodbath!",
	"i wouldn't leave if i were you.\ndos is much worse.",
	"you're trying to say you like dos\nbetter than me, right?",
	"don't leave yet -- there's a\ndemon around that corner!",
	"ya know, next time you come in here\ni'm gonna toast ya.",
	"go ahead and leave. see if i care.",
	"you want to quit?\nthen, thou hast lost an eighth!",
	"don't go now, there's a \ndimensional shambler waiting\nat the dos prompt!",
	"get outta here and go back\nto your boring programs.",
	"if i were your boss, i'd \nflatten ya in a minute!",
	"look, bud. you leave now\nand you forfeit your body count!",
	"just leave. when you come\nback, i'll be waiting with a bat.",
	"you're lucky i don't smack\nyou for thinking about leaving.",
	"fuck you, pussy!\nget the fuck out!",
	"you quit and i'll jizz\nin your cystholes!",
	"if you leave, i'll make\nthe lord drink my jizz.",
	"hey, ron! can we say\n'fuck' in the game?",
	"i'd leave: this is just\nmore monsters and levels.\nwhat a load.",
	"suck it down, asshole!\nyou're a fucking wimp!",
	"don't quit now! we're \nstill spending your money!",
}

local stringSet = English
local mouseSensitivity = 5
local showMessages = true
local detailLevel = 0
local screenblocks = 10
local screenSize = 7
local snd_SfxVolume = 8
local snd_MusicVolume = 8
local quickSaveSlot = -1
local messageToPrint = false
local messageString = ""
local messageLastMenuActive = false
local messageNeedsInput = false
local messageRoutine: MessageRoutine? = nil
local saveStringEnter = false
local saveSlot = 0
local saveCharIndex = 0
local saveOldString = ""
local inhelpscreens = false
local menuactive = false
local currentMenu: MenuDef? = nil
local itemOn = 0
local skullAnimCounter = 10
local whichSkull = 0
local menuTime = 0
local joywait = 0
local mousewait = 0
local mousey = 0
local lasty = 0
local mousex = 0
local lastx = 0
const savegamestrings: { [number]: string } = {}
local endstring = ""
local quitWait = 0

local MainMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local MainDef: MenuDef = (nil :: unknown) :: MenuDef
local EpisodeMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local EpiDef: MenuDef = (nil :: unknown) :: MenuDef
local NewGameMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local NewDef: MenuDef = (nil :: unknown) :: MenuDef
local OptionsMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local OptionsDef: MenuDef = (nil :: unknown) :: MenuDef
local ReadMenu1: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local ReadDef1: MenuDef = (nil :: unknown) :: MenuDef
local ReadMenu2: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local ReadDef2: MenuDef = (nil :: unknown) :: MenuDef
local SoundMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local SoundDef: MenuDef = (nil :: unknown) :: MenuDef
local LoadMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local LoadDef: MenuDef = (nil :: unknown) :: MenuDef
local SaveMenu: { [number]: MenuItem } = (nil :: unknown) :: { [number]: MenuItem }
local SaveDef: MenuDef = (nil :: unknown) :: MenuDef

const messages = 1
const detail = 2
const scrnsize = 3
const mousesens = 5

const sfx_vol = 0
const music_vol = 2

const load_end = 6
const readthis = 4
const quitdoom = 5
const nightmare = 4

const skullName = {
	[0] = "M_SKULL1",
	"M_SKULL2",
}

const gammamsg = {
	[0] = English.GAMMALVL0,
	English.GAMMALVL1,
	English.GAMMALVL2,
	English.GAMMALVL3,
	English.GAMMALVL4,
}

const function SyncLanguage()
	stringSet = if HUD.GetLanguage() == Definitions.french then French else English
	gammamsg[0] = stringSet.GAMMALVL0
	gammamsg[1] = stringSet.GAMMALVL1
	gammamsg[2] = stringSet.GAMMALVL2
	gammamsg[3] = stringSet.GAMMALVL3
	gammamsg[4] = stringSet.GAMMALVL4
end

const function SyncMenuActive()
	Setup.SetMenuActive(menuactive)
end

const function StartSound(soundId: number)
	const startSound = Host.startSound

	if startSound ~= nil then
		startSound(nil, soundId)
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

const function RequireCurrentMenu(_context: string): MenuDef
	const menu = currentMenu


	return menu
end

const function DrawPatchName(x: number, y: number, name: string)
	DrawPatchDirect(x, y, 0, CacheLumpName(name, CACHE))
end

const function IsUserGame(): boolean
	const callback = Host.isUserGame

	if callback ~= nil then
		return callback()
	end

	return true
end

const function IsLevelGameState(): boolean
	const callback = Host.isLevelGameState

	if callback ~= nil then
		return callback()
	end

	return true
end

const function IsDevParm(): boolean
	const callback = Host.isDevParm

	if callback ~= nil then
		return callback()
	end

	return false
end

const function GetGameTic(): number
	const callback = Host.getGameTic

	if callback ~= nil then
		return callback()
	end

	return Setup.GetLevelTime()
end

const function SetPlayerMessage(text: string)
	const player = GetPrimaryPlayer()

	if typeof(player) == "table" then
		player.message = text
		HUD.SetMessageDontFuckWithMe(true)
	end
end

-- Draw border for the savegame description
const function DrawSaveLoadBorder(x: number, y: number)
	DrawPatchName(x - 8, y + 7, "M_LSLEFT")

	for _ = 1, 24 do
		DrawPatchName(x, y + 7, "M_LSCNTR")
		x += 8
	end

	DrawPatchName(x, y + 7, "M_LSRGHT")
end

-- Find string width from hu_font chars
const function StringWidth(text: string): number
	local width = 0

	for index = 1, #text do
		const codepoint = string.byte(string.upper(string.sub(text, index, index)))
		const fontIndex = codepoint - HUD.FontStart

		if fontIndex < 0 or fontIndex >= HUD.FontSize then
			width += 4
		else
			width += buffer.readi16(HUD.hu_font[fontIndex], 0)
		end
	end

	return width
end

-- Find string height from hu_font chars
const function StringHeight(text: string): number
	const height = buffer.readi16(HUD.hu_font[0], 2)
	local total = height

	for index = 1, #text do
		if string.byte(text, index) == 10 then
			total += height
		end
	end

	return total
end

-- Write a string using the hu_font
const function WriteText(x: number, y: number, text: string)
	local cx = x
	local cy = y

	for index = 1, #text do
		const ch = string.sub(text, index, index)

		if ch == "\n" then
			cx = x
			cy += 12
			continue
		end

		const codepoint = string.byte(string.upper(ch))
		const fontIndex = codepoint - HUD.FontStart

		if fontIndex < 0 or fontIndex >= HUD.FontSize then
			cx += 4
			continue
		end

		const patch = HUD.hu_font[fontIndex]
		const width = buffer.readi16(patch, 0)

		if cx + width > Definitions.SCREENWIDTH then
			break
		end

		DrawPatchDirect(cx, cy, 0, patch)
		cx += width
	end
end

const function DrawThermo(x: number, y: number, thermWidth: number, thermDot: number)
	local xx = x

	DrawPatchName(xx, y, "M_THERML")
	xx += 8

	for _ = 1, thermWidth do
		DrawPatchName(xx, y, "M_THERMM")
		xx += 8
	end

	DrawPatchName(xx, y, "M_THERMR")
	DrawPatchName(x + 8 + thermDot * 8, y, "M_THERMO")
end

-- ReadSaveStrings
--  read the strings from the savegame files
const function ReadSaveStrings()
	for index = 0, load_end - 1 do
		local description: string? = nil

		if Host.getSaveDescription ~= nil then
			description = Host.getSaveDescription(index)
		end

		if typeof(description) == "string" then
			savegamestrings[index] = string.sub(description, 1, SAVESTRINGSIZE - 1)
			LoadMenu[index].status = 1
		else
			savegamestrings[index] = stringSet.EMPTYSTRING
			LoadMenu[index].status = 0
		end
	end
end

const function SetupNextMenu(menudef: MenuDef)
	currentMenu = menudef
	itemOn = menudef.lastOn
end

const function ClearMenus()
	menuactive = false
	SyncMenuActive()
end

const function ForceClearAll()
	inhelpscreens = false
	menuactive = false
	messageToPrint = false
	messageString = ""
	messageNeedsInput = false
	messageRoutine = nil
	saveStringEnter = false
	SyncMenuActive()
end

const function StartMessage(text: string, routine: MessageRoutine?, input: boolean)
	messageLastMenuActive = menuactive
	messageToPrint = true
	messageString = text
	messageRoutine = routine
	messageNeedsInput = input
	menuactive = true
	SyncMenuActive()
end

const function BuildMenus()
	const function Item(status: number, name: string, routine: MenuRoutine?, alphaKey: number?): MenuItem
		return {
			status = status,
			name = name,
			routine = routine,
			alphaKey = alphaKey,
		}
	end

	MainMenu = {
		[0] = Item(1, "M_NGAME", nil, 78),
		Item(1, "M_OPTION", nil, 79),
		Item(1, "M_LOADG", nil, 76),
		Item(1, "M_SAVEG", nil, 83),
		Item(1, "M_RDTHIS", nil, 82),
		Item(1, "M_QUITG", nil, 81),
	}

	EpisodeMenu = {
		[0] = Item(1, "M_EPI1", nil, 75),
		Item(1, "M_EPI2", nil, 84),
		Item(1, "M_EPI3", nil, 73),
		Item(1, "M_EPI4", nil, 84),
	}

	NewGameMenu = {
		[0] = Item(1, "M_JKILL", nil, 73),
		Item(1, "M_ROUGH", nil, 72),
		Item(1, "M_HURT", nil, 72),
		Item(1, "M_ULTRA", nil, 85),
		Item(1, "M_NMARE", nil, 78),
	}

	OptionsMenu = {
		[0] = Item(1, "M_ENDGAM", nil, 69),
		Item(1, "M_MESSG", nil, 77),
		Item(1, "M_DETAIL", nil, 71),
		Item(2, "M_SCRNSZ", nil, 83),
		Item(-1, "", nil, nil),
		Item(2, "M_MSENS", nil, 77),
		Item(-1, "", nil, nil),
		Item(1, "M_SVOL", nil, 83),
	}

	ReadMenu1 = {
		[0] = Item(1, "", nil, 0),
	}

	ReadMenu2 = {
		[0] = Item(1, "", nil, 0),
	}

	SoundMenu = {
		[0] = Item(2, "M_SFXVOL", nil, 83),
		Item(-1, "", nil, nil),
		Item(2, "M_MUSVOL", nil, 77),
		Item(-1, "", nil, nil),
	}

	LoadMenu = {
		[0] = Item(1, "", nil, 49),
		Item(1, "", nil, 50),
		Item(1, "", nil, 51),
		Item(1, "", nil, 52),
		Item(1, "", nil, 53),
		Item(1, "", nil, 54),
	}

	SaveMenu = {
		[0] = Item(1, "", nil, 49),
		Item(1, "", nil, 50),
		Item(1, "", nil, 51),
		Item(1, "", nil, 52),
		Item(1, "", nil, 53),
		Item(1, "", nil, 54),
	}

	MainDef = { numitems = 6, prevMenu = nil, menuitems = MainMenu, routine = nil, x = 97, y = 64, lastOn = 0 }
	EpiDef = { numitems = 4, prevMenu = MainDef, menuitems = EpisodeMenu, routine = nil, x = 48, y = 63, lastOn = 0 }
	NewDef = { numitems = 5, prevMenu = EpiDef, menuitems = NewGameMenu, routine = nil, x = 48, y = 63, lastOn = 2 }
	OptionsDef = { numitems = 8, prevMenu = MainDef, menuitems = OptionsMenu, routine = nil, x = 60, y = 37, lastOn = 0 }
	ReadDef1 = { numitems = 1, prevMenu = MainDef, menuitems = ReadMenu1, routine = nil, x = 280, y = 185, lastOn = 0 }
	ReadDef2 = { numitems = 1, prevMenu = ReadDef1, menuitems = ReadMenu2, routine = nil, x = 330, y = 175, lastOn = 0 }
	SoundDef = { numitems = 4, prevMenu = OptionsDef, menuitems = SoundMenu, routine = nil, x = 80, y = 64, lastOn = 0 }
	LoadDef = { numitems = 6, prevMenu = MainDef, menuitems = LoadMenu, routine = nil, x = 80, y = 54, lastOn = 0 }
	SaveDef = { numitems = 6, prevMenu = MainDef, menuitems = SaveMenu, routine = nil, x = 80, y = 54, lastOn = 0 }
end

local epi = 0
local tempstring = ""

const function SyncRuntimeState()
	SyncLanguage()
	showMessages = HUD.GetShowMessages()
	screenblocks = if Setup.GetGameMode() == Definitions.indetermined then 10 else State.setblocks
	detailLevel = State.setdetail
	screenSize = screenblocks - 3

	const getSfxVolume = Host.getSfxVolume

	if getSfxVolume ~= nil then
		const volume = getSfxVolume()

		if typeof(volume) == "number" then
			snd_SfxVolume = volume
		end
	end

	const getMusicVolume = Host.getMusicVolume

	if getMusicVolume ~= nil then
		const volume = getMusicVolume()

		if typeof(volume) == "number" then
			snd_MusicVolume = volume
		end
	end
end

const function StartControlPanel()
	if menuactive then
		return
	end

	SyncRuntimeState()
	menuactive = true
	currentMenu = MainDef
	itemOn = MainDef.lastOn
	SyncMenuActive()
end

-- LoadGame & Cie.
const function DrawLoad()
	DrawPatchName(72, 28, "M_LOADG")

	for index = 0, load_end - 1 do
		DrawSaveLoadBorder(LoadDef.x, LoadDef.y + LINEHEIGHT * index)
		WriteText(LoadDef.x, LoadDef.y + LINEHEIGHT * index, savegamestrings[index])
	end
end

--  SaveGame & Cie.
const function DrawSave()
	DrawPatchName(72, 28, "M_SAVEG")

	for index = 0, load_end - 1 do
		DrawSaveLoadBorder(LoadDef.x, LoadDef.y + LINEHEIGHT * index)
		WriteText(LoadDef.x, LoadDef.y + LINEHEIGHT * index, savegamestrings[index])
	end

	if saveStringEnter then
		const width = StringWidth(savegamestrings[saveSlot])
		WriteText(LoadDef.x + width, LoadDef.y + LINEHEIGHT * saveSlot, "_")
	end
end

-- M_Responder calls this when user is finished
const function DoSave(slot: number)
	if Host.saveGame ~= nil then
		Host.saveGame(slot, savegamestrings[slot])
	end

	ClearMenus()

	if quickSaveSlot == -2 then
		quickSaveSlot = slot
	end
end

const function LoadSelect(choice: number)
	if Host.loadGame ~= nil then
		Host.loadGame(choice)
	end

	ClearMenus()
end

const function LoadGame(_choice: number)
	SetupNextMenu(LoadDef)
	ReadSaveStrings()
end

const function SaveSelect(choice: number)
	saveStringEnter = true
	saveSlot = choice
	saveOldString = savegamestrings[choice]

	if savegamestrings[choice] == stringSet.EMPTYSTRING then
		savegamestrings[choice] = ""
	end

	saveCharIndex = #savegamestrings[choice]
end

const function SaveGame(_choice: number)
	if not IsUserGame() then
		StartMessage(stringSet.SAVEDEAD, nil, false)
		return
	end

	if not IsLevelGameState() then
		return
	end

	SetupNextMenu(SaveDef)
	ReadSaveStrings()
end

const function QuickSaveResponse(ch: number)
	if ch == 89 then
		DoSave(quickSaveSlot)
		StartSound(Sounds.sfx_swtchx)
	end
end

const function QuickSave()
	if not IsUserGame() then
		StartSound(Sounds.sfx_oof)
		return
	end

	if not IsLevelGameState() then
		return
	end

	if quickSaveSlot < 0 then
		StartControlPanel()
		ReadSaveStrings()
		SetupNextMenu(SaveDef)
		quickSaveSlot = -2
		return
	end

	tempstring = string.format(stringSet.QSPROMPT, savegamestrings[quickSaveSlot])
	StartMessage(tempstring, QuickSaveResponse, true)
end

const function QuickLoadResponse(ch: number)
	if ch == 89 then
		LoadSelect(quickSaveSlot)
		StartSound(Sounds.sfx_swtchx)
	end
end

const function QuickLoad()
	if quickSaveSlot < 0 then
		StartMessage(stringSet.QSAVESPOT, nil, false)
		return
	end

	tempstring = string.format(stringSet.QLPROMPT, savegamestrings[quickSaveSlot])
	StartMessage(tempstring, QuickLoadResponse, true)
end

-- Read This Menus
-- Had a "quick hack to fix romero bug"
const function DrawReadThis1()
	inhelpscreens = true
	const gamemode = Setup.GetGameMode()
	ClearScreen(0, 0)

	if gamemode == Definitions.commercial then
		DrawPatchName(0, 0, "HELP")
	elseif gamemode == Definitions.retail then
		DrawPatchName(0, 0, "HELP1")
	elseif gamemode == Definitions.shareware or gamemode == Definitions.registered then
		-- DOS Doom 1.9 shows HELP2 first for shareware/registered.
		DrawPatchName(0, 0, "HELP2")
	end
end

-- Read This Menus - optional second page.
const function DrawReadThis2()
	inhelpscreens = true
	const gamemode = Setup.GetGameMode()
	ClearScreen(0, 0)

	if gamemode == Definitions.retail or gamemode == Definitions.commercial then
		DrawPatchName(0, 0, "CREDIT")
	elseif gamemode == Definitions.shareware or gamemode == Definitions.registered then
		DrawPatchName(0, 0, "HELP1")
	end
end

const function DrawSound()
	DrawPatchName(60, 38, "M_SVOL")
	DrawThermo(SoundDef.x, SoundDef.y + LINEHEIGHT * (sfx_vol + 1), 16, snd_SfxVolume)
	DrawThermo(SoundDef.x, SoundDef.y + LINEHEIGHT * (music_vol + 1), 16, snd_MusicVolume)
end

const function OpenSoundMenu(_choice: number)
	SetupNextMenu(SoundDef)
end

const function SfxVol(choice: number)
	if choice == 0 then
		if snd_SfxVolume > 0 then
			snd_SfxVolume -= 1
		end
	elseif choice == 1 then
		if snd_SfxVolume < 15 then
			snd_SfxVolume += 1
		end
	end

	if Host.setSfxVolume ~= nil then
		Host.setSfxVolume(snd_SfxVolume)
	end
end

const function MusicVol(choice: number)
	if choice == 0 then
		if snd_MusicVolume > 0 then
			snd_MusicVolume -= 1
		end
	elseif choice == 1 then
		if snd_MusicVolume < 15 then
			snd_MusicVolume += 1
		end
	end

	if Host.setMusicVolume ~= nil then
		Host.setMusicVolume(snd_MusicVolume)
	end
end

const function DrawMainMenu()
	DrawPatchName(94, 2, "M_DOOM")
end

const function DrawNewGame()
	DrawPatchName(96, 14, "M_NEWG")
	DrawPatchName(54, 38, "M_SKILL")
end

const function NewGame(_choice: number)
	if Setup.GetGameMode() == Definitions.commercial then
		SetupNextMenu(NewDef)
	else
		SetupNextMenu(EpiDef)
	end
end

const function DrawEpisode()
	DrawPatchName(54, 38, "M_EPISOD")
end

const function VerifyNightmare(ch: number)
	if ch ~= 89 then
		return
	end

	if Host.startNewGame ~= nil then
		Host.startNewGame(nightmare, epi + 1, 1)
	end

	ClearMenus()
end

const function ChooseSkill(choice: number)
	if choice == nightmare then
		StartMessage(stringSet.NIGHTMARE, VerifyNightmare, true)
		return
	end

	if Host.startNewGame ~= nil then
		Host.startNewGame(choice, epi + 1, 1)
	end

	ClearMenus()
end

const function Episode(choice: number)
	const gamemode = Setup.GetGameMode()

	if gamemode == Definitions.shareware and choice ~= 0 then
		StartMessage(stringSet.SWSTRING, nil, false)
		SetupNextMenu(ReadDef1)
		return
	end

	if gamemode == Definitions.registered and choice > 2 then
		Warn("Episode: 4th episode requires UltimateDOOM")
		choice = 0
	end

	epi = choice
	SetupNextMenu(NewDef)
end

const detailNames = {
	[0] = "M_GDHIGH",
	"M_GDLOW",
}

const msgNames = {
	[0] = "M_MSGOFF",
	"M_MSGON",
}

const function DrawOptions()
	DrawPatchName(108, 15, "M_OPTTTL")
	DrawPatchName(OptionsDef.x + 175, OptionsDef.y + LINEHEIGHT * detail, detailNames[detailLevel])
	DrawPatchName(OptionsDef.x + 120, OptionsDef.y + LINEHEIGHT * messages, msgNames[if showMessages then 1 else 0])
	DrawThermo(OptionsDef.x, OptionsDef.y + LINEHEIGHT * (mousesens + 1), 10, mouseSensitivity)
	DrawThermo(OptionsDef.x, OptionsDef.y + LINEHEIGHT * (scrnsize + 1), 9, screenSize)
end

const function Options(_choice: number)
	SetupNextMenu(OptionsDef)
end

const function ChangeMessages(_choice: number)
	showMessages = not showMessages
	HUD.SetShowMessages(showMessages)

	if showMessages then
		SetPlayerMessage(stringSet.MSGON)
	else
		SetPlayerMessage(stringSet.MSGOFF)
	end
end

const function EndGameResponse(ch: number)
	if ch ~= 89 then
		return
	end

	const menu = RequireCurrentMenu("EndGameResponse")
	menu.lastOn = itemOn
	ClearMenus()

	if Host.startTitle ~= nil then
		Host.startTitle()
	end
end

const function EndGame(_choice: number)
	if not IsUserGame() then
		StartSound(Sounds.sfx_oof)
		return
	end

	StartMessage(stringSet.ENDGAME, EndGameResponse, true)
end

const function ReadThis(_choice: number)
	SetupNextMenu(ReadDef1)
end

const function ReadThis2(_choice: number)
	SetupNextMenu(ReadDef2)
end

const function FinishReadThis(_choice: number)
	SetupNextMenu(MainDef)
end

const quitsounds = {
	[0] = Sounds.sfx_pldeth,
	Sounds.sfx_dmpain,
	Sounds.sfx_popain,
	Sounds.sfx_slop,
	Sounds.sfx_telept,
	Sounds.sfx_posit1,
	Sounds.sfx_posit3,
	Sounds.sfx_sgtatk,
}

const quitsounds2 = {
	[0] = Sounds.sfx_vilact,
	Sounds.sfx_getpow,
	Sounds.sfx_boscub,
	Sounds.sfx_slop,
	Sounds.sfx_skeswg,
	Sounds.sfx_kntdth,
	Sounds.sfx_bspact,
	Sounds.sfx_sgtatk,
}

const function QuitResponse(ch: number)
	if ch ~= 89 then
		return
	end

	const soundIndex = bit32.band(bit32.rshift(GetGameTic(), 2), 7)

	if Setup.GetGameMode() == Definitions.commercial then
		StartSound(quitsounds2[soundIndex])
	else
		StartSound(quitsounds[soundIndex])
	end

	quitWait = 105
end

-- QuitDoom
const function QuitDoom(_choice: number)
	if HUD.GetLanguage() ~= Definitions.english then
		endstring = string.format("%s\n\n%s", stringSet.QUITMSG, stringSet.DOSY)
	else
		const index = 1 + (GetGameTic() % (NUM_QUITMESSAGES - 2))
		endstring = string.format("%s\n\n%s", quitMessages[index], stringSet.DOSY)
	end

	StartMessage(endstring, QuitResponse, true)
end

const function ChangeSensitivity(choice: number)
	if choice == 0 then
		if mouseSensitivity > 0 then
			mouseSensitivity -= 1
		end
	elseif choice == 1 then
		if mouseSensitivity < 9 then
			mouseSensitivity += 1
		end
	end
end

const function ChangeDetail(_choice: number)
	detailLevel = 1 - detailLevel
	Main.SetViewSize(screenblocks, detailLevel)
	SetPlayerMessage(if detailLevel == 0 then stringSet.DETAILHI else stringSet.DETAILLO)
end

const function SizeDisplay(choice: number)
	if choice == 0 then
		if screenSize > 0 then
			screenblocks -= 1
			screenSize -= 1
		end
	elseif choice == 1 then
		if screenSize < 8 then
			screenblocks += 1
			screenSize += 1
		end
	end

	Main.SetViewSize(screenblocks, detailLevel)
end

const function WireMenuRoutines()
	MainMenu[0].routine = NewGame
	MainMenu[1].routine = Options
	MainMenu[2].routine = LoadGame
	MainMenu[3].routine = SaveGame
	MainMenu[4].routine = ReadThis
	MainMenu[5].routine = QuitDoom

	EpisodeMenu[0].routine = Episode
	EpisodeMenu[1].routine = Episode
	EpisodeMenu[2].routine = Episode
	EpisodeMenu[3].routine = Episode

	NewGameMenu[0].routine = ChooseSkill
	NewGameMenu[1].routine = ChooseSkill
	NewGameMenu[2].routine = ChooseSkill
	NewGameMenu[3].routine = ChooseSkill
	NewGameMenu[4].routine = ChooseSkill

	OptionsMenu[0].routine = EndGame
	OptionsMenu[1].routine = ChangeMessages
	OptionsMenu[2].routine = ChangeDetail
	OptionsMenu[3].routine = SizeDisplay
	OptionsMenu[5].routine = ChangeSensitivity
	OptionsMenu[7].routine = OpenSoundMenu

	ReadMenu1[0].routine = ReadThis2
	ReadMenu2[0].routine = FinishReadThis

	SoundMenu[0].routine = SfxVol
	SoundMenu[2].routine = MusicVol

	for index = 0, load_end - 1 do
		LoadMenu[index].routine = LoadSelect
		SaveMenu[index].routine = SaveSelect
	end

	MainDef.routine = DrawMainMenu
	EpiDef.routine = DrawEpisode
	NewDef.routine = DrawNewGame
	OptionsDef.routine = DrawOptions
	ReadDef1.routine = DrawReadThis1
	ReadDef2.routine = DrawReadThis2
	SoundDef.routine = DrawSound
	LoadDef.routine = DrawLoad
	SaveDef.routine = DrawSave
end

const function CloneMenuItem(item: MenuItem): MenuItem
	return {
		status = item.status,
		name = item.name,
		routine = item.routine,
		alphaKey = item.alphaKey,
	}
end

const function ApplyGameModeTweaks()
	const gamemode = Setup.GetGameMode()

	if gamemode == Definitions.commercial then
		MainMenu[readthis] = CloneMenuItem(MainMenu[quitdoom])
		MainDef.numitems -= 1
		MainDef.y += 8
		NewDef.prevMenu = MainDef
		ReadDef1.routine = DrawReadThis1
		ReadDef1.x = 330
		ReadDef1.y = 165
		ReadMenu1[0].routine = FinishReadThis
	elseif gamemode == Definitions.shareware or gamemode == Definitions.registered then
		EpiDef.numitems -= 1
	end
end

-- M_Responder
const function Responder(ev: Event): boolean

	SyncRuntimeState()

	if quitWait > 0 then
		return true
	end

	local ch = -1

	if ev.type == ev_joystick and joywait < menuTime then
		if ev.data3 == -1 then
			ch = Definitions.KEY_UPARROW
			joywait = menuTime + 5
		elseif ev.data3 == 1 then
			ch = Definitions.KEY_DOWNARROW
			joywait = menuTime + 5
		end

		if ev.data2 == -1 then
			ch = Definitions.KEY_LEFTARROW
			joywait = menuTime + 2
		elseif ev.data2 == 1 then
			ch = Definitions.KEY_RIGHTARROW
			joywait = menuTime + 2
		end

		if bit32.btest(ev.data1 or 0, 1) then
			ch = Definitions.KEY_ENTER
			joywait = menuTime + 5
		end

		if bit32.btest(ev.data1 or 0, 2) then
			ch = Definitions.KEY_BACKSPACE
			joywait = menuTime + 5
		end
	elseif ev.type == ev_mouse and mousewait < menuTime then
		mousey += ev.data3 or 0

		if mousey < lasty - 30 then
			ch = Definitions.KEY_DOWNARROW
			mousewait = menuTime + 5
			mousey = lasty - 30
			lasty -= 30
		elseif mousey > lasty + 30 then
			ch = Definitions.KEY_UPARROW
			mousewait = menuTime + 5
			mousey = lasty + 30
			lasty += 30
		end

		mousex += ev.data2 or 0

		if mousex < lastx - 30 then
			ch = Definitions.KEY_LEFTARROW
			mousewait = menuTime + 5
			mousex = lastx - 30
			lastx -= 30
		elseif mousex > lastx + 30 then
			ch = Definitions.KEY_RIGHTARROW
			mousewait = menuTime + 5
			mousex = lastx + 30
			lastx += 30
		end

		if bit32.btest(ev.data1 or 0, 1) then
			ch = Definitions.KEY_ENTER
			mousewait = menuTime + 15
		end

		if bit32.btest(ev.data1 or 0, 2) then
			ch = Definitions.KEY_BACKSPACE
			mousewait = menuTime + 15
		end
	elseif ev.type == ev_keydown then
		ch = ev.data1
	end

	if ch == -1 then
		return false
	end

	if saveStringEnter then
		if ch == Definitions.KEY_BACKSPACE then
			if saveCharIndex > 0 then
				saveCharIndex -= 1
				savegamestrings[saveSlot] = string.sub(savegamestrings[saveSlot], 1, saveCharIndex)
			end
		elseif ch == Definitions.KEY_ESCAPE then
			saveStringEnter = false
			savegamestrings[saveSlot] = saveOldString
		elseif ch == Definitions.KEY_ENTER then
			saveStringEnter = false

			if #savegamestrings[saveSlot] > 0 then
				DoSave(saveSlot)
			end
		else
			const upper = string.upper(string.char(ch))
			const upperCode = string.byte(upper)

			if upperCode == 32 or (upperCode - HUD.FontStart >= 0 and upperCode - HUD.FontStart < HUD.FontSize) then
				if upperCode >= 32 and upperCode <= 127
					and saveCharIndex < SAVESTRINGSIZE - 1
					and StringWidth(savegamestrings[saveSlot]) < (SAVESTRINGSIZE - 2) * 8 then
					savegamestrings[saveSlot] ..= upper
					saveCharIndex += 1
				end
			end
		end

		return true
	end

	if messageToPrint then
		const upper = if ch >= 32 and ch <= 127 then string.byte(string.upper(string.char(ch))) else ch

		if messageNeedsInput and upper ~= 32 and upper ~= 78 and upper ~= 89 and upper ~= Definitions.KEY_ESCAPE then
			return false
		end

		menuactive = messageLastMenuActive
		messageToPrint = false
		SyncMenuActive()

		if messageRoutine ~= nil then
			messageRoutine(upper)
		end

		menuactive = false
		SyncMenuActive()
		StartSound(Sounds.sfx_swtchx)
		return true
	end

	if ch == Definitions.KEY_F1 and IsDevParm() and Host.takeScreenshot ~= nil then
		Host.takeScreenshot()
		return true
	end

	if not menuactive then
		if ch == Definitions.KEY_MINUS then
			if Automap.IsActive() then
				return false
			end

			SizeDisplay(0)
			StartSound(Sounds.sfx_stnmov)
			return true
		elseif ch == Definitions.KEY_EQUALS then
			if Automap.IsActive() then
				return false
			end

			SizeDisplay(1)
			StartSound(Sounds.sfx_stnmov)
			return true
		elseif ch == Definitions.KEY_F1 then
			StartControlPanel()

			if Setup.GetGameMode() == Definitions.retail then
				currentMenu = ReadDef2
			else
				currentMenu = ReadDef1
			end

			itemOn = 0
			StartSound(Sounds.sfx_swtchn)
			return true
		elseif ch == Definitions.KEY_F2 then
			StartControlPanel()
			StartSound(Sounds.sfx_swtchn)
			SaveGame(0)
			return true
		elseif ch == Definitions.KEY_F3 then
			StartControlPanel()
			StartSound(Sounds.sfx_swtchn)
			LoadGame(0)
			return true
		elseif ch == Definitions.KEY_F4 then
			StartControlPanel()
			currentMenu = SoundDef
			itemOn = sfx_vol
			StartSound(Sounds.sfx_swtchn)
			return true
		elseif ch == Definitions.KEY_F5 then
			ChangeDetail(0)
			StartSound(Sounds.sfx_swtchn)
			return true
		elseif ch == Definitions.KEY_F6 then
			StartSound(Sounds.sfx_swtchn)
			QuickSave()
			return true
		elseif ch == Definitions.KEY_F7 then
			StartSound(Sounds.sfx_swtchn)
			EndGame(0)
			return true
		elseif ch == Definitions.KEY_F8 then
			ChangeMessages(0)
			StartSound(Sounds.sfx_swtchn)
			return true
		elseif ch == Definitions.KEY_F9 then
			StartSound(Sounds.sfx_swtchn)
			QuickLoad()
			return true
		elseif ch == Definitions.KEY_F10 then
			StartSound(Sounds.sfx_swtchn)
			QuitDoom(0)
			return true
		elseif ch == Definitions.KEY_F11 then
			local gamma = Video.GetUseGamma() + 1

			if gamma > 4 then
				gamma = 0
			end

			Video.SetUseGamma(gamma)
			SetPlayerMessage(gammamsg[gamma])
			return true
		end
	end

	if not menuactive then
		if ch == Definitions.KEY_ESCAPE then
			StartControlPanel()
			StartSound(Sounds.sfx_swtchn)
			return true
		end

		return false
	end

	const menu = RequireCurrentMenu("Responder")

	if ch == Definitions.KEY_DOWNARROW then
		repeat
			if itemOn + 1 > menu.numitems - 1 then
				itemOn = 0
			else
				itemOn += 1
			end

			StartSound(Sounds.sfx_pstop)
		until menu.menuitems[itemOn].status ~= -1

		return true
	elseif ch == Definitions.KEY_UPARROW then
		repeat
			if itemOn == 0 then
				itemOn = menu.numitems - 1
			else
				itemOn -= 1
			end

			StartSound(Sounds.sfx_pstop)
		until menu.menuitems[itemOn].status ~= -1

		return true
	elseif ch == Definitions.KEY_LEFTARROW then
		const item = menu.menuitems[itemOn]

		if item.routine ~= nil and item.status == 2 then
			StartSound(Sounds.sfx_stnmov)
			item.routine(0)
		end

		return true
	elseif ch == Definitions.KEY_RIGHTARROW then
		const item = menu.menuitems[itemOn]

		if item.routine ~= nil and item.status == 2 then
			StartSound(Sounds.sfx_stnmov)
			item.routine(1)
		end

		return true
	elseif ch == Definitions.KEY_ENTER then
		const item = menu.menuitems[itemOn]

		if item.routine ~= nil and item.status ~= 0 then
			menu.lastOn = itemOn

			if item.status == 2 then
				item.routine(1)
				StartSound(Sounds.sfx_stnmov)
			else
				item.routine(itemOn)
				StartSound(Sounds.sfx_pistol)
			end
		end

		return true
	elseif ch == Definitions.KEY_ESCAPE then
		menu.lastOn = itemOn
		ClearMenus()
		StartSound(Sounds.sfx_swtchx)
		return true
	elseif ch == Definitions.KEY_BACKSPACE then
		menu.lastOn = itemOn

		if menu.prevMenu ~= nil then
			currentMenu = menu.prevMenu
			itemOn = menu.prevMenu.lastOn
			StartSound(Sounds.sfx_swtchn)
		end

		return true
	else
		const upper = if ch >= 32 and ch <= 127 then string.byte(string.upper(string.char(ch))) else ch

		for index = itemOn + 1, menu.numitems - 1 do
			if menu.menuitems[index].alphaKey == upper then
				itemOn = index
				StartSound(Sounds.sfx_pstop)
				return true
			end
		end

		for index = 0, itemOn do
			if menu.menuitems[index].alphaKey == upper then
				itemOn = index
				StartSound(Sounds.sfx_pstop)
				return true
			end
		end
	end

	return false
end

-- M_Drawer
-- Called after the view has been rendered,
-- but before it has been blitted.
const function Drawer()
	SyncRuntimeState()
	inhelpscreens = false

	if messageToPrint then
		local y = 100 - StringHeight(messageString) // 2
		local start = 1

		while start <= #messageString do
			const newline = string.find(messageString, "\n", start, true)
			local line = ""

			if newline == nil then
				line = string.sub(messageString, start)
				start = #messageString + 1
			else
				line = string.sub(messageString, start, newline - 1)
				start = newline + 1
			end

			const x = 160 - StringWidth(line) // 2
			WriteText(x, y, line)
			y += buffer.readi16(HUD.hu_font[0], 2)
		end

		return
	end

	if not menuactive then
		return
	end

	const menu = RequireCurrentMenu("Drawer")

	if menu.routine ~= nil then
		menu.routine()
	end

	const x = menu.x
	local y = menu.y

	for index = 0, menu.numitems - 1 do
		const item = menu.menuitems[index]

		if item.name ~= "" then
			DrawPatchName(x, y, item.name)
		end

		y += LINEHEIGHT
	end

	DrawPatchName(x + SKULLXOFF, menu.y - 5 + itemOn * LINEHEIGHT, skullName[whichSkull])
end

const function Ticker()
	if quitWait > 0 then
		quitWait -= 1

		if quitWait == 0 and Host.quitGame ~= nil then
			Host.quitGame()
		end

		return
	end

	menuTime += 1
	skullAnimCounter -= 1

	if skullAnimCounter <= 0 then
		whichSkull = bit32.bxor(whichSkull, 1)
		skullAnimCounter = 8
	end
end

const function Init()
	BuildMenus()
	WireMenuRoutines()
	ApplyGameModeTweaks()
	mouseSensitivity = 5
	showMessages = true
	detailLevel = 0
	screenblocks = 10
	screenSize = 7
	snd_SfxVolume = 8
	snd_MusicVolume = 8
	SyncRuntimeState()
	inhelpscreens = false
	currentMenu = MainDef
	menuactive = false
	itemOn = MainDef.lastOn
	whichSkull = 0
	skullAnimCounter = 10
	quitWait = 0
	messageToPrint = false
	messageString = ""
	messageLastMenuActive = menuactive
	quickSaveSlot = -1

	for index = 0, load_end - 1 do
		savegamestrings[index] = stringSet.EMPTYSTRING
	end

	SyncMenuActive()
end

const function Reset()
	BuildMenus()
	WireMenuRoutines()
	ApplyGameModeTweaks()
	stringSet = English
	mouseSensitivity = 5
	showMessages = true
	detailLevel = 0
	screenblocks = 10
	screenSize = 7
	snd_SfxVolume = 8
	snd_MusicVolume = 8
	SyncRuntimeState()
	inhelpscreens = false
	menuactive = false
	currentMenu = nil
	itemOn = 0
	skullAnimCounter = 10
	whichSkull = 0
	menuTime = 0
	joywait = 0
	mousewait = 0
	mousey = 0
	lasty = 0
	mousex = 0
	lastx = 0
	saveStringEnter = false
	saveSlot = 0
	saveCharIndex = 0
	saveOldString = ""
	quitWait = 0
	quickSaveSlot = -1
	messageToPrint = false
	messageString = ""
	messageNeedsInput = false
	messageRoutine = nil
	messageLastMenuActive = false
	for index = 0, load_end - 1 do
		savegamestrings[index] = stringSet.EMPTYSTRING
	end
	SyncMenuActive()
end

const function GetMenuActive(): boolean
	return menuactive
end

const function GetMessageActive(): boolean
	return messageToPrint
end

const function GetInHelpScreens(): boolean
	return inhelpscreens
end

const function IsHelpScreenVisible(): boolean
	return menuactive and not messageToPrint and (currentMenu == ReadDef1 or currentMenu == ReadDef2)
end

const function IsVisible(): boolean
	return menuactive or messageToPrint
end

const function IsQuitPending(): boolean
	return quitWait > 0
end

const function GetCurrentMenu()
	return currentMenu
end

const function GetMouseSensitivity(): number
	return mouseSensitivity
end

const function GetQuickSaveSlot(): number
	return quickSaveSlot
end

const function SetQuickSaveSlot(value: number)
	quickSaveSlot = value
end

const function GetSaveStrings()
	return savegamestrings
end

return {
	Reset = Reset,
	Init = Init,
	Responder = Responder,
	Ticker = Ticker,
	Drawer = Drawer,
	StartControlPanel = StartControlPanel,
	ClearMenus = ClearMenus,
	ForceClearAll = ForceClearAll,
	GetMenuActive = GetMenuActive,
	GetMessageActive = GetMessageActive,
	GetInHelpScreens = GetInHelpScreens,
	IsHelpScreenVisible = IsHelpScreenVisible,
	IsVisible = IsVisible,
	IsQuitPending = IsQuitPending,
	GetCurrentMenu = GetCurrentMenu,
	GetMouseSensitivity = GetMouseSensitivity,
	GetQuickSaveSlot = GetQuickSaveSlot,
	SetQuickSaveSlot = SetQuickSaveSlot,
	GetSaveStrings = GetSaveStrings,
}
