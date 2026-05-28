--!native
--!optimize 2

-- Public engine entry point.
-- Mirrors the README API.
-- `require("@self/Src")` returns a singleton with:
-- `init(config?)`, `reset()`, `loadIWAD(buffer | { data = buffer })`, `loadPWAD(buffer | { data = buffer })`,
-- `clearPWADs()`, `startNewGame(skill, episode, map)`, `loadMap(episode, map)`,
-- `playDemo(name)`,
-- `startMenu()`, `startTitle()`, `saveGame(slot, desc)`, `loadGame(slot)`,
-- `setSound(soundId, moduleInfo, parent?)`,
-- `addOST(name, soundId)`,
-- `SetScreenshot(callback)`,
-- `clearInput()`, `setInput(action, value)`,
-- `keyDown(keyCode)`, `keyUp(keyCode)`, `setMouseDelta(dx, dy)`,
-- `advanceFrame(dt?) -> buffer`.

const Intermission = require("@self/Interface/Intermission")
const RendererRuntime = require("@self/Renderer/Runtime")
const SpriteState = require("@self/Renderer/SpriteState")
const Definitions = require("@self/Engine/Definitions")
const Interaction = require("@self/Play/Interaction")
const Random = require("@self/Miscellaneous/Random")
const RendererHost = require("@self/Renderer/Host")
const VideoMode = require("@self/System/VideoMode")
const Automap = require("@self/Interface/Automap")
const Fixed = require("@self/Miscellaneous/Fixed")
const Finale = require("@self/Interface/Finale")
const Status = require("@self/Interface/Status")
const Things = require("@self/Renderer/Things")
const SaveGame = require("@self/Play/SaveGame")
const Title = require("@self/Interface/Title")
const Cheats = require("@self/Engine/Cheats")
const Runtime = require("@self/Play/Runtime")
const Shared = require("@self/Engine/Shared")
const Plane = require("@self/Renderer/Plane")
const State = require("@self/Renderer/State")
const Timing = require("@self/Engine/Timing")
const Menu = require("@self/Interface/Menu")
const Input = require("@self/Engine/Input")
const Draw = require("@self/Renderer/Draw")
const Main = require("@self/Renderer/Main")
const Segs = require("@self/Renderer/Segs")
const Data = require("@self/Renderer/Data")
const Sound = require("@self/System/Sound")
const Video = require("@self/System/Video")
const HUD = require("@self/Interface/HUD")
const Demo = require("@self/Engine/Demo")
const Doors = require("@self/Play/Doors")
const Bsp = require("@self/Renderer/Bsp")
const Setup = require("@self/Play/Setup")
const Wipe = require("@self/System/Wipe")
const Zone = require("@self/System/Zone")
const Info = require("@self/Doom/Info")
const Host = require("@self/Play/Host")
const Wad = require("@self/System/Wad")

const VIEWHEIGHT = 41 * Fixed.FRACUNIT
const SPECIAL = 128
const SPECIALMASK = 3
const BTS_PAUSE = 1
const BTS_SAVEGAME = 2
const BTS_SAVEMASK = 4 + 8 + 16
const TURBOTHRESHOLD = 0x32
const PST_LIVE = 0
const PST_DEAD = 1
const PST_REBORN = 2
const PARS = {
	[1] = { 30, 75, 120, 90, 165, 180, 180, 30, 165 },
	[2] = { 90, 90, 90, 120, 90, 360, 240, 30, 170 },
	[3] = { 90, 45, 90, 150, 90, 90, 165, 30, 135 },
}
const CPARS = {
	30, 90, 120, 120, 90, 150, 120, 120, 270, 90,
	210, 150, 150, 150, 210, 150, 420, 150, 210, 150,
	240, 150, 180, 150, 150, 300, 330, 420, 300, 180,
	120, 30,
}

type DemoCommand = {
	forwardmove: number,
	sidemove: number,
	angleturn: number,
	consistancy: number,
	chatchar: number,
	buttons: number,
}
type EngineConfig = {
	screenWidth: number?,
	screenHeight: number?,
	devparm: boolean?,
}
type CallbackMap = { [string]: unknown }
type WadSoundInfo = {
	name: string?,
	priority: number?,
	link: number?,
	volume: number?,
	range: { number }?,
}
type WadData = {
	data: buffer,
	id: string?,
	label: string?,
	name: string?,
	lumpCount: number?,
	soundCount: number?,
	sounds: { [number]: WadSoundInfo }?,
	overriddenSounds: { [number]: boolean }?,
}
type WADLoadInfo = {
	data: buffer,
	id: string?,
	label: string?,
	lumpCount: number?,
	soundCount: number?,
	module: WadData?,
	sounds: { [number]: WadSoundInfo }?,
	overriddenSounds: { [number]: boolean }?,
}
type MobjState = {
	x: number,
	y: number,
	z: number,
	angle: number,
	flags: number,
	renderPrevX: number?,
	renderPrevY: number?,
	renderPrevZ: number?,
	renderPrevAngle: number?,
}
type PlayerSpriteState = {
	sx: number?,
	sy: number?,
	renderPrevSX: number?,
	renderPrevSY: number?,
}
type PlayerState = {
	ammo: { [number]: number },
	armorpoints: number,
	armortype: number,
	attacker: unknown,
	attackdown: boolean,
	backpack: boolean,
	bob: number,
	bonuscount: number,
	cards: { [number]: boolean },
	cheats: number,
	cmd: DemoCommand,
	colormap: number,
	damagecount: number,
	deltaviewheight: number,
	didsecret: boolean,
	extralight: number,
	fixedcolormap: number,
	frags: unknown,
	health: number,
	itemcount: number,
	killcount: number,
	maxammo: { [number]: number },
	message: string | false,
	mo: MobjState | false,
	pendingweapon: number,
	playerstate: number,
	powers: { [number]: number },
	psprites: { [number]: PlayerSpriteState },
	readyweapon: number,
	refire: number,
	renderPrevViewZ: number?,
	secretcount: number,
	usedown: boolean,
	viewheight: number,
	viewz: number,
	weaponowned: { [number]: boolean },
}
type SectorState = {
	floorheight: number,
	ceilingheight: number,
	renderPrevFloorHeight: number?,
	renderPrevCeilingHeight: number?,
	renderFloorHeight: number?,
	renderCeilingHeight: number?,
}
type SaveSlot = {
	description: string,
	version: number,
	episode: number,
	map: number,
	skill: number,
	playeringame: { [number]: boolean },
	leveltime: number,
	totalkills: number,
	totalitems: number,
	totalsecret: number,
	fastParm: boolean,
	respawnMonsters: boolean,
	save: unknown,
	endMarker: number,
}
type TimingOptions = {
	noDrawers: boolean?,
	noBlit: boolean?,
	startTime: number?,
	startGameTic: number?,
	lastReport: unknown?,
}

local blankFrame = buffer.create(0)
local rgbaFrame = buffer.create(0)
local indexedFrameSizeCached = 0
local rgbaFrameSizeCached = 0
const rgbaPaletteCache = buffer.create(256 * 4)
local rgbaPaletteCacheSource = buffer.create(0)
local rgbaPaletteCacheBase = -1
local rgbaPaletteCacheGamma = -1
local presentedIndexedFrame = buffer.create(0)
local playpal = buffer.create(0)
local initialized = false
local hasIWAD = false
local runtimeReady = false
local mapLoaded = false
local currentGameMode = Definitions.indetermined
local currentGameState = Definitions.LEVEL
local lastConfig: EngineConfig? = nil
local lastMenuActive = false
local currentFinaleSecretExit = false
local wipeActive = false
local pendingWipeTics = 0
local hasPresentedFrame = false
local queuedWipeStartFrame = buffer.create(0)
local wipeGameState = Definitions.DEMOSCREEN
local forceWipe = false
local deferredGameAction: (() -> ())? = nil
const saveSlots: { [number]: SaveSlot } = {}
local gameTic = 0
local helpScreenState = false
local statusBarWasFullscreen = false
local borderViewActive = false
local borderMenuActive = false
local borderDrawCount = 0
local demoAdvanceSequence = false
local fastGameplayState = false
local suppressLevelInterpolationFrame = false
local configuredSoundCallbacks = false

const demoRestoreFlags = {
	precache = true,
	noMonsters = false,
	fastParm = false,
	respawnMonsters = false,
	skill = Definitions.sk_medium,
}

local currentLanguage = Definitions.english
local devparm = false

const function SetDeferredGameAction(action: () -> ())
	deferredGameAction = action
end

const function RebuildFrameBuffers()
	const indexedFrameSize = Video.PixelCount
	const rgbaFrameSize = indexedFrameSize * 4
	indexedFrameSizeCached = indexedFrameSize
	rgbaFrameSizeCached = rgbaFrameSize

	blankFrame = buffer.create(rgbaFrameSize)
	rgbaFrame = buffer.create(rgbaFrameSize)
	rgbaPaletteCacheBase = -1
	presentedIndexedFrame = buffer.create(indexedFrameSize)
end

const function NoOp(...: unknown)
end

const function ResetBlankFrame()
	const output = blankFrame

	for outputOffset = 0, rgbaFrameSizeCached - 4, 4 do
		buffer.writeu32(output, outputOffset, 0xFF000000)
	end
end

const function HasQueuedWipeStartFrame(): boolean
	return buffer.len(queuedWipeStartFrame) == indexedFrameSizeCached
end

const function CopyIndexedFrame(source: buffer): buffer
	const indexedFrameSize = indexedFrameSizeCached
	const copy = buffer.create(indexedFrameSize)
	buffer.copy(copy, 0, source, 0, indexedFrameSize)
	return copy
end

const function RememberPresentedFrame(source: buffer)
	const indexedFrameSize = indexedFrameSizeCached

	if buffer.len(source) ~= indexedFrameSize then
		return
	end

	buffer.copy(presentedIndexedFrame, 0, source, 0, indexedFrameSize)
	hasPresentedFrame = true
end

const function PresentHeldFrame(): boolean
	local source = false

	if HasQueuedWipeStartFrame() then
		source = queuedWipeStartFrame
	elseif hasPresentedFrame then
		source = presentedIndexedFrame
	end

	const indexedFrameSize = indexedFrameSizeCached

	if buffer.len(source) ~= indexedFrameSize then
		return false
	end

	buffer.copy(Video.GetScreenBuffer(0), 0, source, 0, indexedFrameSize)
	return true
end

const function DrawPausePatch()
	if not Setup.GetPaused() or currentGameState ~= Definitions.LEVEL then
		return
	end

	const y = if Automap.IsActive() then 4 else State.viewwindowy + 4

	Video.DrawPatchDirectRender(
		State.viewwindowx + (State.scaledviewwidth - 68) // 2,
		y,
		0,
		Wad.CacheLumpName("M_PAUSE", Zone.CACHE)
	)
end

const function RedrawLevelForWipeCapture(
	player: PlayerState?,
	helpScreenVisible: boolean,
	previousGameState: number,
	menuVisible: boolean,
	viewOverride: unknown
)
	const previousScaledViewWidth = State.scaledviewwidth
	const previousViewHeight = State.viewheight

	if previousGameState ~= Definitions.LEVEL then
		if State.scaledviewwidth ~= Video.Width then
			Draw.FillBackScreen()
		end

		borderViewActive = false
	end

	if Automap.IsActive() then
		Automap.Drawer()
	else
		Main.RenderPlayerView(player, viewOverride)
	end

	if previousScaledViewWidth ~= State.scaledviewwidth or previousViewHeight ~= State.viewheight then
		borderDrawCount = 3
	end

	const fullscreen = State.viewheight == Video.Height

	Status.Drawer(fullscreen,
		previousGameState ~= Definitions.LEVEL
		or (not fullscreen and statusBarWasFullscreen)
		or (helpScreenState and not helpScreenVisible)
	)

	HUD.Drawer()

	if not Automap.IsActive() and State.scaledviewwidth ~= Video.Width then
		if menuVisible or borderMenuActive or not borderViewActive then
			borderDrawCount = 3
		end

		if borderDrawCount > 0 then
			Draw.DrawViewBorder()
			borderDrawCount -= 1
		end
	end

	borderMenuActive = menuVisible
	borderViewActive = not Automap.IsActive()
end

const function SnapshotPlayerRenderState(player: PlayerState?)
	if typeof(player) ~= "table" then
		return
	end

	player.renderPrevViewZ = player.viewz

	if typeof(player.psprites) ~= "table" then
		return
	end

	for _, psp in player.psprites do
		if typeof(psp) == "table" then
			psp.renderPrevSX = psp.sx
			psp.renderPrevSY = psp.sy
		end
	end
end

const function SnapshotMobjRenderState(mobj: MobjState?)
	if typeof(mobj) ~= "table"
		or typeof(mobj.x) ~= "number"
		or typeof(mobj.y) ~= "number"
		or typeof(mobj.z) ~= "number"
		or typeof(mobj.angle) ~= "number" then
		return
	end

	mobj.renderPrevX = mobj.x
	mobj.renderPrevY = mobj.y
	mobj.renderPrevZ = mobj.z
	mobj.renderPrevAngle = mobj.angle
end

const function SnapshotSectorRenderState(sector: SectorState?)
	if typeof(sector) ~= "table"
		or typeof(sector.floorheight) ~= "number"
		or typeof(sector.ceilingheight) ~= "number" then
		return
	end

	sector.renderPrevFloorHeight = sector.floorheight
	sector.renderPrevCeilingHeight = sector.ceilingheight
end

const function SnapshotRenderStateBeforeTic()
	const players = Setup.GetPlayers()

	for _, player in players do
		SnapshotPlayerRenderState(player)
	end

	const sectors = Setup.GetSectors()

	for _, sector in sectors do
		SnapshotSectorRenderState(sector)
	end

	const thinkerCap = Setup.GetThinkerCap()
	local thinker = thinkerCap.next

	while thinker ~= thinkerCap do
		SnapshotMobjRenderState(thinker.owner or thinker)
		thinker = thinker.next
	end
end

const function InterpolateScalar(previousValue: number?, currentValue: number, alpha: number): number
	if typeof(previousValue) ~= "number" or alpha <= 0 then
		return currentValue
	end

	return math.modf(previousValue + (currentValue - previousValue) * alpha)
end

const function InterpolateAngle(previousAngle: number?, currentAngle: number, alpha: number): number
	if typeof(previousAngle) ~= "number" or alpha <= 0 then
		return currentAngle
	end

	local delta = currentAngle - previousAngle

	if delta > 0x80000000 then
		delta -= 0x100000000
	elseif delta < -0x80000000 then
		delta += 0x100000000
	end

	return bit32.band(math.modf(previousAngle + delta * alpha), 0xFFFFFFFF)
end

const function SyncSectorRenderState(alpha: number)
	const sectors = Setup.GetSectors()

	for _, sector in sectors do
		if typeof(sector) == "table" then
			sector.renderFloorHeight = InterpolateScalar(sector.renderPrevFloorHeight, sector.floorheight, alpha)
			sector.renderCeilingHeight = InterpolateScalar(sector.renderPrevCeilingHeight, sector.ceilingheight, alpha)
		end
	end
end

const function BuildLevelViewOverride(player: PlayerState?, alpha: number)
	if typeof(player) ~= "table" or typeof(player.mo) ~= "table" then
		return false
	end

	const mo = player.mo

	return {
		x = InterpolateScalar(mo.renderPrevX, mo.x, alpha),
		y = InterpolateScalar(mo.renderPrevY, mo.y, alpha),
		z = InterpolateScalar(player.renderPrevViewZ, player.viewz, alpha),
		angle = InterpolateAngle(mo.renderPrevAngle, mo.angle, alpha),
	}
end

const function DeepCopy(value: unknown)
	if type(value) == "table" then
		const copy: { [unknown]: unknown } = {}

		for key, item in value do
			copy[key] = DeepCopy(item)
		end

		return copy
	else
		return value
	end
end

const function ApplyVideoConfig(config: EngineConfig?)
	local screenWidth = Video.LogicalWidth
	local screenHeight = Video.LogicalHeight

	if config ~= nil and config.screenWidth ~= nil then
		screenWidth = config.screenWidth
	end

	if config ~= nil and config.screenHeight ~= nil then
		screenHeight = config.screenHeight
	end

	VideoMode.SetRenderSize(screenWidth, screenHeight)
	Video.SyncState()
end

const function GetPrimaryPlayer()
	return Setup.GetPlayers()[0]
end

const function ClearPlayerCommand()
	const cmd = GetPrimaryPlayer().cmd
	cmd.forwardmove = 0
	cmd.sidemove = 0
	cmd.angleturn = 0
	cmd.consistancy = 0
	cmd.chatchar = 0
	cmd.buttons = 0
end

const function ClearInput()
	Input.ClearInput(ClearPlayerCommand)
	lastMenuActive = false
end

const function IsLevelViewReady(player: PlayerState?): boolean
	return player ~= nil and player.mo ~= false and player.viewz ~= 1
end

const function SetFastGameplayState(enabled: boolean)
	if fastGameplayState == enabled then
		return
	end

	for stateIndex = Info.SARG_RUN1, Info.SARG_PAIN2 do
		const state = Info.states[stateIndex]

		if enabled then
			state.tics //= 2
		else
			state.tics *= 2
		end
	end

	const bruiserShot = Info.mobjinfo[Info.BRUISERSHOT]
	const headShot = Info.mobjinfo[Info.HEADSHOT]
	const troopShot = Info.mobjinfo[Info.TROOPSHOT]

	bruiserShot.speed = if enabled then 20 * Fixed.FRACUNIT else 15 * Fixed.FRACUNIT
	headShot.speed = if enabled then 20 * Fixed.FRACUNIT else 10 * Fixed.FRACUNIT
	troopShot.speed = if enabled then 20 * Fixed.FRACUNIT else 10 * Fixed.FRACUNIT

	fastGameplayState = enabled
end

const function PrepareForLevelLoad(clearFrags: boolean)
	ClearInput()
	Cheats.Reset()
	Setup.SetPaused(false)
	Sound.ResumeSound()

	if clearFrags then
		const frags = GetPrimaryPlayer().frags

		for index in frags do
			frags[index] = 0
		end
	end
end

const function setLanguage(value: number)
	currentLanguage = value
	HUD.SetLanguage(value)
	Automap.SetLanguage(value)
	Finale.SetLanguage(value)
	Interaction.SetLanguage(value)
	Doors.SetLanguage(value)
end

const function CopyRGBAFrame(source: buffer): buffer
	const rgbaFrameSize = rgbaFrameSizeCached
	const copy = buffer.create(rgbaFrameSize)
	buffer.copy(copy, 0, source, 0, rgbaFrameSize)
	return copy
end

const function GetPlaypal(): buffer
	if buffer.len(playpal) < 256 * 3 then
		if Wad.CheckNumForName("PLAYPAL") == -1 then
			return buffer.create(0)
		end

		playpal = Wad.CacheLumpName("PLAYPAL", Zone.CACHE)
	end

	return playpal
end

const function RebuildRGBAPaletteCache(palette: buffer, paletteBase: number, gammaIndex: number, gammaRow: buffer?)
	rgbaPaletteCacheSource = palette
	rgbaPaletteCacheBase = paletteBase
	rgbaPaletteCacheGamma = gammaIndex

	local paletteOffset = paletteBase
	const paletteCache = rgbaPaletteCache

	if typeof(gammaRow) == "buffer" then
		for cacheOffset = 0, 255 * 4, 4 do
			local red = buffer.readu8(palette, paletteOffset)
			local green = buffer.readu8(palette, paletteOffset + 1)
			local blue = buffer.readu8(palette, paletteOffset + 2)

			red = buffer.readu8(gammaRow, red)
			green = buffer.readu8(gammaRow, green)
			blue = buffer.readu8(gammaRow, blue)

			buffer.writeu32(paletteCache, cacheOffset, red + green * 256 + blue * 65536 + 0xFF000000)
			paletteOffset += 3
		end

		return
	end

	for cacheOffset = 0, 255 * 4, 4 do
		const red = buffer.readu8(palette, paletteOffset)
		const green = buffer.readu8(palette, paletteOffset + 1)
		const blue = buffer.readu8(palette, paletteOffset + 2)

		buffer.writeu32(paletteCache, cacheOffset, red + green * 256 + blue * 65536 + 0xFF000000)
		paletteOffset += 3
	end
end

const function ConvertFrameToRGBA(): buffer
	const palette = GetPlaypal()

	if buffer.len(palette) < 256 * 3 then
		return blankFrame
	end

	const indexed = Video.GetScreenBuffer(0)
	const gammaIndex = Video.GetUseGamma()
	const gammaRow = Video.gammatable[gammaIndex]
	local paletteBase = 0

	if currentGameState == Definitions.LEVEL and not wipeActive then
		paletteBase = Status.GetPaletteIndex() * 256 * 3
	end

	if paletteBase < 0 or paletteBase + 256 * 3 > buffer.len(palette) then
		paletteBase = 0
	end

	const pixelCount = indexedFrameSizeCached

	if rgbaPaletteCacheSource ~= palette or rgbaPaletteCacheBase ~= paletteBase or rgbaPaletteCacheGamma ~= gammaIndex then
		RebuildRGBAPaletteCache(palette, paletteBase, gammaIndex, gammaRow)
	end

	const output = rgbaFrame
	const paletteCache = rgbaPaletteCache
	local inputOffset = 0

	for outputOffset = 0, pixelCount * 4 - 4, 4 do
		const paletteIndex = buffer.readu8(indexed, inputOffset)
		buffer.writeu32(output, outputOffset, buffer.readu32(paletteCache, paletteIndex * 4))
		inputOffset += 1
	end

	return output
end

const function NormalizeWadLabel(label: string): string
	const normalized = string.gsub(string.lower(label), "\\", "/")
	return normalized
end

const function IsFrenchIWADLabel(label: string?): boolean
	if typeof(label) ~= "string" then
		return false
	end

	const normalized = NormalizeWadLabel(label)
	return normalized == "doom2f.wad" or string.sub(normalized, -11) == "/doom2f.wad"
end

const function PlayerFinishLevel()
	const player = GetPrimaryPlayer()
	const powers = player.powers
	const cards = player.cards

	for index = 0, Definitions.NUMPOWERS - 1 do
		powers[index] = 0
	end

	for index = 0, Definitions.NUMCARDS - 1 do
		cards[index] = false
	end

	if player.mo ~= false then
		player.mo.flags = bit32.band(player.mo.flags, bit32.bnot(Info.SHADOW))
	end

	player.extralight = 0
	player.fixedcolormap = 0
	player.damagecount = 0
	player.bonuscount = 0
end

const function PlayerReborn(_playerNumber: number, player: PlayerState?)
	if player == nil then
		player = GetPrimaryPlayer()
	end

	const frags = DeepCopy(player.frags)
	const killcount = player.killcount
	const itemcount = player.itemcount
	const secretcount = player.secretcount
	const maxammo = player.maxammo

	player.mo = false
	player.playerstate = PST_LIVE
	player.killcount = killcount
	player.secretcount = secretcount
	player.itemcount = itemcount
	player.viewz = 0
	player.viewheight = VIEWHEIGHT
	player.deltaviewheight = 0
	player.bob = 0
	player.health = Interaction.MAXHEALTH
	player.armorpoints = 0
	player.armortype = 0
	player.backpack = false
	player.frags = frags
	player.readyweapon = Definitions.wp_pistol
	player.pendingweapon = Definitions.wp_pistol
	player.attackdown = true
	player.usedown = true
	player.cheats = 0
	player.refire = 0
	player.message = false
	player.damagecount = 0
	player.bonuscount = 0
	player.attacker = false
	player.extralight = 0
	player.fixedcolormap = 0
	player.colormap = 0
	player.psprites = {}
	player.didsecret = false

	const cmd = player.cmd
	cmd.forwardmove = 0
	cmd.sidemove = 0
	cmd.angleturn = 0
	cmd.consistancy = 0
	cmd.chatchar = 0
	cmd.buttons = 0

	table.clear(player.powers)

	for index = 0, Definitions.NUMPOWERS - 1 do
		player.powers[index] = 0
	end

	table.clear(player.cards)

	for index = 0, Definitions.NUMCARDS - 1 do
		player.cards[index] = false
	end

	table.clear(player.weaponowned)

	for index = 0, Definitions.NUMWEAPONS - 1 do
		player.weaponowned[index] = false
	end

	player.weaponowned[Definitions.wp_fist] = true
	player.weaponowned[Definitions.wp_pistol] = true

	table.clear(player.ammo)
	table.clear(player.maxammo)

	for index = 0, Definitions.NUMAMMO - 1 do
		player.ammo[index] = 0
		player.maxammo[index] = if typeof(maxammo[index]) == "number" then maxammo[index] else Interaction.maxammo[index] or 0
	end

	player.ammo[Definitions.am_clip] = 50
end

const function TakeScreenshot()
	const callback = Shared.System.takeScreenshot

	if callback == nil then
		return
	end

	callback(CopyRGBAFrame(ConvertFrameToRGBA()))
	GetPrimaryPlayer().message = "screen shot"
end

const function saveGame(slot: number, description: string)
	if not mapLoaded or currentGameState ~= Definitions.LEVEL then
		return false
	end

	SaveGame.ClearSavePointer()
	SaveGame.ArchivePlayers()
	SaveGame.ArchiveWorld()
	SaveGame.ArchiveThinkers()
	SaveGame.ArchiveSpecials()

	saveSlots[slot] = {
		description = string.sub(description, 1, 23),
		version = Definitions.VERSION,
		episode = Setup.GetCurrentEpisode(),
		map = Setup.GetCurrentMap(),
		skill = Setup.GetCurrentSkill(),
		playeringame = {
			[0] = true,
			[1] = false,
			[2] = false,
			[3] = false,
		},
		leveltime = Setup.GetLevelTime(),
		totalkills = Setup.GetTotalKills(),
		totalitems = Setup.GetTotalItems(),
		totalsecret = Setup.GetTotalSecret(),
		fastParm = Setup.GetFastParm(),
		respawnMonsters = Setup.GetRespawnMonsters(),
		save = DeepCopy(SaveGame.GetSavePointer()),
		endMarker = 0x1D,
	}

	return true
end

const function RequestScreenWipe()
	if wipeActive then
		forceWipe = true
		return
	end

	if not hasPresentedFrame and not HasQueuedWipeStartFrame() then
		return
	end

	forceWipe = true
end

const function CaptureWipeStartBuffer()
	if not hasPresentedFrame then
		return false
	end

	return CopyIndexedFrame(presentedIndexedFrame)
end

const function ArmScreenWipeFromBuffer(startBuffer: unknown)
	if typeof(startBuffer) ~= "buffer" or buffer.len(startBuffer) ~= indexedFrameSizeCached then
		return false
	end

	if wipeActive then
		return false
	end

	queuedWipeStartFrame = CopyIndexedFrame(startBuffer)
	forceWipe = true
	return true
end

const function RedrawCurrentSceneWithoutMenu()
	if currentGameState == Definitions.DEMOSCREEN and Title.IsActive() then
		buffer.fill(Video.GetScreenBuffer(0), 0, 0, indexedFrameSizeCached - 1)
		Title.PageDrawer()
		return true
	end

	if currentGameState == Definitions.INTERMISSION and Intermission.IsActive() then
		Intermission.Drawer()
		return true
	end

	if currentGameState == Definitions.FINALE and Finale.IsActive() then
		Finale.Drawer()
		return true
	end

	return false
end

const function CaptureCleanWipeStartBuffer()
	if RedrawCurrentSceneWithoutMenu() then
		return CopyIndexedFrame(Video.GetScreenBuffer(0))
	end

	return CaptureWipeStartBuffer()
end

const function StartScreenWipe(menuVisible: boolean)
	const screen = Video.GetScreenBuffer(0)
	local startBuffer

	if HasQueuedWipeStartFrame() then
		startBuffer = queuedWipeStartFrame
	elseif hasPresentedFrame then
		startBuffer = presentedIndexedFrame
	else
		return false
	end

	Wipe.SetStartScreenBuffer(startBuffer)
	Wipe.SetEndScreenBuffer(screen)
	RememberPresentedFrame(screen)
	Wipe.RestoreStartScreen(0, 0, Video.Width, Video.Height)
	wipeActive = true
	pendingWipeTics = 0
	wipeGameState = currentGameState
	forceWipe = false
	queuedWipeStartFrame = buffer.create(0)

	if Wipe.ScreenWipe(Wipe.wipe_Melt, 0, 0, Video.Width, Video.Height, 1) ~= 0 then
		wipeActive = false
	end

	if menuVisible then
		Menu.Drawer()
	end

	return true
end

const function ArmLevelEntryWipe(startBuffer: unknown)
	suppressLevelInterpolationFrame = true

	if typeof(startBuffer) == "buffer" and buffer.len(startBuffer) == indexedFrameSizeCached then
		ArmScreenWipeFromBuffer(startBuffer)
	else
		RequestScreenWipe()
	end
end

const function StopDemoPlayback(advanceSequence: boolean)
	const hadPlayback = Setup.GetDemoPlayback() or Demo.IsActive()
	const usedDemoStop = Demo.IsActive()

	if usedDemoStop then
		Demo.StopPlayback(if advanceSequence then "finished" else "stopped")
	else
		Demo.Reset()
	end

	Setup.SetPrecache(demoRestoreFlags.precache)
	Setup.SetDemoPlayback(false)
	Setup.SetNoMonsters(demoRestoreFlags.noMonsters)
	SetFastGameplayState(demoRestoreFlags.fastParm or demoRestoreFlags.skill == Definitions.sk_nightmare)
	Setup.SetFastParm(demoRestoreFlags.fastParm)
	Setup.SetRespawnMonsters(demoRestoreFlags.respawnMonsters)
	demoAdvanceSequence = false

	ClearInput()
	Cheats.Reset()

	if advanceSequence and hadPlayback and not usedDemoStop then
		Title.AdvanceDemo()
	end
end

const function ForcePrimaryPlayerReborn()
	GetPrimaryPlayer().playerstate = PST_REBORN
end

const function RebornDeadPlayerForLevelLoad()
	const player = GetPrimaryPlayer()

	if player.playerstate == PST_DEAD then
		player.playerstate = PST_REBORN
	end
end

const function ApplySkillBootstrap(skill: number)
	Random.ClearRandom()
	SetFastGameplayState(skill == Definitions.sk_nightmare)
	Setup.SetRespawnMonsters(skill == Definitions.sk_nightmare)
	Setup.SetFastParm(false)
end

const function RestartCurrentLevel(_playerNumber: number, _player: unknown)
	if Setup.GetDemoPlayback() or Demo.IsActive() then
		Demo.CheckDemoStatus()
		return
	end

	const wipeStartBuffer = CaptureCleanWipeStartBuffer()
	Automap.Stop()
	Menu.ForceClearAll()
	currentGameState = Definitions.LEVEL
	currentFinaleSecretExit = false
	PrepareForLevelLoad(true)
	ForcePrimaryPlayerReborn()
	Setup.SetupLevel(Setup.GetCurrentEpisode(), Setup.GetCurrentMap(), 0, Setup.GetCurrentSkill())
	mapLoaded = true
	ArmLevelEntryWipe(wipeStartBuffer)
end

const function HandleSpecialButtons(player: PlayerState)
	const cmd = player.cmd
	const buttons = cmd.buttons

	if bit32.band(buttons, SPECIAL) == 0 then
		return
	end

	const command = bit32.band(buttons, SPECIALMASK)
	cmd.buttons = 0

	if command == BTS_PAUSE then
		const paused = not Setup.GetPaused()
		Setup.SetPaused(paused)

		if paused then
			Sound.PauseSound()
		else
			Sound.ResumeSound()
		end
	elseif command == BTS_SAVEGAME then
		const slot = bit32.band(buttons, BTS_SAVEMASK) // 4
		const entry = saveSlots[slot]
		const description = if typeof(entry) == "table" and typeof(entry.description) == "string" then entry.description else "SAVE GAME"
		saveGame(slot, description)
	end
end

const function loadGame(slot: number)
	const entry = saveSlots[slot]

	if typeof(entry) ~= "table" then
		return false
	end

	if entry.version ~= nil and entry.version ~= Definitions.VERSION then
		return false
	end

	if entry.endMarker ~= nil and entry.endMarker ~= 0x1D then
		return false
	end

	const wipeStartBuffer = CaptureCleanWipeStartBuffer()
	StopDemoPlayback(false)
	Automap.Stop()
	Finale.Reset()
	Intermission.Reset()
	Title.Reset()
	Menu.ForceClearAll()
	currentGameState = Definitions.LEVEL
	currentFinaleSecretExit = false
	Setup.SetCurrentSkill(entry.skill)
	PrepareForLevelLoad(true)
	ApplySkillBootstrap(entry.skill)
	SetFastGameplayState((entry.fastParm == true) or entry.skill == Definitions.sk_nightmare)
	Setup.SetFastParm(entry.fastParm == true)
	Setup.SetRespawnMonsters(if entry.respawnMonsters ~= nil then entry.respawnMonsters == true else entry.skill == Definitions.sk_nightmare)
	ForcePrimaryPlayerReborn()
	Setup.SetupLevel(entry.episode, entry.map, 0, entry.skill)
	SaveGame.SetSavePointer(DeepCopy(entry.save))
	SaveGame.UnArchivePlayers()
	SaveGame.UnArchiveWorld()
	SaveGame.UnArchiveThinkers()
	SaveGame.UnArchiveSpecials()
	Setup.SetLevelTime(entry.leveltime)
	Setup.SetTotalKills(entry.totalkills)
	Setup.SetTotalItems(entry.totalitems)
	Setup.SetTotalSecret(entry.totalsecret)
	mapLoaded = true
	ClearPlayerCommand()
	ArmLevelEntryWipe(wipeStartBuffer)
	return true
end

const function StartTitleLoop()
	StopDemoPlayback(false)
	Cheats.Reset()
	Automap.Stop()
	Finale.Reset()
	Intermission.Reset()
	Title.Reset()
	deferredGameAction = nil
	Input.ResetTitleInputState()
	ClearPlayerCommand()
	Title.StartTitle()
	Title.ProcessAdvanceDemo()
end

const function PlayDemoByName(name: string, advanceSequence: boolean): boolean
	const info = Demo.StartPlayback(name)

	if info == false then
		return false
	end

	demoRestoreFlags.precache = Setup.GetPrecache()
	demoRestoreFlags.noMonsters = Setup.GetNoMonsters()
	demoRestoreFlags.fastParm = Setup.GetFastParm()
	demoRestoreFlags.respawnMonsters = Setup.GetRespawnMonsters()
	demoRestoreFlags.skill = Setup.GetCurrentSkill()
	demoAdvanceSequence = advanceSequence
	const wipeStartBuffer = CaptureCleanWipeStartBuffer()

	Automap.Stop()
	Finale.Reset()
	Intermission.Reset()

	currentGameState = Definitions.LEVEL
	currentFinaleSecretExit = false
	mapLoaded = false
	PrepareForLevelLoad(true)

	Setup.SetPrecache(false)
	Setup.SetNoMonsters(info.nomonsters)
	SetFastGameplayState(info.fast or info.skill == Definitions.sk_nightmare)
	Setup.SetFastParm(info.fast)
	Setup.SetRespawnMonsters(info.respawn or info.skill == Definitions.sk_nightmare)
	Setup.SetDemoPlayback(true)
	Setup.SetCurrentSkill(info.skill)
	Random.ClearRandom()
	ForcePrimaryPlayerReborn()
	Setup.SetupLevel(info.episode, info.map, 0, info.skill)

	if Demo.GetTimingDemo() then
		const timingOptions = Demo.GetTimingOptions()
		local nextTimingOptions: TimingOptions? = nil

		if timingOptions.startTime == nil then
			nextTimingOptions = {
				startTime = os.clock(),
				startGameTic = Timing.GetGameTic(),
			}
		elseif timingOptions.startGameTic == nil then
			nextTimingOptions = {
				startGameTic = Timing.GetGameTic(),
			}
		end

		if nextTimingOptions ~= nil then
			Demo.SetTimingOptions(nextTimingOptions)
		end
	end

	Setup.SetPrecache(demoRestoreFlags.precache)
	mapLoaded = true
	ArmLevelEntryWipe(wipeStartBuffer)

	return true
end

const function DeferPlayDemoByName(name: string, advanceSequence: boolean): boolean
	SetDeferredGameAction(function()
		if not PlayDemoByName(name, advanceSequence) then
			Demo.GetLastError()
		end
	end)

	return true
end

const function StopAutomap()
	Automap.Stop()
end

const function GetAutomapActive(): boolean
	return Automap.IsActive()
end

const function AdvanceDemoSequence()
	if demoAdvanceSequence then
		demoAdvanceSequence = false
		ClearInput()
		Title.AdvanceDemo()
	end
end

const function GetGameTic(): number
	return Timing.GetGameTic()
end

const function GetRealTime(): number
	return os.clock()
end

const function ChangeTitleMusic(music: number)
	Sound.StartMusic(music)
end

const function RejectPlayDemo(_name: string): boolean
	return false
end

const function PlayTitleDemo(name: string): boolean
	return DeferPlayDemoByName(name, true)
end

const function SetDemoScreen()
	currentGameState = Definitions.DEMOSCREEN
	currentFinaleSecretExit = false
	mapLoaded = false
end

const function InstallDefaultCallbacks()
	Host.playerThink = nil
	Host.startSound = Sound.StartSound
	Host.startSoundSystem = Sound.Start
	Host.stopSound = Sound.StopSound
	Host.playerReborn = PlayerReborn
	Host.startStatus = NoOp
	Host.startHUD = NoOp
	Host.dropWeapon = nil
	Host.stopAutomap = StopAutomap
	Host.getAutomapActive = GetAutomapActive
	Host.tactile = NoOp
	Host.useLines = nil
	Host.exitLevel = NoOp
	Host.secretExitLevel = NoOp
	Host.reloadWad = NoOp

	Shared.Finale.changeMusic = Sound.ChangeMusic
	Shared.Finale.requestWipe = NoOp
	Shared.Finale.startSound = Sound.StartSound
	Shared.Finale.worldDone = NoOp

	Shared.Intermission.changeMusic = Sound.ChangeMusic
	Shared.Intermission.startSound = Sound.StartSound
	Shared.Intermission.worldDone = NoOp

	Shared.Demo.advanceDemo = AdvanceDemoSequence
	Shared.Demo.quit = NoOp
	Shared.Demo.getGameTic = GetGameTic
	Shared.Demo.getRealTime = GetRealTime

	Shared.Title.changeMusic = ChangeTitleMusic
	Shared.Title.playDemo = RejectPlayDemo
	Shared.Title.setDemoScreen = SetDemoScreen

	Runtime.Configure({
		rebornPlayer = RestartCurrentLevel,
		specialButtons = HandleSpecialButtons,
	})
end

const function MarkSecretExit()
	GetPrimaryPlayer().didsecret = true
end

const function ComputeNextMap(secretExit: boolean): number?
	const gamemode = Setup.GetGameMode()
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()

	if gamemode == Definitions.commercial then
		if secretExit then
			if map == 15 then
				return 31
			end

			if map == 31 then
				return 32
			end
		else
			if map == 31 or map == 32 then
				return 16
			end
		end

		return map + 1
	end

	if secretExit then
		return 9
	end

	if map == 9 then
		if episode == 1 then
			return 4
		end

		if episode == 2 then
			return 6
		end

		if episode == 3 then
			return 7
		end

		if episode == 4 then
			return 3
		end
	end

	return map + 1
end

const function LoadNextMapFromWorldInfoOrCompute(secretExit: boolean)
	const wipeStartBuffer = CaptureCleanWipeStartBuffer()
	const worldInfo = Setup.GetWorldInfo()
	const nextMap = if worldInfo.next ~= nil then worldInfo.next + 1 else ComputeNextMap(secretExit)

	if nextMap == nil then
		mapLoaded = false
		currentGameState = Definitions.LEVEL
		return
	end

	Finale.Reset()
	Intermission.Reset()
	Title.Reset()
	currentGameState = Definitions.LEVEL
	currentFinaleSecretExit = false
	PrepareForLevelLoad(true)
	RebornDeadPlayerForLevelLoad()
	Setup.SetupLevel(Setup.GetCurrentEpisode(), nextMap, 0, Setup.GetCurrentSkill())
	mapLoaded = true
	ArmLevelEntryWipe(wipeStartBuffer)
end

const function ShouldStartImmediateFinaleOnExit(_secretExit: boolean): boolean
	return Setup.GetGameMode() ~= Definitions.commercial and Setup.GetCurrentMap() == 8
end

const function ShouldStartFinaleAfterIntermission(secretExit: boolean): boolean
	const gamemode = Setup.GetGameMode()
	const map = Setup.GetCurrentMap()

	if gamemode == Definitions.commercial then
		if map == 6 or map == 11 or map == 20 or map == 30 then
			return true
		end

		if secretExit and (map == 15 or map == 31) then
			return true
		end

		return false
	end

	return false
end

const function ComputeParTimeTics(): number
	const gamemode = Setup.GetGameMode()
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()
	local partimeSeconds = 0

	if gamemode == Definitions.commercial then
		partimeSeconds = CPARS[map] or 0
	else
		const episodePars = PARS[episode]
		partimeSeconds = if episodePars ~= nil then episodePars[map] or 0 else 0
	end

	return partimeSeconds * Definitions.TICRATE
end

const function BuildWorldInfo(secretExit: boolean)
	const player = GetPrimaryPlayer()
	const nextMap = ComputeNextMap(secretExit)

	if nextMap == nil then
		return false
	end

	return {
		didsecret = player.didsecret == true,
		epsd = Setup.GetCurrentEpisode() - 1,
		last = Setup.GetCurrentMap() - 1,
		next = nextMap - 1,
		maxkills = Setup.GetTotalKills(),
		maxitems = Setup.GetTotalItems(),
		maxsecret = Setup.GetTotalSecret(),
		maxfrags = 0,
		partime = ComputeParTimeTics(),
		pnum = 0,
		plyr = {
			[0] = {
				["in"] = true,
				skills = player.killcount,
				sitems = player.itemcount,
				ssecret = player.secretcount,
				stime = Setup.GetLevelTime(),
				frags = player.frags,
			},
		},
	}
end

const function BeginFinale(secretExit: boolean)
	if Setup.GetDemoPlayback() or Demo.IsActive() then
		StopDemoPlayback(false)
	end

	Automap.Stop()
	Title.Reset()
	RequestScreenWipe()
	currentFinaleSecretExit = secretExit
	currentGameState = Definitions.FINALE
	mapLoaded = false
	ClearPlayerCommand()
	Intermission.Reset()
	Finale.StartFinale(secretExit)
	Shared.Finale.requestWipe = RequestScreenWipe

	const function FinishFinaleWorld()
		SetDeferredGameAction(function()
			LoadNextMapFromWorldInfoOrCompute(currentFinaleSecretExit)
		end)
	end

	Shared.Finale.worldDone = FinishFinaleWorld
end

const function BeginIntermission(secretExit: boolean)
	const worldInfo = BuildWorldInfo(secretExit)

	if worldInfo == false then
		LoadNextMapFromWorldInfoOrCompute(secretExit)
		return
	end

	Automap.Stop()
	Title.Reset()
	RequestScreenWipe()
	currentGameState = Definitions.INTERMISSION
	mapLoaded = false
	ClearPlayerCommand()
	Setup.SetWorldInfo(worldInfo)
	Intermission.Start(worldInfo)

	const function FinishIntermissionWorld()
		if secretExit then
			MarkSecretExit()
		end

		if ShouldStartFinaleAfterIntermission(secretExit) then
			BeginFinale(secretExit)
		else
			SetDeferredGameAction(function()
				LoadNextMapFromWorldInfoOrCompute(secretExit)
			end)
		end
	end

	Shared.Intermission.worldDone = FinishIntermissionWorld
end

const function HandleExitLevel(secretExit: boolean)
	if secretExit and Setup.GetGameMode() == Definitions.commercial and Wad.CheckNumForName("MAP31") == -1 then
		secretExit = false
	end

	PlayerFinishLevel()
	Automap.Stop()

	if Setup.GetGameMode() ~= Definitions.commercial and Setup.GetCurrentMap() == 9 then
		MarkSecretExit()
	end

	if ShouldStartImmediateFinaleOnExit(secretExit) then
		BeginFinale(secretExit)
		return
	end

	BeginIntermission(secretExit)
end

const function ExitLevel()
	HandleExitLevel(false)
end

const function SecretExitLevel()
	HandleExitLevel(true)
end

const function BindVideoBuffers()
	Video.Init()
	Draw.SetScreenBuffer(0, Video.GetScreenBuffer(0))
	Draw.SetScreenBuffer(1, Video.GetScreenBuffer(1))
end

const function InstallSoundCallbacks(values: CallbackMap)
	for name, callback in values do
		if name == "startSound" then
			Shared.Sound.startSound = callback
		elseif name == "stopSound" then
			Shared.Sound.stopSound = callback
		elseif name == "isSoundPlaying" then
			Shared.Sound.isSoundPlaying = callback
		elseif name == "updateSoundParams" then
			Shared.Sound.updateSoundParams = callback
		elseif name == "changeMusic" then
			Shared.Sound.changeMusic = callback
		elseif name == "stopMusic" then
			Shared.Sound.stopMusic = callback
		elseif name == "pauseSound" then
			Shared.Sound.pauseSound = callback
		elseif name == "resumeSound" then
			Shared.Sound.resumeSound = callback
		elseif name == "updateSounds" then
			Shared.Sound.updateSounds = callback
		elseif name == "setSfxVolume" then
			Shared.Sound.setSfxVolume = callback
		elseif name == "setMusicVolume" then
			Shared.Sound.setMusicVolume = callback
		end
	end
end

const function RestoreConfiguredSound()
	if configuredSoundCallbacks ~= false then
		InstallSoundCallbacks(configuredSoundCallbacks)
	end
end

const function ResetRuntimeState()
	Automap.Reset()
	Finale.Reset()
	HUD.Reset()
	Intermission.Reset()
	Menu.Reset()
	Title.Reset()
	Demo.Reset()
	Sound.Reset()
	Shared.Reset()
	RendererHost.Reset()
	RendererRuntime.Reset()
	Bsp.Reset()
	Plane.Reset()
	Segs.Reset()
	SpriteState.Reset()
	Things.Reset()
	Data.Reset()
	Draw.Reset()
	Setup.Reset()
	Status.Reset()
	Wipe.Reset()
	Zone.Init()
	State.Reset()
	Main.Reset()
	RebuildFrameBuffers()
	BindVideoBuffers()
	InstallDefaultCallbacks()
	RestoreConfiguredSound()
	Host.exitLevel = ExitLevel
	Host.secretExitLevel = SecretExitLevel
	ClearInput()
	Cheats.Reset()
	ResetBlankFrame()
	playpal = buffer.create(0)
	gameTic = 0
	Timing.Reset()
	demoAdvanceSequence = false
	demoRestoreFlags.precache = true
	demoRestoreFlags.noMonsters = false
	demoRestoreFlags.fastParm = false
	demoRestoreFlags.respawnMonsters = false
	demoRestoreFlags.skill = Definitions.sk_medium
	runtimeReady = false
	mapLoaded = false
	currentGameState = Definitions.LEVEL
	currentFinaleSecretExit = false
	wipeActive = false
	pendingWipeTics = 0
	hasPresentedFrame = false
	queuedWipeStartFrame = buffer.create(0)
	wipeGameState = Definitions.DEMOSCREEN
	forceWipe = false
	deferredGameAction = nil
	helpScreenState = false
	statusBarWasFullscreen = false
	borderViewActive = false
	borderMenuActive = false
	borderDrawCount = 0
	suppressLevelInterpolationFrame = false
	SetFastGameplayState(false)
	setLanguage(currentLanguage)
end

const function DetectGameMode(): number
	if Wad.CheckNumForName("MAP01") ~= -1 then
		return Definitions.commercial
	end

	if Wad.CheckNumForName("E4M1") ~= -1 then
		return Definitions.retail
	end

	if Wad.CheckNumForName("E2M1") ~= -1 then
		return Definitions.registered
	end

	if Wad.CheckNumForName("E1M1") ~= -1 then
		return Definitions.shareware
	end

	return Definitions.indetermined
end

const function GetSaveDescription(slot: number)
	const entry = saveSlots[slot]
	return if typeof(entry) == "table" then entry.description else false
end

const function IsUserGame(): boolean
	return mapLoaded and not Setup.GetDemoPlayback()
end

const function IsLevelGameState(): boolean
	return currentGameState == Definitions.LEVEL
end

const function IsDevParm(): boolean
	return devparm
end

const function RebuildRuntime(startNewGameCallback: (number, number, number) -> ())
	Setup.SetGameMode(currentGameMode)
	Status.SetPlayers(Setup.GetPlayers())
	Status.Init()
	HUD.Init()
	setLanguage(currentLanguage)
	Sound.Init(8, 8)
	Host.startSound = Sound.StartSound
	Host.startSoundSystem = Sound.Start
	Host.stopSound = Sound.StopSound
	Host.playerReborn = PlayerReborn
	Host.startStatus = Status.Start
	Host.startHUD = HUD.Start
	Host.stopAutomap = StopAutomap
	Host.getAutomapActive = GetAutomapActive
	Setup.Init()
	Runtime.Configure({
		rebornPlayer = RestartCurrentLevel,
		specialButtons = HandleSpecialButtons,
	})
	Menu.Init()
	Shared.Menu.startSound = Sound.StartSound
	Shared.Menu.startNewGame = startNewGameCallback
	Shared.Menu.getSaveDescription = GetSaveDescription
	Shared.Menu.getGameTic = GetGameTic
	Shared.Menu.getSfxVolume = Sound.GetSfxVolume
	Shared.Menu.getMusicVolume = Sound.GetMusicVolume
	Shared.Menu.takeScreenshot = TakeScreenshot
	Shared.Menu.saveGame = saveGame
	Shared.Menu.loadGame = loadGame
	Shared.Menu.startTitle = StartTitleLoop
	Shared.Menu.quitGame = NoOp
	Shared.Menu.setSfxVolume = Sound.SetSfxVolume
	Shared.Menu.setMusicVolume = Sound.SetMusicVolume
	Shared.Menu.isUserGame = IsUserGame
	Shared.Menu.isLevelGameState = IsLevelGameState
	Shared.Menu.isDevParm = IsDevParm
	Shared.Demo.advanceDemo = AdvanceDemoSequence
	Shared.Demo.quit = NoOp
	Shared.Demo.getGameTic = GetGameTic
	Shared.Demo.getRealTime = GetRealTime
	Shared.Title.changeMusic = ChangeTitleMusic
	Shared.Title.playDemo = PlayTitleDemo
	Shared.Title.setDemoScreen = SetDemoScreen
	runtimeReady = true
	mapLoaded = false
	playpal = buffer.create(0)
	currentGameState = Definitions.LEVEL
end

const function Init(config: EngineConfig?)
	if initialized then
		return
	end

	ApplyVideoConfig(config)
	lastConfig = if config ~= nil then DeepCopy(config) else nil
	devparm = if config ~= nil and config.devparm == true then true else false
	ResetRuntimeState()
	Wad.Reset()
	table.clear(saveSlots)
	currentGameMode = Definitions.indetermined
	hasIWAD = false
	currentLanguage = Definitions.english
	setLanguage(currentLanguage)
	initialized = true
end

const function Reset()
	ApplyVideoConfig(lastConfig)
	Wad.Reset()
	ResetRuntimeState()
	table.clear(saveSlots)
	currentGameMode = Definitions.indetermined
	hasIWAD = false
	devparm = if lastConfig ~= nil and lastConfig.devparm == true then true else false
	currentLanguage = Definitions.english
	setLanguage(currentLanguage)
	initialized = true
end

const function ResolveWADInput(input: buffer | WadData, label: string?): WADLoadInfo
	if typeof(input) == "buffer" then
		return {
			data = input :: buffer,
			id = nil,
			label = label,
			lumpCount = nil,
			soundCount = nil,
			module = nil,
			sounds = nil,
			overriddenSounds = nil,
		}
	end

	const moduleInfo = input :: WadData
	const data = moduleInfo.data

	local resolvedLabel = label

	if resolvedLabel == nil then
		if moduleInfo.label ~= nil then
			resolvedLabel = moduleInfo.label
		elseif moduleInfo.name ~= nil then
			resolvedLabel = moduleInfo.name
		end
	end

	return {
		data = data,
		id = moduleInfo.id,
		label = resolvedLabel,
		lumpCount = moduleInfo.lumpCount,
		soundCount = moduleInfo.soundCount,
		module = moduleInfo,
		sounds = moduleInfo.sounds,
		overriddenSounds = moduleInfo.overriddenSounds,
	}
end

const function StartNewGame(skill: number, episode: number, map: number)
	const wipeStartBuffer = CaptureCleanWipeStartBuffer()

	ResetRuntimeState()
	Setup.SetCurrentSkill(skill)
	RebuildRuntime(StartNewGame)
	PrepareForLevelLoad(true)
	ApplySkillBootstrap(skill)
	ForcePrimaryPlayerReborn()
	Setup.SetupLevel(episode, map, 0, skill)
	mapLoaded = true
	currentGameState = Definitions.LEVEL
	ArmScreenWipeFromBuffer(wipeStartBuffer)
end

const function LoadIWAD(input: buffer | WadData, label: string?)
	const wadInfo = ResolveWADInput(input, label)

	Wad.Reset()
	ResetRuntimeState()
	Wad.LoadIWAD(wadInfo.data, wadInfo.label)
	table.clear(saveSlots)
	hasIWAD = true
	currentGameMode = DetectGameMode()

	if IsFrenchIWADLabel(wadInfo.label) then
		setLanguage(Definitions.french)
	else
		setLanguage(Definitions.english)
	end

	RebuildRuntime(StartNewGame)
	StartTitleLoop()
end

const function LoadPWAD(input: buffer | WadData, label: string?)
	if not hasIWAD then
		error("loadPWAD: load an IWAD first")
	end

	const wadInfo = ResolveWADInput(input, label)
	const reloadLevel = mapLoaded and currentGameState == Definitions.LEVEL and not Setup.GetDemoPlayback()
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()
	const skill = Setup.GetCurrentSkill()

	Wad.LoadPWAD(wadInfo.data, wadInfo.label)
	ResetRuntimeState()
	table.clear(saveSlots)
	RebuildRuntime(StartNewGame)

	if reloadLevel then
		StartNewGame(skill, episode, map)
	else
		StartTitleLoop()
	end
end

const function ClearPWADs()
	if not hasIWAD then
		return
	end

	Wad.ClearPWADs()
	ResetRuntimeState()
	table.clear(saveSlots)
	RebuildRuntime(StartNewGame)
	StartTitleLoop()
end

const function SetInput(action: string, value: unknown)
	Input.SetInput(action, value)
end

const function SetMouseDelta(deltaX: number, deltaY: number)
	Input.SetMouseDelta(deltaX, deltaY)
end

const function KeyDown(keyCode: string)
	Input.SetKeyCode(keyCode, true)
end

const function KeyUp(keyCode: string)
	Input.SetKeyCode(keyCode, false)
end

const function ApplyDemoCommand(cmd: DemoCommand, demoCmd: DemoCommand)
	cmd.forwardmove = demoCmd.forwardmove
	cmd.sidemove = demoCmd.sidemove
	cmd.angleturn = demoCmd.angleturn
	cmd.consistancy = 0
	cmd.chatchar = 0
	cmd.buttons = demoCmd.buttons
end

const function UsesPlayerCommandInput(): boolean
	return currentGameState == Definitions.LEVEL
		or currentGameState == Definitions.INTERMISSION
		or currentGameState == Definitions.FINALE
end

const function BuildPrimaryPlayerCommand(quitPending: boolean): boolean
	const player = GetPrimaryPlayer()
	const cmd = player.cmd

	if quitPending then
		ClearPlayerCommand()
		return false
	end

	if Setup.GetDemoPlayback() then
		ClearPlayerCommand()

		const demoCmd = Demo.ReadTiccmd()

		if demoCmd == false then
			Demo.CheckDemoStatus()
			Setup.SetPrecache(demoRestoreFlags.precache)
			Setup.SetDemoPlayback(false)
			demoAdvanceSequence = false
			ClearInput()
			return true
		end

		ApplyDemoCommand(cmd, demoCmd)
	elseif UsesPlayerCommandInput() then
		Input.ApplyInput(GetPrimaryPlayer())

		if currentGameState == Definitions.LEVEL and Demo.IsRecording() then
			const recordedCmd = Demo.WriteTiccmd(cmd)

			if recordedCmd ~= false then
				ApplyDemoCommand(cmd, recordedCmd)
			end
		end
	else
		ClearPlayerCommand()
	end

	if cmd.forwardmove > TURBOTHRESHOLD and bit32.band(gameTic, 31) == 0 then
		player.message = "Turbo!"
	end

	return false
end

const function HandleRebornBeforeCommand(): boolean
	if currentGameState ~= Definitions.LEVEL then
		return false
	end

	const player = GetPrimaryPlayer()

	if player.playerstate ~= PST_REBORN then
		return false
	end

	if Setup.GetDemoPlayback() or Demo.IsActive() then
		StopDemoPlayback(true)
		return true
	end

	RestartCurrentLevel(0, player)
	return false
end

const function PumpTitleInput()
	Input.PumpTitleInput(not Demo.GetSingleDemo() and deferredGameAction == nil)
end

const function CanAdvanceCurrentState(menuVisible: boolean): boolean
	return runtimeReady
		and (
			mapLoaded
			or currentGameState == Definitions.FINALE
			or currentGameState == Definitions.INTERMISSION
			or currentGameState == Definitions.DEMOSCREEN
			or menuVisible
		)
end

const function AdvanceTicFrame(): boolean
	local menuVisible = Menu.IsVisible()
	local quitPending = Menu.IsQuitPending()
	local demoEndedThisFrame = false

	if not CanAdvanceCurrentState(menuVisible) then
		helpScreenState = false
		return false
	end

	if not quitPending then
		gameTic = Timing.AdvanceGameTic()
	end

	if wipeActive then
		pendingWipeTics += 1
		return true
	end

	SnapshotRenderStateBeforeTic()

	Input.PumpMenuInput(gameTic)
	if not Menu.IsQuitPending() then
		Title.ProcessAdvanceDemo()
	end
	Menu.Ticker()
	quitPending = Menu.IsQuitPending()
	const menuActive = Menu.GetMenuActive()

	if lastMenuActive and not menuActive and currentGameState == Definitions.LEVEL and mapLoaded and Setup.GetPaused() and not Setup.GetDemoPlayback() then
		Setup.SetPaused(false)
		Sound.ResumeSound()
	end

	lastMenuActive = menuActive

	if quitPending or Menu.IsVisible() then
		Input.ClearAutomapConsumedActions()
		Input.ClearFinaleInputState()
		Input.ResetTitleInputState()
	elseif Setup.GetDemoPlayback() then
		Input.ClearAutomapConsumedActions()
		Input.ClearFinaleInputState()
		PumpTitleInput()
	elseif currentGameState == Definitions.LEVEL then
		Input.PumpAutomapInput()
		
		for _, key in Input.ConsumeGameplayKeys() do
			if Automap.IsActive() then
				Automap.Responder({
					type = 0,
					data1 = key,
					data2 = 0,
					data3 = 0,
				})
			end

			Cheats.Responder({
				type = 0,
				data1 = key,
				data2 = 0,
				data3 = 0,
			})
		end
	elseif currentGameState == Definitions.FINALE then
		Input.ClearAutomapConsumedActions()
		Input.PumpFinaleInput()
	elseif currentGameState == Definitions.DEMOSCREEN then
		Input.ClearAutomapConsumedActions()
		Input.ClearFinaleInputState()
		PumpTitleInput()
	else
		Input.ClearAutomapConsumedActions()
		Input.ClearFinaleInputState()
		Input.ResetTitleInputState()
	end

	menuVisible = Menu.IsVisible()

	const action = deferredGameAction

	if action ~= nil then
		deferredGameAction = nil
		action()
	end

	if HandleRebornBeforeCommand() then
		return true
	end

	demoEndedThisFrame = BuildPrimaryPlayerCommand(quitPending)

	if not quitPending and not demoEndedThisFrame and currentGameState == Definitions.LEVEL then
		Setup.Ticker()
	end

	if quitPending then
		-- Freeze scene updates during the quit delay to stay closer to vanilla's blocking wait.
	elseif currentGameState == Definitions.FINALE then
		Finale.Ticker()
	elseif currentGameState == Definitions.INTERMISSION then
		Intermission.Ticker()
	elseif currentGameState == Definitions.DEMOSCREEN then
		Title.PageTicker()
	end

	if currentGameState == Definitions.LEVEL then
		const player = GetPrimaryPlayer()

		if IsLevelViewReady(player) then
			Status.Ticker()
			HUD.Ticker()
			Automap.Ticker()
		end
	end

	return true
end

const function RenderFrame(timingOptions: TimingOptions?): buffer
	const menuVisible = Menu.IsVisible()
	const helpScreenVisible = Menu.IsHelpScreenVisible()
	const interpolationAlpha = Timing.GetInterpolationAlpha()
	local levelInterpolationAlpha = interpolationAlpha

	if suppressLevelInterpolationFrame and currentGameState == Definitions.LEVEL then
		levelInterpolationAlpha = 0
	end

	State.interpolationAlpha = levelInterpolationAlpha
	SyncSectorRenderState(levelInterpolationAlpha)

	if not CanAdvanceCurrentState(menuVisible) then
		helpScreenState = false
		return blankFrame
	end

	if wipeActive then
		if pendingWipeTics > 0 then
			if Wipe.ScreenWipe(Wipe.wipe_Melt, 0, 0, Video.Width, Video.Height, pendingWipeTics) ~= 0 then
				wipeActive = false
			end

			pendingWipeTics = 0
		end

		if wipeActive then
			if menuVisible then
				Menu.Drawer()
			end

			RememberPresentedFrame(Video.GetScreenBuffer(0))
			helpScreenState = helpScreenVisible

			if timingOptions ~= nil and timingOptions.noBlit == true then
				return blankFrame
			end

			return ConvertFrameToRGBA()
		end
	end

	if timingOptions ~= nil and timingOptions.noDrawers == true then
		helpScreenState = helpScreenVisible
		return blankFrame
	end

	const previousWipeGameState = wipeGameState
	const levelPlayer = if currentGameState == Definitions.LEVEL then GetPrimaryPlayer() else nil
	const levelViewReady = IsLevelViewReady(levelPlayer)
	local levelViewOverride = false

	if currentGameState == Definitions.LEVEL and gameTic ~= 0 and levelViewReady then
		HUD.Erase()
	end

	if currentGameState == Definitions.LEVEL then
		const player = levelPlayer

		if not levelViewReady then
			const heldFrameVisible = PresentHeldFrame()

			if menuVisible then
				Menu.Drawer()
			end

			helpScreenState = helpScreenVisible

			if timingOptions ~= nil and timingOptions.noBlit == true then
				return blankFrame
			end

			return if heldFrameVisible then ConvertFrameToRGBA() else blankFrame
		end

		levelViewOverride = BuildLevelViewOverride(player, levelInterpolationAlpha)
		RedrawLevelForWipeCapture(player, helpScreenVisible, previousWipeGameState, menuVisible, levelViewOverride)
		statusBarWasFullscreen = State.viewheight == Video.Height
	elseif currentGameState == Definitions.INTERMISSION and Intermission.IsActive() then
		Intermission.Drawer()
	elseif currentGameState == Definitions.INTERMISSION then
		const heldFrameVisible = PresentHeldFrame()

		helpScreenState = helpScreenVisible

		if timingOptions ~= nil and timingOptions.noBlit == true then
			return blankFrame
		end

		return if heldFrameVisible then ConvertFrameToRGBA() else blankFrame
	elseif currentGameState == Definitions.FINALE and Finale.IsActive() then
		Finale.Drawer()
	elseif currentGameState == Definitions.DEMOSCREEN then
		Title.PageDrawer()
	elseif menuVisible then
		buffer.fill(Video.GetScreenBuffer(0), 0, 0, indexedFrameSizeCached - 1)
	else
		helpScreenState = false
		return blankFrame
	end

	DrawPausePatch()

	if menuVisible then
		Menu.Drawer()
	end

	if (forceWipe or HasQueuedWipeStartFrame() or (hasPresentedFrame and currentGameState ~= wipeGameState))
		and (currentGameState ~= Definitions.LEVEL or levelViewReady) then
		StartScreenWipe(menuVisible)
	else
		RememberPresentedFrame(Video.GetScreenBuffer(0))
		wipeGameState = currentGameState
	end

	if currentGameState == Definitions.LEVEL then
		if levelPlayer.mo ~= false then
			Sound.UpdateSounds(levelPlayer.mo)
		else
			Sound.UpdateSounds(nil)
		end
	else
		Sound.UpdateSounds(nil)
	end

	if currentGameState == Definitions.LEVEL and not wipeActive and suppressLevelInterpolationFrame then
		SnapshotRenderStateBeforeTic()
		suppressLevelInterpolationFrame = false
	end

	helpScreenState = helpScreenVisible

	if timingOptions ~= nil and timingOptions.noBlit == true then
		return blankFrame
	end

	return ConvertFrameToRGBA()
end

const function AdvanceFrame(dt: number): buffer
	if Demo.GetTimingDemo() then
		Timing.BeginExactTicFrame(1)
		Input.BeginFrame(1)
		while Timing.ConsumePendingTic() do
			AdvanceTicFrame()
		end
		return RenderFrame(Demo.GetTimingOptions())
	end

	const pendingTics = Timing.BeginFrame(dt)
	Input.BeginFrame(if pendingTics > 0 then pendingTics else 1)

	while Timing.ConsumePendingTic() do
		AdvanceTicFrame()
	end

	return RenderFrame()
end

RebuildFrameBuffers()
ResetBlankFrame()

const function WarpToLevel(episode: number, map: number)
	SetDeferredGameAction(function()
		StartNewGame(Setup.GetCurrentSkill(), episode, map)
	end)
end

Shared.Cheats.warpToLevel = WarpToLevel

const function SetSound(soundId: number, moduleInfo: unknown, parent: unknown?)
	const callbacks = Sound.CreateCallbacks(soundId, moduleInfo, parent)

	configuredSoundCallbacks = callbacks
	InstallSoundCallbacks(callbacks)
	return callbacks
end

const function SetScreenshot(callback: unknown)
	Shared.System.takeScreenshot = callback
end

return {
	init = Init,
	reset = Reset,
	loadIWAD = LoadIWAD,
	loadPWAD = LoadPWAD,
	clearPWADs = ClearPWADs,
	startNewGame = StartNewGame,

	saveGame = saveGame,
	loadGame = loadGame,

	setSound = SetSound,
	addOST = Sound.AddOST,

	SetScreenshot = SetScreenshot,

	clearInput = ClearInput,
	setInput = SetInput,
	keyDown = KeyDown,
	keyUp = KeyUp,
	setMouseDelta = SetMouseDelta,
	setLanguage = setLanguage,
	advanceFrame = AdvanceFrame,
}
