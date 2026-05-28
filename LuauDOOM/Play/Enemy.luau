--!native
--!optimize 2

-- Port of p_enemy.c.
-- Sound flooding, chase/AI helpers, and enemy action-pointer functions.

const Definitions = require("../Engine/Definitions")
const Doors = require("./Doors")
const Fixed = require("../Miscellaneous/Fixed")
const Floor = require("./Floor")
const Geometry = require("../Renderer/Geometry")
const Info = require("../Doom/Info")
const Interaction = require("./Interaction")
const Map = require("./Map")
const MapUtil = require("./MapUtil")
const Mobj = require("./Mobj")
const Random = require("../Miscellaneous/Random")
const Runtime = require("./Runtime")
const Sight = require("./Sight")
const Sounds = require("../Doom/Sounds")
const State = require("../Renderer/State")
const Switch = require("./Switch")
const Tables = require("../Engine/Tables")
const Tick = require("./Tick")

const FRACUNIT = 65536
const ANG90 = 0x40000000
const ANG180 = 0x80000000
const ANG270 = 0xC0000000
const ANGLETOFINESHIFT = 19
const FINEMASK = 8191
const UINT32_MASK = 0xFFFFFFFF
const finecosine = Tables.finecosine
const finesine = Tables.finesine
const ToSigned32 = Fixed.ToSigned32
const FixedMul = Fixed.FixedMul
const DoomRandom = Random.PlayRandom

const TWOSIDED = 4
const SOUNDBLOCK = 64
const MELEERANGE = 64 * FRACUNIT
const MISSILERANGE = 32 * 64 * FRACUNIT
const FATSPREAD = ANG90 // 8
const TRACEANGLE = 0x0C000000
const SKULLSPEED = 20 * FRACUNIT
const MAX_BRAIN_TARGETS = 32

const EAST = 0
const NORTHEAST = 1
const NORTH = 2
const NORTHWEST = 3
const WEST = 4
const SOUTHWEST = 5
const SOUTH = 6
const SOUTHEAST = 7
const NODIR = 8

const xspeed = {
	[0] = FRACUNIT,
	47000,
	0,
	-47000,
	-FRACUNIT,
	-47000,
	0,
	47000,
}

const yspeed = {
	[0] = 0,
	47000,
	FRACUNIT,
	47000,
	0,
	-47000,
	-FRACUNIT,
	-47000,
}

const opposite = {
	[0] = WEST,
	SOUTHWEST,
	SOUTH,
	SOUTHEAST,
	EAST,
	NORTHEAST,
	NORTH,
	NORTHWEST,
	NODIR,
}

const diags = {
	[0] = NORTHWEST,
	NORTHEAST,
	SOUTHWEST,
	SOUTHEAST,
}

type DoomMobj = typeof(Mobj.SpawnMobj(0, 0, 0, 0))
type DoomSector = typeof(MapUtil.PointInSubsector(0, 0).sector)
type SoundId = number | boolean | nil

local gamemode = Definitions.indetermined
local gameskill = Definitions.sk_medium
local fastparm = false
local currentepisode = 0
local currentmap = 0
local soundtarget = false
local corpsehit = false
local viletryx = 0
local viletryy = 0
local easy = 0
const braintargets: { [number]: DoomMobj } = {}
local numbraintargets = 0
local braintargeton = 0

const function SignedRightShift(value: number, shift: number): number
	return ToSigned32(bit32.arshift(value, shift))
end

const function MapBlockCoord(value: number, origin: number): number
	return SignedRightShift(ToSigned32(value - origin), MapUtil.MAPBLOCKSHIFT)
end

const function GetLevelTime(): number
	return Runtime.getLevelTime()
end

const function StartSound(origin: DoomMobj?, sound: SoundId)
	if sound ~= nil and sound ~= false then
		Runtime.startSound(origin, sound)
	end
end

const function ExitLevel()
	Runtime.exitLevel()
end

const function GetPrimaryPlayer()
	const players = Tick.GetPlayers()
	return players[0]
end

const function TruthyC(result: unknown): boolean
	return result ~= nil and result ~= false and result ~= 0
end

-- Called by NoiseAlert.
-- Recursively traverse adjacent sectors,
-- sound blocking lines cut off traversal.
const function RecursiveSound(sec: DoomSector, soundblocks: number)
	if sec.validcount == State.validcount and sec.soundtraversed <= soundblocks + 1 then
		return
	end

	sec.validcount = State.validcount
	sec.soundtraversed = soundblocks + 1
	sec.soundtarget = soundtarget

	for index = 0, sec.linecount - 1 do
		const check = sec.lines[index]

		if bit32.band(check.flags, TWOSIDED) == 0 then
			continue
		end

		MapUtil.LineOpening(check)

		if MapUtil.GetOpenRange() <= 0 then
			continue
		end

		local other

		if check.frontsector == sec then
			other = check.backsector
		else
			other = check.frontsector
		end

		if not other then
			continue
		end

		if bit32.btest(check.flags, SOUNDBLOCK) then
			if soundblocks == 0 then
				RecursiveSound(other, 1)
			end
		else
			RecursiveSound(other, soundblocks)
		end
	end
end

-- If a monster yells at a player,
-- it will alert other monsters to the player.
const function NoiseAlert(target: DoomMobj, emmiter: DoomMobj)
	const sector = emmiter.subsector and emmiter.subsector.sector


	soundtarget = target
	State.validcount += 1
	RecursiveSound(sector, 0)
end

const function CheckMeleeRange(actor: DoomMobj): boolean
	const pl = actor.target

	if not pl then
		return false
	end

	const dist = MapUtil.ApproximateDistance(ToSigned32(pl.x - actor.x), ToSigned32(pl.y - actor.y))

	if dist >= MELEERANGE - 20 * FRACUNIT + pl.info.radius then
		return false
	end

	if not Sight.CheckSight(actor, pl) then
		return false
	end

	return true
end

const function CheckMissileRange(actor: DoomMobj): boolean
	const target = actor.target

	if not target then
		return false
	end

	if not Sight.CheckSight(actor, target) then
		return false
	end

	if bit32.btest(actor.flags, Info.JUSTHIT) then
		actor.flags = bit32.band(actor.flags, bit32.bnot(Info.JUSTHIT))
		return true
	end

	if actor.reactiontime ~= 0 then
		return false
	end

	local dist = ToSigned32(MapUtil.ApproximateDistance(ToSigned32(actor.x - target.x), ToSigned32(actor.y - target.y)) - 64 * FRACUNIT)

	if actor.info.meleestate == 0 then
		dist = ToSigned32(dist - 128 * FRACUNIT)
	end

	dist = SignedRightShift(dist, 16)

	if actor.type == Info.VILE then
		if dist > 14 * 64 then
			return false
		end
	end

	if actor.type == Info.UNDEAD then
		if dist < 196 then
			return false
		end

		dist = SignedRightShift(dist, 1)
	end

	if actor.type == Info.CYBORG or actor.type == Info.SPIDER or actor.type == Info.SKULL then
		dist = SignedRightShift(dist, 1)
	end

	if dist > 200 then
		dist = 200
	end

	if actor.type == Info.CYBORG and dist > 160 then
		dist = 160
	end

	if DoomRandom() < dist then
		return false
	end

	return true
end

-- Move in the current direction, returns false if blocked.
const function MoveActor(actor: DoomMobj): boolean
	if actor.movedir == NODIR then
		return false
	end


	const tryx = actor.x + actor.info.speed * xspeed[actor.movedir]
	const tryy = actor.y + actor.info.speed * yspeed[actor.movedir]
	const tryOk = Map.TryMove(actor, tryx, tryy)

	if not tryOk then
		if bit32.btest(actor.flags, Info.FLOAT) and Map.GetFloatOK() then
			if actor.z < Map.GetTMFloorZ() then
				actor.z += 4 * FRACUNIT
			else
				actor.z -= 4 * FRACUNIT
			end

			actor.flags = bit32.bor(actor.flags, Info.INFLOAT)
			return true
		end

		if Map.GetNumSpecialHits() == 0 then
			return false
		end

		actor.movedir = NODIR

		local good = false
		const spechit = Map.GetSpecialHits()

		for index = Map.GetNumSpecialHits() - 1, 0, -1 do
			const ld = spechit[index]

			if TruthyC(Switch.UseSpecialLine(actor, ld, 0)) then
				good = true
			end
		end

		return good
	end

	actor.flags = bit32.band(actor.flags, bit32.bnot(Info.INFLOAT))

	if bit32.band(actor.flags, Info.FLOAT) == 0 then
		actor.z = actor.floorz
	end

	return true
end

const function TryWalk(actor: DoomMobj): boolean
	if not MoveActor(actor) then
		return false
	end

	actor.movecount = bit32.band(DoomRandom(), 15)
	return true
end

const function ChooseChaseDirection(actor: DoomMobj)

	const olddir = actor.movedir
	const turnaround = opposite[olddir]
	const deltax = actor.target.x - actor.x
	const deltay = actor.target.y - actor.y
	const d = {
		[1] = NODIR,
		[2] = NODIR,
	}

	if deltax > 10 * FRACUNIT then
		d[1] = EAST
	elseif deltax < -10 * FRACUNIT then
		d[1] = WEST
	end

	if deltay < -10 * FRACUNIT then
		d[2] = SOUTH
	elseif deltay > 10 * FRACUNIT then
		d[2] = NORTH
	end

	if d[1] ~= NODIR and d[2] ~= NODIR then
		actor.movedir = diags[((if deltay < 0 then 1 else 0) * 2) + (if deltax > 0 then 1 else 0)]

		if actor.movedir ~= turnaround and TryWalk(actor) then
			return
		end
	end

	if DoomRandom() > 200 or math.abs(deltay) > math.abs(deltax) then
		const tdir = d[1]
		d[1] = d[2]
		d[2] = tdir
	end

	if d[1] == turnaround then
		d[1] = NODIR
	end

	if d[2] == turnaround then
		d[2] = NODIR
	end

	if d[1] ~= NODIR then
		actor.movedir = d[1]

		if TryWalk(actor) then
			return
		end
	end

	if d[2] ~= NODIR then
		actor.movedir = d[2]

		if TryWalk(actor) then
			return
		end
	end

	if olddir ~= NODIR then
		actor.movedir = olddir

		if TryWalk(actor) then
			return
		end
	end

	if bit32.btest(DoomRandom(), 1) then
		for tdir = EAST, SOUTHEAST do
			if tdir ~= turnaround then
				actor.movedir = tdir

				if TryWalk(actor) then
					return
				end
			end
		end
	else
		for tdir = SOUTHEAST, EAST, -1 do
			if tdir ~= turnaround then
				actor.movedir = tdir

				if TryWalk(actor) then
					return
				end
			end
		end
	end

	if turnaround ~= NODIR then
		actor.movedir = turnaround

		if TryWalk(actor) then
			return
		end
	end

	actor.movedir = NODIR
end

const function LookForPlayers(actor: DoomMobj, allaround: boolean): boolean
	const player = GetPrimaryPlayer()
	const mo = player and player.mo

	if not player or player.health <= 0 or not mo then
		return false
	end

	if not Sight.CheckSight(actor, mo) then
		return false
	end

	if not allaround then
		const an = bit32.band(Geometry.PointToAngle2(actor.x, actor.y, mo.x, mo.y) - actor.angle, UINT32_MASK)

		if an > ANG90 and an < ANG270 then
			const dist = MapUtil.ApproximateDistance(ToSigned32(mo.x - actor.x), ToSigned32(mo.y - actor.y))

			if dist > MELEERANGE then
				return false
			end
		end
	end

	actor.target = mo
	return true
end

const function FallAction(actor: DoomMobj)
	actor.flags = bit32.band(actor.flags, bit32.bnot(Info.SOLID))
end

const function KeenDieAction(mo: DoomMobj)
	FallAction(mo)

	local thinker = Tick.GetThinkerCap().next

	while thinker ~= Tick.GetThinkerCap() do
		if thinker["function"].acp1 == Mobj.MobjThinker then
			const mo2 = thinker.owner or thinker

			if mo2 ~= mo and mo2.type == mo.type and mo2.health > 0 then
				return
			end
		end

		thinker = thinker.next
	end

	const junk = { tag = 666 }
	Doors.DoDoor(junk, Doors.open)
end

const function LookAction(actor: DoomMobj)
	actor.threshold = 0

	local targ = false
	local seeyou = false

	const sector = actor.subsector and actor.subsector.sector

	if sector then
		targ = sector.soundtarget
	end

	if targ and bit32.btest(targ.flags, Info.SHOOTABLE) then
		actor.target = targ

		if bit32.btest(actor.flags, Info.AMBUSH) then
			seeyou = Sight.CheckSight(actor, actor.target)
		else
			seeyou = true
		end
	end

	if not seeyou and not LookForPlayers(actor, false) then
		return
	end

	if actor.info.seesound then
		local sound = actor.info.seesound

		if sound == Sounds.sfx_posit1 or sound == Sounds.sfx_posit2 or sound == Sounds.sfx_posit3 then
			sound = Sounds.sfx_posit1 + (DoomRandom() % 3)
		elseif sound == Sounds.sfx_bgsit1 or sound == Sounds.sfx_bgsit2 then
			sound = Sounds.sfx_bgsit1 + bit32.band(DoomRandom(), 1)
		end

		if actor.type == Info.SPIDER or actor.type == Info.CYBORG then
			StartSound(nil, sound)
		else
			StartSound(actor, sound)
		end
	end

	Mobj.SetMobjState(actor, actor.info.seestate)
end

const function ChaseAction(actor: DoomMobj)
	if actor.reactiontime ~= 0 then
		actor.reactiontime -= 1
	end

	if actor.threshold ~= 0 then
		if not actor.target or actor.target.health <= 0 then
			actor.threshold = 0
		else
			actor.threshold -= 1
		end
	end

	if actor.movedir < 8 then
		actor.angle = bit32.band(actor.angle, 0xE0000000)

		const delta = ToSigned32(actor.angle - actor.movedir * 0x20000000)

		if delta > 0 then
			actor.angle = bit32.band(actor.angle - ANG90 // 2, UINT32_MASK)
		elseif delta < 0 then
			actor.angle = bit32.band(actor.angle + ANG90 // 2, UINT32_MASK)
		end
	end

	if not actor.target or bit32.band(actor.target.flags, Info.SHOOTABLE) == 0 then
		if LookForPlayers(actor, true) then
			return
		end

		Mobj.SetMobjState(actor, actor.info.spawnstate)
		return
	end

	if bit32.btest(actor.flags, Info.JUSTATTACKED) then
		actor.flags = bit32.band(actor.flags, bit32.bnot(Info.JUSTATTACKED))

		if gameskill ~= Definitions.sk_nightmare and not fastparm then
			ChooseChaseDirection(actor)
		end

		return
	end

	if actor.info.meleestate ~= 0 and CheckMeleeRange(actor) then
		if actor.info.attacksound then
			StartSound(actor, actor.info.attacksound)
		end

		Mobj.SetMobjState(actor, actor.info.meleestate)
		return
	end

	if actor.info.missilestate ~= 0 then
		if gameskill < Definitions.sk_nightmare and not fastparm and actor.movecount ~= 0 then
			-- continue
		elseif CheckMissileRange(actor) then
			Mobj.SetMobjState(actor, actor.info.missilestate)
			actor.flags = bit32.bor(actor.flags, Info.JUSTATTACKED)
			return
		end
	end

	actor.movecount -= 1

	if actor.movecount < 0 or not MoveActor(actor) then
		ChooseChaseDirection(actor)
	end

	if actor.info.activesound and DoomRandom() < 3 then
		StartSound(actor, actor.info.activesound)
	end
end

const function FaceTargetAction(actor: DoomMobj)
	const target = actor.target

	if not target then
		return
	end

	actor.flags = bit32.band(actor.flags, bit32.bnot(Info.AMBUSH))
	actor.angle = Geometry.PointToAngle2(actor.x, actor.y, target.x, target.y)

	if bit32.btest(target.flags, Info.SHADOW) then
		actor.angle = bit32.band(actor.angle + (DoomRandom() - DoomRandom()) * 2097152, UINT32_MASK)
	end
end

const function PosAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	local angle = actor.angle
	const slope = Map.AimLineAttack(actor, angle, MISSILERANGE)

	StartSound(actor, Sounds.sfx_pistol)
	angle = bit32.band(angle + (DoomRandom() - DoomRandom()) * 1048576, UINT32_MASK)

	const damage = ((DoomRandom() % 5) + 1) * 3
	Map.LineAttack(actor, angle, MISSILERANGE, slope, damage)
end

const function SPosAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	StartSound(actor, Sounds.sfx_shotgn)
	FaceTargetAction(actor)

	const bangle = actor.angle
	const slope = Map.AimLineAttack(actor, bangle, MISSILERANGE)

	for _ = 1, 3 do
		const angle = bit32.band(bangle + (DoomRandom() - DoomRandom()) * 1048576, UINT32_MASK)
		const damage = ((DoomRandom() % 5) + 1) * 3
		Map.LineAttack(actor, angle, MISSILERANGE, slope, damage)
	end
end

const function CPosAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	StartSound(actor, Sounds.sfx_shotgn)
	FaceTargetAction(actor)

	const bangle = actor.angle
	const slope = Map.AimLineAttack(actor, bangle, MISSILERANGE)
	const angle = bit32.band(bangle + (DoomRandom() - DoomRandom()) * 1048576, UINT32_MASK)
	const damage = ((DoomRandom() % 5) + 1) * 3

	Map.LineAttack(actor, angle, MISSILERANGE, slope, damage)
end

const function CPosRefireAction(actor: DoomMobj)
	FaceTargetAction(actor)

	if DoomRandom() < 40 then
		return
	end

	if not actor.target or actor.target.health <= 0 or not Sight.CheckSight(actor, actor.target) then
		Mobj.SetMobjState(actor, actor.info.seestate)
	end
end

const function SpidRefireAction(actor: DoomMobj)
	FaceTargetAction(actor)

	if DoomRandom() < 10 then
		return
	end

	if not actor.target or actor.target.health <= 0 or not Sight.CheckSight(actor, actor.target) then
		Mobj.SetMobjState(actor, actor.info.seestate)
	end
end

const function BspiAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)
	Mobj.SpawnMissile(actor, actor.target, Info.ARACHPLAZ)
end

const function TroopAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	if CheckMeleeRange(actor) then
		StartSound(actor, Sounds.sfx_claw)
		const damage = (bit32.band(DoomRandom(), 7) + 1) * 3
		Interaction.DamageMobj(actor.target, actor, actor, damage)
		return
	end

	Mobj.SpawnMissile(actor, actor.target, Info.TROOPSHOT)
end

const function SargAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	if CheckMeleeRange(actor) then
		const damage = ((DoomRandom() % 10) + 1) * 4
		Interaction.DamageMobj(actor.target, actor, actor, damage)
	end
end

const function HeadAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	if CheckMeleeRange(actor) then
		const damage = (DoomRandom() % 6 + 1) * 10
		Interaction.DamageMobj(actor.target, actor, actor, damage)
		return
	end

	Mobj.SpawnMissile(actor, actor.target, Info.HEADSHOT)
end

const function CyberAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)
	Mobj.SpawnMissile(actor, actor.target, Info.ROCKET)
end

const function BruisAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	if CheckMeleeRange(actor) then
		StartSound(actor, Sounds.sfx_claw)
		const damage = (bit32.band(DoomRandom(), 7) + 1) * 10
		Interaction.DamageMobj(actor.target, actor, actor, damage)
		return
	end

	Mobj.SpawnMissile(actor, actor.target, Info.BRUISERSHOT)
end

const function SkelMissileAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)
	actor.z += 16 * FRACUNIT

	const mo = Mobj.SpawnMissile(actor, actor.target, Info.TRACER)

	actor.z -= 16 * FRACUNIT

	mo.x += mo.momx
	mo.y += mo.momy
	mo.tracer = actor.target
end

const function TracerAction(actor: DoomMobj)

	if bit32.btest(GetLevelTime(), 3) then
		return
	end

	Mobj.SpawnPuff(actor.x, actor.y, actor.z)

	const th = Mobj.SpawnMobj(actor.x - actor.momx, actor.y - actor.momy, actor.z, Info.SMOKE)
	th.momz = FRACUNIT
	th.tics -= bit32.band(DoomRandom(), 3)

	if th.tics < 1 then
		th.tics = 1
	end

	const dest = actor.tracer

	if not dest or dest.health <= 0 then
		return
	end

	const exact = Geometry.PointToAngle2(actor.x, actor.y, dest.x, dest.y)

	if exact ~= actor.angle then
		if bit32.band(exact - actor.angle, UINT32_MASK) > 0x80000000 then
			actor.angle = bit32.band(actor.angle - TRACEANGLE, UINT32_MASK)

			if bit32.band(exact - actor.angle, UINT32_MASK) < 0x80000000 then
				actor.angle = exact
			end
		else
			actor.angle = bit32.band(actor.angle + TRACEANGLE, UINT32_MASK)

			if bit32.band(exact - actor.angle, UINT32_MASK) > 0x80000000 then
				actor.angle = exact
			end
		end
	end

	const fineAngle = bit32.band(bit32.rshift(actor.angle, ANGLETOFINESHIFT), FINEMASK)
	actor.momx = FixedMul(actor.info.speed, finecosine[fineAngle])
	actor.momy = FixedMul(actor.info.speed, finesine[fineAngle])

	local dist = math.modf(MapUtil.ApproximateDistance(dest.x - actor.x, dest.y - actor.y) / actor.info.speed)

	if dist < 1 then
		dist = 1
	end

	const slope = math.modf((dest.z + 40 * FRACUNIT - actor.z) / dist)

	if slope < actor.momz then
		actor.momz -= FRACUNIT // 8
	else
		actor.momz += FRACUNIT // 8
	end
end

const function SkelWhooshAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)
	StartSound(actor, Sounds.sfx_skeswg)
end

const function SkelFistAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	if CheckMeleeRange(actor) then
		const damage = ((DoomRandom() % 10) + 1) * 6
		StartSound(actor, Sounds.sfx_skepch)
		Interaction.DamageMobj(actor.target, actor, actor, damage)
	end
end

const function VileCheckIterator(thing: DoomMobj)

	if bit32.band(thing.flags, Info.CORPSE) == 0 then
		return true
	end

	if thing.tics ~= -1 then
		return true
	end

	if thing.info.raisestate == Info.NULL then
		return true
	end

	const maxdist = thing.info.radius + Info.mobjinfo[Info.VILE].radius

	if math.abs(thing.x - viletryx) > maxdist or math.abs(thing.y - viletryy) > maxdist then
		return true
	end

	corpsehit = thing
	corpsehit.momx = 0
	corpsehit.momy = 0
	corpsehit.height *= 4

	const check = Map.CheckPosition(corpsehit, corpsehit.x, corpsehit.y)
	corpsehit.height = math.modf(corpsehit.height / 4)

	if not check then
		return true
	end

	return false
end

const function VileChaseAction(actor: DoomMobj)

	if actor.movedir ~= NODIR then
		viletryx = actor.x + actor.info.speed * xspeed[actor.movedir]
		viletryy = actor.y + actor.info.speed * yspeed[actor.movedir]

		const xl = MapBlockCoord(viletryx - Map.MAXRADIUS * 2, MapUtil.GetBMapOrgX())
		const xh = MapBlockCoord(viletryx + Map.MAXRADIUS * 2, MapUtil.GetBMapOrgX())
		const yl = MapBlockCoord(viletryy - Map.MAXRADIUS * 2, MapUtil.GetBMapOrgY())
		const yh = MapBlockCoord(viletryy + Map.MAXRADIUS * 2, MapUtil.GetBMapOrgY())

		for bx = xl, xh do
			for by = yl, yh do
				if not TruthyC(MapUtil.BlockThingsIterator(bx, by, VileCheckIterator)) then
					const temp = actor.target
					actor.target = corpsehit
					FaceTargetAction(actor)
					actor.target = temp

					Mobj.SetMobjState(actor, Info.VILE_HEAL1)
					StartSound(corpsehit, Sounds.sfx_slop)

					const info = corpsehit.info

					Mobj.SetMobjState(corpsehit, info.raisestate)
					corpsehit.height *= 4
					corpsehit.flags = info.flags
					corpsehit.health = info.spawnhealth
					corpsehit.target = false
					return
				end
			end
		end
	end

	ChaseAction(actor)
end

const function VileStartAction(actor: DoomMobj)
	StartSound(actor, Sounds.sfx_vilatk)
end

const function FireAction(actor: DoomMobj)

	const dest = actor.tracer

	if not dest then
		return
	end

	if not actor.target or not Sight.CheckSight(actor.target, dest) then
		return
	end

	const an = bit32.band(bit32.rshift(dest.angle, ANGLETOFINESHIFT), FINEMASK)

	MapUtil.UnsetThingPosition(actor)
	actor.x = dest.x + FixedMul(24 * FRACUNIT, finecosine[an])
	actor.y = dest.y + FixedMul(24 * FRACUNIT, finesine[an])
	actor.z = dest.z
	MapUtil.SetThingPosition(actor)
end

const function StartFireAction(actor: DoomMobj)
	StartSound(actor, Sounds.sfx_flamst)
	FireAction(actor)
end

const function FireCrackleAction(actor: DoomMobj)
	StartSound(actor, Sounds.sfx_flame)
	FireAction(actor)
end

const function VileTargetAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	-- This keeps the reference source's x/x/z spawn call.
	const fog = Mobj.SpawnMobj(actor.target.x, actor.target.x, actor.target.z, Info.FIRE)

	actor.tracer = fog
	fog.target = actor
	fog.tracer = actor.target
	FireAction(fog)
end

const function VileAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)

	if not Sight.CheckSight(actor, actor.target) then
		return
	end

	StartSound(actor, Sounds.sfx_barexp)
	Interaction.DamageMobj(actor.target, actor, actor, 20)

	actor.target.momz = (1000 * FRACUNIT) // actor.target.info.mass

	const an = bit32.band(bit32.rshift(actor.angle, ANGLETOFINESHIFT), FINEMASK)
	const fire = actor.tracer

	if not fire then
		return
	end

	fire.x = actor.target.x - FixedMul(24 * FRACUNIT, finecosine[an])
	fire.y = actor.target.y - FixedMul(24 * FRACUNIT, finesine[an])
	Map.RadiusAttack(fire, actor, 70)
end

const function FatRaiseAction(actor: DoomMobj)
	FaceTargetAction(actor)
	StartSound(actor, Sounds.sfx_manatk)
end

const function FatAttack1Action(actor: DoomMobj)
	FaceTargetAction(actor)
	actor.angle = bit32.band(actor.angle + FATSPREAD, UINT32_MASK)
	Mobj.SpawnMissile(actor, actor.target, Info.FATSHOT)

	const mo = Mobj.SpawnMissile(actor, actor.target, Info.FATSHOT)
	mo.angle = bit32.band(mo.angle + FATSPREAD, UINT32_MASK)

	const an = bit32.band(bit32.rshift(mo.angle, ANGLETOFINESHIFT), FINEMASK)
	mo.momx = FixedMul(mo.info.speed, finecosine[an])
	mo.momy = FixedMul(mo.info.speed, finesine[an])
end

const function FatAttack2Action(actor: DoomMobj)
	FaceTargetAction(actor)
	actor.angle = bit32.band(actor.angle - FATSPREAD, UINT32_MASK)
	Mobj.SpawnMissile(actor, actor.target, Info.FATSHOT)

	const mo = Mobj.SpawnMissile(actor, actor.target, Info.FATSHOT)
	mo.angle = bit32.band(mo.angle - FATSPREAD * 2, UINT32_MASK)

	const an = bit32.band(bit32.rshift(mo.angle, ANGLETOFINESHIFT), FINEMASK)
	mo.momx = FixedMul(mo.info.speed, finecosine[an])
	mo.momy = FixedMul(mo.info.speed, finesine[an])
end

const function FatAttack3Action(actor: DoomMobj)
	FaceTargetAction(actor)

	local mo = Mobj.SpawnMissile(actor, actor.target, Info.FATSHOT)
	mo.angle = bit32.band(mo.angle - FATSPREAD // 2, UINT32_MASK)

	local an = bit32.band(bit32.rshift(mo.angle, ANGLETOFINESHIFT), FINEMASK)
	mo.momx = FixedMul(mo.info.speed, finecosine[an])
	mo.momy = FixedMul(mo.info.speed, finesine[an])

	mo = Mobj.SpawnMissile(actor, actor.target, Info.FATSHOT)
	mo.angle = bit32.band(mo.angle + FATSPREAD // 2, UINT32_MASK)

	an = bit32.band(bit32.rshift(mo.angle, ANGLETOFINESHIFT), FINEMASK)
	mo.momx = FixedMul(mo.info.speed, finecosine[an])
	mo.momy = FixedMul(mo.info.speed, finesine[an])
end

const function SkullAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	const dest = actor.target
	actor.flags = bit32.bor(actor.flags, Info.SKULLFLY)
	StartSound(actor, actor.info.attacksound)
	FaceTargetAction(actor)

	const an = bit32.band(bit32.rshift(actor.angle, ANGLETOFINESHIFT), FINEMASK)
	actor.momx = FixedMul(SKULLSPEED, finecosine[an])
	actor.momy = FixedMul(SKULLSPEED, finesine[an])

	local dist = math.modf(MapUtil.ApproximateDistance(dest.x - actor.x, dest.y - actor.y) / SKULLSPEED)

	if dist < 1 then
		dist = 1
	end

	actor.momz = math.modf((dest.z + bit32.arshift(dest.height, 1) - actor.z) / dist)
end

const function PainShootSkullAction(actor: DoomMobj, angle: number)

	local count = 0
	local currentthinker = Tick.GetThinkerCap().next

	while currentthinker ~= Tick.GetThinkerCap() do

		const thinkerFunction = currentthinker["function"]
		const owner = currentthinker.owner

		if thinkerFunction
			and thinkerFunction.acp1 == Mobj.MobjThinker
			and owner
			and owner.type == Info.SKULL then
			count += 1
		end

		currentthinker = currentthinker.next
	end

	if count > 20 then
		return
	end

	const an = bit32.band(bit32.rshift(angle, ANGLETOFINESHIFT), FINEMASK)
	const skullInfo = Info.mobjinfo[Info.SKULL]
	const prestep = 4 * FRACUNIT + (3 * (actor.info.radius + skullInfo.radius)) // 2
	const x = actor.x + FixedMul(prestep, finecosine[an])
	const y = actor.y + FixedMul(prestep, finesine[an])
	const z = actor.z + 8 * FRACUNIT
	const newmobj = Mobj.SpawnMobj(x, y, z, Info.SKULL)

	if not Map.TryMove(newmobj, newmobj.x, newmobj.y) then
		Interaction.DamageMobj(newmobj, actor, actor, 10000)
		return
	end

	newmobj.target = actor.target
	SkullAttackAction(newmobj)
end

const function PainAttackAction(actor: DoomMobj)

	if not actor.target then
		return
	end

	FaceTargetAction(actor)
	PainShootSkullAction(actor, actor.angle)
end

const function PainDieAction(actor: DoomMobj)
	FallAction(actor)
	PainShootSkullAction(actor, bit32.band(actor.angle + ANG90, UINT32_MASK))
	PainShootSkullAction(actor, bit32.band(actor.angle + ANG180, UINT32_MASK))
	PainShootSkullAction(actor, bit32.band(actor.angle + ANG270, UINT32_MASK))
end

const function ScreamAction(actor: DoomMobj)

	local sound = actor.info.deathsound

	if sound == 0 or sound == false or sound == nil then
		return
	elseif sound == Sounds.sfx_podth1 or sound == Sounds.sfx_podth2 or sound == Sounds.sfx_podth3 then
		sound = Sounds.sfx_podth1 + (DoomRandom() % 3)
	elseif sound == Sounds.sfx_bgdth1 or sound == Sounds.sfx_bgdth2 then
		sound = Sounds.sfx_bgdth1 + bit32.band(DoomRandom(), 1)
	end

	if actor.type == Info.SPIDER or actor.type == Info.CYBORG then
		StartSound(nil, sound)
	else
		StartSound(actor, sound)
	end
end

const function XScreamAction(actor: DoomMobj)
	StartSound(actor, Sounds.sfx_slop)
end

const function PainAction(actor: DoomMobj)

	if actor.info.painsound ~= false and actor.info.painsound ~= nil then
		StartSound(actor, actor.info.painsound)
	end
end

const function ExplodeAction(thingy: DoomMobj)
	Map.RadiusAttack(thingy, thingy.target, 128)
end

const function BossDeathAction(mo: DoomMobj)

	if gamemode == Definitions.commercial then
		if currentmap ~= 7 then
			return
		end

		if mo.type ~= Info.FATSO and mo.type ~= Info.BABY then
			return
		end
	else
		if currentepisode == 1 then
			if currentmap ~= 8 or mo.type ~= Info.BRUISER then
				return
			end
		elseif currentepisode == 2 then
			if currentmap ~= 8 or mo.type ~= Info.CYBORG then
				return
			end
		elseif currentepisode == 3 then
			if currentmap ~= 8 or mo.type ~= Info.SPIDER then
				return
			end
		elseif currentepisode == 4 then
			if currentmap == 6 then
				if mo.type ~= Info.CYBORG then
					return
				end
			elseif currentmap == 8 then
				if mo.type ~= Info.SPIDER then
					return
				end
			else
				return
			end
		elseif currentmap ~= 8 then
			return
		end
	end

	const player = GetPrimaryPlayer()

	if not player or player.health <= 0 then
		return
	end

	local thinker = Tick.GetThinkerCap().next

	while thinker ~= Tick.GetThinkerCap() do
		if thinker["function"].acp1 == Mobj.MobjThinker then
			const mo2 = thinker.owner or thinker

			if mo2 ~= mo and mo2.type == mo.type and mo2.health > 0 then
				return
			end
		end

		thinker = thinker.next
	end

	const junk = { tag = 666 }

	if gamemode == Definitions.commercial then
		if currentmap == 7 then
			if mo.type == Info.FATSO then
				Floor.DoFloor(junk, Floor.lowerFloorToLowest)
				return
			end

			if mo.type == Info.BABY then
				junk.tag = 667
				Floor.DoFloor(junk, Floor.raiseToTexture)
				return
			end
		end
	else
		if currentepisode == 1 then
			Floor.DoFloor(junk, Floor.lowerFloorToLowest)
			return
		elseif currentepisode == 4 then
			if currentmap == 6 then
				Doors.DoDoor(junk, Doors.blazeOpen)
				return
			elseif currentmap == 8 then
				Floor.DoFloor(junk, Floor.lowerFloorToLowest)
				return
			end
		end
	end

	ExitLevel()
end

const function HoofAction(mo: DoomMobj)
	StartSound(mo, Sounds.sfx_hoof)
	ChaseAction(mo)
end

const function MetalAction(mo: DoomMobj)
	StartSound(mo, Sounds.sfx_metal)
	ChaseAction(mo)
end

const function BabyMetalAction(mo: DoomMobj)
	StartSound(mo, Sounds.sfx_bspwlk)
	ChaseAction(mo)
end

const function BrainAwakeAction(_mo: DoomMobj)
	table.clear(braintargets)
	numbraintargets = 0
	braintargeton = 0

	local thinker = Tick.GetThinkerCap().next

	while thinker ~= Tick.GetThinkerCap() do
		if thinker["function"].acp1 == Mobj.MobjThinker then
			const m = thinker.owner or thinker

			if m.type == Info.BOSSTARGET then
				if numbraintargets < MAX_BRAIN_TARGETS then
					braintargets[numbraintargets] = m
					numbraintargets += 1
				end
			end
		end

		thinker = thinker.next
	end

	StartSound(nil, Sounds.sfx_bossit)
end

const function BrainPainAction(_mo: DoomMobj)
	StartSound(nil, Sounds.sfx_bospn)
end

const function BrainScreamAction(mo: DoomMobj)

	for x = mo.x - 196 * FRACUNIT, mo.x + 320 * FRACUNIT, 8 * FRACUNIT do
		const y = mo.y - 320 * FRACUNIT
		const z = 128 + DoomRandom() * 2 * FRACUNIT
		const th = Mobj.SpawnMobj(x, y, z, Info.ROCKET)

		th.momz = DoomRandom() * 512
		Mobj.SetMobjState(th, Info.BRAINEXPLODE1)

		th.tics -= bit32.band(DoomRandom(), 7)

		if th.tics < 1 then
			th.tics = 1
		end
	end

	StartSound(nil, Sounds.sfx_bosdth)
end

const function BrainExplodeAction(mo: DoomMobj)

	const x = mo.x + (DoomRandom() - DoomRandom()) * 2048
	const y = mo.y
	const z = 128 + DoomRandom() * 2 * FRACUNIT
	const th = Mobj.SpawnMobj(x, y, z, Info.ROCKET)

	th.momz = DoomRandom() * 512
	Mobj.SetMobjState(th, Info.BRAINEXPLODE1)

	th.tics -= bit32.band(DoomRandom(), 7)

	if th.tics < 1 then
		th.tics = 1
	end
end

const function BrainDieAction(_mo: DoomMobj)
	ExitLevel()
end

const function BrainSpitAction(mo: DoomMobj)
	easy = bit32.bxor(easy, 1)

	if gameskill <= Definitions.sk_easy and easy == 0 then
		return
	end

	if numbraintargets <= 0 then
		return
	end

	const targ = braintargets[braintargeton]
	braintargeton = (braintargeton + 1) % numbraintargets

	if not targ then
		return
	end

	const newmobj = Mobj.SpawnMissile(mo, targ, Info.SPAWNSHOT)
	newmobj.target = targ

	const stateTics = if newmobj.state then newmobj.state.tics else 0

	if newmobj.momy ~= 0 and stateTics ~= 0 then
		newmobj.reactiontime = math.modf(math.modf((targ.y - mo.y) / newmobj.momy) / stateTics)
	else
		newmobj.reactiontime = 0
	end

	StartSound(nil, Sounds.sfx_bospit)
end

const function SpawnFlyAction(mo: DoomMobj)
	mo.reactiontime -= 1

	if mo.reactiontime ~= 0 then
		return
	end

	const targ = mo.target

	const fog = Mobj.SpawnMobj(targ.x, targ.y, targ.z, Info.SPAWNFIRE)
	StartSound(fog, Sounds.sfx_telept)

	const r = DoomRandom()
	local type_

	if r < 50 then
		type_ = Info.TROOP
	elseif r < 90 then
		type_ = Info.SERGEANT
	elseif r < 120 then
		type_ = Info.SHADOWS
	elseif r < 130 then
		type_ = Info.PAIN
	elseif r < 160 then
		type_ = Info.HEAD
	elseif r < 162 then
		type_ = Info.VILE
	elseif r < 172 then
		type_ = Info.UNDEAD
	elseif r < 192 then
		type_ = Info.BABY
	elseif r < 222 then
		type_ = Info.FATSO
	elseif r < 246 then
		type_ = Info.KNIGHT
	else
		type_ = Info.BRUISER
	end

	const newmobj = Mobj.SpawnMobj(targ.x, targ.y, targ.z, type_)

	if LookForPlayers(newmobj, true) then
		Mobj.SetMobjState(newmobj, newmobj.info.seestate)
	end

	Map.TeleportMove(newmobj, newmobj.x, newmobj.y)
	Mobj.RemoveMobj(mo)
end

const function SpawnSoundAction(mo: DoomMobj)
	StartSound(mo, Sounds.sfx_boscub)
	SpawnFlyAction(mo)
end

const function PlayerScreamAction(mo: DoomMobj)

	local sound = Sounds.sfx_pldeth

	if gamemode == Definitions.commercial and mo.health < -50 then
		sound = Sounds.sfx_pdiehi
	end

	StartSound(mo, sound)
end

const function GetStateActions()
	return {
		KeenDieAction = KeenDieAction,
		LookAction = LookAction,
		ChaseAction = ChaseAction,
		FaceTargetAction = FaceTargetAction,
		PosAttackAction = PosAttackAction,
		SPosAttackAction = SPosAttackAction,
		CPosAttackAction = CPosAttackAction,
		CPosRefireAction = CPosRefireAction,
		SpidRefireAction = SpidRefireAction,
		BspiAttackAction = BspiAttackAction,
		TroopAttackAction = TroopAttackAction,
		SargAttackAction = SargAttackAction,
		HeadAttackAction = HeadAttackAction,
		CyberAttackAction = CyberAttackAction,
		BruisAttackAction = BruisAttackAction,
		SkelMissileAction = SkelMissileAction,
		TracerAction = TracerAction,
		SkelWhooshAction = SkelWhooshAction,
		SkelFistAction = SkelFistAction,
		VileStartAction = VileStartAction,
		StartFireAction = StartFireAction,
		FireCrackleAction = FireCrackleAction,
		FireAction = FireAction,
		VileTargetAction = VileTargetAction,
		VileAttackAction = VileAttackAction,
		FatRaiseAction = FatRaiseAction,
		FatAttack1Action = FatAttack1Action,
		FatAttack2Action = FatAttack2Action,
		FatAttack3Action = FatAttack3Action,
		SkullAttackAction = SkullAttackAction,
		PainAttackAction = PainAttackAction,
		PainDieAction = PainDieAction,
		ScreamAction = ScreamAction,
		XScreamAction = XScreamAction,
		PainAction = PainAction,
		FallAction = FallAction,
		ExplodeAction = ExplodeAction,
		BossDeathAction = BossDeathAction,
		HoofAction = HoofAction,
		MetalAction = MetalAction,
		BabyMetalAction = BabyMetalAction,
		BrainAwakeAction = BrainAwakeAction,
		BrainPainAction = BrainPainAction,
		BrainScreamAction = BrainScreamAction,
		BrainExplodeAction = BrainExplodeAction,
		BrainDieAction = BrainDieAction,
		BrainSpitAction = BrainSpitAction,
		SpawnFlyAction = SpawnFlyAction,
		SpawnSoundAction = SpawnSoundAction,
		VileChaseAction = VileChaseAction,
		PlayerScreamAction = PlayerScreamAction,
	}
end

const function Reset()
	gamemode = Definitions.indetermined
	gameskill = Definitions.sk_medium
	fastparm = false
	currentepisode = 0
	currentmap = 0
	soundtarget = false
	corpsehit = false
	viletryx = 0
	viletryy = 0
	easy = 0
	table.clear(braintargets)
	numbraintargets = 0
	braintargeton = 0
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

const function SetFastParm(value: boolean)
	fastparm = value
end

const function GetFastParm(): boolean
	return fastparm
end

const function SetCurrentEpisode(value: number)
	currentepisode = value
end

const function GetCurrentEpisode(): number
	return currentepisode
end

const function SetCurrentMap(value: number)
	currentmap = value
end

const function GetCurrentMap(): number
	return currentmap
end

const function GetSoundTarget()
	return soundtarget
end

Reset()

return {
	TWOSIDED = TWOSIDED,
	SOUNDBLOCK = SOUNDBLOCK,
	MELEERANGE = MELEERANGE,
	MISSILERANGE = MISSILERANGE,
	FATSPREAD = FATSPREAD,
	TRACEANGLE = TRACEANGLE,
	SKULLSPEED = SKULLSPEED,

	Reset = Reset,
	SetGameMode = SetGameMode,
	GetGameMode = GetGameMode,
	SetGameSkill = SetGameSkill,
	GetGameSkill = GetGameSkill,
	SetFastParm = SetFastParm,
	GetFastParm = GetFastParm,
	SetCurrentEpisode = SetCurrentEpisode,
	GetCurrentEpisode = GetCurrentEpisode,
	SetCurrentMap = SetCurrentMap,
	GetCurrentMap = GetCurrentMap,
	GetSoundTarget = GetSoundTarget,
	GetStateActions = GetStateActions,
	RecursiveSound = (RecursiveSound),
	NoiseAlert = (NoiseAlert),
	CheckMeleeRange = (CheckMeleeRange),
	CheckMissileRange = (CheckMissileRange),
	MoveActor = (MoveActor),
	TryWalk = (TryWalk),
	ChooseChaseDirection = (ChooseChaseDirection),
	LookForPlayers = (LookForPlayers),
	KeenDieAction = KeenDieAction,
	LookAction = LookAction,
	ChaseAction = ChaseAction,
	FaceTargetAction = FaceTargetAction,
	PosAttackAction = PosAttackAction,
	SPosAttackAction = SPosAttackAction,
	CPosAttackAction = CPosAttackAction,
	CPosRefireAction = CPosRefireAction,
	SpidRefireAction = SpidRefireAction,
	BspiAttackAction = BspiAttackAction,
	TroopAttackAction = TroopAttackAction,
	SargAttackAction = SargAttackAction,
	HeadAttackAction = HeadAttackAction,
	CyberAttackAction = CyberAttackAction,
	BruisAttackAction = BruisAttackAction,
	SkelMissileAction = SkelMissileAction,
	TracerAction = TracerAction,
	SkelWhooshAction = SkelWhooshAction,
	SkelFistAction = SkelFistAction,
	VileStartAction = VileStartAction,
	StartFireAction = StartFireAction,
	FireCrackleAction = FireCrackleAction,
	FireAction = FireAction,
	VileTargetAction = VileTargetAction,
	VileAttackAction = VileAttackAction,
	FatRaiseAction = FatRaiseAction,
	FatAttack1Action = FatAttack1Action,
	FatAttack2Action = FatAttack2Action,
	FatAttack3Action = FatAttack3Action,
	SkullAttackAction = SkullAttackAction,
	PainAttackAction = PainAttackAction,
	PainDieAction = PainDieAction,
	ScreamAction = ScreamAction,
	XScreamAction = XScreamAction,
	PainAction = PainAction,
	FallAction = FallAction,
	ExplodeAction = ExplodeAction,
	BossDeathAction = BossDeathAction,
	HoofAction = HoofAction,
	MetalAction = MetalAction,
	BabyMetalAction = BabyMetalAction,
	BrainAwakeAction = BrainAwakeAction,
	BrainPainAction = BrainPainAction,
	BrainScreamAction = BrainScreamAction,
	BrainExplodeAction = BrainExplodeAction,
	BrainDieAction = BrainDieAction,
	BrainSpitAction = BrainSpitAction,
	SpawnFlyAction = SpawnFlyAction,
	SpawnSoundAction = SpawnSoundAction,
	VileChaseAction = VileChaseAction,
	PlayerScreamAction = PlayerScreamAction,
}
