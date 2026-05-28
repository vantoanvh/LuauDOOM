--!native
--!optimize 2

-- Port of p_user.c
-- Player related stuff.
-- Bobbing POV/weapon, movement.
-- Pending weapon.
-- Note: `UseLines` is supplied through the shared play runtime.

const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const Geometry = require("../Renderer/Geometry")
const Info = require("../Doom/Info")
const Mobj = require("./Mobj")
const Psprites = require("./Psprites")
const Runtime = require("./Runtime")
const Specials = require("./Specials")
const Tables = require("../Engine/Tables")

const FRACUNIT = 65536
const FINEANGLES = 8192
const FINEMASK = 8191
const ANG90 = 0x40000000
const ANG180 = 0x80000000
const ANGLETOFINESHIFT = 19
const UINT32_MASK = 0xFFFFFFFF
const finecosine = Tables.finecosine
const finesine = Tables.finesine
const FixedMul = Fixed.FixedMul

-- Index of the special effects (INVUL inverse) map.
const INVERSECOLORMAP = 32

-- 16 pixels of bob
const MAXBOB = 0x100000

const VIEWHEIGHT = 41 * FRACUNIT
const ANG5 = ANG90 // 18

const PST_LIVE = 0
const PST_DEAD = 1
const PST_REBORN = 2

const NOCLIP = 1
const NOMOMENTUM = 4

const ATTACK = 1
const USE = 2
const CHANGE = 4
const WEAPONMASK = 8 + 16 + 32
const WEAPONSHIFT = 3
const SPECIAL = 128

type NumberMap = { [number]: number }
type BooleanMap = { [number]: boolean }
type TicCmd = {
	forwardmove: number,
	sidemove: number,
	angleturn: number,
	buttons: number,
}
type Sector = {
	special: number,
}
type Subsector = {
	sector: Sector | false,
}
type PlayerMobj = {
	[string]: unknown,
	angle: number,
	ceilingz: number,
	flags: number,
	floorz: number,
	momx: number,
	momy: number,
	reactiontime: number,
	state: unknown,
	subsector: Subsector | false,
	x: number,
	y: number,
	z: number,
}
type Player = {
	[string]: unknown,
	attacker: PlayerMobj | false,
	bob: number,
	bonuscount: number,
	cheats: number,
	cmd: TicCmd,
	damagecount: number,
	deltaviewheight: number,
	fixedcolormap: number,
	mo: PlayerMobj,
	pendingweapon: number,
	playerstate: number,
	powers: NumberMap,
	readyweapon: number,
	usedown: boolean,
	viewheight: number,
	viewz: number,
	weaponowned: BooleanMap,
}

local gamemode = Definitions.indetermined
local onground = false

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function GetPlayerPower(player: Player, index: number): number
	const value = player.powers[index]

	if value == nil then
		return 0
	end

	return value
end

-- Thrust
-- Moves the given origin along a given angle.
const function Thrust(player: Player, angle: number, move: number)
	const fineAngle = bit32.rshift(bit32.band(angle, UINT32_MASK), ANGLETOFINESHIFT)

	player.mo.momx += FixedMul(move, finecosine[fineAngle])
	player.mo.momy += FixedMul(move, finesine[fineAngle])
end

-- CalcHeight
-- Calculate the walking / running height adjustment
const function CalcHeight(player: Player)
	local bob = FixedMul(player.mo.momx, player.mo.momx)
	bob += FixedMul(player.mo.momy, player.mo.momy)
	bob = bit32.arshift(bob, 2)

	if bob > MAXBOB then
		bob = MAXBOB
	end

	player.bob = bob

	if bit32.btest(player.cheats, NOMOMENTUM) or not onground then
		player.viewz = player.mo.z + VIEWHEIGHT

		if player.viewz > player.mo.ceilingz - 4 * FRACUNIT then
			player.viewz = player.mo.ceilingz - 4 * FRACUNIT
		end

		player.viewz = player.mo.z + player.viewheight
		return
	end

	const angle = bit32.band((FINEANGLES // 20) * GetLevelTime(), FINEMASK)
	bob = FixedMul(player.bob // 2, finesine[angle])

	if player.playerstate == PST_LIVE then
		player.viewheight += player.deltaviewheight

		if player.viewheight > VIEWHEIGHT then
			player.viewheight = VIEWHEIGHT
			player.deltaviewheight = 0
		end

		if player.viewheight < VIEWHEIGHT // 2 then
			player.viewheight = VIEWHEIGHT // 2

			if player.deltaviewheight <= 0 then
				player.deltaviewheight = 1
			end
		end

		if player.deltaviewheight ~= 0 then
			player.deltaviewheight += FRACUNIT // 4

			if player.deltaviewheight == 0 then
				player.deltaviewheight = 1
			end
		end
	end

	player.viewz = player.mo.z + player.viewheight + bob

	if player.viewz > player.mo.ceilingz - 4 * FRACUNIT then
		player.viewz = player.mo.ceilingz - 4 * FRACUNIT
	end
end

-- MovePlayer
const function MovePlayer(player: Player)
	const cmd = player.cmd

	player.mo.angle = bit32.band(player.mo.angle + bit32.band(cmd.angleturn, 0xFFFF) * 65536, UINT32_MASK)

	-- Do not let the player control movement
	--  if not onground.
	onground = player.mo.z <= player.mo.floorz

	if cmd.forwardmove ~= 0 and onground then
		Thrust(player, player.mo.angle, cmd.forwardmove * 2048)
	end

	if cmd.sidemove ~= 0 and onground then
		Thrust(player, bit32.band(player.mo.angle - ANG90, UINT32_MASK), cmd.sidemove * 2048)
	end

	if (cmd.forwardmove ~= 0 or cmd.sidemove ~= 0) and player.mo.state == Info.states[Info.PLAY] then
		Mobj.SetMobjState(player.mo, Info.PLAY_RUN1)
	end
end

-- DeathThink
-- Fall on your face when dying.
-- Decrease POV height to floor height.
const function DeathThink(player: Player)
	Psprites.MovePsprites(player)

	if player.viewheight > 6 * FRACUNIT then
		player.viewheight -= FRACUNIT
	end

	if player.viewheight < 6 * FRACUNIT then
		player.viewheight = 6 * FRACUNIT
	end

	player.deltaviewheight = 0
	onground = player.mo.z <= player.mo.floorz
	CalcHeight(player)

	if player.attacker and player.attacker ~= player.mo then
		const angle = Geometry.PointToAngle2(player.mo.x, player.mo.y, player.attacker.x, player.attacker.y)
		const delta = bit32.band(angle - player.mo.angle, UINT32_MASK)

		if delta < ANG5 or delta > bit32.band(-ANG5, UINT32_MASK) then
			player.mo.angle = angle

			if player.damagecount ~= 0 then
				player.damagecount -= 1
			end
		elseif delta < ANG180 then
			player.mo.angle = bit32.band(player.mo.angle + ANG5, UINT32_MASK)
		else
			player.mo.angle = bit32.band(player.mo.angle - ANG5, UINT32_MASK)
		end
	elseif player.damagecount ~= 0 then
		player.damagecount -= 1
	end

	if bit32.btest(player.cmd.buttons, USE) then
		player.playerstate = PST_REBORN
	end
end

-- PlayerThink
const function PlayerThink(player: Player)
	const cmd = player.cmd

	if bit32.btest(player.cheats, NOCLIP) then
		player.mo.flags = bit32.bor(player.mo.flags, Info.NOCLIP)
	else
		player.mo.flags = bit32.band(player.mo.flags, bit32.bnot(Info.NOCLIP))
	end

	if bit32.btest(player.mo.flags, Info.JUSTATTACKED) then
		cmd.angleturn = 0
		cmd.forwardmove = 0xC800 // 512
		cmd.sidemove = 0
		player.mo.flags = bit32.band(player.mo.flags, bit32.bnot(Info.JUSTATTACKED))
	end

	if player.playerstate == PST_DEAD then
		DeathThink(player)
		return
	end

	if player.mo.reactiontime ~= 0 then
		player.mo.reactiontime -= 1
	else
		MovePlayer(player)
	end

	CalcHeight(player)

	const sector = player.mo.subsector and player.mo.subsector.sector

	if sector and sector.special ~= 0 then
		Specials.PlayerInSpecialSector(player)
	end

	if bit32.btest(cmd.buttons, SPECIAL) then
		cmd.buttons = 0
	end

	if bit32.btest(cmd.buttons, CHANGE) then
		local newweapon = bit32.rshift(bit32.band(cmd.buttons, WEAPONMASK), WEAPONSHIFT)

		if newweapon == Definitions.wp_fist
			and player.weaponowned[Definitions.wp_chainsaw]
			and not (player.readyweapon == Definitions.wp_chainsaw and GetPlayerPower(player, Definitions.pw_strength) ~= 0) then
			newweapon = Definitions.wp_chainsaw
		end

		if gamemode == Definitions.commercial
			and newweapon == Definitions.wp_shotgun
			and player.weaponowned[Definitions.wp_supershotgun]
			and player.readyweapon ~= Definitions.wp_supershotgun then
			newweapon = Definitions.wp_supershotgun
		end

		if newweapon >= 0
			and newweapon < Definitions.NUMWEAPONS
			and player.weaponowned[newweapon]
			and newweapon ~= player.readyweapon then
			if (newweapon ~= Definitions.wp_plasma and newweapon ~= Definitions.wp_bfg)
				or gamemode ~= Definitions.shareware then
				player.pendingweapon = newweapon
			end
		end
	end

	if bit32.btest(cmd.buttons, USE) then
		if not player.usedown then
			Runtime.useLines(player)

			player.usedown = true
		end
	else
		player.usedown = false
	end

	Psprites.MovePsprites(player)

	if GetPlayerPower(player, Definitions.pw_strength) ~= 0 then
		player.powers[Definitions.pw_strength] += 1
	end

	if GetPlayerPower(player, Definitions.pw_invulnerability) ~= 0 then
		player.powers[Definitions.pw_invulnerability] -= 1
	end

	if GetPlayerPower(player, Definitions.pw_invisibility) ~= 0 then
		player.powers[Definitions.pw_invisibility] -= 1

		if player.powers[Definitions.pw_invisibility] == 0 then
			player.mo.flags = bit32.band(player.mo.flags, bit32.bnot(Info.SHADOW))
		end
	end

	if GetPlayerPower(player, Definitions.pw_infrared) ~= 0 then
		player.powers[Definitions.pw_infrared] -= 1
	end

	if GetPlayerPower(player, Definitions.pw_ironfeet) ~= 0 then
		player.powers[Definitions.pw_ironfeet] -= 1
	end

	if player.damagecount ~= 0 then
		player.damagecount -= 1
	end

	if player.bonuscount ~= 0 then
		player.bonuscount -= 1
	end

	if GetPlayerPower(player, Definitions.pw_invulnerability) ~= 0 then
		if player.powers[Definitions.pw_invulnerability] > 4 * 32
			or bit32.btest(player.powers[Definitions.pw_invulnerability] :: number, 8) then
			player.fixedcolormap = INVERSECOLORMAP
		else
			player.fixedcolormap = 0
		end
	elseif GetPlayerPower(player, Definitions.pw_infrared) ~= 0 then
		if player.powers[Definitions.pw_infrared] > 4 * 32
			or bit32.btest(player.powers[Definitions.pw_infrared] :: number, 8) then
			player.fixedcolormap = 1
		else
			player.fixedcolormap = 0
		end
	else
		player.fixedcolormap = 0
	end
end

const function Reset()
	gamemode = Definitions.indetermined
	onground = false
end

const function SetGameMode(value: number)
	gamemode = value
end

const function GetGameMode(): number
	return gamemode
end

const function GetOnGround(): boolean
	return onground
end

Reset()

return {
	INVERSECOLORMAP = INVERSECOLORMAP,
	MAXBOB = MAXBOB,
	ATTACK = ATTACK,
	USE = USE,
	CHANGE = CHANGE,
	WEAPONMASK = WEAPONMASK,
	WEAPONSHIFT = WEAPONSHIFT,
	SPECIAL = SPECIAL,
	PST_LIVE = PST_LIVE,
	PST_DEAD = PST_DEAD,
	PST_REBORN = PST_REBORN,
	NOCLIP = NOCLIP,
	NOMOMENTUM = NOMOMENTUM,

	Reset = Reset,
	SetGameMode = SetGameMode,
	GetGameMode = GetGameMode,
	GetOnGround = GetOnGround,

	Thrust = Thrust :: (Player, number, number) -> (),
	CalcHeight = CalcHeight :: (Player) -> (),
	MovePlayer = MovePlayer :: (Player) -> (),
	DeathThink = DeathThink :: (Player) -> (),
	PlayerThink = PlayerThink :: (Player) -> (),
}
