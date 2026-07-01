--!native
--!optimize 2

-- Port of Interaction.C
-- Handling interactions (i.e., collisions).
-- Runtime-owned hooks such as sound playback, automap stop, tactile feedback,
-- and `DropWeapon` route through Play/Runtime.

const Definitions = require("../Engine/Definitions")
const English = require("../Doom/English")
const Fixed = require("../Miscellaneous/Fixed")
const French = require("../Doom/French")
const Info = require("../Doom/Info")
const Geometry = require("../Renderer/Geometry")
const Mobj = require("./Mobj")
const Random = require("../Miscellaneous/Random")
const Runtime = require("./Runtime")
const Tables = require("../Engine/Tables")

const BONUSADD = 6
const MAXHEALTH = 100
const BASETHRESHOLD = 100

const PST_LIVE = 0
const PST_DEAD = 1
const PST_REBORN = 2

const GODMODE = 2

const sfx_slop = 31
const sfx_itemup = 32
const sfx_wpnup = 33
const sfx_pldeth = 57
const sfx_pdiehi = 58
const sfx_getpow = 93

type NumberMap = { [number]: number }
type BooleanMap = { [number]: boolean }
type StringMap = { [string]: string }
type PlayerBody = {
	health: number,
	flags: number,
}
type Player = {
	[string]: unknown,
	ammo: NumberMap,
	armorpoints: number,
	armortype: number,
	backpack: boolean,
	bonuscount: number,
	cards: BooleanMap,
	cheats: number,
	damagecount: number,
	frags: NumberMap,
	health: number,
	itemcount: number,
	killcount: number,
	maxammo: NumberMap,
	message: string,
	mo: PlayerBody,
	pendingweapon: number,
	playerstate: number,
	powers: NumberMap,
	readyweapon: number,
	weaponowned: BooleanMap,
}
type MobjInfo = {
	deathstate: number,
	mass: number,
	painchance: number,
	painstate: number,
	seestate: number,
	spawnhealth: number,
	spawnstate: number,
	xdeathstate: number,
}
type Sector = {
	special: number,
}
type Subsector = {
	sector: Sector,
}
type MapObject = {
	[string]: unknown,
	flags: number,
	health: number,
	height: number,
	info: MobjInfo,
	momx: number,
	momy: number,
	momz: number,
	player: Player?,
	reactiontime: number,
	sprite: number,
	state: unknown,
	subsector: Subsector,
	target: MapObject?,
	threshold: number?,
	tics: number,
	type: number,
	x: number,
	y: number,
	z: number,
}
type PlayerMapObject = MapObject & {
	player: Player,
}
type PlayerMap = { [number]: Player }

local language = Definitions.english
local gamemode = Definitions.indetermined
local gameskill = Definitions.sk_medium
local strings: StringMap = English
local players: PlayerMap = {}

-- a weapon is found with two clip loads,
-- a big item has five clip loads
const maxammo = {
	[0] = 200,
	50,
	300,
	50,
}

const clipammo = {
	[0] = 10,
	4,
	20,
	1,
}

const weaponinfo = {
	[Definitions.wp_fist] = {
		ammo = Definitions.am_noammo,
		upstate = Info.PUNCHUP,
		downstate = Info.PUNCHDOWN,
		readystate = Info.PUNCH,
		atkstate = Info.PUNCH1,
		flashstate = Info.NULL,
	},
	[Definitions.wp_pistol] = {
		ammo = Definitions.am_clip,
		upstate = Info.PISTOLUP,
		downstate = Info.PISTOLDOWN,
		readystate = Info.PISTOL,
		atkstate = Info.PISTOL1,
		flashstate = Info.PISTOLFLASH,
	},
	[Definitions.wp_shotgun] = {
		ammo = Definitions.am_shell,
		upstate = Info.SGUNUP,
		downstate = Info.SGUNDOWN,
		readystate = Info.SGUN,
		atkstate = Info.SGUN1,
		flashstate = Info.SGUNFLASH1,
	},
	[Definitions.wp_chaingun] = {
		ammo = Definitions.am_clip,
		upstate = Info.CHAINUP,
		downstate = Info.CHAINDOWN,
		readystate = Info.CHAIN,
		atkstate = Info.CHAIN1,
		flashstate = Info.CHAINFLASH1,
	},
	[Definitions.wp_missile] = {
		ammo = Definitions.am_misl,
		upstate = Info.MISSILEUP,
		downstate = Info.MISSILEDOWN,
		readystate = Info.MissileWeaponReady,
		atkstate = Info.MISSILE1,
		flashstate = Info.MISSILEFLASH1,
	},
	[Definitions.wp_plasma] = {
		ammo = Definitions.am_cell,
		upstate = Info.PLASMAUP,
		downstate = Info.PLASMADOWN,
		readystate = Info.PlasmaWeaponReady,
		atkstate = Info.PLASMA1,
		flashstate = Info.PLASMAFLASH1,
	},
	[Definitions.wp_bfg] = {
		ammo = Definitions.am_cell,
		upstate = Info.BFGUP,
		downstate = Info.BFGDOWN,
		readystate = Info.BfgWeaponReady,
		atkstate = Info.BFG1,
		flashstate = Info.BFGFLASH1,
	},
	[Definitions.wp_chainsaw] = {
		ammo = Definitions.am_noammo,
		upstate = Info.SAWUP,
		downstate = Info.SAWDOWN,
		readystate = Info.SAW,
		atkstate = Info.SAW1,
		flashstate = Info.NULL,
	},
	[Definitions.wp_supershotgun] = {
		ammo = Definitions.am_shell,
		upstate = Info.DSGUNUP,
		downstate = Info.DSGUNDOWN,
		readystate = Info.DSGUN,
		atkstate = Info.DSGUN1,
		flashstate = Info.DSGUNFLASH1,
	},
}

const function ToUnsigned32(value: number): number
	return bit32.band(value, 0xFFFFFFFF)
end

const function SetLanguage(value: number)
	language = value
	strings = if value == Definitions.french then French else English
end

const function GetString(name: string): string
	const value = strings[name]


	return value
end

const function CheckIndex(index: number, count: number, context: string): number

	return index
end

const function GetPlayerPower(player: Player, index: number): number
	CheckIndex(index, Definitions.NUMPOWERS, "GetPlayerPower")

	const value = player.powers[index]

	if value == nil then
		return 0
	end

	return value
end

const function GetPrimaryPlayer(): Player | false
	return players[0] or false
end

const function GetPlayerIndex(player: Player, context: string): number
	for index = 0, Definitions.MAXPLAYERS - 1 do
		if players[index] == player then
			return index
		end
	end

	for index = 1, Definitions.MAXPLAYERS do
		if players[index] == player then
			return index - 1
		end
	end

	error(`{context}: player is not registered`)
end

--
-- GiveAmmo
-- Num is the number of clip loads,
-- not the individual count (0= 1/2 clip).
-- Returns false if the ammo can't be picked up at all
--
const function GiveAmmo(player: Player, ammo: number, num: number): boolean
	if ammo == Definitions.am_noammo then
		return false
	end

	CheckIndex(ammo, Definitions.NUMAMMO, "GiveAmmo")

	if player.ammo[ammo] == player.maxammo[ammo] then
		return false
	end

	if num ~= 0 then
		num *= clipammo[ammo]
	else
		num = clipammo[ammo] // 2
	end

	if gameskill == Definitions.sk_baby or gameskill == Definitions.sk_nightmare then
		num *= 2
	end

	const oldammo = player.ammo[ammo]
	player.ammo[ammo] += num

	if player.ammo[ammo] > player.maxammo[ammo] then
		player.ammo[ammo] = player.maxammo[ammo]
	end

	if oldammo ~= 0 then
		return true
	end

	if ammo == Definitions.am_clip then
		if player.readyweapon == Definitions.wp_fist then
			if player.weaponowned[Definitions.wp_chaingun] then
				player.pendingweapon = Definitions.wp_chaingun
			else
				player.pendingweapon = Definitions.wp_pistol
			end
		end
	elseif ammo == Definitions.am_shell then
		if player.readyweapon == Definitions.wp_fist or player.readyweapon == Definitions.wp_pistol then
			if player.weaponowned[Definitions.wp_shotgun] then
				player.pendingweapon = Definitions.wp_shotgun
			end
		end
	elseif ammo == Definitions.am_cell then
		if player.readyweapon == Definitions.wp_fist or player.readyweapon == Definitions.wp_pistol then
			if player.weaponowned[Definitions.wp_plasma] then
				player.pendingweapon = Definitions.wp_plasma
			end
		end
	elseif ammo == Definitions.am_misl then
		if player.readyweapon == Definitions.wp_fist then
			if player.weaponowned[Definitions.wp_missile] then
				player.pendingweapon = Definitions.wp_missile
			end
		end
	end

	return true
end

--
-- GiveWeapon
-- The weapon name may have a DROPPED flag ored in.
--
const function GiveWeapon(player: Player, weapon: number, dropped: boolean): boolean
	CheckIndex(weapon, Definitions.NUMWEAPONS, "GiveWeapon")

	const info = weaponinfo[weapon]


	local gaveammo

	if info.ammo ~= Definitions.am_noammo then
		if dropped then
			gaveammo = GiveAmmo(player, info.ammo, 1)
		else
			gaveammo = GiveAmmo(player, info.ammo, 2)
		end
	else
		gaveammo = false
	end

	local gaveweapon

	if player.weaponowned[weapon] then
		gaveweapon = false
	else
		gaveweapon = true
		player.weaponowned[weapon] = true
		player.pendingweapon = weapon
	end

	return gaveweapon or gaveammo
end

--
-- GiveBody
-- Returns false if the body isn't needed at all
--
const function GiveBody(player: Player, num: number): boolean
	const mo = player.mo

	if player.health >= MAXHEALTH then
		return false
	end

	player.health += num

	if player.health > MAXHEALTH then
		player.health = MAXHEALTH
	end

	mo.health = player.health

	return true
end

--
-- GiveArmor
-- Returns false if the armor is worse
-- than the current armor.
--
const function GiveArmor(player: Player, armortype: number): boolean
	const hits = armortype * 100

	if player.armorpoints >= hits then
		return false
	end

	player.armortype = armortype
	player.armorpoints = hits

	return true
end

--
-- GiveCard
--
const function GiveCard(player: Player, card: number)
	CheckIndex(card, Definitions.NUMCARDS, "GiveCard")

	if player.cards[card] then
		return
	end

	player.bonuscount = BONUSADD
	player.cards[card] = true
end

--
-- GivePower
--
const function GivePower(player: Player, power: number): boolean
	const mo = player.mo
	CheckIndex(power, Definitions.NUMPOWERS, "GivePower")

	if power == Definitions.pw_invulnerability then
		player.powers[power] = Definitions.INVULNTICS
		return true
	end

	if power == Definitions.pw_invisibility then
		player.powers[power] = Definitions.INVISTICS
		mo.flags = bit32.bor(mo.flags, Info.SHADOW)
		return true
	end

	if power == Definitions.pw_infrared then
		player.powers[power] = Definitions.INFRATICS
		return true
	end

	if power == Definitions.pw_ironfeet then
		player.powers[power] = Definitions.IRONTICS
		return true
	end

	if power == Definitions.pw_strength then
		GiveBody(player, 100)
		player.powers[power] = 1
		return true
	end

	if GetPlayerPower(player, power) ~= 0 then
		return false
	end

	player.powers[power] = 1
	return true
end

--
-- TouchSpecialThing
--
const function TouchSpecialThing(special: MapObject, toucher: PlayerMapObject)
	const delta = special.z - toucher.z

	if delta > toucher.height or delta < -8 * Fixed.FRACUNIT then
		return
	end

	local sound = sfx_itemup
	const player = toucher.player
	const playerMo = player.mo

	if toucher.health <= 0 then
		return
	end

	if special.sprite == Info.SPR_ARM1 then
		if not GiveArmor(player, 1) then
			return
		end
		player.message = GetString("GOTARMOR")
	elseif special.sprite == Info.SPR_ARM2 then
		if not GiveArmor(player, 2) then
			return
		end
		player.message = GetString("GOTMEGA")
	elseif special.sprite == Info.SPR_BON1 then
		player.health += 1

		if player.health > 200 then
			player.health = 200
		end

		playerMo.health = player.health
		player.message = GetString("GOTHTHBONUS")
	elseif special.sprite == Info.SPR_BON2 then
		player.armorpoints += 1

		if player.armorpoints > 200 then
			player.armorpoints = 200
		end

		if not player.armortype or player.armortype == 0 then
			player.armortype = 1
		end

		player.message = GetString("GOTARMBONUS")
	elseif special.sprite == Info.SPR_SOUL then
		player.health += 100

		if player.health > 200 then
			player.health = 200
		end

		playerMo.health = player.health
		player.message = GetString("GOTSUPER")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_MEGA then
		if gamemode ~= Definitions.commercial then
			return
		end

		player.health = 200
		playerMo.health = player.health
		GiveArmor(player, 2)
		player.message = GetString("GOTMSPHERE")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_BKEY then
		if not player.cards[Definitions.it_bluecard] then
			player.message = GetString("GOTBLUECARD")
		end
		GiveCard(player, Definitions.it_bluecard)
	elseif special.sprite == Info.SPR_YKEY then
		if not player.cards[Definitions.it_yellowcard] then
			player.message = GetString("GOTYELWCARD")
		end
		GiveCard(player, Definitions.it_yellowcard)
	elseif special.sprite == Info.SPR_RKEY then
		if not player.cards[Definitions.it_redcard] then
			player.message = GetString("GOTREDCARD")
		end
		GiveCard(player, Definitions.it_redcard)
	elseif special.sprite == Info.SPR_BSKU then
		if not player.cards[Definitions.it_blueskull] then
			player.message = GetString("GOTBLUESKUL")
		end
		GiveCard(player, Definitions.it_blueskull)
	elseif special.sprite == Info.SPR_YSKU then
		if not player.cards[Definitions.it_yellowskull] then
			player.message = GetString("GOTYELWSKUL")
		end
		GiveCard(player, Definitions.it_yellowskull)
	elseif special.sprite == Info.SPR_RSKU then
		if not player.cards[Definitions.it_redskull] then
			player.message = GetString("GOTREDSKULL")
		end
		GiveCard(player, Definitions.it_redskull)
	elseif special.sprite == Info.SPR_STIM then
		if not GiveBody(player, 10) then
			return
		end
		player.message = GetString("GOTSTIM")
	elseif special.sprite == Info.SPR_MEDI then
		if not GiveBody(player, 25) then
			return
		end

		if player.health < 25 then
			player.message = GetString("GOTMEDINEED")
		else
			player.message = GetString("GOTMEDIKIT")
		end
	elseif special.sprite == Info.SPR_PINV then
		if not GivePower(player, Definitions.pw_invulnerability) then
			return
		end
		player.message = GetString("GOTINVUL")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_PSTR then
		if not GivePower(player, Definitions.pw_strength) then
			return
		end
		player.message = GetString("GOTBERSERK")

		if player.readyweapon ~= Definitions.wp_fist then
			player.pendingweapon = Definitions.wp_fist
		end

		sound = sfx_getpow
	elseif special.sprite == Info.SPR_PINS then
		if not GivePower(player, Definitions.pw_invisibility) then
			return
		end
		player.message = GetString("GOTINVIS")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_SUIT then
		if not GivePower(player, Definitions.pw_ironfeet) then
			return
		end
		player.message = GetString("GOTSUIT")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_PMAP then
		if not GivePower(player, Definitions.pw_allmap) then
			return
		end
		player.message = GetString("GOTMAP")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_PVIS then
		if not GivePower(player, Definitions.pw_infrared) then
			return
		end
		player.message = GetString("GOTVISOR")
		sound = sfx_getpow
	elseif special.sprite == Info.SPR_CLIP then
		if bit32.btest(special.flags, Info.DROPPED) then
			if not GiveAmmo(player, Definitions.am_clip, 0) then
				return
			end
		else
			if not GiveAmmo(player, Definitions.am_clip, 1) then
				return
			end
		end
		player.message = GetString("GOTCLIP")
	elseif special.sprite == Info.SPR_AMMO then
		if not GiveAmmo(player, Definitions.am_clip, 5) then
			return
		end
		player.message = GetString("GOTCLIPBOX")
	elseif special.sprite == Info.SPR_ROCK then
		if not GiveAmmo(player, Definitions.am_misl, 1) then
			return
		end
		player.message = GetString("GOTROCKET")
	elseif special.sprite == Info.SPR_BROK then
		if not GiveAmmo(player, Definitions.am_misl, 5) then
			return
		end
		player.message = GetString("GOTROCKBOX")
	elseif special.sprite == Info.SPR_CELL then
		if not GiveAmmo(player, Definitions.am_cell, 1) then
			return
		end
		player.message = GetString("GOTCELL")
	elseif special.sprite == Info.SPR_CELP then
		if not GiveAmmo(player, Definitions.am_cell, 5) then
			return
		end
		player.message = GetString("GOTCELLBOX")
	elseif special.sprite == Info.SPR_SHEL then
		if not GiveAmmo(player, Definitions.am_shell, 1) then
			return
		end
		player.message = GetString("GOTSHELLS")
	elseif special.sprite == Info.SPR_SBOX then
		if not GiveAmmo(player, Definitions.am_shell, 5) then
			return
		end
		player.message = GetString("GOTSHELLBOX")
	elseif special.sprite == Info.SPR_BPAK then
		if not player.backpack then
			for index = 0, Definitions.NUMAMMO - 1 do
				player.maxammo[index] *= 2
			end
			player.backpack = true
		end

		for index = 0, Definitions.NUMAMMO - 1 do
			GiveAmmo(player, index, 1)
		end

		player.message = GetString("GOTBACKPACK")
	elseif special.sprite == Info.SPR_BFUG then
		if not GiveWeapon(player, Definitions.wp_bfg, false) then
			return
		end
		player.message = GetString("GOTBFG9000")
		sound = sfx_wpnup
	elseif special.sprite == Info.SPR_MGUN then
		if not GiveWeapon(player, Definitions.wp_chaingun, bit32.btest(special.flags, Info.DROPPED)) then
			return
		end
		player.message = GetString("GOTCHAINGUN")
		sound = sfx_wpnup
	elseif special.sprite == Info.SPR_CSAW then
		if not GiveWeapon(player, Definitions.wp_chainsaw, false) then
			return
		end
		player.message = GetString("GOTCHAINSAW")
		sound = sfx_wpnup
	elseif special.sprite == Info.SPR_LAUN then
		if not GiveWeapon(player, Definitions.wp_missile, false) then
			return
		end
		player.message = GetString("GOTLAUNCHER")
		sound = sfx_wpnup
	elseif special.sprite == Info.SPR_PLAS then
		if not GiveWeapon(player, Definitions.wp_plasma, false) then
			return
		end
		player.message = GetString("GOTPLASMA")
		sound = sfx_wpnup
	elseif special.sprite == Info.SPR_SHOT then
		if not GiveWeapon(player, Definitions.wp_shotgun, bit32.btest(special.flags, Info.DROPPED)) then
			return
		end
		player.message = GetString("GOTSHOTGUN")
		sound = sfx_wpnup
	elseif special.sprite == Info.SPR_SGN2 then
		if not GiveWeapon(player, Definitions.wp_supershotgun, bit32.btest(special.flags, Info.DROPPED)) then
			return
		end
		player.message = GetString("GOTSHOTGUN2")
		sound = sfx_wpnup
	else
		error("SpecialThing: Unknown gettable thing")
	end

	if bit32.btest(special.flags, Info.COUNTITEM) then
		player.itemcount = (player.itemcount or 0) + 1
	end

	Mobj.RemoveMobj(special)
	player.bonuscount += BONUSADD

	if player == GetPrimaryPlayer() then
		Runtime.startSound(nil, sound)
	end
end

--
-- KillMobj
--
const function KillMobj(source: MapObject?, target: MapObject)
	target.flags = bit32.band(target.flags, bit32.bnot(bit32.bor(Info.SHOOTABLE, Info.FLOAT, Info.SKULLFLY)))

	if target.type ~= Info.SKULL then
		target.flags = bit32.band(target.flags, bit32.bnot(Info.NOGRAVITY))
	end

	target.flags = bit32.bor(target.flags, Info.CORPSE, Info.DROPOFF)
	target.height = target.height // 4

	if source and source.player then
		if bit32.btest(target.flags, Info.COUNTKILL) then
			source.player.killcount = (source.player.killcount or 0) + 1
		end

		if target.player then
			const targetIndex = GetPlayerIndex(target.player, "KillMobj target")
			source.player.frags[targetIndex] = (source.player.frags[targetIndex] or 0) + 1
		end
	elseif bit32.btest(target.flags, Info.COUNTKILL) then
		const player = GetPrimaryPlayer()

		if player then
			player.killcount = (player.killcount or 0) + 1
		end
	end

	if target.player then
		const player = target.player

		if not source then
			const playerIndex = GetPlayerIndex(player, "KillMobj player")
			player.frags[playerIndex] = (player.frags[playerIndex] or 0) + 1
		end

		target.flags = bit32.band(target.flags, bit32.bnot(Info.SOLID))
		player.playerstate = PST_DEAD
		Runtime.dropWeapon(player)

		if player == GetPrimaryPlayer() and Runtime.getAutomapActive() then
			Runtime.stopAutomap()
		end
	end

	if target.health < -target.info.spawnhealth and target.info.xdeathstate ~= Info.NULL then
		Mobj.SetMobjState(target, target.info.xdeathstate)
	else
		Mobj.SetMobjState(target, target.info.deathstate)
	end

	target.tics -= bit32.band(Random.PlayRandom(), 3)

	if target.tics < 1 then
		target.tics = 1
	end

	local item

	if target.type == Info.WOLFSS or target.type == Info.POSSESSED then
		item = Info.ClipMobj
	elseif target.type == Info.SHOTGUY then
		item = Info.SHOTGUN
	elseif target.type == Info.CHAINGUY then
		item = Info.CHAINGUN
	else
		return
	end

	const mo = Mobj.SpawnMobj(target.x, target.y, Mobj.ONFLOORZ, item)
	mo.flags = bit32.bor(mo.flags, Info.DROPPED)
end

--
-- DamageMobj
-- Damages both enemies and players
-- "inflictor" is the thing that caused the damage
--  creature or missile, can be NULL (slime, etc)
-- "source" is the thing to target after taking damage
--  creature or NULL
-- Source and inflictor are the same for melee attacks.
-- Source can be NULL for slime, barrel explosions
-- and other environmental stuff.
--
const function DamageMobj(target: MapObject, inflictor: MapObject?, source: MapObject?, damage: number)
	if bit32.band(target.flags, Info.SHOOTABLE) == 0 then
		return
	end

	if target.health <= 0 then
		return
	end

	if bit32.btest(target.flags, Info.SKULLFLY) then
		target.momx = 0
		target.momy = 0
		target.momz = 0
	end

	const player = target.player

	if player then
		if gameskill == Definitions.sk_baby then
			damage //= 2
		end
	end

	if inflictor
		and bit32.band(target.flags, Info.NOCLIP) == 0
		and (not source or not source.player or source.player.readyweapon ~= Definitions.wp_chainsaw) then
		const mass = target.info.mass

		if mass ~= 0 then
			local ang = Geometry.PointToAngle2(inflictor.x, inflictor.y, target.x, target.y)
			local thrust = (damage * bit32.arshift(Fixed.FRACUNIT, 3) * 100) // mass

			if damage < 40
				and damage > target.health
				and target.z - inflictor.z > 64 * Fixed.FRACUNIT
				and bit32.btest(Random.PlayRandom(), 1) then
				ang = ToUnsigned32(ang + Tables.ANG180)
				thrust *= 4
			end

			ang = bit32.rshift(ang, Tables.ANGLETOFINESHIFT)
			target.momx += Fixed.FixedMul(thrust, Tables.finecosine[ang])
			target.momy += Fixed.FixedMul(thrust, Tables.finesine[ang])
		end
	end

	if player then

		if target.subsector.sector.special == 11 and damage >= target.health then
			damage = target.health - 1
		end

		if damage < 1000 and (bit32.btest(player.cheats, GODMODE) or GetPlayerPower(player, Definitions.pw_invulnerability) ~= 0) then
			return
		end

		if player.armortype and player.armortype ~= 0 then
			local saved

			if player.armortype == 1 then
				saved = damage // 3
			else
				saved = damage // 2
			end

			if player.armorpoints <= saved then
				saved = player.armorpoints
				player.armortype = 0
			end

			player.armorpoints -= saved
			damage -= saved
		end

		player.health -= damage

		if player.health < 0 then
			player.health = 0
		end

		player.attacker = source
		player.damagecount += damage

		if player.damagecount > 100 then
			player.damagecount = 100
		end

		const temp = if damage < 100 then damage else 100

		if player == GetPrimaryPlayer() then
			Runtime.tactile(40, 10, 40 + temp * 2)
		end
	end

	target.health -= damage

	if target.health <= 0 then
		KillMobj(source, target)
		return
	end

	if Random.PlayRandom() < target.info.painchance and bit32.band(target.flags, Info.SKULLFLY) == 0 then
		target.flags = bit32.bor(target.flags, Info.JUSTHIT)
		Mobj.SetMobjState(target, target.info.painstate)
	end

	target.reactiontime = 0

	if (target.threshold == nil or target.threshold == 0 or target.type == Info.VILE)
		and source
		and source ~= target
		and source.type ~= Info.VILE then
		target.target = source
		target.threshold = BASETHRESHOLD

		if target.state == Info.states[target.info.spawnstate] and target.info.seestate ~= Info.NULL then
			Mobj.SetMobjState(target, target.info.seestate)
		end
	end
end

const function SetPlayers(value: PlayerMap)
	players = value
end

const function GetPlayers(): PlayerMap
	return players
end

const function GetLanguage(): number
	return language
end

const function GetStrings(): StringMap
	return strings
end

const function SetGameMode(value: number)
	gamemode = value
end

const function GetGameMode(): number
	return gamemode
end

const function SetGameSkill(value: number)
	gameskill = value
end

const function GetGameSkill(): number
	return gameskill
end

const function Reset()
	language = Definitions.english
	gamemode = Definitions.indetermined
	gameskill = Definitions.sk_medium
	players = {}
	SetLanguage(language)
end

Reset()

const Exports = {
	BONUSADD = BONUSADD,
	MAXHEALTH = MAXHEALTH,
	BASETHRESHOLD = BASETHRESHOLD,
	PST_LIVE = PST_LIVE,
	PST_DEAD = PST_DEAD,
	PST_REBORN = PST_REBORN,
	GODMODE = GODMODE,

	sfx_slop = sfx_slop,
	sfx_itemup = sfx_itemup,
	sfx_wpnup = sfx_wpnup,
	sfx_pldeth = sfx_pldeth,
	sfx_pdiehi = sfx_pdiehi,
	sfx_getpow = sfx_getpow,

	maxammo = maxammo,
	clipammo = clipammo,
	weaponinfo = weaponinfo,

	Reset = Reset,
	SetPlayers = SetPlayers,
	GetPlayers = GetPlayers,
	SetLanguage = SetLanguage,
	GetLanguage = GetLanguage,
	GetStrings = GetStrings,
	SetGameMode = SetGameMode,
	GetGameMode = GetGameMode,
	SetGameSkill = SetGameSkill,
	GetGameSkill = GetGameSkill,

	GiveAmmo = GiveAmmo,
	GiveWeapon = GiveWeapon,
	GiveBody = GiveBody,
	GiveArmor = GiveArmor,
	GiveCard = GiveCard,
	GivePower = GivePower,
	TouchSpecialThing = TouchSpecialThing,
	KillMobj = KillMobj,
	DamageMobj = DamageMobj,
}

Exports.GiveAmmo = GiveAmmo
Exports.GiveWeapon = GiveWeapon
Exports.GiveBody = GiveBody
Exports.GiveArmor = GiveArmor
Exports.GiveCard = GiveCard
Exports.GivePower = GivePower
Exports.TouchSpecialThing = TouchSpecialThing
Exports.KillMobj = KillMobj
Exports.DamageMobj = DamageMobj

return Exports
