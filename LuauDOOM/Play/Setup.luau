--!native
--!optimize 2

-- Port of p_setup.c, p_setup.h
-- Do all the WAD I/O, get map description,
-- set up initial state and misc. LUTs.
-- Note: user/game hooks, sound startup, automap side effects, and reload
-- still route through shared host/runtime wiring when they belong outside the
-- Play owner set.
-- Note: `blockmaplump` / `blockmap` are unpacked into Luau tables instead of
-- C `short*` pointers.

const Definitions = require("../Engine/Definitions")
const Fixed = require("../Miscellaneous/Fixed")
const BoundingBox = require("../Miscellaneous/BoundingBox")
const SpriteNames = require("../Doom/SpriteNames")
const Ceiling = require("./Ceiling")
const Doors = require("./Doors")
const Enemy = require("./Enemy")
const Floor = require("./Floor")
const Host = require("./Host")
const Info = require("../Doom/Info")
const Interaction = require("./Interaction")
const Lights = require("./Lights")
const Map = require("./Map")
const Mobj = require("./Mobj")
const Platforms = require("./Platforms")
const Psprites = require("./Psprites")
const Runtime = require("./Runtime")
const Sight = require("./Sight")
const RendererHost = require("../Renderer/Host")
const Sky = require("../Renderer/Sky")
const Specials = require("./Specials")
const Tick = require("./Tick")
const User = require("./User")
const WorldState = require("./WorldState")
const Data = require("../Renderer/Data")
const Draw = require("../Renderer/Draw")
const Main = require("../Renderer/Main")
const Sounds = require("../Doom/Sounds")
const State = require("../Renderer/State")
const Things = require("../Renderer/Things")
const Switch = require("./Switch")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const MAXPLAYERS = Definitions.MAXPLAYERS
const VIEWHEIGHT = 41 * Fixed.FRACUNIT

const LABEL = 0
const THINGS = 1
const LINEDEFS = 2
const SIDEDEFS = 3
const VERTEXES = 4
const SEGS = 5
const SSECTORS = 6
const NODES = 7
const SECTORS = 8
const REJECT = 9
const BLOCKMAP = 10

const TWOSIDED = 4

const SlopeHorizontal = 0
const SlopeVertical = 1
const SlopePositive = 2
const SlopeNegative = 3

const MAPBLOCKUNITS = 128
const MAPBLOCKSIZE = MAPBLOCKUNITS * Fixed.FRACUNIT
const MAPBLOCKSHIFT = Fixed.FRACBITS + 7
const MAPBMASK = MAPBLOCKSIZE - 1
const MAPBTOFRAC = MAPBLOCKSHIFT - Fixed.FRACBITS
const MAXRADIUS = 32 * Fixed.FRACUNIT

type NumberMap = { [number]: number }
type BooleanMap = { [number]: boolean }
type UnknownMap = { [number]: unknown }
type ActionMap = { [string]: unknown }
type PlayerStart = {
	x: number,
	y: number,
	angle: number,
	type: number,
	options: number,
}
type TicCmd = {
	forwardmove: number,
	sidemove: number,
	angleturn: number,
	consistancy: number,
	chatchar: number,
	buttons: number,
}
type PlayerSlot = {
	[string]: unknown,
	playerstate: number,
	cmd: TicCmd,
	killcount: number,
	secretcount: number,
	itemcount: number,
	viewz: number,
	viewheight: number,
	deltaviewheight: number,
	bob: number,
	health: number,
	armorpoints: number,
	armortype: number,
	powers: NumberMap,
	cards: BooleanMap,
	backpack: boolean,
	frags: NumberMap,
	readyweapon: number,
	pendingweapon: number,
	weaponowned: BooleanMap,
	ammo: NumberMap,
	maxammo: NumberMap,
	attackdown: boolean,
	usedown: boolean,
	cheats: number,
	refire: number,
	damagecount: number,
	bonuscount: number,
	extralight: number,
	fixedcolormap: number,
	colormap: number,
	psprites: UnknownMap,
	didsecret: boolean,
}
type WorldInfo = {
	maxfrags: number,
	partime: number,
}
type Vertex = {
	x: number,
	y: number,
}
type Sector = {
	[string]: unknown,
	index: number,
	floorheight: number,
	ceilingheight: number,
	floorpic: number,
	ceilingpic: number,
	lightlevel: number,
	special: number,
	tag: number,
	soundtraversed: number,
	blockbox: NumberMap,
	soundorg: {
		[string]: unknown,
		x: number,
		y: number,
		z: number,
	},
	validcount: number,
	linecount: number,
	lines: UnknownMap,
}
type SideDef = {
	textureoffset: number,
	rowoffset: number,
	toptexture: number,
	bottomtexture: number,
	midtexture: number,
	sector: Sector,
}
type LineDef = {
	index: number,
	v1: Vertex,
	v2: Vertex,
	dx: number,
	dy: number,
	flags: number,
	special: number,
	tag: number,
	sidenum: NumberMap,
	bbox: NumberMap,
	slopetype: number,
	frontsector: Sector,
	backsector: Sector | false,
	validcount: number,
	specialdata: unknown,
}
type Seg = {
	v1: Vertex,
	v2: Vertex,
	angle: number,
	offset: number,
	sidedef: SideDef,
	linedef: LineDef,
	frontsector: Sector,
	backsector: Sector | false,
}
type Subsector = {
	sector: Sector | false,
	numlines: number,
	firstline: number,
}
type Node = {
	x: number,
	y: number,
	dx: number,
	dy: number,
	bbox: { [number]: NumberMap },
	children: NumberMap,
}

local gamemode = Definitions.indetermined
local precache = true
local totalkills = 0
local totalitems = 0
local totalsecret = 0
local currentskill = Definitions.sk_medium
local currentepisode = 0
local currentmap = 0
local bodyqueslot = 0
local noMonsters = false
local fastParm = false

local players: { [number]: PlayerSlot } = {}
local wminfo: WorldInfo = {
	maxfrags = 0,
	partime = 0,
}

-- MAP related Lookup tables.
-- Store VERTEXES, LINEDEFS, SIDEDEFS, etc.
local numvertexes = 0
local vertexes: { [number]: Vertex } = {}

local numsegs = 0
local segs: { [number]: Seg } = {}

local numsectors = 0
local sectors: { [number]: Sector } = {}

local numsubsectors = 0
local subsectors: { [number]: Subsector } = {}

local numnodes = 0
local nodes: { [number]: Node } = {}

local numlines = 0
local lines: { [number]: LineDef } = {}

local numsides = 0
local sides: { [number]: SideDef } = {}

-- BLOCKMAP
-- Created from axis aligned bounding box
-- of the map, a rectangular array of
-- blocks of size ...
-- Used to speed up collision detection
-- by spatial subdivision in 2D.
-- Blockmap size.
local bmapwidth = 0
local bmapheight = 0 -- size in mapblocks
local blockmap: NumberMap = {}
local blockmaplump: NumberMap = {}
local bmaporgx = 0
local bmaporgy = 0
local blocklinks: UnknownMap = {}

-- REJECT
-- For fast sight rejection.
-- Speeds up enemy AI by skipping detailed
--  LineOf Sight calculation.
-- Without special effect, this could be
--  used as a PVS lookup as well.
local rejectmatrix = buffer.create(0)

-- Maintain single-player starting spots.
const playerstarts: { [number]: PlayerStart } = {}

const function SyncWorldState()
	WorldState.bmapwidth = bmapwidth
	WorldState.bmapheight = bmapheight
	WorldState.blockmap = blockmap
	WorldState.blockmaplump = blockmaplump
	WorldState.bmaporgx = bmaporgx
	WorldState.bmaporgy = bmaporgy
	WorldState.blocklinks = blocklinks
	WorldState.rejectmatrix = rejectmatrix
end

const function ToFixed(value: number): number
	return value * Fixed.FRACUNIT
end

const function ArithmeticShiftRight(value: number, shift: number): number
	return Fixed.ToSigned32(bit32.arshift(value, shift))
end

const function ReadName(data: buffer, offset: number): string
	local name = ""

	for index = 0, 7 do
		local value = buffer.readu8(data, offset + index)

		if value == 0 then
			break
		end

		if value >= 97 and value <= 122 then
			value -= 32
		end

		name ..= string.char(value)
	end

	return name
end

const function GetPlayerSlot(index: number)
	local player = players[index]

	if player == nil then
		player = players[index + 1]
	end


	return player
end

const function NewPlayerStart()
	return {
		x = 0,
		y = 0,
		angle = 0,
		type = 0,
		options = 0,
	}
end

const function NewPlayerSlot()
	const powers: NumberMap = {}
	const cards: BooleanMap = {}
	const frags: NumberMap = {}
	const weaponowned: BooleanMap = {}
	const ammo: NumberMap = {}
	const maxammo: NumberMap = {}
	const cmd = {
		forwardmove = 0,
		sidemove = 0,
		angleturn = 0,
		consistancy = 0,
		chatchar = 0,
		buttons = 0,
	}

	for index = 0, Definitions.NUMPOWERS - 1 do
		powers[index] = 0
	end

	for index = 0, Definitions.NUMCARDS - 1 do
		cards[index] = false
	end

	for index = 0, MAXPLAYERS - 1 do
		frags[index] = 0
	end

	for index = 0, Definitions.NUMWEAPONS - 1 do
		weaponowned[index] = false
	end

	for index = 0, Definitions.NUMAMMO - 1 do
		ammo[index] = 0
		maxammo[index] = Interaction.maxammo[index] or 0
	end

	weaponowned[Definitions.wp_fist] = true
	weaponowned[Definitions.wp_pistol] = true
	ammo[Definitions.am_clip] = 50

	return {
		mo = false,
		playerstate = Interaction.PST_REBORN,
		cmd = cmd,
		killcount = 0,
		secretcount = 0,
		itemcount = 0,
		viewz = 0,
		viewheight = VIEWHEIGHT,
		deltaviewheight = 0,
		bob = 0,
		health = Interaction.MAXHEALTH,
		armorpoints = 0,
		armortype = 0,
		powers = powers,
		cards = cards,
		backpack = false,
		frags = frags,
		readyweapon = Definitions.wp_pistol,
		pendingweapon = Definitions.wp_pistol,
		weaponowned = weaponowned,
		ammo = ammo,
		maxammo = maxammo,
		attackdown = false,
		usedown = false,
		cheats = 0,
		refire = 0,
		message = false,
		damagecount = 0,
		bonuscount = 0,
		attacker = false,
		extralight = 0,
		fixedcolormap = 0,
		colormap = 0,
		psprites = {},
		didsecret = false,
	}
end

const function InitializePlayers()
	table.clear(players)

	for index = 0, MAXPLAYERS - 1 do
		players[index] = NewPlayerSlot()
	end

	Tick.SetPlayers(players)
	Interaction.SetPlayers(players)
	Mobj.SetPlayers(players)
end

const function InitializePlayerStarts()
	table.clear(playerstarts)

	for index = 0, MAXPLAYERS - 1 do
		playerstarts[index] = NewPlayerStart()
	end

	Mobj.SetPlayerStarts(playerstarts)
end

const function SyncRendererState()
	State.numvertexes = numvertexes
	State.vertexes = vertexes
	State.numsegs = numsegs
	State.segs = segs
	State.numsectors = numsectors
	State.sectors = sectors
	State.numsubsectors = numsubsectors
	State.subsectors = subsectors
	State.numnodes = numnodes
	State.nodes = nodes
	State.numlines = numlines
	State.lines = lines
	State.numsides = numsides
	State.sides = sides
end

const function MergeActionMap(target: ActionMap, source: ActionMap, context: string)
	for name, action in source do

		target[name] = action
	end
end

const function ResolveInfoBindings()
	const actions: ActionMap = {}

	MergeActionMap(actions, Psprites.GetStateActions(), "ResolveInfoBindings Psprites")
	MergeActionMap(actions, Enemy.GetStateActions(), "ResolveInfoBindings Enemy")

	Info.ResolveStateActions(actions)
	Info.ResolveMobjSounds(Sounds.ByName)
end

const function UpdateSkyForLevel(episode: number, map: number)
	Sky.SetSkyFlatNum(Data.FlatNumForName(Sky.SKYFLATNAME))

	local textureName = "SKY1"

	if gamemode == Definitions.commercial then
		textureName = "SKY3"

		if map < 12 then
			textureName = "SKY1"
		elseif map < 21 then
			textureName = "SKY2"
		end
	else
		if episode == 2 then
			textureName = "SKY2"
		elseif episode == 3 then
			textureName = "SKY3"
		elseif episode == 4 then
			textureName = "SKY4"
		end
	end

	Sky.SetSkyTexture(Data.TextureNumForName(textureName))
end

const function ResetMapData()
	numvertexes = 0
	vertexes = {}
	numsegs = 0
	segs = {}
	numsectors = 0
	sectors = {}
	numsubsectors = 0
	subsectors = {}
	numnodes = 0
	nodes = {}
	numlines = 0
	lines = {}
	numsides = 0
	sides = {}
	bmapwidth = 0
	bmapheight = 0
	blockmap = {}
	blockmaplump = {}
	bmaporgx = 0
	bmaporgy = 0
	blocklinks = {}
	rejectmatrix = buffer.create(0)
	SyncWorldState()

	SyncRendererState()
end

const function Reset()
	ResetMapData()
	Ceiling.Reset()
	Doors.Reset()
	Floor.Reset()
	Lights.Reset()
	Map.Reset()
	Mobj.Reset()
	Interaction.Reset()
	Platforms.Reset()
	Enemy.Reset()
	Specials.Reset()
	Sight.Reset()
	Tick.Reset()
	Psprites.Reset()
	User.Reset()
	totalkills = 0
	totalitems = 0
	totalsecret = 0
	currentskill = Definitions.sk_medium
	currentepisode = 0
	currentmap = 0
	bodyqueslot = 0
	noMonsters = false
	fastParm = false
	wminfo.maxfrags = 0
	wminfo.partime = 0

	InitializePlayers()
	InitializePlayerStarts()
end

const function ReadMapThing(data: buffer, offset: number)
	return {
		x = buffer.readi16(data, offset),
		y = buffer.readi16(data, offset + 2),
		angle = buffer.readi16(data, offset + 4),
		type = buffer.readi16(data, offset + 6),
		options = buffer.readi16(data, offset + 8),
	}
end

-- LoadVertexes
const function LoadVertexes(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numvertexes = length // 4
	vertexes = {}

	for index = 0, numvertexes - 1 do
		const offset = index * 4

		vertexes[index] = {
			x = ToFixed(buffer.readi16(data, offset)),
			y = ToFixed(buffer.readi16(data, offset + 2)),
		}
	end

	SyncRendererState()
end

-- LoadSegs
const function LoadSegs(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numsegs = length // 12
	segs = {}

	for index = 0, numsegs - 1 do
		const offset = index * 12
		const v1 = vertexes[buffer.readi16(data, offset)]
		const v2 = vertexes[buffer.readi16(data, offset + 2)]
		const linedef = lines[buffer.readi16(data, offset + 6)]
		const sideIndex = buffer.readi16(data, offset + 8)
		const sideNumber = linedef.sidenum[sideIndex]
		const sidedef = sides[sideNumber]
		const frontsector = sidedef.sector
		local backsector = false

		if bit32.btest(linedef.flags, TWOSIDED) then
			backsector = sides[linedef.sidenum[bit32.bxor(sideIndex, 1)]].sector
		end

		segs[index] = {
			v1 = v1,
			v2 = v2,
			angle = buffer.readi16(data, offset + 4) * 65536,
			offset = ToFixed(buffer.readi16(data, offset + 10)),
			sidedef = sidedef,
			linedef = linedef,
			frontsector = frontsector,
			backsector = backsector,
		}
	end

	SyncRendererState()
end

-- LoadSubsectors
const function LoadSubsectors(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numsubsectors = length // 4
	subsectors = {}

	for index = 0, numsubsectors - 1 do
		const offset = index * 4

		subsectors[index] = {
			sector = false,
			numlines = buffer.readi16(data, offset),
			firstline = buffer.readi16(data, offset + 2),
		}
	end

	SyncRendererState()
end

-- LoadSectors
const function LoadSectors(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numsectors = length // 26
	sectors = {}

	for index = 0, numsectors - 1 do
		const offset = index * 26

		sectors[index] = {
			index = index,
			floorheight = ToFixed(buffer.readi16(data, offset)),
			ceilingheight = ToFixed(buffer.readi16(data, offset + 2)),
			floorpic = Data.FlatNumForName(ReadName(data, offset + 4)),
			ceilingpic = Data.FlatNumForName(ReadName(data, offset + 12)),
			lightlevel = buffer.readi16(data, offset + 20),
			special = buffer.readi16(data, offset + 22),
			tag = buffer.readi16(data, offset + 24),
			soundtraversed = 0,
			soundtarget = false,
			blockbox = {
				[BoundingBox.BOXTOP] = 0,
				[BoundingBox.BOXBOTTOM] = 0,
				[BoundingBox.BOXLEFT] = 0,
				[BoundingBox.BOXRIGHT] = 0,
			},
			soundorg = {
				thinker = false,
				x = 0,
				y = 0,
				z = 0,
			},
			validcount = 0,
			thinglist = false,
			specialdata = false,
			linecount = 0,
			lines = {},
		}

		sectors[index].renderPrevFloorHeight = sectors[index].floorheight
		sectors[index].renderPrevCeilingHeight = sectors[index].ceilingheight
		sectors[index].renderFloorHeight = sectors[index].floorheight
		sectors[index].renderCeilingHeight = sectors[index].ceilingheight
	end

	SyncRendererState()
end

-- LoadNodes
const function LoadNodes(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numnodes = length // 28
	nodes = {}

	for index = 0, numnodes - 1 do
		const offset = index * 28
		const bbox = {
			[0] = {},
			[1] = {},
		}

		for child = 0, 1 do
			const bboxOffset = offset + 8 + child * 8

			for coord = 0, 3 do
				bbox[child][coord] = ToFixed(buffer.readi16(data, bboxOffset + coord * 2))
			end
		end

		nodes[index] = {
			x = ToFixed(buffer.readi16(data, offset)),
			y = ToFixed(buffer.readi16(data, offset + 2)),
			dx = ToFixed(buffer.readi16(data, offset + 4)),
			dy = ToFixed(buffer.readi16(data, offset + 6)),
			bbox = bbox,
			children = {
				[0] = buffer.readu16(data, offset + 24),
				[1] = buffer.readu16(data, offset + 26),
			},
		}
	end

	SyncRendererState()
end

-- LoadThings
const function LoadThings(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)
	const numthings = length // 10

	for index = 0, numthings - 1 do
		const mthing = ReadMapThing(data, index * 10)
		local spawn = true

		-- Do not spawn cool, new monsters if !commercial
		if gamemode ~= Definitions.commercial then
			if mthing.type == 68
				or mthing.type == 64
				or mthing.type == 88
				or mthing.type == 89
				or mthing.type == 69
				or mthing.type == 67
				or mthing.type == 71
				or mthing.type == 65
				or mthing.type == 66
				or mthing.type == 84 then
				spawn = false
			end
		end

		if spawn == false then
			continue
		end

		Mobj.SpawnMapThing(mthing)
	end
end

-- LoadLineDefs
-- Also counts secret lines for intermissions.
const function LoadLineDefs(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numlines = length // 14
	lines = {}

	for index = 0, numlines - 1 do
		const offset = index * 14
		const v1 = vertexes[buffer.readi16(data, offset)]
		const v2 = vertexes[buffer.readi16(data, offset + 2)]
		const dx = v2.x - v1.x
		const dy = v2.y - v1.y
		local slopetype

		if dx == 0 then
			slopetype = SlopeVertical
		elseif dy == 0 then
			slopetype = SlopeHorizontal
		elseif Fixed.FixedDiv(dy, dx) > 0 then
			slopetype = SlopePositive
		else
			slopetype = SlopeNegative
		end

		const bbox = {
			[BoundingBox.BOXTOP] = if v1.y < v2.y then v2.y else v1.y,
			[BoundingBox.BOXBOTTOM] = if v1.y < v2.y then v1.y else v2.y,
			[BoundingBox.BOXLEFT] = if v1.x < v2.x then v1.x else v2.x,
			[BoundingBox.BOXRIGHT] = if v1.x < v2.x then v2.x else v1.x,
		}

		const sidenum0 = buffer.readi16(data, offset + 10)
		const sidenum1 = buffer.readi16(data, offset + 12)
		local frontsector = false
		local backsector = false

		if sidenum0 ~= -1 then
			frontsector = sides[sidenum0].sector
		end

		if sidenum1 ~= -1 then
			backsector = sides[sidenum1].sector
		end

		lines[index] = {
			index = index,
			v1 = v1,
			v2 = v2,
			dx = dx,
			dy = dy,
			flags = buffer.readi16(data, offset + 4),
			special = buffer.readi16(data, offset + 6),
			tag = buffer.readi16(data, offset + 8),
			sidenum = {
				[0] = sidenum0,
				[1] = sidenum1,
			},
			bbox = bbox,
			slopetype = slopetype,
			frontsector = frontsector,
			backsector = backsector,
			validcount = 0,
			specialdata = false,
		}
	end

	SyncRendererState()
end

-- LoadSideDefs
const function LoadSideDefs(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.STATIC)

	numsides = length // 30
	sides = {}

	for index = 0, numsides - 1 do
		const offset = index * 30

		sides[index] = {
			textureoffset = ToFixed(buffer.readi16(data, offset)),
			rowoffset = ToFixed(buffer.readi16(data, offset + 2)),
			toptexture = Data.TextureNumForName(ReadName(data, offset + 4)),
			bottomtexture = Data.TextureNumForName(ReadName(data, offset + 12)),
			midtexture = Data.TextureNumForName(ReadName(data, offset + 20)),
			sector = sectors[buffer.readi16(data, offset + 28)],
		}
	end

	SyncRendererState()
end

-- LoadBlockMap
const function LoadBlockMap(lump: number)
	const length = Wad.LumpLength(lump)

	const data = Wad.CacheLumpNum(lump, Zone.LEVEL)
	const count = length // 2

	blockmaplump = {}

	for index = 0, count - 1 do
		blockmaplump[index] = buffer.readi16(data, index * 2)
	end

	blockmap = {}

	for index = 4, count - 1 do
		blockmap[index - 4] = blockmaplump[index]
	end

	bmaporgx = ToFixed(blockmaplump[0])
	bmaporgy = ToFixed(blockmaplump[1])
	bmapwidth = blockmaplump[2]
	bmapheight = blockmaplump[3]

	blocklinks = {}

	for index = 0, bmapwidth * bmapheight - 1 do
		blocklinks[index] = false
	end

	SyncWorldState()
end

-- GroupLines
-- Builds sector line lists and subsector sector numbers.
-- Finds block bounding boxes for sectors.
const function GroupLines()
	-- look up sector number for each subsector
	for index = 0, numsubsectors - 1 do
		const subsector = subsectors[index]
		const seg = segs[subsector.firstline]

		subsector.sector = seg.sidedef.sector
	end

	-- count number of lines in each sector
	for index = 0, numlines - 1 do
		const line = lines[index]

		line.frontsector.linecount += 1

		if line.backsector and line.backsector ~= line.frontsector then
			line.backsector.linecount += 1
		end
	end

	-- build line tables for each sector
	for sectorIndex = 0, numsectors - 1 do
		const sector = sectors[sectorIndex]
		const bbox = BoundingBox.Create()
		local linecount = 0

		BoundingBox.ClearBox(bbox)
		sector.lines = {}

		for lineIndex = 0, numlines - 1 do
			const line = lines[lineIndex]

			if line.frontsector == sector or line.backsector == sector then
				sector.lines[linecount] = line
				linecount += 1
				BoundingBox.AddToBox(bbox, line.v1.x, line.v1.y)
				BoundingBox.AddToBox(bbox, line.v2.x, line.v2.y)
			end
		end


		-- set the degenmobj_t to the middle of the bounding box
		const bboxRight = buffer.readi32(bbox, BoundingBox.BOXRIGHT * 4)
		const bboxLeft = buffer.readi32(bbox, BoundingBox.BOXLEFT * 4)
		const bboxTop = buffer.readi32(bbox, BoundingBox.BOXTOP * 4)
		const bboxBottom = buffer.readi32(bbox, BoundingBox.BOXBOTTOM * 4)
		sector.soundorg.x = math.modf((bboxRight + bboxLeft) / 2)
		sector.soundorg.y = math.modf((bboxTop + bboxBottom) / 2)

		-- adjust bounding box to map blocks
		local block = ArithmeticShiftRight(bboxTop - bmaporgy + MAXRADIUS, MAPBLOCKSHIFT)
		block = if block >= bmapheight then bmapheight - 1 else block
		sector.blockbox[BoundingBox.BOXTOP] = block

		block = ArithmeticShiftRight(bboxBottom - bmaporgy - MAXRADIUS, MAPBLOCKSHIFT)
		block = if block < 0 then 0 else block
		sector.blockbox[BoundingBox.BOXBOTTOM] = block

		block = ArithmeticShiftRight(bboxRight - bmaporgx + MAXRADIUS, MAPBLOCKSHIFT)
		block = if block >= bmapwidth then bmapwidth - 1 else block
		sector.blockbox[BoundingBox.BOXRIGHT] = block

		block = ArithmeticShiftRight(bboxLeft - bmaporgx - MAXRADIUS, MAPBLOCKSHIFT)
		block = if block < 0 then 0 else block
		sector.blockbox[BoundingBox.BOXLEFT] = block
	end

	SyncRendererState()
end

const function BuildMapLumpName(episode: number, map: number): string
	if gamemode == Definitions.commercial then
		if map < 10 then
			return `MAP0{map}`
		end

		return `MAP{map}`
	end

	return `E{episode}M{map}`
end

-- SetupLevel
const function SetupLevel(episode: number, map: number, _playermask: number, skill: number)
	const player = GetPlayerSlot(0)

	if skill == nil then
		skill = currentskill
	end

	totalkills = 0
	totalitems = 0
	totalsecret = 0
	currentskill = skill
	Mobj.SetGameSkill(skill)
	Interaction.SetGameSkill(skill)
	Enemy.SetGameSkill(skill)
	currentepisode = episode
	currentmap = map
	Enemy.SetCurrentEpisode(episode)
	Enemy.SetCurrentMap(map)
	UpdateSkyForLevel(episode, map)
	wminfo.maxfrags = 0
	wminfo.partime = 180
	player.killcount = 0
	player.secretcount = 0
	player.itemcount = 0
	for index = 0, MAXPLAYERS - 1 do
		player.frags[index] = 0
	end

	if player.playerstate == Interaction.PST_REBORN then
		player.attackdown = true
		player.usedown = true
	end

	-- Initial height of PointOfView
	-- will be set by player think.
	player.viewz = 1

	-- Make sure all sounds are stopped before FreeTags.
	Host.startSoundSystem()

	Zone.FreeTags(Zone.LEVEL, Zone.PURGELEVEL - 1)
	ResetMapData()
	Ceiling.Reset()
	Doors.Reset()
	Floor.Reset()
	Lights.Reset()
	Map.Reset()
	Platforms.Reset()

	Tick.InitThinkers()

	-- if working with a development map, reload it
	Host.reloadWad()

	const lumpnum = Wad.GetNumForName(BuildMapLumpName(episode, map))

	Tick.SetLevelTime(0)

	-- note: most of this ordering is important
	LoadBlockMap(lumpnum + BLOCKMAP)
	LoadVertexes(lumpnum + VERTEXES)
	LoadSectors(lumpnum + SECTORS)
	LoadSideDefs(lumpnum + SIDEDEFS)
	LoadLineDefs(lumpnum + LINEDEFS)
	LoadSubsectors(lumpnum + SSECTORS)
	LoadNodes(lumpnum + NODES)
	LoadSegs(lumpnum + SEGS)

	rejectmatrix = Wad.CacheLumpNum(lumpnum + REJECT, Zone.LEVEL)
	SyncWorldState()
	GroupLines()

	bodyqueslot = 0
	LoadThings(lumpnum + THINGS)

	-- clear special respawning que
	Mobj.ClearItemRespawnQueue()

	-- set up world state
	totalsecret = Specials.SpawnSpecials()

	-- preload graphics
	if precache then
		Data.PrecacheLevel()
	end
end

const function AddTotalKills(value: number)
	totalkills += value
end

const function AddTotalItems(value: number)
	totalitems += value
end

const function GetMapNumber(): number
	return currentmap
end

-- Init
const function Init()
	Switch.SetGameMode(gamemode)
	Tick.SetPlayers(players)
	Mobj.SetGameSkill(currentskill)
	Mobj.SetNoMonsters(noMonsters)
	Interaction.SetPlayers(players)
	Interaction.SetGameMode(gamemode)
	Interaction.SetGameSkill(currentskill)
	Enemy.SetGameMode(gamemode)
	Enemy.SetGameSkill(currentskill)
	Enemy.SetFastParm(fastParm)
	User.SetGameMode(gamemode)
	Psprites.SetGameMode(gamemode)
	Draw.SetGameMode(gamemode)
	Psprites.SetWeaponInfo(Interaction.weaponinfo)
	Main.Init()
	RendererHost.getThinkerCap = Tick.GetThinkerCap
	RendererHost.mobjThinker = Mobj.MobjThinker
	Runtime.Configure({
		addThinker = Tick.AddThinker,
		removeThinker = Tick.RemoveThinker,
		getThinkerCap = Tick.GetThinkerCap,
		changeSector = Map.ChangeSector,
		movePlane = Floor.MovePlane,
		startSound = Host.startSound,
		stopSound = Host.stopSound,
		getLevelTime = Tick.GetLevelTime,
		damageMobj = Interaction.DamageMobj,
		spawnMobj = Mobj.SpawnMobj,
		spawnPlayerMissile = Mobj.SpawnPlayerMissile,
		playerThink = if Host.playerThink ~= nil then Host.playerThink else User.PlayerThink,
		respawnSpecials = Mobj.RespawnSpecials,
		setMobjState = Mobj.SetMobjState,
		removeMobj = Mobj.RemoveMobj,
		spawnPuff = Mobj.SpawnPuff,
		spawnBlood = Mobj.SpawnBlood,
		noiseAlert = Enemy.NoiseAlert,
		setupPsprites = Psprites.SetupPsprites,
		playerReborn = Host.playerReborn,
		startStatus = Host.startStatus,
		startHUD = Host.startHUD,
		dropWeapon = if Host.dropWeapon ~= nil then Host.dropWeapon else Psprites.DropWeapon,
		stopAutomap = Host.stopAutomap,
		getAutomapActive = Host.getAutomapActive,
		tactile = Host.tactile,
		addTotalKills = AddTotalKills,
		addTotalItems = AddTotalItems,
		touchSpecialThing = Interaction.TouchSpecialThing,
		crossSpecialLine = Specials.CrossSpecialLine,
		useLines = if Host.useLines ~= nil then Host.useLines else Map.UseLines,
		useSpecialLine = Switch.UseSpecialLine,
		shootSpecialLine = Specials.ShootSpecialLine,
		checkSight = Sight.CheckSight,
		getMapNumber = GetMapNumber,
		verticalDoor = Doors.ActivateVerticalDoor,
		buildStairs = Floor.BuildStairs,
		doDonut = Specials.DoDonut,
		exitLevel = Host.exitLevel,
		secretExitLevel = Host.secretExitLevel,
		doFloor = Floor.DoFloor,
		doPlat = Platforms.DoPlat,
		doCeiling = Ceiling.DoCeiling,
		doDoor = Doors.DoDoor,
		doLockedDoor = Doors.DoLockedDoor,
		lightTurnOn = Lights.LightTurnOn,
	})
	ResolveInfoBindings()
	Switch.InitSwitchList()
	Specials.InitPicAnimations()
	Things.InitSprites(SpriteNames.sprnames)
end

const function SetGameMode(value: number)
	gamemode = value
	Switch.SetGameMode(value)
	Interaction.SetGameMode(value)
	Enemy.SetGameMode(value)
	User.SetGameMode(value)
	Psprites.SetGameMode(value)
	Draw.SetGameMode(value)
end

const function GetGameMode(): number
	return gamemode
end

const function SetPrecache(value: boolean)
	precache = value
end

const function GetPrecache(): boolean
	return precache
end

const function SetNoMonsters(value: boolean)
	noMonsters = value
	Mobj.SetNoMonsters(value)
end

const function GetNoMonsters(): boolean
	return noMonsters
end

const function SetRespawnMonsters(value: boolean)
	Mobj.SetRespawnMonsters(value)
end

const function GetRespawnMonsters(): boolean
	return Mobj.GetRespawnMonsters()
end

const function SetFastParm(value: boolean)
	fastParm = value
	Enemy.SetFastParm(value)
end

const function GetFastParm(): boolean
	return fastParm
end

const function SetPlayers(value: { [number]: PlayerSlot })
	players = value
	Tick.SetPlayers(value)
	Interaction.SetPlayers(value)
	Mobj.SetPlayers(value)
end

const function GetPlayers(): { [number]: PlayerSlot }
	return players
end

const function SetWorldInfo(value: WorldInfo)
	wminfo = value
	wminfo.maxfrags = wminfo.maxfrags or 0
	wminfo.partime = wminfo.partime or 0
end

const function GetWorldInfo(): WorldInfo
	return wminfo
end

const function GetPlayerStarts(): { [number]: PlayerStart }
	return playerstarts
end

const function GetTotalKills(): number
	return totalkills
end

const function SetTotalKills(value: number)
	totalkills = value
end

const function GetTotalItems(): number
	return totalitems
end

const function SetTotalItems(value: number)
	totalitems = value
end

const function GetTotalSecret(): number
	return totalsecret
end

const function SetTotalSecret(value: number)
	totalsecret = value
end

const function GetLevelTime(): number
	return Tick.GetLevelTime()
end

const function GetThinkerCap()
	return Tick.GetThinkerCap()
end

const function SetLevelTime(value: number)
	Tick.SetLevelTime(value)
end

const function GetCurrentSkill(): number
	return currentskill
end

const function SetCurrentSkill(value: number)
	currentskill = value
	Mobj.SetGameSkill(value)
	Interaction.SetGameSkill(value)
	Enemy.SetGameSkill(value)
end

const function GetCurrentEpisode(): number
	return currentepisode
end

const function GetCurrentMap(): number
	return currentmap
end

const function GetBodyQueSlot(): number
	return bodyqueslot
end

const function SetBodyQueSlot(value: number)
	bodyqueslot = value
end

const function GetIQueHead(): number
	return Mobj.GetIQueHead()
end

const function SetIQueHead(value: number)
	error("SetIQueHead: item respawn queue is owned by Play/Mobj")
end

const function GetIQueTail(): number
	return Mobj.GetIQueTail()
end

const function SetIQueTail(value: number)
	error("SetIQueTail: item respawn queue is owned by Play/Mobj")
end

const function GetNumVertexes(): number
	return numvertexes
end

const function GetVertexes(): { [number]: Vertex }
	return vertexes
end

const function GetNumSegs(): number
	return numsegs
end

const function GetSegs(): { [number]: Seg }
	return segs
end

const function GetNumSectors(): number
	return numsectors
end

const function GetSectors(): { [number]: Sector }
	return sectors
end

const function GetNumSubsectors(): number
	return numsubsectors
end

const function GetSubsectors(): { [number]: Subsector }
	return subsectors
end

const function GetNumNodes(): number
	return numnodes
end

const function GetNodes(): { [number]: Node }
	return nodes
end

const function GetNumLines(): number
	return numlines
end

const function GetLines(): { [number]: LineDef }
	return lines
end

const function GetNumSides(): number
	return numsides
end

const function GetSides(): { [number]: SideDef }
	return sides
end

const function GetBlockMapWidth(): number
	return bmapwidth
end

const function GetBlockMapHeight(): number
	return bmapheight
end

const function GetBlockMap(): NumberMap
	return blockmap
end

const function GetBlockMapLump(): NumberMap
	return blockmaplump
end

const function GetBlockLinks(): UnknownMap
	return blocklinks
end

const function GetBlockMapOriginX(): number
	return bmaporgx
end

const function GetBlockMapOriginY(): number
	return bmaporgy
end

const function GetRejectMatrix(): buffer
	return rejectmatrix
end

Reset()

const Setup = {
	LABEL = LABEL,
	THINGS = THINGS,
	LINEDEFS = LINEDEFS,
	SIDEDEFS = SIDEDEFS,
	VERTEXES = VERTEXES,
	SEGS = SEGS,
	SSECTORS = SSECTORS,
	NODES = NODES,
	SECTORS = SECTORS,
	REJECT = REJECT,
	BLOCKMAP = BLOCKMAP,
	TWOSIDED = TWOSIDED,

	SlopeHorizontal = SlopeHorizontal,
	SlopeVertical = SlopeVertical,
	SlopePositive = SlopePositive,
	SlopeNegative = SlopeNegative,

	MAPBLOCKUNITS = MAPBLOCKUNITS,
	MAPBLOCKSIZE = MAPBLOCKSIZE,
	MAPBLOCKSHIFT = MAPBLOCKSHIFT,
	MAPBMASK = MAPBMASK,
	MAPBTOFRAC = MAPBTOFRAC,
	MAXRADIUS = MAXRADIUS,

	Reset = Reset,
	ResetMapData = ResetMapData,
	SetGameMode = SetGameMode,
	GetGameMode = GetGameMode,
	SetPrecache = SetPrecache,
	GetPrecache = GetPrecache,
	SetNoMonsters = SetNoMonsters,
	GetNoMonsters = GetNoMonsters,
	SetRespawnMonsters = SetRespawnMonsters,
	GetRespawnMonsters = GetRespawnMonsters,
	SetFastParm = SetFastParm,
	GetFastParm = GetFastParm,
	SetPaused = Tick.SetPaused,
	GetPaused = Tick.GetPaused,
	SetMenuActive = Tick.SetMenuActive,
	GetMenuActive = Tick.GetMenuActive,
	SetDemoPlayback = Tick.SetDemoPlayback,
	GetDemoPlayback = Tick.GetDemoPlayback,
	SetPlayers = SetPlayers,
	GetPlayers = GetPlayers,
	SetWorldInfo = SetWorldInfo,
	GetWorldInfo = GetWorldInfo,
	GetPlayerStarts = GetPlayerStarts,
	GetTotalKills = GetTotalKills,
	SetTotalKills = SetTotalKills,
	GetTotalItems = GetTotalItems,
	SetTotalItems = SetTotalItems,
	GetTotalSecret = GetTotalSecret,
	SetTotalSecret = SetTotalSecret,
	GetLevelTime = GetLevelTime,
	GetThinkerCap = GetThinkerCap,
	SetLevelTime = SetLevelTime,
	GetCurrentSkill = GetCurrentSkill,
	SetCurrentSkill = SetCurrentSkill,
	GetCurrentEpisode = GetCurrentEpisode,
	GetCurrentMap = GetCurrentMap,
	GetBodyQueSlot = GetBodyQueSlot,
	SetBodyQueSlot = SetBodyQueSlot,
	GetIQueHead = GetIQueHead,
	SetIQueHead = SetIQueHead,
	GetIQueTail = GetIQueTail,
	SetIQueTail = SetIQueTail,

	LoadVertexes = LoadVertexes,
	LoadSegs = LoadSegs,
	LoadSubsectors = LoadSubsectors,
	LoadSectors = LoadSectors,
	LoadNodes = LoadNodes,
	LoadThings = LoadThings,
	LoadLineDefs = LoadLineDefs,
	LoadSideDefs = LoadSideDefs,
	LoadBlockMap = LoadBlockMap,
	GroupLines = GroupLines,
	SetupLevel = SetupLevel,
	Init = Init,

	GetNumVertexes = GetNumVertexes,
	GetVertexes = GetVertexes,
	GetNumSegs = GetNumSegs,
	GetSegs = GetSegs,
	GetNumSectors = GetNumSectors,
	GetSectors = GetSectors,
	GetNumSubsectors = GetNumSubsectors,
	GetSubsectors = GetSubsectors,
	GetNumNodes = GetNumNodes,
	GetNodes = GetNodes,
	GetNumLines = GetNumLines,
	GetLines = GetLines,
	GetNumSides = GetNumSides,
	GetSides = GetSides,
	GetBlockMapWidth = GetBlockMapWidth,
	GetBlockMapHeight = GetBlockMapHeight,
	GetBlockMap = GetBlockMap,
	GetBlockMapLump = GetBlockMapLump,
	GetBlockLinks = GetBlockLinks,
	GetBlockMapOriginX = GetBlockMapOriginX,
	GetBlockMapOriginY = GetBlockMapOriginY,
	GetRejectMatrix = GetRejectMatrix,

	InitThinkers = Tick.InitThinkers,
	RunThinkers = Tick.RunThinkers,
	Ticker = Tick.Ticker,
}

Setup.LoadVertexes = LoadVertexes
Setup.LoadSegs = LoadSegs
Setup.LoadSubsectors = LoadSubsectors
Setup.LoadSectors = LoadSectors
Setup.LoadNodes = LoadNodes
Setup.LoadThings = LoadThings
Setup.LoadLineDefs = LoadLineDefs
Setup.LoadSideDefs = LoadSideDefs
Setup.LoadBlockMap = LoadBlockMap
Setup.GroupLines = GroupLines
Setup.SetupLevel = SetupLevel
Setup.Init = Init

return Setup
