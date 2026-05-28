--!native
--!optimize 2

-- Port of p_saveg.c, p_saveg.h
-- Savegame archiving/persistence.
-- Luau adaptation: uses a structured archive table instead of raw byte*
-- pointer copying, but keeps the same Archive*/UnArchive* surface.

const Ceiling = require("./Ceiling")
const Doors = require("./Doors")
const Floor = require("./Floor")
const Info = require("../Doom/Info")
const Lights = require("./Lights")
const MapUtil = require("./MapUtil")
const Mobj = require("./Mobj")
const Platforms = require("./Platforms")
const Setup = require("./Setup")
const State = require("../Renderer/State")
const Switch = require("./Switch")
const Tick = require("./Tick")

const tc_end = 0
const tc_mobj = 1

const tc_ceiling = 0
const tc_door = 1
const tc_floor = 2
const tc_plat = 3
const tc_flash = 4
const tc_strobe = 5
const tc_glow = 6
const tc_fireflicker = 7
const tc_button = 8
const tc_endspecials = 9

type LooseTable = {
	[unknown]: unknown,
}
type LooseList = { [number]: LooseTable }
type WorldArchive = {
	sectors: LooseList,
	lines: LooseList,
}
type SaveArchive = {
	players: LooseTable?,
	world: WorldArchive?,
	thinkers: LooseList?,
	specials: LooseList?,
}

local save_p: SaveArchive = {}

const function DeepCopy(value: unknown)
	if typeof(value) ~= "table" then
		return value
	end

	const copy: LooseTable = {}

	for key, item in value do
		copy[key] = DeepCopy(item)
	end

	return copy
end

const function GetStateIndex(state: unknown): number
	if state == nil or state == false then
		return -1
	end

	for index = 0, Info.NUMSTATES - 1 do
		if Info.states[index] == state then
			return index
		end
	end

	error("Play/SaveGame: state is not indexed in Info.states")
end

const function GetSectorIndex(sector: unknown): number
	if sector == nil or sector == false then
		return -1
	end

	for index = 0, State.numsectors - 1 do
		if State.sectors[index] == sector then
			return index
		end
	end

	error("Play/SaveGame: sector is not indexed in State.sectors")
end

const function GetLineIndex(line: unknown): number
	if line == nil or line == false then
		return -1
	end

	for index = 0, State.numlines - 1 do
		if State.lines[index] == line then
			return index
		end
	end

	error("Play/SaveGame: line is not indexed in State.lines")
end

const function GetPlayerIndex(player: unknown): number
	if player == nil or player == false then
		return 0
	end

	const players = Setup.GetPlayers()

	for index = 0, 3 do
		if players[index] == player then
			return index + 1
		end
	end

	return 0
end

const function GetMobjArchiveIndex(mobj: unknown, archiveIndices: LooseTable?): number
	if mobj == nil or mobj == false then
		return 0
	end

	if archiveIndices == nil or archiveIndices == false then
		return 0
	end

	return (archiveIndices[mobj] :: number?) or 0
end

const function IsRemovedThinker(thinker: LooseTable?): boolean
	return thinker ~= nil and thinker["function"] ~= nil and thinker["function"].acv == -1
end

const function NewThinker(owner: unknown, thinkerFunction: unknown)
	return {
		owner = owner,
		prev = false,
		next = false,
		["function"] = {
			acp1 = thinkerFunction,
		},
	}
end

const function SnapshotPlayer(player: LooseTable)
	const snapshot: LooseTable = {}

	for key, value in player do
		if key == "mo" or key == "message" or key == "attacker" then
			continue
		end

		if key == "psprites" and value then
			const psprites: LooseTable = {}

			for index, psp in value do
				if psp then
					psprites[index] = {
						state = if psp.state then GetStateIndex(psp.state) else false,
						tics = psp.tics or 0,
						sx = psp.sx or 0,
						sy = psp.sy or 0,
					}
				end
			end

			snapshot[key] = psprites
		elseif typeof(value) == "table" then
			snapshot[key] = DeepCopy(value)
		else
			snapshot[key] = value
		end
	end

	snapshot.mo = false
	snapshot.message = false
	snapshot.attacker = false
	return snapshot
end

const function RestorePlayer(snapshot: LooseTable)
	const player = DeepCopy(snapshot)

	player.mo = false
	player.message = false
	player.attacker = false

	if player.psprites then
		for index, psp in player.psprites do
			if psp and psp.state ~= false and psp.state ~= nil then
				player.psprites[index].state = Info.states[psp.state]
			end
		end
	end

	return player
end

const function ApplyPlayerSnapshot(target: LooseTable, snapshot: LooseTable)
	const restored = RestorePlayer(snapshot)
	const keys: { unknown } = {}

	for key in target do
		keys[#keys + 1] = key
	end

	for _, key in keys do
		target[key] = nil
	end

	for key, value in restored do
		target[key] = value
	end
end

const function SnapshotMobj(mobj: LooseTable, archiveIndices: LooseTable)
	return {
		x = mobj.x,
		y = mobj.y,
		z = mobj.z,
		angle = mobj.angle,
		sprite = mobj.sprite,
		frame = mobj.frame,
		floorz = mobj.floorz,
		ceilingz = mobj.ceilingz,
		radius = mobj.radius,
		height = mobj.height,
		momx = mobj.momx,
		momy = mobj.momy,
		momz = mobj.momz,
		validcount = mobj.validcount,
		type = mobj.type,
		tics = mobj.tics,
		state = GetStateIndex(mobj.state),
		flags = mobj.flags,
		health = mobj.health,
		movedir = mobj.movedir,
		movecount = mobj.movecount,
		reactiontime = mobj.reactiontime,
		threshold = mobj.threshold,
		lastlook = mobj.lastlook,
		spawnpoint = DeepCopy(mobj.spawnpoint),
		player = GetPlayerIndex(mobj.player),
		target = GetMobjArchiveIndex(mobj.target, archiveIndices),
		tracer = GetMobjArchiveIndex(mobj.tracer, archiveIndices),
	}
end

const function RestoreMobj(snapshot: LooseTable)
	const info = Info.mobjinfo[snapshot.type]
	const state = Info.states[snapshot.state]
	const mobj = {
		type = snapshot.type,
		info = info,
		x = snapshot.x,
		y = snapshot.y,
		z = snapshot.z,
		angle = snapshot.angle,
		sprite = snapshot.sprite,
		frame = snapshot.frame,
		floorz = snapshot.floorz,
		ceilingz = snapshot.ceilingz,
		radius = snapshot.radius,
		height = snapshot.height,
		momx = snapshot.momx,
		momy = snapshot.momy,
		momz = snapshot.momz,
		validcount = snapshot.validcount,
		tics = snapshot.tics,
		state = state,
		flags = snapshot.flags,
		health = snapshot.health,
		movedir = snapshot.movedir,
		movecount = snapshot.movecount,
		reactiontime = snapshot.reactiontime,
		threshold = snapshot.threshold,
		lastlook = snapshot.lastlook,
		target = false,
		tracer = false,
		player = false,
		subsector = false,
		snext = false,
		sprev = false,
		bnext = false,
		bprev = false,
		spawnpoint = DeepCopy(snapshot.spawnpoint),
	}

	mobj.thinker = NewThinker(mobj, Mobj.MobjThinker)

	if snapshot.player ~= 0 then
		const player = Setup.GetPlayers()[snapshot.player - 1]

		if player then
			mobj.player = player
			player.mo = mobj
		end
	end

	MapUtil.SetThingPosition(mobj)

	if mobj.subsector and mobj.subsector.sector then
		mobj.floorz = mobj.subsector.sector.floorheight
		mobj.ceilingz = mobj.subsector.sector.ceilingheight
	end

	Tick.AddThinker(mobj.thinker)

	return mobj
end

const function SnapshotSpecial(base: LooseTable, class: number, thinkerActive: boolean?)
	const snapshot = {
		class = class,
		sector = GetSectorIndex(base.sector),
		thinkerActive = thinkerActive ~= false,
	}

	for key, value in base do
		if key == "sector" or key == "thinker" then
			continue
		end

		if typeof(value) == "number" or typeof(value) == "boolean" or typeof(value) == "string" then
			snapshot[key] = value
		end
	end

	return snapshot
end

const function ApplySnapshot(target: LooseTable, snapshot: LooseTable)
	for key, value in snapshot do
		if key ~= "sector" and key ~= "class" and key ~= "thinkerActive" then
			target[key] = DeepCopy(value)
		end
	end
end

const function IsActiveCeiling(ceiling: unknown): boolean
	for i = 0, Ceiling.MAXCEILINGS - 1 do
		if Ceiling.GetActiveCeilings()[i] == ceiling then
			return true
		end
	end

	return false
end

const function IsActivePlat(plat: unknown): boolean
	for i = 0, Platforms.MAXPLATS - 1 do
		if Platforms.GetActivePlats()[i] == plat then
			return true
		end
	end

	return false
end

const function SnapshotButton(button: LooseTable, slot: number)
	return {
		class = tc_button,
		slot = slot,
		line = GetLineIndex(button.line),
		where = button.where,
		btexture = button.btexture,
		btimer = button.btimer,
	}
end

const function ResetButtons()
	const buttons = Switch.GetButtonList()

	for index = 0, Switch.MAXBUTTONS - 1 do
		const button = buttons[index]

		if button == nil then
			buttons[index] = {
				line = false,
				where = Switch.top,
				btexture = 0,
				btimer = 0,
				soundorg = false,
			}
		else
			button.line = false
			button.where = Switch.top
			button.btexture = 0
			button.btimer = 0
			button.soundorg = false
		end
	end
end

const function SnapshotSpecialThinker(thinker: LooseTable?)
	if thinker == nil or thinker["function"] == nil or IsRemovedThinker(thinker) then
		return nil
	end

	const owner = thinker.owner or thinker
	const action = thinker["function"].acp1

	if action == nil then
		if owner and IsActiveCeiling(owner) then
			return SnapshotSpecial(owner, tc_ceiling, false)
		end

		if owner and IsActivePlat(owner) then
			return SnapshotSpecial(owner, tc_plat, false)
		end

		return nil
	end

	if action == Ceiling.MoveCeiling then
		return SnapshotSpecial(owner, tc_ceiling, true)
	end

	if action == Doors.VerticalDoor then
		return SnapshotSpecial(owner, tc_door, true)
	end

	if action == Floor.MoveFloor then
		return SnapshotSpecial(owner, tc_floor, true)
	end

	if action == Platforms.PlatRaise then
		return SnapshotSpecial(owner, tc_plat, true)
	end

	if action == Lights.LightFlashTick then
		return SnapshotSpecial(owner, tc_flash, true)
	end

	if action == Lights.StrobeFlashTick then
		return SnapshotSpecial(owner, tc_strobe, true)
	end

	if action == Lights.GlowTick then
		return SnapshotSpecial(owner, tc_glow, true)
	end

	if action == Lights.FireFlickerTick then
		return SnapshotSpecial(owner, tc_fireflicker, true)
	end

	return nil
end

--
-- ArchivePlayers
--
const function ArchivePlayers()
	const players = Setup.GetPlayers()
	const player = players[0]


	save_p.players = SnapshotPlayer(player)
end

--
-- UnArchivePlayers
--
const function UnArchivePlayers()
	const snapshot = save_p.players


	const player = Setup.GetPlayers()[0]


	ApplyPlayerSnapshot(player, snapshot)
end

--
-- ArchiveWorld
--
const function ArchiveWorld()
	const sectors: LooseList = {}
	const lines: LooseList = {}

	for index = 0, State.numsectors - 1 do
		const sec = State.sectors[index]

		sectors[index] = {
			floorheight = sec.floorheight,
			ceilingheight = sec.ceilingheight,
			floorpic = sec.floorpic,
			ceilingpic = sec.ceilingpic,
			lightlevel = sec.lightlevel,
			special = sec.special,
			tag = sec.tag,
		}
	end

	for index = 0, State.numlines - 1 do
		const li = State.lines[index]
		const sides: LooseList = {}

		for side = 0, 1 do
			if li.sidenum[side] ~= -1 then
				const si = State.sides[li.sidenum[side]]

				sides[side] = {
					textureoffset = si.textureoffset,
					rowoffset = si.rowoffset,
					toptexture = si.toptexture,
					bottomtexture = si.bottomtexture,
					midtexture = si.midtexture,
				}
			end
		end

		lines[index] = {
			flags = li.flags,
			special = li.special,
			tag = li.tag,
			sides = sides,
		}
	end

	save_p.world = {
		sectors = sectors,
		lines = lines,
	}
end

--
-- UnArchiveWorld
--
const function UnArchiveWorld()
	const world = save_p.world


	for index = 0, State.numsectors - 1 do
		const sec = State.sectors[index]
		const snapshot = world.sectors[index]

		sec.floorheight = snapshot.floorheight
		sec.ceilingheight = snapshot.ceilingheight
		sec.floorpic = snapshot.floorpic
		sec.ceilingpic = snapshot.ceilingpic
		sec.lightlevel = snapshot.lightlevel
		sec.special = snapshot.special
		sec.tag = snapshot.tag
		sec.specialdata = false
		sec.soundtarget = false
	end

	for index = 0, State.numlines - 1 do
		const li = State.lines[index]
		const snapshot = world.lines[index]

		li.flags = snapshot.flags
		li.special = snapshot.special
		li.tag = snapshot.tag

		for side = 0, 1 do
			if li.sidenum[side] ~= -1 then
				const si = State.sides[li.sidenum[side]]
				const sideSnapshot = snapshot.sides[side]

				si.textureoffset = sideSnapshot.textureoffset
				si.rowoffset = sideSnapshot.rowoffset
				si.toptexture = sideSnapshot.toptexture
				si.bottomtexture = sideSnapshot.bottomtexture
				si.midtexture = sideSnapshot.midtexture
			end
		end
	end
end

--
-- ArchiveThinkers
--
const function ArchiveThinkers()
	const thinkers: LooseList = {}
	local current = Tick.GetThinkerCap().next
	const mobjs: LooseList = {}
	const archiveIndices: LooseTable = {}

	while current ~= Tick.GetThinkerCap() do
		if not IsRemovedThinker(current) and current["function"].acp1 == Mobj.MobjThinker then
			const mobj = current.owner or current

			archiveIndices[mobj] = #mobjs + 1
			mobjs[#mobjs + 1] = mobj
		end

		current = current.next
	end

	for _, mobj in mobjs do
		thinkers[#thinkers + 1] = {
			class = tc_mobj,
			mobj = SnapshotMobj(mobj, archiveIndices),
		}
	end

	thinkers[#thinkers + 1] = { class = tc_end }
	save_p.thinkers = thinkers
end

--
-- UnArchiveThinkers
--
const function UnArchiveThinkers()
	const thinkers = save_p.thinkers


	local current = Tick.GetThinkerCap().next

	while current ~= Tick.GetThinkerCap() do
		const nextThinker = current.next

		if current["function"].acp1 == Mobj.MobjThinker then
			Mobj.RemoveMobj(current.owner or current)
		end

		current = nextThinker
	end

	Tick.InitThinkers()

	const restoredMobjs: LooseList = {}
	const pendingSnapshots: LooseList = {}

	for _, entry in thinkers do
		if entry.class == tc_end then
			break
		end

		if entry.class == tc_mobj then
			restoredMobjs[#restoredMobjs + 1] = RestoreMobj(entry.mobj)
			pendingSnapshots[#pendingSnapshots + 1] = entry.mobj
		else
			error(`UnArchiveThinkers: unknown thinker class {entry.class}`)
		end
	end

	for index = 1, #restoredMobjs do
		const snapshot = pendingSnapshots[index]
		const targetIndex = if snapshot then snapshot.target or 0 else 0
		const tracerIndex = if snapshot then snapshot.tracer or 0 else 0

		if targetIndex ~= 0 then
			restoredMobjs[index].target = restoredMobjs[targetIndex] or false
		end

		if tracerIndex ~= 0 then
			restoredMobjs[index].tracer = restoredMobjs[tracerIndex] or false
		end
	end
end

--
-- ArchiveSpecials
--
const function ArchiveSpecials()
	const specials: LooseList = {}
	local current = Tick.GetThinkerCap().next

	while current ~= Tick.GetThinkerCap() do
		const snapshot = SnapshotSpecialThinker(current)

		if snapshot ~= nil then
			specials[#specials + 1] = snapshot
		end

		current = current.next
	end

	const buttons = Switch.GetButtonList()

	for index = 0, Switch.MAXBUTTONS - 1 do
		const button = buttons[index]

		if button ~= nil and button.btimer ~= 0 and button.line ~= false then
			specials[#specials + 1] = SnapshotButton(button, index)
		end
	end

	specials[#specials + 1] = { class = tc_endspecials }
	save_p.specials = specials
end

--
-- UnArchiveSpecials
--
const function UnArchiveSpecials()
	const specials = save_p.specials


	Ceiling.Reset()
	Doors.Reset()
	Floor.Reset()
	Platforms.Reset()
	Lights.Reset()
	ResetButtons()

	for _, entry in specials do
		if entry.class == tc_endspecials then
			return
		end

		const sector = if entry.sector ~= nil then State.sectors[entry.sector] else nil

		if entry.class == tc_ceiling then
			const ceiling = { sector = sector }
			ApplySnapshot(ceiling, entry)
			ceiling.thinker = NewThinker(ceiling, if entry.thinkerActive then Ceiling.MoveCeiling else nil)
			sector.specialdata = ceiling
			Tick.AddThinker(ceiling.thinker)
			Ceiling.AddActiveCeiling(ceiling)
		elseif entry.class == tc_door then
			const door = { sector = sector }
			ApplySnapshot(door, entry)
			door.thinker = NewThinker(door, Doors.VerticalDoor)
			sector.specialdata = door
			Tick.AddThinker(door.thinker)
			table.insert(Doors.GetActiveDoors(), door)
		elseif entry.class == tc_floor then
			const floor = { sector = sector }
			ApplySnapshot(floor, entry)
			floor.thinker = NewThinker(floor, Floor.MoveFloor)
			sector.specialdata = floor
			Tick.AddThinker(floor.thinker)
			table.insert(Floor.GetActiveFloors(), floor)
		elseif entry.class == tc_plat then
			const plat = { sector = sector }
			ApplySnapshot(plat, entry)
			plat.thinker = NewThinker(plat, if entry.thinkerActive then Platforms.PlatRaise else nil)
			sector.specialdata = plat
			Tick.AddThinker(plat.thinker)
			Platforms.AddActivePlat(plat)
		elseif entry.class == tc_flash then
			const flash = { sector = sector }
			ApplySnapshot(flash, entry)
			flash.thinker = NewThinker(flash, Lights.LightFlashTick)
			Tick.AddThinker(flash.thinker)
			table.insert(Lights.GetLightFlashes(), flash)
			table.insert(Lights.GetThinkers(), flash)
		elseif entry.class == tc_strobe then
			const strobe = { sector = sector }
			ApplySnapshot(strobe, entry)
			strobe.thinker = NewThinker(strobe, Lights.StrobeFlashTick)
			Tick.AddThinker(strobe.thinker)
			table.insert(Lights.GetStrobes(), strobe)
			table.insert(Lights.GetThinkers(), strobe)
		elseif entry.class == tc_glow then
			const glow = { sector = sector }
			ApplySnapshot(glow, entry)
			glow.thinker = NewThinker(glow, Lights.GlowTick)
			Tick.AddThinker(glow.thinker)
			table.insert(Lights.GetGlows(), glow)
			table.insert(Lights.GetThinkers(), glow)
		elseif entry.class == tc_fireflicker then
			const flick = { sector = sector }
			ApplySnapshot(flick, entry)
			flick.thinker = NewThinker(flick, Lights.FireFlickerTick)
			Tick.AddThinker(flick.thinker)
			table.insert(Lights.GetFireFlickers(), flick)
			table.insert(Lights.GetThinkers(), flick)
		elseif entry.class == tc_button then
			const line = State.lines[entry.line]

			if line ~= nil then
				const buttons = Switch.GetButtonList()
				const slot = entry.slot or 0
				local button = buttons[slot]

				if button == nil then
					button = {
						line = false,
						where = Switch.top,
						btexture = 0,
						btimer = 0,
						soundorg = false,
					}
					buttons[slot] = button
				end

				button.line = line
				button.where = entry.where or Switch.top
				button.btexture = entry.btexture or 0
				button.btimer = entry.btimer or 0
				button.soundorg = line.frontsector.soundorg
			end
		else
			error(`UnArchiveSpecials: unknown special class {entry.class}`)
		end
	end
end

const function SetSavePointer(value: SaveArchive)
	save_p = value
end

const function GetSavePointer()
	return save_p
end

const function ClearSavePointer()
	save_p = {}
end

return {
	SetSavePointer = SetSavePointer,
	GetSavePointer = GetSavePointer,
	ClearSavePointer = ClearSavePointer,

	ArchivePlayers = ArchivePlayers,
	UnArchivePlayers = UnArchivePlayers,
	ArchiveWorld = ArchiveWorld,
	UnArchiveWorld = UnArchiveWorld,
	ArchiveThinkers = ArchiveThinkers,
	UnArchiveThinkers = UnArchiveThinkers,
	ArchiveSpecials = ArchiveSpecials,
	UnArchiveSpecials = UnArchiveSpecials,
}
