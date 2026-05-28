--!native
--!optimize 2

-- Port of p_switch.c, p_spec.h
-- Switches, buttons. Two-state animation. Exits.
-- Note: door/floor/ceiling/light/game actions and sound playback come from
-- the shared play runtime.

const Definitions = require("../Engine/Definitions")
const Data = require("../Renderer/Data")
const State = require("../Renderer/State")
const Runtime = require("./Runtime")

const MAXSWITCHES = 50
const MAXBUTTONS = 16
const BUTTONTIME = 35

const SECRET = 32

const sfx_swtchn = 23
const sfx_swtchx = 24

const top = 0
const middle = 1
const bottom = 2

const build8 = 0
const turbo16 = 1

const downWaitUpStay = 1
const raiseAndChange = 2
const raiseToNearestAndChange = 3
const blazeDWUS = 4

const normal = 0
const close = 2
const open = 3
const blazeRaise = 5
const blazeOpen = 6
const blazeClose = 7

const lowerToFloor = 0
const crushAndRaise = 3

const lowerFloor = 0
const lowerFloorToLowest = 1
const turboLower = 2
const raiseFloor = 3
const raiseFloorToNearest = 4
const raiseFloorCrush = 9
const raiseFloorTurbo = 10
const raiseFloor512 = 12

type NumberMap = { [number]: number }
type Sector = {
	[string]: unknown,
	soundorg: unknown,
}
type SideDef = {
	toptexture: number,
	midtexture: number,
	bottomtexture: number,
}
type LineDef = {
	[string]: unknown,
	flags: number,
	special: number,
	sidenum: NumberMap,
	frontsector: Sector,
}
type Thing = {
	[string]: unknown,
	player: unknown,
}
type Button = {
	line: LineDef | false,
	where: number,
	btexture: number,
	btimer: number,
	soundorg: unknown,
}

const alphSwitchList = {
	-- Doom shareware episode 1 switches
	{ name1 = "SW1BRCOM", name2 = "SW2BRCOM", episode = 1 },
	{ name1 = "SW1BRN1", name2 = "SW2BRN1", episode = 1 },
	{ name1 = "SW1BRN2", name2 = "SW2BRN2", episode = 1 },
	{ name1 = "SW1BRNGN", name2 = "SW2BRNGN", episode = 1 },
	{ name1 = "SW1BROWN", name2 = "SW2BROWN", episode = 1 },
	{ name1 = "SW1COMM", name2 = "SW2COMM", episode = 1 },
	{ name1 = "SW1COMP", name2 = "SW2COMP", episode = 1 },
	{ name1 = "SW1DIRT", name2 = "SW2DIRT", episode = 1 },
	{ name1 = "SW1EXIT", name2 = "SW2EXIT", episode = 1 },
	{ name1 = "SW1GRAY", name2 = "SW2GRAY", episode = 1 },
	{ name1 = "SW1GRAY1", name2 = "SW2GRAY1", episode = 1 },
	{ name1 = "SW1METAL", name2 = "SW2METAL", episode = 1 },
	{ name1 = "SW1PIPE", name2 = "SW2PIPE", episode = 1 },
	{ name1 = "SW1SLAD", name2 = "SW2SLAD", episode = 1 },
	{ name1 = "SW1STARG", name2 = "SW2STARG", episode = 1 },
	{ name1 = "SW1STON1", name2 = "SW2STON1", episode = 1 },
	{ name1 = "SW1STON2", name2 = "SW2STON2", episode = 1 },
	{ name1 = "SW1STONE", name2 = "SW2STONE", episode = 1 },
	{ name1 = "SW1STRTN", name2 = "SW2STRTN", episode = 1 },

	-- Doom registered episodes 2&3 switches
	{ name1 = "SW1BLUE", name2 = "SW2BLUE", episode = 2 },
	{ name1 = "SW1CMT", name2 = "SW2CMT", episode = 2 },
	{ name1 = "SW1GARG", name2 = "SW2GARG", episode = 2 },
	{ name1 = "SW1GSTON", name2 = "SW2GSTON", episode = 2 },
	{ name1 = "SW1HOT", name2 = "SW2HOT", episode = 2 },
	{ name1 = "SW1LION", name2 = "SW2LION", episode = 2 },
	{ name1 = "SW1SATYR", name2 = "SW2SATYR", episode = 2 },
	{ name1 = "SW1SKIN", name2 = "SW2SKIN", episode = 2 },
	{ name1 = "SW1VINE", name2 = "SW2VINE", episode = 2 },
	{ name1 = "SW1WOOD", name2 = "SW2WOOD", episode = 2 },

	-- Doom II switches
	{ name1 = "SW1PANEL", name2 = "SW2PANEL", episode = 3 },
	{ name1 = "SW1ROCK", name2 = "SW2ROCK", episode = 3 },
	{ name1 = "SW1MET2", name2 = "SW2MET2", episode = 3 },
	{ name1 = "SW1WDMET", name2 = "SW2WDMET", episode = 3 },
	{ name1 = "SW1BRIK", name2 = "SW2BRIK", episode = 3 },
	{ name1 = "SW1MOD1", name2 = "SW2MOD1", episode = 3 },
	{ name1 = "SW1ZIM", name2 = "SW2ZIM", episode = 3 },
	{ name1 = "SW1STON6", name2 = "SW2STON6", episode = 3 },
	{ name1 = "SW1TEK", name2 = "SW2TEK", episode = 3 },
	{ name1 = "SW1MARB", name2 = "SW2MARB", episode = 3 },
	{ name1 = "SW1SKULL", name2 = "SW2SKULL", episode = 3 },

	{ name1 = "", name2 = "", episode = 0 },
}

const switchlist: { [number]: number } = {}
local numswitches = 0
const buttonlist: { [number]: Button } = {}
local gamemode = Definitions.indetermined

const function NewButton(): Button
	return {
		line = false,
		where = top,
		btexture = 0,
		btimer = 0,
		soundorg = false,
	}
end

const function Reset()
	table.clear(switchlist)
	table.clear(buttonlist)
	numswitches = 0

	for index = 0, MAXSWITCHES * 2 - 1 do
		switchlist[index] = -1
	end

	for index = 0, MAXBUTTONS - 1 do
		buttonlist[index] = NewButton()
	end
end

const function ActionSucceeded(result: number | boolean | nil): boolean
	return result ~= nil and result ~= false and result ~= 0
end

const function GetFrontSide(line: LineDef, context: string): SideDef
	const side = State.sides[line.sidenum[0]]


	return side
end

const function GetEpisodeForGameMode(): number
	local episode = 1

	if gamemode == Definitions.registered then
		episode = 2
	elseif gamemode == Definitions.commercial then
		episode = 3
	end

	return episode
end

const function GetSwitchSoundOrigin()
	return buttonlist[0].soundorg
end

--
-- InitSwitchList
-- Only called at game initialization.
--
const function InitSwitchList()
	Reset()

	local index = 0
	const episode = GetEpisodeForGameMode()

	for i = 0, MAXSWITCHES - 1 do
		const entry = alphSwitchList[i + 1]


		if entry.episode == 0 then
			numswitches = index // 2
			switchlist[index] = -1
			break
		end

		if entry.episode <= episode then
			switchlist[index] = Data.TextureNumForName(entry.name1)
			index += 1
			switchlist[index] = Data.TextureNumForName(entry.name2)
			index += 1
		end
	end
end

--
-- Start a button counting down till it turns off.
--
const function StartButton(line: LineDef, w: number, texture: number, time: number)
	-- See if button is already pressed
	for index = 0, MAXBUTTONS - 1 do
		const button = buttonlist[index]

		if button.btimer ~= 0 and button.line == line then
			return
		end
	end

	for index = 0, MAXBUTTONS - 1 do
		const button = buttonlist[index]

		if button.btimer == 0 then
			button.line = line
			button.where = w
			button.btexture = texture
			button.btimer = time
			button.soundorg = line.frontsector.soundorg
			return
		end
	end

	error("StartButton: no button slots left!")
end

--
-- Function that changes wall texture.
-- Tell it if switch is ok to use again (1=yes, it's a button).
--
const function ChangeSwitchTexture(line: LineDef, useAgain: number)
	const side = GetFrontSide(line, "ChangeSwitchTexture")

	if useAgain == 0 then
		line.special = 0
	end

	const texTop = side.toptexture
	const texMid = side.midtexture
	const texBot = side.bottomtexture
	local sound = sfx_swtchn

	-- EXIT SWITCH?
	if line.special == 11 then
		sound = sfx_swtchx
	end

	for index = 0, numswitches * 2 - 1 do
		if switchlist[index] == texTop then
			Runtime.startSound(GetSwitchSoundOrigin(), sound)
			side.toptexture = switchlist[bit32.bxor(index, 1)]

			if useAgain ~= 0 then
				StartButton(line, top, switchlist[index], BUTTONTIME)
			end

			return
		elseif switchlist[index] == texMid then
			Runtime.startSound(GetSwitchSoundOrigin(), sound)
			side.midtexture = switchlist[bit32.bxor(index, 1)]

			if useAgain ~= 0 then
				StartButton(line, middle, switchlist[index], BUTTONTIME)
			end

			return
		elseif switchlist[index] == texBot then
			Runtime.startSound(GetSwitchSoundOrigin(), sound)
			side.bottomtexture = switchlist[bit32.bxor(index, 1)]

			if useAgain ~= 0 then
				StartButton(line, bottom, switchlist[index], BUTTONTIME)
			end

			return
		end
	end
end

const function ActivateSpecialLine(special: number, line: LineDef, thing: Thing, button: number)
	if special == 1 or special == 26 or special == 27 or special == 28 or special == 31 or special == 32
		or special == 33 or special == 34 or special == 117 or special == 118 then
		Runtime.verticalDoor(line, thing)
	elseif special == 7 then
		if ActionSucceeded(Runtime.buildStairs(line, build8)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 9 then
		if ActionSucceeded(Runtime.doDonut(line)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 11 then
		ChangeSwitchTexture(line, 0)
		Runtime.exitLevel()
	elseif special == 14 then
		if ActionSucceeded(Runtime.doPlat(line, raiseAndChange, 32)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 15 then
		if ActionSucceeded(Runtime.doPlat(line, raiseAndChange, 24)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 18 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloorToNearest)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 20 then
		if ActionSucceeded(Runtime.doPlat(line, raiseToNearestAndChange, 0)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 21 then
		if ActionSucceeded(Runtime.doPlat(line, downWaitUpStay, 0)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 23 then
		if ActionSucceeded(Runtime.doFloor(line, lowerFloorToLowest)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 29 then
		if ActionSucceeded(Runtime.doDoor(line, normal)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 41 then
		if ActionSucceeded(Runtime.doCeiling(line, lowerToFloor)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 42 then
		if ActionSucceeded(Runtime.doDoor(line, close)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 43 then
		if ActionSucceeded(Runtime.doCeiling(line, lowerToFloor)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 45 then
		if ActionSucceeded(Runtime.doFloor(line, lowerFloor)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 49 then
		if ActionSucceeded(Runtime.doCeiling(line, crushAndRaise)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 50 then
		if ActionSucceeded(Runtime.doDoor(line, close)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 51 then
		ChangeSwitchTexture(line, 0)
		Runtime.secretExitLevel()
	elseif special == 55 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloorCrush)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 60 then
		if ActionSucceeded(Runtime.doFloor(line, lowerFloorToLowest)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 61 then
		if ActionSucceeded(Runtime.doDoor(line, open)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 62 then
		if ActionSucceeded(Runtime.doPlat(line, downWaitUpStay, 1)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 63 then
		if ActionSucceeded(Runtime.doDoor(line, normal)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 64 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloor)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 65 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloorCrush)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 66 then
		if ActionSucceeded(Runtime.doPlat(line, raiseAndChange, 24)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 67 then
		if ActionSucceeded(Runtime.doPlat(line, raiseAndChange, 32)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 68 then
		if ActionSucceeded(Runtime.doPlat(line, raiseToNearestAndChange, 0)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 69 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloorToNearest)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 70 then
		if ActionSucceeded(Runtime.doFloor(line, turboLower)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 71 then
		if ActionSucceeded(Runtime.doFloor(line, turboLower)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 99 or special == 134 or special == 136 then
		if ActionSucceeded(Runtime.doLockedDoor(line, blazeOpen, thing)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 101 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloor)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 102 then
		if ActionSucceeded(Runtime.doFloor(line, lowerFloor)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 103 then
		if ActionSucceeded(Runtime.doDoor(line, open)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 111 then
		if ActionSucceeded(Runtime.doDoor(line, blazeRaise)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 112 then
		if ActionSucceeded(Runtime.doDoor(line, blazeOpen)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 113 then
		if ActionSucceeded(Runtime.doDoor(line, blazeClose)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 114 then
		if ActionSucceeded(Runtime.doDoor(line, blazeRaise)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 115 then
		if ActionSucceeded(Runtime.doDoor(line, blazeOpen)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 116 then
		if ActionSucceeded(Runtime.doDoor(line, blazeClose)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 122 then
		if ActionSucceeded(Runtime.doPlat(line, blazeDWUS, 0)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 123 then
		if ActionSucceeded(Runtime.doPlat(line, blazeDWUS, 0)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 127 then
		if ActionSucceeded(Runtime.buildStairs(line, turbo16)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 131 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloorTurbo)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 132 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloorTurbo)) then
			ChangeSwitchTexture(line, 1)
		end
	elseif special == 133 or special == 135 or special == 137 then
		if ActionSucceeded(Runtime.doLockedDoor(line, blazeOpen, thing)) then
			ChangeSwitchTexture(line, button)
		end
	elseif special == 138 then
		Runtime.lightTurnOn(line, 255)
		ChangeSwitchTexture(line, 1)
	elseif special == 139 then
		Runtime.lightTurnOn(line, 35)
		ChangeSwitchTexture(line, 1)
	elseif special == 140 then
		if ActionSucceeded(Runtime.doFloor(line, raiseFloor512)) then
			ChangeSwitchTexture(line, button)
		end
	end
end

--
-- UseSpecialLine
-- Called when a thing uses a special line.
-- Only the front sides of lines are usable.
--
const function UseSpecialLine(thing: Thing, line: LineDef, side: number): boolean
	-- Err...
	-- Use the back sides of VERY SPECIAL lines...
	if side ~= 0 then
		if line.special ~= 124 then
			return false
		end
	end

	-- Switches that other things can activate.
	if thing.player == nil or thing.player == false then
		-- never open secret doors
		if bit32.btest(line.flags, SECRET) then
			return false
		end

		if line.special ~= 1 and line.special ~= 32 and line.special ~= 33 and line.special ~= 34 then
			return false
		end
	end

	-- do something
	if line.special >= 42 and line.special <= 139
		and line.special ~= 49
		and line.special ~= 50
		and line.special ~= 51
		and line.special ~= 55
		and line.special ~= 71
		and line.special ~= 101
		and line.special ~= 102
		and line.special ~= 103
		and line.special ~= 111
		and line.special ~= 112
		and line.special ~= 113
		and line.special ~= 117
		and line.special ~= 118
		and line.special ~= 122
		and line.special ~= 127
		and line.special ~= 131
		and line.special ~= 133
		and line.special ~= 135
		and line.special ~= 137
		and line.special ~= 140 then
		ActivateSpecialLine(line.special, line, thing, 1)
	else
		ActivateSpecialLine(line.special, line, thing, 0)
	end

	return true
end

const function SetGameMode(value: number)
	gamemode = value
end

const function GetGameMode(): number
	return gamemode
end

const function GetSwitchList(): { [number]: number }
	return switchlist
end

const function GetNumSwitches(): number
	return numswitches
end

const function GetButtonList(): { [number]: Button }
	return buttonlist
end

Reset()

const Exports = {
	MAXSWITCHES = MAXSWITCHES,
	MAXBUTTONS = MAXBUTTONS,
	BUTTONTIME = BUTTONTIME,

	sfx_swtchn = sfx_swtchn,
	sfx_swtchx = sfx_swtchx,

	top = top,
	middle = middle,
	bottom = bottom,

	build8 = build8,
	turbo16 = turbo16,

	downWaitUpStay = downWaitUpStay,
	raiseAndChange = raiseAndChange,
	raiseToNearestAndChange = raiseToNearestAndChange,
	blazeDWUS = blazeDWUS,

	normal = normal,
	close = close,
	open = open,
	blazeRaise = blazeRaise,
	blazeOpen = blazeOpen,
	blazeClose = blazeClose,

	lowerToFloor = lowerToFloor,
	crushAndRaise = crushAndRaise,

	lowerFloor = lowerFloor,
	lowerFloorToLowest = lowerFloorToLowest,
	turboLower = turboLower,
	raiseFloor = raiseFloor,
	raiseFloorToNearest = raiseFloorToNearest,
	raiseFloorCrush = raiseFloorCrush,
	raiseFloorTurbo = raiseFloorTurbo,
	raiseFloor512 = raiseFloor512,

	alphSwitchList = alphSwitchList,
	Reset = Reset,
	SetGameMode = SetGameMode,
	GetGameMode = GetGameMode,

	InitSwitchList = InitSwitchList,
	StartButton = StartButton,
	ChangeSwitchTexture = ChangeSwitchTexture,
	UseSpecialLine = UseSpecialLine,

	GetSwitchList = GetSwitchList,
	GetNumSwitches = GetNumSwitches,
	GetButtonList = GetButtonList,
}

Exports.InitSwitchList = InitSwitchList
Exports.StartButton = StartButton
Exports.ChangeSwitchTexture = ChangeSwitchTexture
Exports.UseSpecialLine = UseSpecialLine

return Exports
