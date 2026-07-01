--!native
--!optimize 2

-- Port of p_pspr.c plus the weapon-state helpers declared in info.c/p_enemy.c.
-- This file owns the player weapon psprite state machine and weapon actions.
-- Runtime-owned helpers such as sound, monster wakeup, and missile spawning
-- come from Play/Runtime.

const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const Geometry = require("../Renderer/Geometry")
const Info = require("../Doom/Info")
const Map = require("./Map")
const Random = require("../Miscellaneous/Random")
const Runtime = require("./Runtime")
const Tables = require("../Engine/Tables")

const FRACUNIT = 65536
const FINEANGLES = 8192
const FINEMASK = 8191
const ANG90 = 0x40000000
const ANG180 = 0x80000000
const UINT32_MASK = 0xFFFFFFFF
const finecosine = Tables.finecosine
const finesine = Tables.finesine
const ToSigned32 = Fixed.ToSigned32
const FixedMul = Fixed.FixedMul
const RandomValue = Random.PlayRandom

const FULLBRIGHT = 0x8000
const FRAMEMASK = 0x7FFF

const LOWERSPEED = 6 * FRACUNIT
const RAISESPEED = 6 * FRACUNIT
const WEAPONBOTTOM = 128 * FRACUNIT
const WEAPONTOP = 32 * FRACUNIT
const BFGCELLS = 40
const MELEERANGE = 64 * FRACUNIT
const MISSILERANGE = 32 * 64 * FRACUNIT

const PST_DEAD = 1
const ATTACK = 1

const sfx_pistol = 1
const sfx_shotgn = 2
const sfx_dshtgn = 4
const sfx_dbopn = 5
const sfx_dbcls = 6
const sfx_dbload = 7
const sfx_bfg = 9
const sfx_sawup = 10
const sfx_sawidl = 11
const sfx_sawful = 12
const sfx_sawhit = 13
const sfx_punch = 83

const ps_weapon = 0
const ps_flash = 1
const NUMPSPRITES = 2

type StateAction = (...unknown) -> ()
type StateInfo = {
	tics: number,
	action: false | StateAction,
	nextstate: number,
	misc1: number,
	misc2: number,
}
type PlayerSpriteState = {
	state: false | StateInfo,
	tics: number,
	sx: number,
	sy: number,
}
type MobjState = {
	x: number,
	y: number,
	z: number,
	angle: number,
	flags: number,
	height: number,
	state: StateInfo?,
	target: MobjState?,
}
type PlayerCommand = {
	buttons: number,
}
type PlayerState = {
	ammo: { [number]: number },
	attackdown: boolean,
	bob: number,
	cmd: PlayerCommand,
	extralight: number,
	health: number,
	mo: MobjState,
	pendingweapon: number,
	playerstate: number,
	powers: { [number]: number },
	psprites: { [number]: PlayerSpriteState },
	readyweapon: number,
	refire: number,
	weaponowned: { [number]: boolean },
}
type WeaponInfo = {
	ammo: number,
	upstate: number,
	downstate: number,
	atkstate: number,
	readystate: number,
	flashstate: number,
}
type StateActionMap = { [string]: StateAction }

local gamemode = Definitions.indetermined
local bulletslope = 0
local swingx = 0
local swingy = 0
const stateIndices: { [StateInfo]: number } = {}
local stateIndicesBuilt = false
local weaponinfo: false | { [number]: WeaponInfo } = false

const function Reset()
	gamemode = Definitions.indetermined
	bulletslope = 0
	swingx = 0
	swingy = 0
	table.clear(stateIndices)
	stateIndicesBuilt = false
	weaponinfo = false
end

const function GetState(index: number, context: string): StateInfo
	return Info.states[index] :: StateInfo
end

const function GetWeaponDefinition(index: number, context: string): WeaponInfo
	return (weaponinfo :: { [number]: WeaponInfo })[index]
end

const function GetPlayerPower(player: PlayerState, index: number): number
	return player.powers[index] or 0
end

const function StartSound(origin: unknown, sound: number)
	if Runtime.startSound ~= nil then
		Runtime.startSound(origin, sound)
	end
end

const function NoiseAlert(target: unknown, emitter: unknown)
	Runtime.noiseAlert(target, emitter)
end

const function GetPSprite(player: PlayerState, position: number): PlayerSpriteState
	local psp = player.psprites[position]

	if typeof(psp) ~= "table" then
		psp = {
			state = false,
			tics = 0,
			sx = 0,
			sy = 0,
		}
		player.psprites[position] = psp
	end

	return psp
end

const function BuildStateIndices()
	table.clear(stateIndices)

	for index, state in Info.states do
		if state then
			stateIndices[state] = index
		end
	end

	stateIndicesBuilt = true
end

const function GetStateIndex(state: StateInfo, context: string): number
	if not stateIndicesBuilt then
		BuildStateIndices()
	end

	return stateIndices[state]
end

-- SetPsprite
const function SetPsprite(player: PlayerState, position: number, stnum: number)
	const psp = GetPSprite(player, position)

	repeat
		if stnum == Info.NULL then
			psp.state = false
			psp.tics = 0
			break
		end

		const state = GetState(stnum, "SetPsprite")
		psp.state = state
		psp.tics = state.tics

		if state.misc1 ~= 0 then
			psp.sx = state.misc1 * FRACUNIT
			psp.sy = state.misc2 * FRACUNIT
		end

		if typeof(state.action) == "function" then
			state.action(player, psp)

			if not psp.state then
				break
			end
		end

		const nextstate = psp.state


		stnum = nextstate.nextstate
	until psp.tics ~= 0
end

-- CalculateSwing
const function CalculateSwing(player: PlayerState)
	const swing = player.bob
	local angle = bit32.band((FINEANGLES // 70) * Runtime.getLevelTime(), FINEMASK)

	swingx = FixedMul(swing, finesine[angle])
	angle = bit32.band((FINEANGLES // 70) * Runtime.getLevelTime() + FINEANGLES // 2, FINEMASK)
	swingy = -FixedMul(swingx, finesine[angle])
end

-- BringUpWeapon
const function BringUpWeapon(player: PlayerState)
	if player.pendingweapon == Definitions.wp_nochange then
		player.pendingweapon = player.readyweapon
	end

	if player.pendingweapon == Definitions.wp_chainsaw then
		StartSound(player.mo, sfx_sawup)
	end

	const info = GetWeaponDefinition(player.pendingweapon, "BringUpWeapon")
	player.pendingweapon = Definitions.wp_nochange
	GetPSprite(player, ps_weapon).sy = WEAPONBOTTOM
	SetPsprite(player, ps_weapon, info.upstate)
end

-- CheckAmmo
const function CheckAmmo(player: PlayerState): boolean
	const ammo = GetWeaponDefinition(player.readyweapon, "CheckAmmo").ammo
	local count

	if player.readyweapon == Definitions.wp_bfg then
		count = BFGCELLS
	elseif player.readyweapon == Definitions.wp_supershotgun then
		count = 2
	else
		count = 1
	end

	if ammo == Definitions.am_noammo or player.ammo[ammo] >= count then
		return true
	end

	repeat
		if player.weaponowned[Definitions.wp_plasma]
			and player.ammo[Definitions.am_cell] ~= 0
			and gamemode ~= Definitions.shareware then
			player.pendingweapon = Definitions.wp_plasma
		elseif player.weaponowned[Definitions.wp_supershotgun]
			and player.ammo[Definitions.am_shell] > 2
			and gamemode == Definitions.commercial then
			player.pendingweapon = Definitions.wp_supershotgun
		elseif player.weaponowned[Definitions.wp_chaingun]
			and player.ammo[Definitions.am_clip] ~= 0 then
			player.pendingweapon = Definitions.wp_chaingun
		elseif player.weaponowned[Definitions.wp_shotgun]
			and player.ammo[Definitions.am_shell] ~= 0 then
			player.pendingweapon = Definitions.wp_shotgun
		elseif player.ammo[Definitions.am_clip] ~= 0 then
			player.pendingweapon = Definitions.wp_pistol
		elseif player.weaponowned[Definitions.wp_chainsaw] then
			player.pendingweapon = Definitions.wp_chainsaw
		elseif player.weaponowned[Definitions.wp_missile]
			and player.ammo[Definitions.am_misl] ~= 0 then
			player.pendingweapon = Definitions.wp_missile
		elseif player.weaponowned[Definitions.wp_bfg]
			and player.ammo[Definitions.am_cell] > 40
			and gamemode ~= Definitions.shareware then
			player.pendingweapon = Definitions.wp_bfg
		else
			player.pendingweapon = Definitions.wp_fist
		end
	until player.pendingweapon ~= Definitions.wp_nochange

	SetPsprite(player, ps_weapon, GetWeaponDefinition(player.readyweapon, "CheckAmmo").downstate)
	return false
end

-- FireWeapon
const function FireWeapon(player: PlayerState)
	if not CheckAmmo(player) then
		return
	end

	Runtime.setMobjState(player.mo, Info.PLAY_ATK1)
	SetPsprite(player, ps_weapon, GetWeaponDefinition(player.readyweapon, "FireWeapon").atkstate)
	NoiseAlert(player.mo, player.mo)
end

-- DropWeapon
const function DropWeapon(player: PlayerState)
	SetPsprite(player, ps_weapon, GetWeaponDefinition(player.readyweapon, "DropWeapon").downstate)
end

-- WeaponReadyAction
const function WeaponReadyAction(player: PlayerState, psp: PlayerSpriteState)
	if player.mo.state == Info.states[Info.PLAY_ATK1] or player.mo.state == Info.states[Info.PLAY_ATK2] then
		Runtime.setMobjState(player.mo, Info.PLAY)
	end

	if player.readyweapon == Definitions.wp_chainsaw and psp.state == Info.states[Info.SAW] then
		StartSound(player.mo, sfx_sawidl)
	end

	if player.pendingweapon ~= Definitions.wp_nochange or player.health == 0 then
		SetPsprite(player, ps_weapon, GetWeaponDefinition(player.readyweapon, "WeaponReadyAction").downstate)
		return
	end

	if bit32.btest(player.cmd.buttons, ATTACK) then
		if not player.attackdown
			or (player.readyweapon ~= Definitions.wp_missile and player.readyweapon ~= Definitions.wp_bfg) then
			player.attackdown = true
			FireWeapon(player)
			return
		end
	else
		player.attackdown = false
	end

	local angle = bit32.band(128 * Runtime.getLevelTime(), FINEMASK)
	psp.sx = FRACUNIT + FixedMul(player.bob, finecosine[angle])
	angle = bit32.band(angle, FINEANGLES // 2 - 1)
	psp.sy = WEAPONTOP + FixedMul(player.bob, finesine[angle])
end

-- RefireAction
const function RefireAction(player: PlayerState, _psp: PlayerSpriteState)
	if bit32.btest(player.cmd.buttons, ATTACK)
		and player.pendingweapon == Definitions.wp_nochange
		and player.health ~= 0 then
		player.refire += 1
		FireWeapon(player)
	else
		player.refire = 0
		CheckAmmo(player)
	end
end

const function CheckReloadAction(player: PlayerState, _psp: PlayerSpriteState)
	CheckAmmo(player)
end

const function OpenShotgun2Action(player: PlayerState, _psp: PlayerSpriteState)
	StartSound(player.mo, sfx_dbopn)
end

const function LoadShotgun2Action(player: PlayerState, _psp: PlayerSpriteState)
	StartSound(player.mo, sfx_dbload)
end

const function CloseShotgun2Action(player: PlayerState, psp: PlayerSpriteState)
	StartSound(player.mo, sfx_dbcls)
	RefireAction(player, psp)
end

-- LowerAction
const function LowerAction(player: PlayerState, psp: PlayerSpriteState)
	psp.sy += LOWERSPEED

	if psp.sy < WEAPONBOTTOM then
		return
	end

	if player.playerstate == PST_DEAD then
		psp.sy = WEAPONBOTTOM
		return
	end

	if player.health == 0 then
		SetPsprite(player, ps_weapon, Info.NULL)
		return
	end

	player.readyweapon = player.pendingweapon
	BringUpWeapon(player)
end

-- RaiseAction
const function RaiseAction(player: PlayerState, psp: PlayerSpriteState)
	psp.sy -= RAISESPEED

	if psp.sy > WEAPONTOP then
		return
	end

	psp.sy = WEAPONTOP
	SetPsprite(player, ps_weapon, GetWeaponDefinition(player.readyweapon, "RaiseAction").readystate)
end

-- GunFlashAction
const function GunFlashAction(player: PlayerState, _psp: PlayerSpriteState)
	Runtime.setMobjState(player.mo, Info.PLAY_ATK2)
	SetPsprite(player, ps_flash, GetWeaponDefinition(player.readyweapon, "GunFlashAction").flashstate)
end

-- PunchAction
const function PunchAction(player: PlayerState, _psp: PlayerSpriteState)
	local damage = (RandomValue() % 10 + 1) * 2

	if GetPlayerPower(player, Definitions.pw_strength) ~= 0 then
		damage *= 10
	end

	const angle = bit32.band(player.mo.angle + (RandomValue() - RandomValue()) * 262144, UINT32_MASK)
	const slope = Map.AimLineAttack(player.mo, angle, MELEERANGE)

	Map.LineAttack(player.mo, angle, MELEERANGE, slope, damage)

	const target = Map.GetLineTarget()

	if target then
		StartSound(player.mo, sfx_punch)
		player.mo.angle = Geometry.PointToAngle2(player.mo.x, player.mo.y, target.x, target.y)
	end
end

-- SawAction
const function SawAction(player: PlayerState, _psp: PlayerSpriteState)
	const damage = 2 * (RandomValue() % 10 + 1)
	local angle = bit32.band(player.mo.angle + (RandomValue() - RandomValue()) * 262144, UINT32_MASK)
	const slope = Map.AimLineAttack(player.mo, angle, MELEERANGE + 1)

	Map.LineAttack(player.mo, angle, MELEERANGE + 1, slope, damage)

	const target = Map.GetLineTarget()

	if not target then
		StartSound(player.mo, sfx_sawful)
		return
	end

	StartSound(player.mo, sfx_sawhit)

	angle = Geometry.PointToAngle2(player.mo.x, player.mo.y, target.x, target.y)
	const delta = bit32.band(angle - player.mo.angle, UINT32_MASK)

	if delta > ANG180 then
		if delta < bit32.band(-(ANG90 // 20), UINT32_MASK) then
			player.mo.angle = bit32.band(angle + ANG90 // 21, UINT32_MASK)
		else
			player.mo.angle = bit32.band(player.mo.angle - ANG90 // 20, UINT32_MASK)
		end
	else
		if delta > ANG90 // 20 then
			player.mo.angle = bit32.band(angle - ANG90 // 21, UINT32_MASK)
		else
			player.mo.angle = bit32.band(player.mo.angle + ANG90 // 20, UINT32_MASK)
		end
	end

	player.mo.flags = bit32.bor(player.mo.flags, Info.JUSTATTACKED)
end

const function FireMissileAction(player: PlayerState, _psp: PlayerSpriteState)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FireMissileAction").ammo] -= 1
	Runtime.spawnPlayerMissile(player.mo, Info.RocketMobj)
end

const function FireBFGAction(player: PlayerState, _psp: PlayerSpriteState)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FireBFGAction").ammo] -= BFGCELLS
	Runtime.spawnPlayerMissile(player.mo, Info.BfgMobj)
end

const function FirePlasmaAction(player: PlayerState, _psp: PlayerSpriteState)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FirePlasmaAction").ammo] -= 1
	SetPsprite(
		player,
		ps_flash,
		GetWeaponDefinition(player.readyweapon, "FirePlasmaAction").flashstate + bit32.band(RandomValue(), 1)
	)
	Runtime.spawnPlayerMissile(player.mo, Info.PlasmaMobj)
end

-- CalculateBulletSlope
const function CalculateBulletSlope(mo: MobjState)
	local an = mo.angle
	bulletslope = Map.AimLineAttack(mo, an, 16 * 64 * FRACUNIT)

	if not Map.GetLineTarget() then
		an = bit32.band(an + 67108864, UINT32_MASK)
		bulletslope = Map.AimLineAttack(mo, an, 16 * 64 * FRACUNIT)

		if not Map.GetLineTarget() then
			an = bit32.band(an - 134217728, UINT32_MASK)
			bulletslope = Map.AimLineAttack(mo, an, 16 * 64 * FRACUNIT)
		end
	end
end

-- FireGunShot
const function FireGunShot(mo: MobjState, accurate: boolean)
	const damage = 5 * (RandomValue() % 3 + 1)
	local angle = mo.angle

	if not accurate then
		angle = bit32.band(angle + (RandomValue() - RandomValue()) * 262144, UINT32_MASK)
	end

	Map.LineAttack(mo, angle, MISSILERANGE, bulletslope, damage)
end

const function FirePistolAction(player: PlayerState, _psp: PlayerSpriteState)
	StartSound(player.mo, sfx_pistol)
	Runtime.setMobjState(player.mo, Info.PLAY_ATK2)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FirePistolAction").ammo] -= 1
	SetPsprite(player, ps_flash, GetWeaponDefinition(player.readyweapon, "FirePistolAction").flashstate)
	CalculateBulletSlope(player.mo)
	FireGunShot(player.mo, player.refire == 0)
end

const function FireShotgunAction(player: PlayerState, _psp: PlayerSpriteState)
	StartSound(player.mo, sfx_shotgn)
	Runtime.setMobjState(player.mo, Info.PLAY_ATK2)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FireShotgunAction").ammo] -= 1
	SetPsprite(player, ps_flash, GetWeaponDefinition(player.readyweapon, "FireShotgunAction").flashstate)
	CalculateBulletSlope(player.mo)

	for _ = 0, 6 do
		FireGunShot(player.mo, false)
	end
end

const function FireShotgun2Action(player: PlayerState, _psp: PlayerSpriteState)
	StartSound(player.mo, sfx_dshtgn)
	Runtime.setMobjState(player.mo, Info.PLAY_ATK2)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FireShotgun2Action").ammo] -= 2
	SetPsprite(player, ps_flash, GetWeaponDefinition(player.readyweapon, "FireShotgun2Action").flashstate)
	CalculateBulletSlope(player.mo)

	for _ = 0, 19 do
		const damage = 5 * (RandomValue() % 3 + 1)
		const angle = bit32.band(player.mo.angle + ToSigned32((RandomValue() - RandomValue()) * 524288), UINT32_MASK)
		const slope = bulletslope + ToSigned32((RandomValue() - RandomValue()) * 32)

		Map.LineAttack(player.mo, angle, MISSILERANGE, slope, damage)
	end
end

const function FireCGunAction(player: PlayerState, psp: PlayerSpriteState)
	StartSound(player.mo, sfx_pistol)

	if player.ammo[GetWeaponDefinition(player.readyweapon, "FireCGunAction").ammo] == 0 then
		return
	end

	Runtime.setMobjState(player.mo, Info.PLAY_ATK2)
	player.ammo[GetWeaponDefinition(player.readyweapon, "FireCGunAction").ammo] -= 1

	SetPsprite(
		player,
		ps_flash,
		GetWeaponDefinition(player.readyweapon, "FireCGunAction").flashstate + GetStateIndex(psp.state, "FireCGunAction") - Info.CHAIN1
	)

	CalculateBulletSlope(player.mo)
	FireGunShot(player.mo, player.refire == 0)
end

const function Light0Action(player: PlayerState, _psp: PlayerSpriteState)
	player.extralight = 0
end

const function Light1Action(player: PlayerState, _psp: PlayerSpriteState)
	player.extralight = 1
end

const function Light2Action(player: PlayerState, _psp: PlayerSpriteState)
	player.extralight = 2
end

const function BFGSprayAction(mo: MobjState)
	if not mo.target then
		return
	end

	for index = 0, 39 do
		const an = bit32.band(mo.angle - ANG90 // 2 + (ANG90 // 40) * index, UINT32_MASK)
		Map.AimLineAttack(mo.target, an, 16 * 64 * FRACUNIT)

		const target = Map.GetLineTarget()

		if not target then
			continue
		end

		Runtime.spawnMobj(target.x, target.y, target.z + target.height // 4, Info.EXTRABFG)

		local damage = 0

		for _ = 0, 14 do
			damage += bit32.band(RandomValue(), 7) + 1
		end

		Runtime.damageMobj(target, mo.target, mo.target, damage)
	end
end

const function BFGSoundAction(player: PlayerState, _psp: PlayerSpriteState)
	StartSound(player.mo, sfx_bfg)
end

-- SetupPsprites
const function SetupPsprites(player: PlayerState)
	for index = 0, NUMPSPRITES - 1 do
		const psp = GetPSprite(player, index)
		psp.state = false
		psp.tics = 0
	end

	player.pendingweapon = player.readyweapon
	BringUpWeapon(player)
end

-- MovePsprites
const function MovePsprites(player: PlayerState)
	for index = 0, NUMPSPRITES - 1 do
		const psp = GetPSprite(player, index)
		const state = psp.state

		if state and psp.tics ~= -1 then
			psp.tics -= 1

			if psp.tics == 0 then
				SetPsprite(player, index, state.nextstate)
			end
		end
	end

	const flash = GetPSprite(player, ps_flash)
	const weapon = GetPSprite(player, ps_weapon)
	flash.sx = weapon.sx
	flash.sy = weapon.sy
end

const function GetStateActions(): StateActionMap
	return {
		WeaponReadyAction = WeaponReadyAction,
		LowerAction = LowerAction,
		RaiseAction = RaiseAction,
		PunchAction = PunchAction,
		RefireAction = RefireAction,
		CheckReloadAction = CheckReloadAction,
		OpenShotgun2Action = OpenShotgun2Action,
		LoadShotgun2Action = LoadShotgun2Action,
		CloseShotgun2Action = CloseShotgun2Action,
		FirePistolAction = FirePistolAction,
		FireShotgunAction = FireShotgunAction,
		FireShotgun2Action = FireShotgun2Action,
		FireCGunAction = FireCGunAction,
		GunFlashAction = GunFlashAction,
		FireMissileAction = FireMissileAction,
		SawAction = SawAction,
		FirePlasmaAction = FirePlasmaAction,
		BFGSoundAction = BFGSoundAction,
		FireBFGAction = FireBFGAction,
		Light0Action = Light0Action,
		Light1Action = Light1Action,
		Light2Action = Light2Action,
		BFGSprayAction = BFGSprayAction,
	}
end

const function ResolveStateActions(extraActions: StateActionMap?)
	const actions: StateActionMap = {}

	if extraActions ~= nil then
		for name, action in extraActions do
			actions[name] = action
		end
	end

	BuildStateIndices()

	for name, action in GetStateActions() do
		actions[name] = action
	end

	Info.ResolveStateActions(actions)
end

const function SetWeaponInfo(value: { [number]: WeaponInfo })
	weaponinfo = value
end

const function SetGameMode(value: number)
	gamemode = value
end

const function GetGameMode(): number
	return gamemode
end

const function GetBulletSlope(): number
	return bulletslope
end

const function GetSwingX(): number
	return swingx
end

const function GetSwingY(): number
	return swingy
end

const function GetWeaponInfo(): false | { [number]: WeaponInfo }
	return weaponinfo
end

Reset()

const Psprites = {
	FULLBRIGHT = FULLBRIGHT,
	FRAMEMASK = FRAMEMASK,
	LOWERSPEED = LOWERSPEED,
	RAISESPEED = RAISESPEED,
	WEAPONBOTTOM = WEAPONBOTTOM,
	WEAPONTOP = WEAPONTOP,
	BFGCELLS = BFGCELLS,
	MELEERANGE = MELEERANGE,
	MISSILERANGE = MISSILERANGE,
	ps_weapon = ps_weapon,
	ps_flash = ps_flash,
	NUMPSPRITES = NUMPSPRITES,

	Reset = Reset,
	SetWeaponInfo = SetWeaponInfo,
	SetGameMode = SetGameMode,
	GetGameMode = GetGameMode,
	GetBulletSlope = GetBulletSlope,
	GetSwingX = GetSwingX,
	GetSwingY = GetSwingY,
	GetWeaponInfo = GetWeaponInfo,
	GetStateActions = GetStateActions,
	ResolveStateActions = ResolveStateActions,

	WeaponReadyAction = WeaponReadyAction,
	RefireAction = RefireAction,
	CheckReloadAction = CheckReloadAction,
	OpenShotgun2Action = OpenShotgun2Action,
	LoadShotgun2Action = LoadShotgun2Action,
	CloseShotgun2Action = CloseShotgun2Action,
	LowerAction = LowerAction,
	RaiseAction = RaiseAction,
	GunFlashAction = GunFlashAction,
	PunchAction = PunchAction,
	SawAction = SawAction,
	FireMissileAction = FireMissileAction,
	FireBFGAction = FireBFGAction,
	FirePlasmaAction = FirePlasmaAction,
	FirePistolAction = FirePistolAction,
	FireShotgunAction = FireShotgunAction,
	FireShotgun2Action = FireShotgun2Action,
	FireCGunAction = FireCGunAction,
	Light0Action = Light0Action,
	Light1Action = Light1Action,
	Light2Action = Light2Action,
	BFGSprayAction = BFGSprayAction,
	BFGSoundAction = BFGSoundAction,
}

Psprites.SetPsprite = SetPsprite
Psprites.CalculateSwing = CalculateSwing
Psprites.BringUpWeapon = BringUpWeapon
Psprites.CheckAmmo = CheckAmmo
Psprites.FireWeapon = FireWeapon
Psprites.SetupPsprites = SetupPsprites
Psprites.MovePsprites = MovePsprites
Psprites.DropWeapon = DropWeapon
Psprites.CalculateBulletSlope = CalculateBulletSlope
Psprites.FireGunShot = FireGunShot

return Psprites
