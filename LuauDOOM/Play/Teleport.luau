--!native
--!optimize 2

-- Port of p_telept.c
-- Teleportation.
-- Note: fog spawning and sound playback come from the shared play runtime.

const Map = require("./Map")
const Mobj = require("./Mobj")
const Runtime = require("./Runtime")
const State = require("../Renderer/State")
const Tables = require("../Engine/Tables")

const MISSILE = Map.MISSILE

const TFOG = 39
const TELEPORTMAN = 41

const sfx_telept = 35

type Sector = typeof(State.sectors[0])
type Line = typeof(State.lines[0])
type DoomMobj = typeof(Mobj.SpawnMobj(0, 0, 0, 0))

const function FindTeleportManInSector(sector: Sector)
	const thinkercap = Runtime.getThinkerCap()
	local thinker = thinkercap.next

	while thinker ~= thinkercap do
		if thinker["function"].acp1 == Mobj.MobjThinker then
			const mobj = thinker.owner or thinker

			if mobj.type == TELEPORTMAN and mobj.subsector and mobj.subsector.sector == sector then
				return mobj
			end
		end

		thinker = thinker.next
	end

	return false
end

-- TELEPORTATION
const function Teleport(line: Line, side: number, thing: DoomMobj): number
	if bit32.btest(thing.flags, MISSILE) then
		return 0
	end

	if side == 1 then
		return 0
	end

	const tag = line.tag

	for index = 0, State.numsectors - 1 do
		const sector = State.sectors[index]

		if sector.tag ~= tag then
			continue
		end

		const dest = FindTeleportManInSector(sector)

		if not dest then
			continue
		end

		const oldx = thing.x
		const oldy = thing.y
		const oldz = thing.z

		if not Map.TeleportMove(thing, dest.x, dest.y) then
			return 0
		end

		thing.z = thing.floorz

		if thing.player then
			thing.player.viewz = thing.z + thing.player.viewheight
		end

		local fog = Runtime.spawnMobj(oldx, oldy, oldz, TFOG)
		Runtime.startSound(fog, sfx_telept)

		const an = bit32.band(bit32.rshift(dest.angle, Tables.ANGLETOFINESHIFT), Tables.FINEMASK)
		fog = Runtime.spawnMobj(
			dest.x + 20 * Tables.finecosine[an],
			dest.y + 20 * Tables.finesine[an],
			thing.z,
			TFOG
		)
		Runtime.startSound(fog, sfx_telept)

		if thing.player then
			thing.reactiontime = 18
		end

		thing.angle = dest.angle
		thing.momx = 0
		thing.momy = 0
		thing.momz = 0

		return 1
	end

	return 0
end

return {
	TFOG = TFOG,
	TELEPORTMAN = TELEPORTMAN,
	sfx_telept = sfx_telept,

	FindTeleportManInSector = FindTeleportManInSector,
	Teleport = Teleport,
}
