--!native
--!optimize 2

-- Port of p_lights.c
-- Handle Sector base lighting effects.
-- Muzzle flash?
-- Thinker registration goes through the shared play runtime, and this module
-- keeps the spawned effect tables as the owner of those light thinkers.
-- Note: `getNextSector`, `FindSectorFromLineTag`, and
-- `FindMinSurroundingLight` are implemented locally here because `p_lights.c`
-- depends on those `p_spec.c` helpers directly.

const Random = require("../Miscellaneous/Random")
const State = require("../Renderer/State")
const Runtime = require("./Runtime")

const TWOSIDED = 4

const GLOWSPEED = 8
const STROBEBRIGHT = 5
const FASTDARK = 15
const SLOWDARK = 35

type Sector = {
	lightlevel: number,
	special: number,
	tag: number,
	linecount: number,
	lines: { [number]: unknown },
	specialdata: unknown,
}

type LineDef = {
	flags: number,
	tag: number,
	frontsector: Sector,
	backsector: Sector | false,
}

type FireFlicker = {
	sector: Sector,
	maxlight: number,
	minlight: number,
	count: number,
}

type LightFlash = {
	sector: Sector,
	maxlight: number,
	minlight: number,
	maxtime: number,
	mintime: number,
	count: number,
}

type StrobeFlash = {
	sector: Sector,
	darktime: number,
	brighttime: number,
	maxlight: number,
	minlight: number,
	count: number,
}

type Glow = {
	sector: Sector,
	minlight: number,
	maxlight: number,
	direction: number,
}

const activeThinkers: { [number]: unknown } = {}
const fireflickers: { [number]: unknown } = {}
const lightflashes: { [number]: unknown } = {}
const strobes: { [number]: unknown } = {}
const glows: { [number]: unknown } = {}

const function NewThinker(owner: unknown, thinkerFunction: unknown)
	return {
		owner = owner,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function RegisterThinker(effect: { thinker: unknown }, list: { [number]: unknown })
	list[#list + 1] = effect
	activeThinkers[#activeThinkers + 1] = effect

	Runtime.addThinker(effect.thinker)
end

const function Reset()
	table.clear(activeThinkers)
	table.clear(fireflickers)
	table.clear(lightflashes)
	table.clear(strobes)
	table.clear(glows)
end

-- getNextSector()
-- Return sector_t * of sector next to current.
-- NULL if not two-sided line
const function getNextSector(line: LineDef, sec: Sector): Sector | false
	if bit32.band(line.flags, TWOSIDED) == 0 then
		return false
	end

	if line.frontsector == sec then
		return line.backsector or false
	end

	return line.frontsector or false
end

-- RETURN NEXT SECTOR # THAT LINE TAG REFERS TO
const function FindSectorFromLineTag(line: LineDef, start: number): number
	for index = start + 1, State.numsectors - 1 do
		const sector = State.sectors[index]

		if sector.tag == line.tag then
			return index
		end
	end

	return -1
end

-- Find minimum light from an adjacent sector
const function FindMinSurroundingLight(sector: Sector, max: number): number
	local min = max

	for index = 0, sector.linecount - 1 do
		const line = sector.lines[index] :: LineDef


		const check = getNextSector(line, sector)

		if not check then
			continue
		end

		if check.lightlevel < min then
			min = check.lightlevel
		end
	end

	return min
end

-- FIRELIGHT FLICKER

-- FireFlickerTick
const function FireFlickerTick(flick: FireFlicker)
	const sector = flick.sector
	flick.count -= 1

	if flick.count ~= 0 then
		return
	end

	const amount = bit32.band(Random.PlayRandom(), 3) * 16

	if sector.lightlevel - amount < flick.minlight then
		sector.lightlevel = flick.minlight
	else
		sector.lightlevel = flick.maxlight - amount
	end

	flick.count = 4
end

-- SpawnFireFlicker
const function SpawnFireFlicker(sector: Sector)
	-- Note that we are resetting sector attributes.
	-- Nothing special about it during gameplay.
	sector.special = 0

	const flick = {
		sector = sector,
		maxlight = sector.lightlevel,
		minlight = FindMinSurroundingLight(sector, sector.lightlevel) + 16,
		count = 4,
	}

	flick.thinker = NewThinker(flick, FireFlickerTick)
	RegisterThinker(flick, fireflickers)

	return flick
end

-- BROKEN LIGHT FLASHING

-- LightFlashTick
-- Do flashing lights.
const function LightFlashTick(flash: LightFlash)
	const sector = flash.sector
	flash.count -= 1

	if flash.count ~= 0 then
		return
	end

	if sector.lightlevel == flash.maxlight then
		sector.lightlevel = flash.minlight
		flash.count = bit32.band(Random.PlayRandom(), flash.mintime) + 1
	else
		sector.lightlevel = flash.maxlight
		flash.count = bit32.band(Random.PlayRandom(), flash.maxtime) + 1
	end
end

-- SpawnLightFlash
-- After the map has been loaded, scan each sector
-- for specials that spawn thinkers
const function SpawnLightFlash(sector: Sector)
	-- nothing special about it during gameplay
	sector.special = 0

	const flash = {
		sector = sector,
		maxlight = sector.lightlevel,
		minlight = FindMinSurroundingLight(sector, sector.lightlevel),
		maxtime = 64,
		mintime = 7,
		count = bit32.band(Random.PlayRandom(), 64) + 1,
	}

	flash.thinker = NewThinker(flash, LightFlashTick)
	RegisterThinker(flash, lightflashes)

	return flash
end

-- STROBE LIGHT FLASHING

-- StrobeFlashTick
const function StrobeFlashTick(flash: StrobeFlash)
	const sector = flash.sector
	flash.count -= 1

	if flash.count ~= 0 then
		return
	end

	if sector.lightlevel == flash.minlight then
		sector.lightlevel = flash.maxlight
		flash.count = flash.brighttime
	else
		sector.lightlevel = flash.minlight
		flash.count = flash.darktime
	end
end

-- SpawnStrobeFlash
-- After the map has been loaded, scan each sector
-- for specials that spawn thinkers
const function SpawnStrobeFlash(sector: Sector, fastOrSlow: number, inSync: number)
	const flash = {
		sector = sector,
		darktime = fastOrSlow,
		brighttime = STROBEBRIGHT,
		maxlight = sector.lightlevel,
		minlight = FindMinSurroundingLight(sector, sector.lightlevel),
		count = 0,
	}

	if flash.minlight == flash.maxlight then
		flash.minlight = 0
	end

	-- nothing special about it during gameplay
	sector.special = 0

	if inSync == 0 then
		flash.count = bit32.band(Random.PlayRandom(), 7) + 1
	else
		flash.count = 1
	end

	flash.thinker = NewThinker(flash, StrobeFlashTick)
	RegisterThinker(flash, strobes)

	return flash
end

-- Start strobing lights (usually from a trigger)
const function StartLightStrobing(line: LineDef)
	local secnum = -1

	while true do
		secnum = FindSectorFromLineTag(line, secnum)

		if secnum < 0 then
			break
		end

		const sec = State.sectors[secnum]

		if sec.specialdata then
			continue
		end

		SpawnStrobeFlash(sec, SLOWDARK, 0)
	end
end

-- TURN LINE'S TAG LIGHTS OFF
const function TurnTagLightsOff(line: LineDef)
	for sectorIndex = 0, State.numsectors - 1 do
		const sector = State.sectors[sectorIndex]

		if sector.tag == line.tag then
			local min = sector.lightlevel

			for lineIndex = 0, sector.linecount - 1 do
				const tempLine = sector.lines[lineIndex] :: LineDef


				const tempSector = getNextSector(tempLine, sector)

				if not tempSector then
					continue
				end

				if tempSector.lightlevel < min then
					min = tempSector.lightlevel
				end
			end

			sector.lightlevel = min
		end
	end
end

-- TURN LINE'S TAG LIGHTS ON
const function LightTurnOn(line: LineDef, bright: number)
	for sectorIndex = 0, State.numsectors - 1 do
		const sector = State.sectors[sectorIndex]

		if sector.tag == line.tag then
			-- bright = 0 means to search
			-- for highest light level
			-- surrounding sector
			if bright == 0 then
				for lineIndex = 0, sector.linecount - 1 do
					const tempLine = sector.lines[lineIndex] :: LineDef


					const temp = getNextSector(tempLine, sector)

					if not temp then
						continue
					end

					if temp.lightlevel > bright then
						bright = temp.lightlevel
					end
				end
			end

			sector.lightlevel = bright
		end
	end
end

-- Spawn glowing light
const function GlowTick(g: Glow)
	const sector = g.sector
	if g.direction == -1 then
		-- DOWN
		sector.lightlevel -= GLOWSPEED

		if sector.lightlevel <= g.minlight then
			sector.lightlevel += GLOWSPEED
			g.direction = 1
		end
	elseif g.direction == 1 then
		-- UP
		sector.lightlevel += GLOWSPEED

		if sector.lightlevel >= g.maxlight then
			sector.lightlevel -= GLOWSPEED
			g.direction = -1
		end
	end
end

const function SpawnGlowingLight(sector: Sector)
	const glow = {
		sector = sector,
		minlight = FindMinSurroundingLight(sector, sector.lightlevel),
		maxlight = sector.lightlevel,
		direction = -1,
	}

	glow.thinker = NewThinker(glow, GlowTick)
	RegisterThinker(glow, glows)

	sector.special = 0

	return glow
end

const function GetThinkers()
	return activeThinkers
end

const function GetFireFlickers()
	return fireflickers
end

const function GetLightFlashes()
	return lightflashes
end

const function GetStrobes()
	return strobes
end

const function GetGlows()
	return glows
end

Reset()

return {
	GLOWSPEED = GLOWSPEED,
	STROBEBRIGHT = STROBEBRIGHT,
	FASTDARK = FASTDARK,
	SLOWDARK = SLOWDARK,

	Reset = Reset,
	FireFlickerTick = FireFlickerTick,
	SpawnFireFlicker = SpawnFireFlicker,
	LightFlashTick = LightFlashTick,
	SpawnLightFlash = SpawnLightFlash,
	StrobeFlashTick = StrobeFlashTick,
	SpawnStrobeFlash = SpawnStrobeFlash,
	StartLightStrobing = StartLightStrobing,
	TurnTagLightsOff = TurnTagLightsOff,
	LightTurnOn = LightTurnOn,
	GlowTick = GlowTick,
	SpawnGlowingLight = SpawnGlowingLight,

	GetThinkers = GetThinkers,
	GetFireFlickers = GetFireFlickers,
	GetLightFlashes = GetLightFlashes,
	GetStrobes = GetStrobes,
	GetGlows = GetGlows,
}
