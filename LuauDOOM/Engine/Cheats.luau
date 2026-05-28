--!optimize 2
--!native

--[[
	Cheats.luau

	Handles Doom cheat sequence state, cheat reset, and keyboard responder effects.
]]

const Definitions = require("./Definitions")
const Host = require("./Shared").Cheats
const Sounds = require("../Doom/Sounds")
const Interaction = require("../Play/Interaction")
const Setup = require("../Play/Setup")
const Sound = require("../System/Sound")

const KeyDownEvent = 0
const NOCLIP = 1
const GODMODE = 2

type CheatSequence = { [number]: number }
type Cheat = {
	template: CheatSequence,
	sequence: CheatSequence,
	p: number,
}
type Player = typeof(Setup.GetPlayers()[0])
type CheatEvent = {
	type: number,
	data1: number?,
}

local firsttime = true
const cheat_xlate_table = table.create(256, 0)

const function CopySequence(sequence: CheatSequence): CheatSequence
	const copy: CheatSequence = {}

	for index = 1, #sequence do
		copy[index] = sequence[index]
	end

	return copy
end

const function NewCheat(sequence: CheatSequence): Cheat
	return {
		template = CopySequence(sequence),
		sequence = CopySequence(sequence),
		p = 0,
	}
end

--
-- CHEAT SEQUENCE PACKAGE
--

const function SCRAMBLE(a: number): number
	return bit32.band(a, 1) * 128
		+ bit32.band(a, 2) * 32
		+ bit32.band(a, 4)
		+ bit32.band(a, 8) * 2
		+ bit32.rshift(bit32.band(a, 16), 1)
		+ bit32.band(a, 32)
		+ bit32.rshift(bit32.band(a, 64), 5)
		+ bit32.rshift(bit32.band(a, 128), 7)
end

--
-- Massive bunches of cheat shit
--  to keep it from being easy to figure them out.
-- Yeah, right...
--

const cheat_mus = NewCheat({
	0xB2,
	0x26,
	0xB6,
	0xAE,
	0xEA,
	1,
	0,
	0,
	0xFF,
})

const cheat_choppers = NewCheat({
	0xB2,
	0x26,
	0xE2,
	0x32,
	0xF6,
	0x2A,
	0x2A,
	0xA6,
	0x6A,
	0xEA,
	0xFF,
})

const cheat_god = NewCheat({
	0xB2,
	0x26,
	0x26,
	0xAA,
	0x26,
	0xFF,
})

const cheat_ammo = NewCheat({
	0xB2,
	0x26,
	0xF2,
	0x66,
	0xA2,
	0xFF,
})

const cheat_ammonokey = NewCheat({
	0xB2,
	0x26,
	0x66,
	0xA2,
	0xFF,
})

-- Smashing Pumpkins Into Samml Piles Of Putried Debris.
const cheat_noclip = NewCheat({
	0xB2,
	0x26,
	0xEA,
	0x2A,
	0xB2,
	0xEA,
	0x2A,
	0xF6,
	0x2A,
	0x26,
	0xFF,
})

--
const cheat_commercial_noclip = NewCheat({
	0xB2,
	0x26,
	0xE2,
	0x36,
	0xB2,
	0x2A,
	0xFF,
})

const cheat_powerup = {
	[0] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0x6E,
		0xFF,
	}),
	[1] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0xEA,
		0xFF,
	}),
	[2] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0xB2,
		0xFF,
	}),
	[3] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0x6A,
		0xFF,
	}),
	[4] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0xA2,
		0xFF,
	}),
	[5] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0x36,
		0xFF,
	}),
	[6] = NewCheat({
		0xB2,
		0x26,
		0x62,
		0xA6,
		0x32,
		0xF6,
		0x36,
		0x26,
		0xFF,
	}),
}

const cheat_clev = NewCheat({
	0xB2,
	0x26,
	0xE2,
	0x36,
	0xA6,
	0x6E,
	1,
	0,
	0,
	0xFF,
})

-- my position cheat
const cheat_mypos = NewCheat({
	0xB2,
	0x26,
	0xB6,
	0xBA,
	0x2A,
	0xF6,
	0xEA,
	0xFF,
})

const allCheats = {
	cheat_mus,
	cheat_choppers,
	cheat_god,
	cheat_ammo,
	cheat_ammonokey,
	cheat_noclip,
	cheat_commercial_noclip,
	cheat_clev,
	cheat_mypos,
}

for index = 0, 6 do
	allCheats[#allCheats + 1] = cheat_powerup[index]
end

const function GetString(name: string): string
	const strings = Interaction.GetStrings()
	const value = if typeof(strings) == "table" then strings[name] else nil


	return value
end

const function GetPrimaryPlayer()
	return Setup.GetPlayers()[0]
end

const function ToUnsigned32(value: number): number
	return bit32.band(value, 0xFFFFFFFF)
end

const function GiveAllWeaponsAndAmmo(player: Player)
	player.armorpoints = 200
	player.armortype = 2

	for index = 0, Definitions.NUMWEAPONS - 1 do
		player.weaponowned[index] = true
	end

	for index = 0, Definitions.NUMAMMO - 1 do
		player.ammo[index] = player.maxammo[index]
	end
end

const function GetCheatDigit(value: string, index: number, base: number): number
	const byte = string.byte(value, index)

	if byte == nil then
		return -base
	end

	return byte - base
end

const function ResetCheat(cheat: Cheat)
	cheat.sequence = CopySequence(cheat.template)
	cheat.p = 0
end

--
-- Called in st_stuff module, which handles the input.
-- Returns a 1 if the cheat was successful, 0 if failed.
--
const function cht_CheckCheat(cht: Cheat, key: number): boolean
	if firsttime then
		firsttime = false

		for index = 0, 255 do
			cheat_xlate_table[index + 1] = SCRAMBLE(index)
		end
	end

	if cht.p == 0 then
		cht.p = 1
	end

	if cht.sequence[cht.p] == 0 then
		cht.sequence[cht.p] = key
		cht.p += 1
	elseif cheat_xlate_table[key + 1] == cht.sequence[cht.p] then
		cht.p += 1
	else
		cht.p = 1
	end

	if cht.sequence[cht.p] == 1 then
		cht.p += 1
	elseif cht.sequence[cht.p] == 0xFF then
		cht.p = 1
		return true
	end

	return false
end

const function cht_GetParam(cht: Cheat): string
	local p = 1
	const chars: { string } = {}

	while cht.sequence[p] ~= 1 do
		p += 1
	end

	p += 1

	while cht.sequence[p] ~= 0xFF do
		const c = cht.sequence[p]

		if c == 0 then
			break
		end

		chars[#chars + 1] = string.char(c :: number)
		cht.sequence[p] = 0
		p += 1
	end

	return table.concat(chars)
end

--
-- Respond to keyboard input events,
--  intercept cheats.
--
const function Responder(ev: CheatEvent): boolean
	if ev.type ~= KeyDownEvent then
		return false
	end

	const plyr = GetPrimaryPlayer()

	if typeof(plyr) ~= "table" then
		return false
	end

	local key = bit32.band(ev.data1 or 0, 0xFF)

	-- Host gameplay key queues use uppercase A-Z; Doom cheat sequences are lower-case.
	if key >= 65 and key <= 90 then
		key += 32
	end

	-- 'dqd' cheat for toggleable god mode
	if cht_CheckCheat(cheat_god, key) then
		plyr.cheats = bit32.bxor(plyr.cheats, GODMODE)

		if bit32.btest(plyr.cheats, GODMODE) then
			if plyr.mo then
				plyr.mo.health = 100
			end

			plyr.health = 100
			plyr.message = GetString("STSTR_DQDON")
		else
			plyr.message = GetString("STSTR_DQDOFF")
		end
	-- 'fa' cheat for killer fucking arsenal
	elseif cht_CheckCheat(cheat_ammonokey, key) then
		GiveAllWeaponsAndAmmo(plyr)
		plyr.message = GetString("STSTR_FAADDED")
	-- 'kfa' cheat for key full ammo
	elseif cht_CheckCheat(cheat_ammo, key) then
		GiveAllWeaponsAndAmmo(plyr)

		for index = 0, Definitions.NUMCARDS - 1 do
			plyr.cards[index] = true
		end

		plyr.message = GetString("STSTR_KFAADDED")
	-- 'mus' cheat for changing music
	elseif cht_CheckCheat(cheat_mus, key) then
		const buf = cht_GetParam(cheat_mus)
		local musnum

		plyr.message = GetString("STSTR_MUS")

		if Setup.GetGameMode() == Definitions.commercial then
			musnum = Sounds.mus_runnin + GetCheatDigit(buf, 1, string.byte("0")) * 10 + GetCheatDigit(buf, 2, string.byte("0")) - 1

			if GetCheatDigit(buf, 1, string.byte("0")) * 10 + GetCheatDigit(buf, 2, string.byte("0")) > 35 then
				plyr.message = GetString("STSTR_NOMUS")
			else
				Sound.ChangeMusic(musnum, true)
			end
		else
			musnum = Sounds.mus_e1m1 + GetCheatDigit(buf, 1, string.byte("1")) * 9 + GetCheatDigit(buf, 2, string.byte("1"))

			if GetCheatDigit(buf, 1, string.byte("1")) * 9 + GetCheatDigit(buf, 2, string.byte("1")) > 31 then
				plyr.message = GetString("STSTR_NOMUS")
			else
				Sound.ChangeMusic(musnum, true)
			end
		end
	-- Simplified, accepting both "noclip" and "idspispopd".
	-- no clipping mode cheat
	elseif cht_CheckCheat(cheat_noclip, key) or cht_CheckCheat(cheat_commercial_noclip, key) then
		plyr.cheats = bit32.bxor(plyr.cheats, NOCLIP)

		if bit32.btest(plyr.cheats, NOCLIP) then
			plyr.message = GetString("STSTR_NCON")
		else
			plyr.message = GetString("STSTR_NCOFF")
		end
	end

	-- 'behold?' power-up cheats
	for index = 0, 5 do
		if cht_CheckCheat(cheat_powerup[index], key) then
			if not plyr.powers[index] or plyr.powers[index] == 0 then
				Interaction.GivePower(plyr, index)
			elseif index ~= Definitions.pw_strength then
				plyr.powers[index] = 1
			else
				plyr.powers[index] = 0
			end

			plyr.message = GetString("STSTR_BEHOLDX")
		end
	end

	-- 'behold' power-up menu
	if cht_CheckCheat(cheat_powerup[6], key) then
		plyr.message = GetString("STSTR_BEHOLD")
	-- 'choppers' invulnerability & chainsaw
	elseif cht_CheckCheat(cheat_choppers, key) then
		plyr.weaponowned[Definitions.wp_chainsaw] = true
		plyr.powers[Definitions.pw_invulnerability] = 1
		plyr.message = GetString("STSTR_CHOPPERS")
	-- 'mypos' for player position
	elseif cht_CheckCheat(cheat_mypos, key) then
		plyr.message = string.format(
			"ang=0x%08x;x,y=(0x%08x,0x%08x)",
			ToUnsigned32(plyr.mo.angle),
			ToUnsigned32(plyr.mo.x),
			ToUnsigned32(plyr.mo.y)
		)
	end

	-- 'clev' change-level cheat
	if cht_CheckCheat(cheat_clev, key) then
		const buf = cht_GetParam(cheat_clev)
		local epsd
		local map
		const gamemode = Setup.GetGameMode()

		if gamemode == Definitions.commercial then
			epsd = 0
			map = GetCheatDigit(buf, 1, string.byte("0")) * 10 + GetCheatDigit(buf, 2, string.byte("0"))
		else
			epsd = GetCheatDigit(buf, 1, string.byte("0"))
			map = GetCheatDigit(buf, 2, string.byte("0"))
		end

		-- Catch invalid maps.
		if epsd < 1 then
			return false
		end

		if map < 1 then
			return false
		end

		-- Ohmygod - this is not going to work.
		if gamemode == Definitions.retail and (epsd > 4 or map > 9) then
			return false
		end

		if gamemode == Definitions.registered and (epsd > 3 or map > 9) then
			return false
		end

		if gamemode == Definitions.shareware and (epsd > 1 or map > 9) then
			return false
		end

		if gamemode == Definitions.commercial and (epsd > 1 or map > 34) then
			return false
		end

		-- So be it.
		plyr.message = GetString("STSTR_CLEV")

		if Host.warpToLevel ~= nil then
			Host.warpToLevel(epsd, map)
		end
	end

	return false
end

const function Reset()
	firsttime = true

	for _, cheat in allCheats do
		ResetCheat(cheat)
	end
end

Reset()

return {
	Reset = Reset,
	Responder = Responder,
}
