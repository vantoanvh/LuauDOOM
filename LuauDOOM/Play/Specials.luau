--!native
--!optimize 2

-- Port of p_spec.c
-- Special effects:
-- texture animation, sector effects, line triggers, and related runtime state.
-- Note: exits, damage, and sound come from the shared play runtime.

const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const Data = require("../Renderer/Data")
const Doors = require("./Doors")
const Floor = require("./Floor")
const Lights = require("./Lights")
const Platforms = require("./Platforms")
const Ceiling = require("./Ceiling")
const Random = require("../Miscellaneous/Random")
const Runtime = require("./Runtime")
const State = require("../Renderer/State")
const Switch = require("./Switch")
const Teleport = require("./Teleport")
const Wad = require("../System/Wad")

const GODMODE = 2

const ROCKET = 33
const PLASMA = 34
const BFG = 35
const TROOPSHOT = 31
const HEADSHOT = 32
const BRUISERSHOT = 16

const MAXANIMS = 32
const MAXLINEANIMS = 64

type NumberMap = { [number]: number }
type Anim = {
	istexture: boolean,
	picnum: number,
	basepic: number,
	numpics: number,
	speed: number,
}
type Sector = {
	[string]: unknown,
	floorheight: number,
	floorpic: number,
	special: number,
	tag: number,
	specialdata: unknown,
	lines: { [number]: LineDef },
	linecount: number,
}
type LineDef = {
	special: number,
	tag: number,
	sidenum: NumberMap,
	frontsector: Sector,
	backsector: Sector | false,
}
type Mobj = {
	[string]: unknown,
	player: unknown,
	type: number,
	subsector: {
		sector: Sector,
	},
	z: number,
}
type PlayerSlot = {
	[string]: unknown,
	mo: Mobj,
	powers: NumberMap,
	secretcount: number,
	cheats: number,
	health: number,
}

const animdefs = {
	{ istexture = false, endname = "NUKAGE3", startname = "NUKAGE1", speed = 8 },
	{ istexture = false, endname = "FWATER4", startname = "FWATER1", speed = 8 },
	{ istexture = false, endname = "SWATER4", startname = "SWATER1", speed = 8 },
	{ istexture = false, endname = "LAVA4", startname = "LAVA1", speed = 8 },
	{ istexture = false, endname = "BLOOD3", startname = "BLOOD1", speed = 8 },
	{ istexture = false, endname = "RROCK08", startname = "RROCK05", speed = 8 },
	{ istexture = false, endname = "SLIME04", startname = "SLIME01", speed = 8 },
	{ istexture = false, endname = "SLIME08", startname = "SLIME05", speed = 8 },
	{ istexture = false, endname = "SLIME12", startname = "SLIME09", speed = 8 },
	{ istexture = true, endname = "BLODGR4", startname = "BLODGR1", speed = 8 },
	{ istexture = true, endname = "SLADRIP3", startname = "SLADRIP1", speed = 8 },
	{ istexture = true, endname = "BLODRIP4", startname = "BLODRIP1", speed = 8 },
	{ istexture = true, endname = "FIREWALL", startname = "FIREWALA", speed = 8 },
	{ istexture = true, endname = "GSTFONT3", startname = "GSTFONT1", speed = 8 },
	{ istexture = true, endname = "FIRELAVA", startname = "FIRELAV3", speed = 8 },
	{ istexture = true, endname = "FIREMAG3", startname = "FIREMAG1", speed = 8 },
	{ istexture = true, endname = "FIREBLU2", startname = "FIREBLU1", speed = 8 },
	{ istexture = true, endname = "ROCKRED3", startname = "ROCKRED1", speed = 8 },
	{ istexture = true, endname = "BFALL4", startname = "BFALL1", speed = 8 },
	{ istexture = true, endname = "SFALL4", startname = "SFALL1", speed = 8 },
	{ istexture = true, endname = "WFALL4", startname = "WFALL1", speed = 8 },
	{ istexture = true, endname = "DBRAIN4", startname = "DBRAIN1", speed = 8 },
}

const anims: { [number]: Anim } = {}
local numanims = 0
local numlinespecials = 0
const linespeciallist: { [number]: LineDef } = {}
local levelTimer = false
local levelTimeCount = 0
local totalSecret = 0

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function NewButton()
	return {
		line = false,
		where = Switch.top,
		btexture = 0,
		btimer = 0,
		soundorg = false,
	}
end

const function ResetButtons()
	const buttons = Switch.GetButtonList()

	for index = 0, Switch.MAXBUTTONS - 1 do
		const button = buttons[index]

		if not button then
			buttons[index] = NewButton()
		else
			button.line = false
			button.where = Switch.top
			button.btexture = 0
			button.btimer = 0
			button.soundorg = false
		end
	end
end

const function Reset()
	table.clear(anims)
	table.clear(linespeciallist)
	numanims = 0
	numlinespecials = 0
	levelTimer = false
	levelTimeCount = 0
	totalSecret = 0
	ResetButtons()
end

-- InitPicAnimations
const function InitPicAnimations()
	table.clear(anims)
	numanims = 0

	for _, animdef in animdefs do

		local picnum
		local basepic

		if animdef.istexture then
			if Data.CheckTextureNumForName(animdef.startname) == -1 then
				continue
			end

			picnum = Data.TextureNumForName(animdef.endname)
			basepic = Data.TextureNumForName(animdef.startname)
		else
			if Wad.CheckNumForName(animdef.startname) == -1 then
				continue
			end

			picnum = Data.FlatNumForName(animdef.endname)
			basepic = Data.FlatNumForName(animdef.startname)
		end

		const numpics = picnum - basepic + 1


		anims[numanims] = {
			istexture = animdef.istexture,
			picnum = picnum,
			basepic = basepic,
			numpics = numpics,
			speed = animdef.speed,
		}
		numanims += 1
	end
end

const function IsProjectileType(type_: number): boolean
	return type_ == ROCKET
		or type_ == PLASMA
		or type_ == BFG
		or type_ == TROOPSHOT
		or type_ == HEADSHOT
		or type_ == BRUISERSHOT
end

-- CrossSpecialLine - TRIGGER
-- Called every time a thing origin is about
--  to cross a line with a non 0 special.
const function CrossSpecialLine(linenum: number, side: number, thing: Mobj)
	const line = State.lines[linenum]

	if not thing.player then
		if IsProjectileType(thing.type) then
			return
		end

		local ok = false

		if line.special == 39
			or line.special == 97
			or line.special == 125
			or line.special == 126
			or line.special == 4
			or line.special == 10
			or line.special == 88 then
			ok = true
		end

		if not ok then
			return
		end
	end

	if line.special == 2 then
		Doors.DoDoor(line, Doors.open)
		line.special = 0
	elseif line.special == 3 then
		Doors.DoDoor(line, Doors.close)
		line.special = 0
	elseif line.special == 4 then
		Doors.DoDoor(line, Doors.normal)
		line.special = 0
	elseif line.special == 5 then
		Floor.DoFloor(line, Floor.raiseFloor)
		line.special = 0
	elseif line.special == 6 then
		Ceiling.DoCeiling(line, Ceiling.fastCrushAndRaise)
		line.special = 0
	elseif line.special == 8 then
		Floor.BuildStairs(line, Floor.build8)
		line.special = 0
	elseif line.special == 10 then
		Platforms.DoPlat(line, Platforms.downWaitUpStay, 0)
		line.special = 0
	elseif line.special == 12 then
		Lights.LightTurnOn(line, 0)
		line.special = 0
	elseif line.special == 13 then
		Lights.LightTurnOn(line, 255)
		line.special = 0
	elseif line.special == 16 then
		Doors.DoDoor(line, Doors.close30ThenOpen)
		line.special = 0
	elseif line.special == 17 then
		Lights.StartLightStrobing(line)
		line.special = 0
	elseif line.special == 19 then
		Floor.DoFloor(line, Floor.lowerFloor)
		line.special = 0
	elseif line.special == 22 then
		Platforms.DoPlat(line, Platforms.raiseToNearestAndChange, 0)
		line.special = 0
	elseif line.special == 25 then
		Ceiling.DoCeiling(line, Ceiling.crushAndRaise)
		line.special = 0
	elseif line.special == 30 then
		Floor.DoFloor(line, Floor.raiseToTexture)
		line.special = 0
	elseif line.special == 35 then
		Lights.LightTurnOn(line, 35)
		line.special = 0
	elseif line.special == 36 then
		Floor.DoFloor(line, Floor.turboLower)
		line.special = 0
	elseif line.special == 37 then
		Floor.DoFloor(line, Floor.lowerAndChange)
		line.special = 0
	elseif line.special == 38 then
		Floor.DoFloor(line, Floor.lowerFloorToLowest)
		line.special = 0
	elseif line.special == 39 then
		Teleport.Teleport(line, side, thing)
		line.special = 0
	elseif line.special == 40 then
		Ceiling.DoCeiling(line, Ceiling.raiseToHighest)
		Floor.DoFloor(line, Floor.lowerFloorToLowest)
		line.special = 0
	elseif line.special == 44 then
		Ceiling.DoCeiling(line, Ceiling.lowerAndCrush)
		line.special = 0
	elseif line.special == 52 then
		Runtime.exitLevel()
	elseif line.special == 53 then
		Platforms.DoPlat(line, Platforms.perpetualRaise, 0)
		line.special = 0
	elseif line.special == 54 then
		Platforms.StopPlat(line)
		line.special = 0
	elseif line.special == 56 then
		Floor.DoFloor(line, Floor.raiseFloorCrush)
		line.special = 0
	elseif line.special == 57 then
		Ceiling.CeilingCrushStop(line)
		line.special = 0
	elseif line.special == 58 then
		Floor.DoFloor(line, Floor.raiseFloor24)
		line.special = 0
	elseif line.special == 59 then
		Floor.DoFloor(line, Floor.raiseFloor24AndChange)
		line.special = 0
	elseif line.special == 104 then
		Lights.TurnTagLightsOff(line)
		line.special = 0
	elseif line.special == 108 then
		Doors.DoDoor(line, Doors.blazeRaise)
		line.special = 0
	elseif line.special == 109 then
		Doors.DoDoor(line, Doors.blazeOpen)
		line.special = 0
	elseif line.special == 100 then
		Floor.BuildStairs(line, Floor.turbo16)
		line.special = 0
	elseif line.special == 110 then
		Doors.DoDoor(line, Doors.blazeClose)
		line.special = 0
	elseif line.special == 119 then
		Floor.DoFloor(line, Floor.raiseFloorToNearest)
		line.special = 0
	elseif line.special == 121 then
		Platforms.DoPlat(line, Platforms.blazeDWUS, 0)
		line.special = 0
	elseif line.special == 124 then
		Runtime.secretExitLevel()
	elseif line.special == 125 then
		if not thing.player then
			Teleport.Teleport(line, side, thing)
			line.special = 0
		end
	elseif line.special == 130 then
		Floor.DoFloor(line, Floor.raiseFloorTurbo)
		line.special = 0
	elseif line.special == 141 then
		Ceiling.DoCeiling(line, Ceiling.silentCrushAndRaise)
		line.special = 0
	elseif line.special == 72 then
		Ceiling.DoCeiling(line, Ceiling.lowerAndCrush)
	elseif line.special == 73 then
		Ceiling.DoCeiling(line, Ceiling.crushAndRaise)
	elseif line.special == 74 then
		Ceiling.CeilingCrushStop(line)
	elseif line.special == 75 then
		Doors.DoDoor(line, Doors.close)
	elseif line.special == 76 then
		Doors.DoDoor(line, Doors.close30ThenOpen)
	elseif line.special == 77 then
		Ceiling.DoCeiling(line, Ceiling.fastCrushAndRaise)
	elseif line.special == 79 then
		Lights.LightTurnOn(line, 35)
	elseif line.special == 80 then
		Lights.LightTurnOn(line, 0)
	elseif line.special == 81 then
		Lights.LightTurnOn(line, 255)
	elseif line.special == 82 then
		Floor.DoFloor(line, Floor.lowerFloorToLowest)
	elseif line.special == 83 then
		Floor.DoFloor(line, Floor.lowerFloor)
	elseif line.special == 84 then
		Floor.DoFloor(line, Floor.lowerAndChange)
	elseif line.special == 86 then
		Doors.DoDoor(line, Doors.open)
	elseif line.special == 87 then
		Platforms.DoPlat(line, Platforms.perpetualRaise, 0)
	elseif line.special == 88 then
		Platforms.DoPlat(line, Platforms.downWaitUpStay, 0)
	elseif line.special == 89 then
		Platforms.StopPlat(line)
	elseif line.special == 90 then
		Doors.DoDoor(line, Doors.normal)
	elseif line.special == 91 then
		Floor.DoFloor(line, Floor.raiseFloor)
	elseif line.special == 92 then
		Floor.DoFloor(line, Floor.raiseFloor24)
	elseif line.special == 93 then
		Floor.DoFloor(line, Floor.raiseFloor24AndChange)
	elseif line.special == 94 then
		Floor.DoFloor(line, Floor.raiseFloorCrush)
	elseif line.special == 95 then
		Platforms.DoPlat(line, Platforms.raiseToNearestAndChange, 0)
	elseif line.special == 96 then
		Floor.DoFloor(line, Floor.raiseToTexture)
	elseif line.special == 97 then
		Teleport.Teleport(line, side, thing)
	elseif line.special == 98 then
		Floor.DoFloor(line, Floor.turboLower)
	elseif line.special == 105 then
		Doors.DoDoor(line, Doors.blazeRaise)
	elseif line.special == 106 then
		Doors.DoDoor(line, Doors.blazeOpen)
	elseif line.special == 107 then
		Doors.DoDoor(line, Doors.blazeClose)
	elseif line.special == 120 then
		Platforms.DoPlat(line, Platforms.blazeDWUS, 0)
	elseif line.special == 126 then
		if not thing.player then
			Teleport.Teleport(line, side, thing)
		end
	elseif line.special == 128 then
		Floor.DoFloor(line, Floor.raiseFloorToNearest)
	elseif line.special == 129 then
		Floor.DoFloor(line, Floor.raiseFloorTurbo)
	end
end

-- ShootSpecialLine - IMPACT SPECIALS
-- Called when a thing shoots a special line.
const function ShootSpecialLine(thing: Mobj, line: LineDef)
	if not thing.player and line.special ~= 46 then
		return
	end

	if line.special == 24 then
		Floor.DoFloor(line, Floor.raiseFloor)
		Switch.ChangeSwitchTexture(line, 0)
	elseif line.special == 46 then
		Doors.DoDoor(line, Doors.open)
		Switch.ChangeSwitchTexture(line, 1)
	elseif line.special == 47 then
		Platforms.DoPlat(line, Platforms.raiseToNearestAndChange, 0)
		Switch.ChangeSwitchTexture(line, 0)
	end
end

-- PlayerInSpecialSector
-- Called every tic frame
--  that the player origin is in a special sector
const function PlayerInSpecialSector(player: PlayerSlot)
	const mo = player.mo

	const subsector = mo.subsector

	const sector = subsector.sector

	if mo.z ~= sector.floorheight then
		return
	end

	if sector.special == 5 then
		if (player.powers[Definitions.pw_ironfeet] or 0) == 0 and bit32.band(GetLevelTime(), 0x1f) == 0 then
			Runtime.damageMobj(mo, nil, nil, 10)
		end
	elseif sector.special == 7 then
		if (player.powers[Definitions.pw_ironfeet] or 0) == 0 and bit32.band(GetLevelTime(), 0x1f) == 0 then
			Runtime.damageMobj(mo, nil, nil, 5)
		end
	elseif sector.special == 16 or sector.special == 4 then
		if ((player.powers[Definitions.pw_ironfeet] or 0) == 0 or Random.PlayRandom() < 5)
			and bit32.band(GetLevelTime(), 0x1f) == 0 then
			Runtime.damageMobj(mo, nil, nil, 20)
		end
	elseif sector.special == 9 then
		player.secretcount = (player.secretcount or 0) + 1
		sector.special = 0
	elseif sector.special == 11 then
		player.cheats = bit32.band(player.cheats, bit32.bnot(GODMODE))

		if bit32.band(GetLevelTime(), 0x1f) == 0 then
			Runtime.damageMobj(mo, nil, nil, 20)
		end

		if player.health <= 10 then
			Runtime.exitLevel()
		end
	elseif sector.special ~= 0 then
		error(`PlayerInSpecialSector: unknown special {sector.special}`)
	end
end

-- UpdateSpecials
-- Animate planes, scroll walls, etc.
const function UpdateSpecials()
	if levelTimer then
		levelTimeCount -= 1

		if levelTimeCount == 0 then
			Runtime.exitLevel()
		end
	end

	const leveltime = GetLevelTime()

	for index = 0, numanims - 1 do
		const anim = anims[index]

		for picIndex = anim.basepic, anim.basepic + anim.numpics - 1 do
			const pic = anim.basepic + ((leveltime // anim.speed + picIndex) % anim.numpics)

			if anim.istexture then
				State.texturetranslation[picIndex] = pic
			else
				State.flattranslation[picIndex] = pic
			end
		end
	end

	for index = 0, numlinespecials - 1 do
		const line = linespeciallist[index]

		if line.special == 48 then
			const sidenum = line.sidenum[0]


			const side = State.sides[sidenum]

			side.textureoffset += Fixed.FRACUNIT
		end
	end

	const buttons = Switch.GetButtonList()

	for index = 0, Switch.MAXBUTTONS - 1 do
		const button = buttons[index]

		if button.btimer ~= 0 then
			button.btimer -= 1

			if button.btimer == 0 then
				const line = button.line

				const sidenum = line.sidenum[0]


				const side = State.sides[sidenum]

				if button.where == Switch.top then
					side.toptexture = button.btexture
				elseif button.where == Switch.middle then
					side.midtexture = button.btexture
				elseif button.where == Switch.bottom then
					side.bottomtexture = button.btexture
				end

				Runtime.startSound(button.soundorg, Switch.sfx_swtchn)
				button.line = false
				button.where = Switch.top
				button.btexture = 0
				button.soundorg = false
			end
		end
	end
end

-- SpawnSpecials
-- After the map has been loaded, scan for specials
--  that spawn thinkers
const function SpawnSpecials(): number
	table.clear(linespeciallist)
	numlinespecials = 0
	totalSecret = 0
	levelTimer = false
	ResetButtons()

	for index = 0, State.numsectors - 1 do
		const sector = State.sectors[index]

		if sector.special == 0 then
			continue
		end

		if sector.special == 1 then
			Lights.SpawnLightFlash(sector)
		elseif sector.special == 2 then
			Lights.SpawnStrobeFlash(sector, Lights.FASTDARK, 0)
		elseif sector.special == 3 then
			Lights.SpawnStrobeFlash(sector, Lights.SLOWDARK, 0)
		elseif sector.special == 4 then
			Lights.SpawnStrobeFlash(sector, Lights.FASTDARK, 0)
			sector.special = 4
		elseif sector.special == 8 then
			Lights.SpawnGlowingLight(sector)
		elseif sector.special == 9 then
			totalSecret += 1
		elseif sector.special == 10 then
			Doors.SpawnDoorCloseIn30(sector)
		elseif sector.special == 12 then
			Lights.SpawnStrobeFlash(sector, Lights.SLOWDARK, 1)
		elseif sector.special == 13 then
			Lights.SpawnStrobeFlash(sector, Lights.FASTDARK, 1)
		elseif sector.special == 14 then
			Doors.SpawnDoorRaiseIn5Mins(sector, index)
		elseif sector.special == 17 then
			Lights.SpawnFireFlicker(sector)
		end
	end

	for index = 0, State.numlines - 1 do
		const line = State.lines[index]

		if line.special == 48 then

			linespeciallist[numlinespecials] = line
			numlinespecials += 1
		end
	end

	return totalSecret
end

-- Special Stuff that can not be categorized
const function DoDonut(line: LineDef): number
	local secnum = -1
	local rtn = 0

	while true do
		secnum = Floor.FindSectorFromLineTag(line, secnum)

		if secnum < 0 then
			break
		end

		const s1 = State.sectors[secnum]

		if s1.specialdata then
			continue
		end

		rtn = 1

		const firstLine = s1.lines[0]

		const s2 = Floor.getNextSector(firstLine, s1)

		if not s2 then
			continue
		end

		for index = 0, s2.linecount - 1 do
			const mapLine = s2.lines[index]

			-- Preserve the original `!flags & TWOSIDED` precedence bug for source parity.
			if mapLine.backsector == s1 then
				continue
			end

			const s3 = mapLine.backsector

			if not s3 then
				continue
			end

			Floor.SpawnFloorMove({
				type = Floor.donutRaise,
				crush = false,
				direction = 1,
				sector = s2,
				speed = Floor.FLOORSPEED // 2,
				texture = s3.floorpic,
				newspecial = 0,
				floordestheight = s3.floorheight,
			})

			Floor.SpawnFloorMove({
				type = Floor.lowerFloor,
				crush = false,
				direction = -1,
				sector = s1,
				speed = Floor.FLOORSPEED // 2,
				floordestheight = s3.floorheight,
			})
			break
		end
	end

	return rtn
end

const function GetAnims(): { [number]: Anim }
	return anims
end

const function GetNumAnims(): number
	return numanims
end

const function GetLineSpecialList(): { [number]: LineDef }
	return linespeciallist
end

const function GetNumLineSpecials(): number
	return numlinespecials
end

const function GetLevelTimer(): boolean
	return levelTimer
end

const function SetLevelTimer(value: boolean)
	levelTimer = value
end

const function GetLevelTimeCount(): number
	return levelTimeCount
end

const function SetLevelTimeCount(value: number)
	levelTimeCount = value
end

const function GetTotalSecret(): number
	return totalSecret
end

Reset()

return {
	MAXANIMS = MAXANIMS,
	MAXLINEANIMS = MAXLINEANIMS,
	GODMODE = GODMODE,

	Reset = Reset,
	GetAnims = GetAnims,
	GetNumAnims = GetNumAnims,
	GetLineSpecialList = GetLineSpecialList,
	GetNumLineSpecials = GetNumLineSpecials,
	GetLevelTimer = GetLevelTimer,
	SetLevelTimer = SetLevelTimer,
	GetLevelTimeCount = GetLevelTimeCount,
	SetLevelTimeCount = SetLevelTimeCount,
	GetTotalSecret = GetTotalSecret,

	InitPicAnimations = InitPicAnimations,
	CrossSpecialLine = CrossSpecialLine,
	ShootSpecialLine = ShootSpecialLine,
	PlayerInSpecialSector = PlayerInSpecialSector,
	UpdateSpecials = UpdateSpecials,
	SpawnSpecials = SpawnSpecials,
	DoDonut = DoDonut,
}
