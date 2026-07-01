--!native
--!optimize 2

-- Port of p_mobj.c
-- Map object state changes, spawning, movement, thinker ownership, and map
-- thing spawning.
-- Note: sound ids and state action pointers are resolved through
-- `Doom/Info.luau` and setup-time owner wiring.

const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const Info = require("../Doom/Info")
const Map = require("./Map")
const MapUtil = require("./MapUtil")
const Random = require("../Miscellaneous/Random")
const Geometry = require("../Renderer/Geometry")
const Runtime = require("./Runtime")
const Sky = require("../Renderer/Sky")
const Tables = require("../Engine/Tables")

const ONFLOORZ = -2147483648
const ONCEILINGZ = 2147483647
const ITEMQUESIZE = 128
const FRACUNIT = 65536
const ANG90 = 0x40000000
const ANGLETOFINESHIFT = 19
const VIEWHEIGHT = 41 * FRACUNIT
const FLOATSPEED = 4 * FRACUNIT
const GRAVITY = FRACUNIT
const GRAVITY2 = 2 * GRAVITY
const GRAVITY8 = 8 * GRAVITY
const FRACUNIT_QUARTER = FRACUNIT // 4
const MAXMOVE = 30 * FRACUNIT
const STOPSPEED = 0x1000
const FRICTION = 0xE800
const MTF_AMBUSH = 8
const PST_LIVE = 0
const PST_REBORN = 2
const NOMOMENTUM = 4
const sfx_oof = 34
const sfx_telept = 35

type MapThing = {
	x: number,
	y: number,
	angle: number,
	type: number,
	options: number,
}

type ThinkerFunction = {
	acp1: (Mobj) -> (),
	acv: number?,
}

type Thinker = {
	owner: Mobj,
	prev: boolean,
	next: boolean,
	["function"]: ThinkerFunction,
}

type Sector = {
	floorheight: number,
	ceilingheight: number,
	ceilingpic: number?,
}

type Subsector = {
	sector: Sector,
}

type MobjInfo = {
	deathstate: number,
	deathsound: number?,
	spawnstate: number,
	radius: number,
	height: number,
	flags: number,
	spawnhealth: number,
	reactiontime: number,
	seesound: number?,
	speed: number,
	doomednum: number,
}

type State = {
	tics: number,
	sprite: number,
	frame: number,
	action: ((Mobj) -> ())?,
	nextstate: number,
}

type Command = {
	forwardmove: number,
	sidemove: number,
}

type Player = {
	playerstate: number,
	health: number,
	cheats: number?,
	cmd: Command?,
	mo: Mobj?,
	refire: number,
	message: unknown,
	damagecount: number,
	bonuscount: number,
	extralight: number,
	fixedcolormap: number,
	viewheight: number,
	deltaviewheight: number?,
}

type Mobj = {
	type: number,
	info: MobjInfo,
	x: number,
	y: number,
	z: number,
	angle: number,
	momx: number,
	momy: number,
	momz: number,
	validcount: number,
	radius: number,
	height: number,
	flags: number,
	health: number,
	reactiontime: number,
	lastlook: number,
	state: State | false,
	tics: number,
	sprite: number,
	frame: number,
	floorz: number,
	ceilingz: number,
	movedir: number,
	movecount: number,
	threshold: number,
	target: Mobj | false,
	tracer: Mobj | false,
	player: Player | false,
	subsector: Subsector | false,
	snext: Mobj | false,
	sprev: Mobj | false,
	bnext: Mobj | false,
	bprev: Mobj | false,
	spawnpoint: MapThing,
	thinker: Thinker,
}

local gameskill = Definitions.sk_medium
local respawnmonsters = false
local nomonsters = false
const itemrespawnque: { [number]: MapThing } = {}
const itemrespawntime: { [number]: number } = {}
local iquehead = 0
local iquetail = 0
local players: { [number]: Player } = {}
local playerstarts: { [number]: MapThing | boolean } = {}

const MELEERANGE = 64 * FRACUNIT
const FixedMul = Fixed.FixedMul
const ToSigned32 = Fixed.ToSigned32
const states = Info.states
const mobjinfo = Info.mobjinfo
const RandomNumber = Random.PlayRandom
const finecosine = Tables.finecosine
const finesine = Tables.finesine
const ThinkerCallbacks = {
	MobjThinker = false :: false | ((Mobj) -> ()),
}

const function SignedRightShift(value: number, shift: number): number
	return ToSigned32(bit32.arshift(value, shift))
end

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function CopyMapThing(mthing: MapThing?)
	if not mthing then
		return false
	end

	return {
		x = mthing.x or 0,
		y = mthing.y or 0,
		angle = mthing.angle or 0,
		type = mthing.type or 0,
		options = mthing.options or 0,
	}
end

const function NewEmptyMapThing()
	return {
		x = 0,
		y = 0,
		angle = 0,
		type = 0,
		options = 0,
	}
end

const function NewThinker(owner: Mobj, thinkerFunction: (Mobj) -> ())
	return {
		owner = owner,
		prev = false,
		next = false,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function Reset()
	table.clear(itemrespawnque)
	table.clear(itemrespawntime)
	iquehead = 0
	iquetail = 0
	gameskill = Definitions.sk_medium
	respawnmonsters = false
	nomonsters = false
end

const function ClearItemRespawnQueue()
	table.clear(itemrespawnque)
	table.clear(itemrespawntime)
	iquehead = 0
	iquetail = 0
end

-- RemoveMobj
const function RemoveMobj(mobj: Mobj)
	if bit32.btest(mobj.flags, Info.SPECIAL)
		and bit32.band(mobj.flags, Info.DROPPED) == 0
		and mobj.type ~= Info.INV
		and mobj.type ~= Info.INS then
		itemrespawnque[iquehead] = mobj.spawnpoint
		itemrespawntime[iquehead] = GetLevelTime()
		iquehead = bit32.band(iquehead + 1, ITEMQUESIZE - 1)

		if iquehead == iquetail then
			iquetail = bit32.band(iquetail + 1, ITEMQUESIZE - 1)
		end
	end

	MapUtil.UnsetThingPosition(mobj)

	Runtime.stopSound(mobj)
	Runtime.removeThinker(mobj.thinker)
end

-- SetMobjState
-- Returns true if the mobj is still present.
const function SetMobjState(mobj: Mobj, state: number): boolean
	while true do
		if state == Info.NULL then
			mobj.state = false
			RemoveMobj(mobj)
			return false
		end

		const st = states[state]
		mobj.state = st
		mobj.tics = st.tics
		mobj.sprite = st.sprite
		mobj.frame = st.frame

		const action = st.action

		if action then
			action(mobj)
		end

		if mobj.tics ~= 0 then
			return true
		end

		state = st.nextstate
	end
end

-- ExplodeMissile
const function ExplodeMissile(mobj: Mobj)
	mobj.momx = 0
	mobj.momy = 0
	mobj.momz = 0

	SetMobjState(mobj, mobj.info.deathstate)

	mobj.tics -= bit32.band(RandomNumber(), 3)

	if mobj.tics < 1 then
		mobj.tics = 1
	end

	mobj.flags = bit32.band(mobj.flags, bit32.bnot(Info.MissileFlag))

	if mobj.info.deathsound then
		Runtime.startSound(mobj, mobj.info.deathsound)
	end
end

-- ApplyXYMovement
const function ApplyXYMovement(mo: Mobj)
	if mo.momx == 0 and mo.momy == 0 then
		if bit32.btest(mo.flags, Info.SKULLFLY) then
			mo.flags = bit32.band(mo.flags, bit32.bnot(Info.SKULLFLY))
			mo.momx = 0
			mo.momy = 0
			mo.momz = 0
			SetMobjState(mo, mo.info.spawnstate)
		end

		return
	end

	const player = mo.player

	if mo.momx > MAXMOVE then
		mo.momx = MAXMOVE
	elseif mo.momx < -MAXMOVE then
		mo.momx = -MAXMOVE
	end

	if mo.momy > MAXMOVE then
		mo.momy = MAXMOVE
	elseif mo.momy < -MAXMOVE then
		mo.momy = -MAXMOVE
	end

	local xmove = mo.momx
	local ymove = mo.momy

	repeat
		local ptryx
		local ptryy

		if xmove > MAXMOVE // 2 or ymove > MAXMOVE // 2 then
			ptryx = mo.x + math.modf(xmove / 2)
			ptryy = mo.y + math.modf(ymove / 2)
			xmove = SignedRightShift(xmove, 1)
			ymove = SignedRightShift(ymove, 1)
		else
			ptryx = mo.x + xmove
			ptryy = mo.y + ymove
			xmove = 0
			ymove = 0
		end

		if not Map.TryMove(mo, ptryx, ptryy) then
			if mo.player then
				Map.SlideMove(mo)
			elseif bit32.btest(mo.flags, Info.MissileFlag) then
				const line = Map.GetCeilingLine()

				if line
					and line.backsector
					and line.backsector.ceilingpic == Sky.GetSkyFlatNum() then
					RemoveMobj(mo)
					return
				end

				ExplodeMissile(mo)
			else
				mo.momx = 0
				mo.momy = 0
			end
		end
	until xmove == 0 and ymove == 0

	if player and bit32.btest(player.cheats or 0, NOMOMENTUM) then
		mo.momx = 0
		mo.momy = 0
		return
	end

	if bit32.btest(mo.flags, bit32.bor(Info.MissileFlag, Info.SKULLFLY)) then
		return
	end

	if mo.z > mo.floorz then
		return
	end

	if bit32.btest(mo.flags, Info.CORPSE) then
		if mo.momx > FRACUNIT_QUARTER
			or mo.momx < -FRACUNIT_QUARTER
			or mo.momy > FRACUNIT_QUARTER
			or mo.momy < -FRACUNIT_QUARTER then
			const sector = mo.subsector and mo.subsector.sector

			if sector and mo.floorz ~= sector.floorheight then
				return
			end
		end
	end

	const cmd = player and player.cmd

	if mo.momx > -STOPSPEED
		and mo.momx < STOPSPEED
		and mo.momy > -STOPSPEED
		and mo.momy < STOPSPEED
		and (
			not player
			or (cmd and cmd.forwardmove == 0 and cmd.sidemove == 0)
		) then
		if player and (mo.state == Info.states[Info.PLAY_RUN1]
			or mo.state == Info.states[Info.PLAY_RUN2]
			or mo.state == Info.states[Info.PLAY_RUN3]
			or mo.state == Info.states[Info.PLAY_RUN4]) then
			SetMobjState(mo, Info.PLAY)
		end

		mo.momx = 0
		mo.momy = 0
	else
		mo.momx = FixedMul(mo.momx, FRICTION)
		mo.momy = FixedMul(mo.momy, FRICTION)
	end
end

-- ApplyZMovement
const function ApplyZMovement(mo: Mobj)
	if mo.player and mo.z < mo.floorz then
		mo.player.viewheight -= mo.floorz - mo.z
		mo.player.deltaviewheight = SignedRightShift(VIEWHEIGHT - mo.player.viewheight, 3)
	end

	mo.z += mo.momz

	if bit32.btest(mo.flags, Info.FLOAT) and mo.target then
		if bit32.band(mo.flags, Info.SKULLFLY) == 0
			and bit32.band(mo.flags, Info.INFLOAT) == 0 then
			const dist = MapUtil.ApproximateDistance(mo.x - mo.target.x, mo.y - mo.target.y)
			const delta = (mo.target.z + SignedRightShift(mo.height, 1)) - mo.z

			if delta < 0 and dist < -(delta * 3) then
				mo.z -= FLOATSPEED
			elseif delta > 0 and dist < delta * 3 then
				mo.z += FLOATSPEED
			end
		end
	end

	if mo.z <= mo.floorz then
		if bit32.btest(mo.flags, Info.SKULLFLY) then
			mo.momz = -mo.momz
		end

		if mo.momz < 0 then
			if mo.player and mo.momz < -GRAVITY8 then
				mo.player.deltaviewheight = SignedRightShift(mo.momz, 3)
				Runtime.startSound(mo, sfx_oof)
			end

			mo.momz = 0
		end

		mo.z = mo.floorz

		if bit32.btest(mo.flags, Info.MissileFlag)
			and bit32.band(mo.flags, Info.NOCLIP) == 0 then
			ExplodeMissile(mo)
			return
		end
	elseif bit32.band(mo.flags, Info.NOGRAVITY) == 0 then
		if mo.momz == 0 then
			mo.momz = -GRAVITY2
		else
			mo.momz -= GRAVITY
		end
	end

	if mo.z + mo.height > mo.ceilingz then
		if mo.momz > 0 then
			mo.momz = 0
		end

		mo.z = mo.ceilingz - mo.height

		if bit32.btest(mo.flags, Info.SKULLFLY) then
			mo.momz = -mo.momz
		end

		if bit32.btest(mo.flags, Info.MissileFlag)
			and bit32.band(mo.flags, Info.NOCLIP) == 0 then
			ExplodeMissile(mo)
			return
		end
	end
end

-- SpawnMobj
const function SpawnMobj(x: number, y: number, z: number, type_: number)

	const info = mobjinfo[type_]
	const state = states[info.spawnstate]
	const mobj = {
		type = type_,
		info = info,
		x = x,
		y = y,
		z = 0,
		angle = 0,
		momx = 0,
		momy = 0,
		momz = 0,
		validcount = 0,
		radius = info.radius,
		height = info.height,
		flags = info.flags,
		health = info.spawnhealth,
		reactiontime = if gameskill ~= Definitions.sk_nightmare then info.reactiontime else 0,
		-- Chocolate Doom uses PlayRandom() here to preserve vanilla demo RNG.
		lastlook = bit32.band(RandomNumber(), Definitions.MAXPLAYERS - 1),
		state = state,
		tics = state.tics,
		sprite = state.sprite,
		frame = state.frame,
		floorz = 0,
		ceilingz = 0,
		movedir = 0,
		movecount = 0,
		threshold = 0,
		target = false,
		tracer = false,
		player = false,
		subsector = false,
		snext = false,
		sprev = false,
		bnext = false,
		bprev = false,
		spawnpoint = NewEmptyMapThing(),
	}

	mobj.thinker = NewThinker(mobj, ThinkerCallbacks.MobjThinker :: (Mobj) -> ())

	MapUtil.SetThingPosition(mobj)

	const subsector = mobj.subsector
	const sector = subsector and subsector.sector


	mobj.floorz = sector.floorheight
	mobj.ceilingz = sector.ceilingheight

	if z == ONFLOORZ then
		mobj.z = mobj.floorz
	elseif z == ONCEILINGZ then
		mobj.z = mobj.ceilingz - mobj.info.height
	else
		mobj.z = z
	end

	Runtime.addThinker(mobj.thinker)

	return mobj
end

-- NightmareRespawn
const function NightmareRespawn(mobj: Mobj)
	const x = mobj.spawnpoint.x * FRACUNIT
	const y = mobj.spawnpoint.y * FRACUNIT

	if not Map.CheckPosition(mobj, x, y) then
		return
	end

	local mo = SpawnMobj(mobj.x, mobj.y, mobj.subsector.sector.floorheight, Info.TfogMobj)
	Runtime.startSound(mo, sfx_telept)

	const ss = MapUtil.PointInSubsector(x, y)
	mo = SpawnMobj(x, y, ss.sector.floorheight, Info.TfogMobj)
	Runtime.startSound(mo, sfx_telept)

	const z = if bit32.btest(mobj.info.flags, Info.SPAWNCEILING) then ONCEILINGZ else ONFLOORZ
	mo = SpawnMobj(x, y, z, mobj.type)
	mo.spawnpoint = CopyMapThing(mobj.spawnpoint)
	mo.angle = (ANG90 // 2) * math.modf(mobj.spawnpoint.angle / 45)

	if bit32.btest(mobj.spawnpoint.options or 0, MTF_AMBUSH) then
		mo.flags = bit32.bor(mo.flags, Info.AMBUSH)
	end

	mo.reactiontime = 18
	RemoveMobj(mobj)
end

-- MobjThinker
const function MobjThinker(mobj: Mobj)
	if mobj.momx ~= 0 or mobj.momy ~= 0 or bit32.btest(mobj.flags, Info.SKULLFLY) then
		ApplyXYMovement(mobj)

		if mobj.thinker["function"].acv == -1 then
			return
		end
	end

	if mobj.z ~= mobj.floorz or mobj.momz ~= 0 then
		ApplyZMovement(mobj)

		if mobj.thinker["function"].acv == -1 then
			return
		end
	end

	if mobj.tics ~= -1 then
		mobj.tics -= 1

		if mobj.tics == 0 then
			const state = mobj.state


			if not SetMobjState(mobj, state.nextstate) then
				return
			end
		end
	else
		if bit32.band(mobj.flags, Info.COUNTKILL) == 0 then
			return
		end

		if not respawnmonsters then
			return
		end

		mobj.movecount += 1

		if mobj.movecount < 12 * 35 then
			return
		end

		if bit32.btest(GetLevelTime(), 31) then
			return
		end

		if RandomNumber() > 4 then
			return
		end

		NightmareRespawn(mobj)
	end
end

ThinkerCallbacks.MobjThinker = MobjThinker

-- SpawnPuff
const function SpawnPuff(x: number, y: number, z: number)
	z += ToSigned32((RandomNumber() - RandomNumber()) * 1024)
	
	const mobj = SpawnMobj(x, y, z, Info.PUFF)
	mobj.momz = FRACUNIT
	mobj.tics -= bit32.band(RandomNumber(), 3)

	if mobj.tics < 1 then
		mobj.tics = 1
	end

	if Map.GetAttackRange() == MELEERANGE then
		SetMobjState(mobj, Info.PUFF3)
	end

	return mobj
end

-- SpawnBlood
const function SpawnBlood(x: number, y: number, z: number, damage: number)
	z += ToSigned32((RandomNumber() - RandomNumber()) * 1024)

	const mobj = SpawnMobj(x, y, z, Info.BLOOD)
	mobj.momz = 2 * FRACUNIT
	mobj.tics -= bit32.band(RandomNumber(), 3)

	if mobj.tics < 1 then
		mobj.tics = 1
	end

	if damage <= 12 and damage >= 9 then
		SetMobjState(mobj, Info.BLOOD2)
	elseif damage < 9 then
		SetMobjState(mobj, Info.BLOOD3)
	end

	return mobj
end

-- CheckMissileSpawn
const function CheckMissileSpawn(mobj: Mobj)
	mobj.tics -= bit32.band(RandomNumber(), 3)

	if mobj.tics < 1 then
		mobj.tics = 1
	end

	mobj.x += SignedRightShift(mobj.momx, 1)
	mobj.y += SignedRightShift(mobj.momy, 1)
	mobj.z += SignedRightShift(mobj.momz, 1)

	if not Map.TryMove(mobj, mobj.x, mobj.y) then
		ExplodeMissile(mobj)
	end
end

-- SpawnMissile
const function SpawnMissile(source: Mobj, dest: Mobj, type_: number)
	const missile = SpawnMobj(source.x, source.y, source.z + 32 * FRACUNIT, type_)
	const missileInfo = missile.info

	if missileInfo.seesound then
		Runtime.startSound(missile, missileInfo.seesound)
	end

	missile.target = source

	local angle = Geometry.PointToAngle2(source.x, source.y, dest.x, dest.y)

	if bit32.btest(dest.flags, Info.SHADOW) then
		angle = bit32.band(angle + (RandomNumber() - RandomNumber()) * 1048576, 0xFFFFFFFF)
	end

	missile.angle = angle

	const fineAngle = bit32.rshift(bit32.band(angle, 0xFFFFFFFF), ANGLETOFINESHIFT)
	const missileSpeed = missileInfo.speed
	missile.momx = FixedMul(missileSpeed, finecosine[fineAngle])
	missile.momy = FixedMul(missileSpeed, finesine[fineAngle])

	local dist = MapUtil.ApproximateDistance(dest.x - source.x, dest.y - source.y)
	dist //= missileSpeed

	if dist < 1 then
		dist = 1
	end

	missile.momz = math.modf((dest.z - source.z) / dist)
	CheckMissileSpawn(missile)

	return missile
end

-- SpawnPlayerMissile
const function SpawnPlayerMissile(source: Mobj, type_: number)
	local angle = source.angle
	local slope = Map.AimLineAttack(source, angle, 16 * 64 * FRACUNIT)

	if not Map.GetLineTarget() then
		angle = bit32.band(angle + 67108864, 0xFFFFFFFF)
		slope = Map.AimLineAttack(source, angle, 16 * 64 * FRACUNIT)

		if not Map.GetLineTarget() then
			angle = bit32.band(angle - 134217728, 0xFFFFFFFF)
			slope = Map.AimLineAttack(source, angle, 16 * 64 * FRACUNIT)
		end

		if not Map.GetLineTarget() then
			angle = source.angle
			slope = 0
		end
	end

	const missile = SpawnMobj(source.x, source.y, source.z + 32 * FRACUNIT, type_)
	const missileInfo = missile.info

	if missileInfo.seesound then
		Runtime.startSound(missile, missileInfo.seesound)
	end

	missile.target = source
	missile.angle = angle

	const fineAngle = bit32.rshift(bit32.band(angle, 0xFFFFFFFF), ANGLETOFINESHIFT)
	const missileSpeed = missileInfo.speed
	missile.momx = FixedMul(missileSpeed, finecosine[fineAngle])
	missile.momy = FixedMul(missileSpeed, finesine[fineAngle])
	missile.momz = FixedMul(missileSpeed, slope)

	CheckMissileSpawn(missile)

	return missile
end

-- RespawnSpecials
const function RespawnSpecials()
	return
end

-- SpawnPlayer
-- Called when a player is spawned on the level.
const function SpawnPlayer(mthing: MapThing)
	if mthing.type ~= 1 then
		return
	end

	const player = players[0]

	if player.playerstate == PST_REBORN then
		Runtime.playerReborn(0)
	end

	const x = mthing.x * FRACUNIT
	const y = mthing.y * FRACUNIT
	const mobj = SpawnMobj(x, y, ONFLOORZ, Info.PLAYER)

	mobj.angle = (ANG90 // 2) * math.modf(mthing.angle / 45)
	mobj.player = player
	mobj.health = player.health

	player.mo = mobj
	player.playerstate = PST_LIVE
	player.refire = 0
	player.message = false
	player.damagecount = 0
	player.bonuscount = 0
	player.extralight = 0
	player.fixedcolormap = 0
	player.viewheight = VIEWHEIGHT

	Runtime.setupPsprites(player)
	Runtime.startStatus()
	Runtime.startHUD()
end

-- SpawnMapThing
-- The fields of the mapthing should already be in host byte order.
const function SpawnMapThing(mthing: MapThing)
	if mthing.type == 11 then
		return
	end

	if mthing.type <= 4 then
		if mthing.type ~= 1 then
			return
		end

		playerstarts[0] = CopyMapThing(mthing)
		SpawnPlayer(mthing)
		return
	end

	if bit32.btest(mthing.options or 0, 16) then
		return
	end

	local bit

	if gameskill == Definitions.sk_baby then
		bit = 1
	elseif gameskill == Definitions.sk_nightmare then
		bit = 4
	else
		bit = bit32.lshift(1, gameskill - 1)
	end

	if bit32.band(mthing.options or 0, bit) == 0 then
		return
	end

	local doomedType = -1

	for index = 0, Info.NUMMOBJTYPES - 1 do
		const info = mobjinfo[index]

		if info.doomednum == mthing.type then
			doomedType = index
			break
		end
	end


	const doomedInfo = mobjinfo[doomedType]

	if nomonsters and (doomedType == Info.SKULL or bit32.btest(doomedInfo.flags, Info.COUNTKILL)) then
		return
	end

	const x = mthing.x * FRACUNIT
	const y = mthing.y * FRACUNIT
	const z = if bit32.btest(doomedInfo.flags, Info.SPAWNCEILING) then ONCEILINGZ else ONFLOORZ
	const mobj = SpawnMobj(x, y, z, doomedType)

	mobj.spawnpoint = CopyMapThing(mthing)

	if mobj.tics > 0 then
		mobj.tics = 1 + (RandomNumber() % mobj.tics)
	end

	if bit32.btest(mobj.flags, Info.COUNTKILL) then
		Runtime.addTotalKills(1)
	end

	if bit32.btest(mobj.flags, Info.COUNTITEM) then
		Runtime.addTotalItems(1)
	end

	mobj.angle = (ANG90 // 2) * math.modf(mthing.angle / 45)

	if bit32.btest(mthing.options or 0, MTF_AMBUSH) then
		mobj.flags = bit32.bor(mobj.flags, Info.AMBUSH)
	end
end

const function SetGameSkill(value: number)
	gameskill = value
end

const function GetGameSkill(): number
	return gameskill
end

const function SetNoMonsters(value: boolean)
	nomonsters = value
end

const function GetNoMonsters(): boolean
	return nomonsters
end

const function SetRespawnMonsters(value: boolean)
	respawnmonsters = value
end

const function GetRespawnMonsters(): boolean
	return respawnmonsters
end

const function SetPlayers(value: { [number]: Player })
	players = value
end

const function GetPlayers(): { [number]: Player }
	return players
end

const function SetPlayerStarts(value: { [number]: MapThing | boolean })
	playerstarts = value
end

const function GetPlayerStarts(): { [number]: MapThing | boolean }
	return playerstarts
end

const function GetItemRespawnQueue(): { [number]: MapThing }
	return itemrespawnque
end

const function GetItemRespawnTime(): { [number]: number }
	return itemrespawntime
end

const function GetIQueHead(): number
	return iquehead
end

const function GetIQueTail(): number
	return iquetail
end

Reset()

const MobjModule = {
	ONFLOORZ = ONFLOORZ,
	ONCEILINGZ = ONCEILINGZ,
	ITEMQUESIZE = ITEMQUESIZE,

	Reset = Reset,
	ClearItemRespawnQueue = ClearItemRespawnQueue,
	SetGameSkill = SetGameSkill,
	GetGameSkill = GetGameSkill,
	SetNoMonsters = SetNoMonsters,
	GetNoMonsters = GetNoMonsters,
	SetRespawnMonsters = SetRespawnMonsters,
	GetRespawnMonsters = GetRespawnMonsters,
	SetPlayers = SetPlayers,
	GetPlayers = GetPlayers,
	SetPlayerStarts = SetPlayerStarts,
	GetPlayerStarts = GetPlayerStarts,
	GetItemRespawnQueue = GetItemRespawnQueue,
	GetItemRespawnTime = GetItemRespawnTime,
	GetIQueHead = GetIQueHead,
	GetIQueTail = GetIQueTail,
}

MobjModule.SetMobjState = SetMobjState
MobjModule.ExplodeMissile = ExplodeMissile
MobjModule.ApplyXYMovement = ApplyXYMovement
MobjModule.ApplyZMovement = ApplyZMovement
MobjModule.NightmareRespawn = NightmareRespawn
MobjModule.MobjThinker = MobjThinker
MobjModule.SpawnMobj = SpawnMobj
MobjModule.SpawnPlayer = SpawnPlayer
MobjModule.SpawnMapThing = SpawnMapThing
MobjModule.SpawnPuff = SpawnPuff
MobjModule.SpawnBlood = SpawnBlood
MobjModule.CheckMissileSpawn = CheckMissileSpawn
MobjModule.SpawnMissile = SpawnMissile
MobjModule.SpawnPlayerMissile = SpawnPlayerMissile
MobjModule.RemoveMobj = RemoveMobj
MobjModule.RespawnSpecials = RespawnSpecials

return MobjModule
