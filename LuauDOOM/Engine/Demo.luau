--!native
--!optimize 2

--[[
	Demo.luau

	Manages demo header parsing, playback, timing, and recording state.
]]

const Definitions = require("./Definitions")
const Host = require("./Shared").Demo
const Random = require("../Miscellaneous/Random")
const Setup = require("../Play/Setup")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const CheckNumForName = Wad.CheckNumForName
const CacheLumpName = Wad.CacheLumpName
const ChangeTag = Zone.ChangeTag
const STATIC = Zone.STATIC
const CACHE = Zone.CACHE

const DEMOMARKER = 0x80
const HEADER_SIZE = 13
const TICCMD_SIZE = 4
const DEFAULT_MAXDEMO = 0x20000
const EMPTY_BUFFER = buffer.create(0)
const STRICT_COMPATIBLE_VERSIONS = {
	[Definitions.DEMO_VERSION] = true,
}

const COMPATIBLE_VERSIONS = {
	[Definitions.DEMO_VERSION] = true,
	[Definitions.VERSION] = true,
}

type PlayerFlags = {
	[number]: boolean,
}

type DemoHeader = {
	version: number,
	skill: number,
	episode: number,
	map: number,
	deathmatch: boolean,
	respawn: boolean,
	fast: boolean,
	nomonsters: boolean,
	consoleplayer: number,
	playeringame: PlayerFlags,
	size: number?,
	headerSize: number?,
	ticcmdSize: number?,
}

type HeaderInput = {
	version: number?,
	skill: number?,
	episode: number?,
	map: number?,
	deathmatch: (boolean | number)?,
	respawn: (boolean | number)?,
	fast: (boolean | number)?,
	nomonsters: (boolean | number)?,
	consoleplayer: number?,
	playeringame: PlayerFlags?,
	size: number?,
	headerSize: number?,
	ticcmdSize: number?,
}

type VersionSet = {
	[number]: boolean,
}

type Ticcmd = {
	forwardmove: number,
	sidemove: number,
	angleturn: number,
	buttons: number,
}

type TimingOptions = {
	noDrawers: boolean?,
	noBlit: boolean?,
	startTime: number?,
	startGameTic: number?,
}

type TimingReport = {
	gametics: number?,
	starttime: number?,
	startgametic: number?,
	endgametic: number?,
	endtime: number?,
	realtics: number?,
}

local playbackActive = false
local playbackBuffer = EMPTY_BUFFER
local playbackZoneOwned = false
local playbackOffset = 0
local playbackName: string? = nil
local playbackVersion: number? = nil
local playbackHeader: DemoHeader? = nil
local playbackStopReason: string? = nil
local deferredDemoName: string? = nil
local singleDemo = false
local timingDemo = false
local noDrawers = false
local noBlit = false
local startTime: number? = nil
local startGameTic: number? = nil
local lastTimingReport: TimingReport? = nil
local lastError: string? = nil

local recordingActive = false
local recordingBuffer = EMPTY_BUFFER
local recordingOffset = 0
local recordingCapacity = 0
local recordingName: string? = nil
local recordingBaseName: string? = nil
local recordingHeader: DemoHeader? = nil
local recordingSize = 0
local recordedBuffer = EMPTY_BUFFER
local recordingStopReason: string? = nil

const function ToUnsignedByte(value: number): number
	return bit32.band(value, 0xFF)
end

const function ToSignedByte(value: number): number
	value = ToUnsignedByte(value)
	return if value >= 0x80 then value - 0x100 else value
end

const function ToBoolean(value: boolean | number | nil, defaultValue: boolean, name: string): boolean
	if value == nil then
		return defaultValue
	end

	if typeof(value) == "boolean" then
		return value
	end

	if typeof(value) == "number" then
		return value ~= 0
	end

	error(`{name}: expected boolean or number`)
end

const function ToByteField(value: number?, defaultValue: number): number
	if value == nil then
		return defaultValue
	end

	return ToUnsignedByte(value)
end

const function ClonePlayerFlags(flags: PlayerFlags?): PlayerFlags
	const copy: PlayerFlags = {}

	for player = 0, Definitions.MAXPLAYERS - 1 do
		copy[player] = typeof(flags) == "table" and flags[player] == true
	end

	return copy
end

const function NormalizeHeader(header: HeaderInput?, defaults: HeaderInput?): DemoHeader
	const source: HeaderInput = if typeof(header) == "table" then header else {}
	const base: HeaderInput = if typeof(defaults) == "table" then defaults else {}

	return {
		version = ToByteField(source.version, if base.version ~= nil then base.version else Definitions.DEMO_VERSION),
		skill = ToByteField(source.skill, if base.skill ~= nil then base.skill else 0),
		episode = ToByteField(source.episode, if base.episode ~= nil then base.episode else 1),
		map = ToByteField(source.map, if base.map ~= nil then base.map else 1),
		deathmatch = ToBoolean(source.deathmatch, if base.deathmatch == true then true else false, "header.deathmatch"),
		respawn = ToBoolean(source.respawn, if base.respawn == true then true else false, "header.respawn"),
		fast = ToBoolean(source.fast, if base.fast == true then true else false, "header.fast"),
		nomonsters = ToBoolean(source.nomonsters, if base.nomonsters == true then true else false, "header.nomonsters"),
		consoleplayer = ToByteField(source.consoleplayer, if base.consoleplayer ~= nil then base.consoleplayer else 0),
		playeringame = ClonePlayerFlags(if source.playeringame ~= nil then source.playeringame else base.playeringame),
	}
end

const function BuildRecordingHeader(): DemoHeader
	const skill = Setup.GetCurrentSkill()

	return {
		version = Definitions.DEMO_VERSION,
		skill = skill,
		episode = Setup.GetCurrentEpisode(),
		map = Setup.GetCurrentMap(),
		deathmatch = false,
		-- Demo headers store the respawn parm bit, not the derived nightmare gameplay state.
		respawn = Setup.GetRespawnMonsters() and skill ~= Definitions.sk_nightmare,
		fast = Setup.GetFastParm(),
		nomonsters = Setup.GetNoMonsters(),
		consoleplayer = 0,
		playeringame = {
			[0] = true,
			[1] = false,
			[2] = false,
			[3] = false,
		},
	}
end

const function CloneHeader(header: DemoHeader?): DemoHeader?
	if typeof(header) ~= "table" then
		return nil
	end

	return {
		version = header.version,
		skill = header.skill,
		episode = header.episode,
		map = header.map,
		deathmatch = header.deathmatch == true,
		respawn = header.respawn == true,
		fast = header.fast == true,
		nomonsters = header.nomonsters == true,
		consoleplayer = header.consoleplayer,
		playeringame = ClonePlayerFlags(header.playeringame),
		size = header.size,
		headerSize = header.headerSize,
		ticcmdSize = header.ticcmdSize,
	}
end

const function NormalizeRecordingHeader(header: HeaderInput?): DemoHeader
	const normalized = NormalizeHeader(header, BuildRecordingHeader())

	normalized.version = Definitions.DEMO_VERSION
	normalized.deathmatch = false
	normalized.consoleplayer = 0
	normalized.playeringame[0] = true
	normalized.playeringame[1] = false
	normalized.playeringame[2] = false
	normalized.playeringame[3] = false

	return normalized
end

const function ParseHeaderBuffer(data: buffer, versions: VersionSet?)
	if typeof(data) ~= "buffer" then
		return false, "demo buffer missing"
	end

	versions = if typeof(versions) == "table" then versions else STRICT_COMPATIBLE_VERSIONS

	const length = buffer.len(data)

	if length < HEADER_SIZE then
		return false, "demo header truncated"
	end

	const version = buffer.readu8(data, 0)

	if versions[version] ~= true then
		return false, `unsupported demo version {version}`
	end

	const header: DemoHeader = {
		version = version,
		skill = buffer.readu8(data, 1),
		episode = buffer.readu8(data, 2),
		map = buffer.readu8(data, 3),
		deathmatch = buffer.readu8(data, 4) ~= 0,
		respawn = buffer.readu8(data, 5) ~= 0,
		fast = buffer.readu8(data, 6) ~= 0,
		nomonsters = buffer.readu8(data, 7) ~= 0,
		consoleplayer = buffer.readu8(data, 8),
		playeringame = {} :: PlayerFlags,
		size = length,
		headerSize = HEADER_SIZE,
		ticcmdSize = TICCMD_SIZE,
	}

	for player = 0, Definitions.MAXPLAYERS - 1 do
		header.playeringame[player] = buffer.readu8(data, 9 + player) ~= 0
	end

	return header
end

const function WriteHeaderBuffer(dest: buffer, header: DemoHeader)
	buffer.writeu8(dest, 0, header.version)
	buffer.writeu8(dest, 1, header.skill)
	buffer.writeu8(dest, 2, header.episode)
	buffer.writeu8(dest, 3, header.map)
	buffer.writeu8(dest, 4, if header.deathmatch then 1 else 0)
	buffer.writeu8(dest, 5, if header.respawn then 1 else 0)
	buffer.writeu8(dest, 6, if header.fast then 1 else 0)
	buffer.writeu8(dest, 7, if header.nomonsters then 1 else 0)
	buffer.writeu8(dest, 8, header.consoleplayer)

	for player = 0, Definitions.MAXPLAYERS - 1 do
		buffer.writeu8(dest, 9 + player, if header.playeringame[player] then 1 else 0)
	end
end

const function DecodeTiccmd(data: buffer, offset: number)
	if offset < 0 or offset >= buffer.len(data) then
		return false, "demo stream truncated"
	end

	const marker = buffer.readu8(data, offset)

	if marker == DEMOMARKER then
		return false, "finished"
	end

	if offset + TICCMD_SIZE > buffer.len(data) then
		return false, "demo stream truncated"
	end

	return {
		forwardmove = ToSignedByte(marker),
		sidemove = ToSignedByte(buffer.readu8(data, offset + 1)),
		angleturn = buffer.readu8(data, offset + 2) * 256,
		buttons = buffer.readu8(data, offset + 3),
	}, offset + TICCMD_SIZE
end

const function CopyTiccmd(dest: Ticcmd, src: Ticcmd): Ticcmd
	dest.forwardmove = src.forwardmove
	dest.sidemove = src.sidemove
	dest.angleturn = src.angleturn
	dest.buttons = src.buttons
	return dest
end

const function NormalizeDemoName(name: string): string
	if string.sub(name, -4) == ".lmp" then
		return name
	end

	return `{name}.lmp`
end

const function StopPlaybackInternal(reason: string?)
	playbackStopReason = if reason == nil then "stopped" else reason
end

const function ReleasePlaybackBuffer()
	if playbackZoneOwned and typeof(playbackBuffer) == "buffer" and buffer.len(playbackBuffer) > 0 then
		ChangeTag(playbackBuffer, CACHE)
	end

	playbackBuffer = EMPTY_BUFFER
	playbackZoneOwned = false
end

const function ResetPlayback()
	playbackActive = false
	ReleasePlaybackBuffer()
	playbackOffset = 0
	playbackName = nil
	playbackVersion = nil
	playbackHeader = nil
	playbackStopReason = nil
end

const function ResetRecording()
	recordingActive = false
	recordingBuffer = EMPTY_BUFFER
	recordingOffset = 0
	recordingCapacity = 0
	recordingName = nil
	recordingBaseName = nil
	recordingHeader = nil
	recordingSize = 0
	recordedBuffer = EMPTY_BUFFER
	recordingStopReason = nil
end

const function ResetState()
	deferredDemoName = nil
	singleDemo = false
	timingDemo = false
	noDrawers = false
	noBlit = false
	startTime = nil
	startGameTic = nil
	lastTimingReport = nil
end

const function ActivatePlaybackBuffer(data: buffer, name: string?, header: DemoHeader, zoneOwned: boolean)
	ResetPlayback()

	playbackActive = true
	playbackBuffer = data
	playbackZoneOwned = zoneOwned
	playbackOffset = HEADER_SIZE
	playbackName = if name == nil or name == "" then "<buffer>" else name
	playbackVersion = header.version
	playbackHeader = header
	playbackStopReason = nil
	lastError = nil

	return CloneHeader(header)
end

const function StartPlaybackData(data: buffer, name: string?, versions: VersionSet?, zoneOwned: boolean)

	const header, reason = ParseHeaderBuffer(data, versions)

	if header == false then
		lastError = reason
		return false, reason
	end

	return ActivatePlaybackBuffer(data, name, header, zoneOwned)
end

const function StartPlaybackBuffer(data: buffer, name: string?, versions: VersionSet?)
	return StartPlaybackData(data, name, versions, false)
end

const function StartStrictPlaybackBuffer(data: buffer, name: string?)
	return StartPlaybackData(data, name, STRICT_COMPATIBLE_VERSIONS, false)
end

const function ReadHeader(name: string)
	if CheckNumForName(name) == -1 then
		lastError = `missing demo lump {name}`
		return false
	end

	const data = CacheLumpName(name, STATIC)
	const header = ParseHeaderBuffer(data, COMPATIBLE_VERSIONS)

	if header == false then
		lastError = "failed to read demo header"
		return false
	end

	lastError = nil
	return CloneHeader(header)
end

const function BeginRecording(header: HeaderInput?)


	if header == nil then
		if Host.getRecordingHeader ~= nil then
			header = Host.getRecordingHeader()
		else
			header = BuildRecordingHeader()
		end
	end

	const normalized = NormalizeRecordingHeader(header)

	WriteHeaderBuffer(recordingBuffer, normalized)

	recordingHeader = CloneHeader(normalized)
	recordingHeader.size = nil
	recordingHeader.headerSize = HEADER_SIZE
	recordingHeader.ticcmdSize = TICCMD_SIZE
	recordingOffset = HEADER_SIZE

	return CloneHeader(recordingHeader)
end

const function FinishRecording(reason: string?)
	if not recordingActive then
		return false
	end

	if recordingHeader == nil then
		BeginRecording(nil)
	end


	buffer.writeu8(recordingBuffer, recordingOffset, DEMOMARKER)
	recordingOffset += 1
	recordingSize = recordingOffset
	recordedBuffer = buffer.create(recordingSize)
	buffer.copy(recordedBuffer, 0, recordingBuffer, 0, recordingSize)
	recordingActive = false
	recordingStopReason = if reason == nil then "finished" else reason

	return {
		name = recordingName,
		baseName = recordingBaseName,
		size = recordingSize,
		reason = recordingStopReason,
		header = CloneHeader(recordingHeader),
		buffer = recordedBuffer,
	}
end

const function StartRecording(name: string, maxSize: number?)


	const capacity = if maxSize == nil then DEFAULT_MAXDEMO else maxSize


	ResetRecording()

	recordingActive = true
	recordingBuffer = buffer.create(capacity)
	recordingCapacity = capacity
	recordingBaseName = name
	recordingName = NormalizeDemoName(name)

	return true
end

const function StartPlayback(name: string)

	if CheckNumForName(name) == -1 then
		lastError = `missing demo lump {name}`
		return false
	end

	const data = CacheLumpName(name, STATIC)

	return StartPlaybackData(data, name, COMPATIBLE_VERSIONS, true)
end

const function StartStrictPlayback(name: string)

	if CheckNumForName(name) == -1 then
		lastError = `missing demo lump {name}`
		return false
	end

	const data = CacheLumpName(name, STATIC)

	return StartPlaybackData(data, name, STRICT_COMPATIBLE_VERSIONS, true)
end

const function ReadPlaybackTiccmd(stopOnFailure: boolean)
	if not playbackActive then
		return false, "inactive"
	end

	const cmd, nextOffset = DecodeTiccmd(playbackBuffer, playbackOffset)

	if cmd == false then
		if stopOnFailure then
			StopPlaybackInternal(nextOffset)
		end

		return false, nextOffset
	end

	playbackOffset = nextOffset
	return cmd
end

const function ReadTiccmd()
	const cmd = ReadPlaybackTiccmd(true)

	if cmd == false then
		return false
	end

	return cmd
end

const function CheckDemoStatus(): boolean
	if timingDemo then
		const endTime = if Host.getRealTime ~= nil then Host.getRealTime() else nil
		const gameTic = if Host.getGameTic ~= nil then Host.getGameTic() else nil
		local gameTicsElapsed: number? = nil

		if typeof(gameTic) == "number" and typeof(startGameTic) == "number" then
			gameTicsElapsed = gameTic - startGameTic
		else
			gameTicsElapsed = gameTic
		end

		lastTimingReport = {
			gametics = gameTicsElapsed,
			starttime = startTime,
			startgametic = startGameTic,
			endgametic = gameTic,
			endtime = endTime,
			realtics = if typeof(endTime) == "number" and typeof(startTime) == "number" then endTime - startTime else nil,
		}

		if Host.onTimingDemoComplete ~= nil then
			Host.onTimingDemoComplete(lastTimingReport)
		end

		timingDemo = false

		if playbackActive then
			StopPlaybackInternal("timedemo")
		end
	end

	if playbackActive then
		const stopReason = if playbackStopReason == nil then "finished" else playbackStopReason
		const shouldAdvance = stopReason == "finished"
		const shouldQuit = singleDemo and shouldAdvance

		playbackStopReason = stopReason
		playbackActive = false
		ReleasePlaybackBuffer()
		Setup.SetDemoPlayback(false)
		Setup.SetRespawnMonsters(false)
		Setup.SetFastParm(false)
		Setup.SetNoMonsters(false)

		if shouldQuit then
			if Host.quit ~= nil then
				Host.quit()
			end
		elseif shouldAdvance and Host.advanceDemo ~= nil then
			Host.advanceDemo()
		end

		return true
	end

	if recordingActive then
		const result = FinishRecording("finished")

		if result ~= false and Host.writeRecordedDemo ~= nil then
			Host.writeRecordedDemo(recordingName, result.buffer, result)
		end

		return true
	end

	return false
end

const function ReadDemoTiccmd(cmd: Ticcmd?)
	const demoCmd, reason = ReadPlaybackTiccmd(false)

	if demoCmd == false then
		if reason ~= "inactive" then
			StopPlaybackInternal(reason)
			CheckDemoStatus()
		end

		return false
	end

	if typeof(cmd) == "table" then
		return CopyTiccmd(cmd, demoCmd)
	end

	return demoCmd
end

const function WriteDemoTiccmd(cmd: Ticcmd)


	if recordingHeader == nil then
		BeginRecording(nil)
	end

	const baseOffset = recordingOffset

	buffer.writeu8(recordingBuffer, baseOffset, ToUnsignedByte(cmd.forwardmove or 0))
	buffer.writeu8(recordingBuffer, baseOffset + 1, ToUnsignedByte(cmd.sidemove or 0))
	buffer.writeu8(recordingBuffer, baseOffset + 2, ToUnsignedByte(bit32.rshift(bit32.band(cmd.angleturn or 0, 0xFFFF) + 128, 8)))
	buffer.writeu8(recordingBuffer, baseOffset + 3, ToUnsignedByte(cmd.buttons or 0))

	if baseOffset > recordingCapacity - 16 then
		recordingOffset = baseOffset
		CheckDemoStatus()
		return false
	end

	const exact = DecodeTiccmd(recordingBuffer, baseOffset)

	if exact == false then
		recordingOffset = baseOffset
		CheckDemoStatus()
		return false
	end

	recordingOffset = baseOffset + TICCMD_SIZE
	return CopyTiccmd(cmd, exact)
end

const function WriteTiccmd(cmd: Ticcmd)
	const exact = WriteDemoTiccmd(cmd)

	if exact == false then
		return false
	end

	return {
		forwardmove = exact.forwardmove,
		sidemove = exact.sidemove,
		angleturn = exact.angleturn,
		buttons = exact.buttons,
	}
end

const function DeferedPlayDemo(name: string)

	deferredDemoName = name
	return true
end

const function DoPlayDemo()
	if deferredDemoName == nil then
		return false
	end

	const name = deferredDemoName
	deferredDemoName = nil

	if CheckNumForName(name) == -1 then
		lastError = `missing demo lump {name}`
		return false
	end

	const data = CacheLumpName(name, STATIC)
	const header, reason = ParseHeaderBuffer(data, COMPATIBLE_VERSIONS)

	if header == false then
		lastError = reason
		return false, reason
	end

	const info = ActivatePlaybackBuffer(data, name, header, true)
	const restorePrecache = Setup.GetPrecache()

	Setup.SetNoMonsters(header.nomonsters)
	Setup.SetFastParm(header.fast)
	Setup.SetRespawnMonsters(header.respawn or header.skill == Definitions.sk_nightmare)
	Setup.SetDemoPlayback(true)
	Setup.SetCurrentSkill(header.skill)
	Setup.SetPrecache(false)
	Random.ClearRandom()
	Setup.GetPlayers()[0].playerstate = 2
	Setup.SetupLevel(header.episode, header.map, 0, header.skill)
	Setup.SetPrecache(restorePrecache)

	if info ~= false and Host.applyPlaybackHeader ~= nil then
		Host.applyPlaybackHeader(CloneHeader(info))
	end

	return info
end

const function TimeDemo(name: string, options: TimingOptions?)
	DeferedPlayDemo(name)
	singleDemo = false
	timingDemo = true
	lastTimingReport = nil
	noDrawers = false
	noBlit = false
	startTime = nil
	startGameTic = nil

	if typeof(options) == "table" then
		noDrawers = options.noDrawers == true
		noBlit = options.noBlit == true
		startTime = options.startTime
		startGameTic = options.startGameTic
	end

	return true
end

const function Reset()
	ResetPlayback()
	ResetRecording()
	ResetState()
end

const function ReadStrictHeader(name: string)
	if CheckNumForName(name) == -1 then
		return false
	end

	const data = CacheLumpName(name, STATIC)
	const header = ParseHeaderBuffer(data, STRICT_COMPATIBLE_VERSIONS)

	if header == false then
		return false
	end

	return CloneHeader(header)
end

const function ReadHeaderBuffer(data: buffer)
	const header = ParseHeaderBuffer(data, COMPATIBLE_VERSIONS)

	if header == false then
		return false
	end

	return CloneHeader(header)
end

const function ReadStrictHeaderBuffer(data: buffer)
	const header = ParseHeaderBuffer(data, STRICT_COMPATIBLE_VERSIONS)

	if header == false then
		return false
	end

	return CloneHeader(header)
end

const function IsCompatibleVersion(version: number): boolean
	if typeof(version) ~= "number" or version ~= version // 1 then
		return false
	end

	return COMPATIBLE_VERSIONS[ToUnsignedByte(version)] == true
end

const function IsStrictCompatibleVersion(version: number): boolean
	if typeof(version) ~= "number" or version ~= version // 1 then
		return false
	end

	return STRICT_COMPATIBLE_VERSIONS[ToUnsignedByte(version)] == true
end

const function PlayDemo(name: string)
	DeferedPlayDemo(name)
	return DoPlayDemo()
end

const function StopPlayback(reason: string?): boolean
	if not playbackActive then
		return false
	end

	StopPlaybackInternal(if reason == nil then "stopped" else reason)
	return CheckDemoStatus()
end

const function IsActive(): boolean
	return playbackActive
end

const function GetName()
	return playbackName
end

const function GetVersion()
	return playbackVersion
end

const function GetHeader()
	return CloneHeader(playbackHeader)
end

const function GetOffset(): number
	return playbackOffset
end

const function GetDeferredName()
	return deferredDemoName
end

const function SetSingleDemo(value: boolean)
	singleDemo = value
end

const function GetSingleDemo(): boolean
	return singleDemo
end

const function SetTimingDemo(value: boolean)
	timingDemo = value
end

const function GetTimingDemo(): boolean
	return timingDemo
end

const function SetTimingOptions(values: TimingOptions)
	if values.noDrawers ~= nil then
		noDrawers = values.noDrawers == true
	end

	if values.noBlit ~= nil then
		noBlit = values.noBlit == true
	end

	if values.startTime ~= nil then
		startTime = values.startTime
	end

	if values.startGameTic ~= nil then
		startGameTic = values.startGameTic
	end
end

const function GetTimingOptions()
	return {
		noDrawers = noDrawers,
		noBlit = noBlit,
		startTime = startTime,
		startGameTic = startGameTic,
		lastReport = lastTimingReport,
	}
end

const function GetLastError(): string?
	return lastError
end

const function GetLastStopReason()
	return playbackStopReason
end

const function IsRecording(): boolean
	return recordingActive
end

const function GetRecordingName()
	return recordingName
end

const function GetRecordingBaseName()
	return recordingBaseName
end

const function GetRecordingHeader()
	return CloneHeader(recordingHeader)
end

const function GetRecordingOffset(): number
	return recordingOffset
end

const function GetRecordingSize(): number
	return recordingSize
end

const function GetRecordingStopReason()
	return recordingStopReason
end

const function GetRecordedBuffer()
	return recordedBuffer
end

return {
	DEMOMARKER = DEMOMARKER,
	HEADER_SIZE = HEADER_SIZE,
	TICCMD_SIZE = TICCMD_SIZE,
	DEFAULT_MAXDEMO = DEFAULT_MAXDEMO,
	COMPATIBLE_VERSIONS = COMPATIBLE_VERSIONS,
	STRICT_COMPATIBLE_VERSIONS = STRICT_COMPATIBLE_VERSIONS,

	Reset = Reset,

	ReadHeader = ReadHeader,
	ReadStrictHeader = ReadStrictHeader,
	ReadHeaderBuffer = ReadHeaderBuffer,
	ReadStrictHeaderBuffer = ReadStrictHeaderBuffer,
	IsCompatibleVersion = IsCompatibleVersion,
	IsStrictCompatibleVersion = IsStrictCompatibleVersion,
	StartPlayback = StartPlayback,
	StartStrictPlayback = StartStrictPlayback,
	StartPlaybackBuffer = StartPlaybackBuffer,
	StartStrictPlaybackBuffer = StartStrictPlaybackBuffer,
	DeferedPlayDemo = DeferedPlayDemo,
	DoPlayDemo = DoPlayDemo,
	PlayDemo = PlayDemo,
	TimeDemo = TimeDemo,
	StopPlayback = StopPlayback,
	ReadTiccmd = ReadTiccmd,
	ReadDemoTiccmd = ReadDemoTiccmd,
	IsActive = IsActive,
	GetName = GetName,
	GetVersion = GetVersion,
	GetHeader = GetHeader,
	GetOffset = GetOffset,
	GetDeferredName = GetDeferredName,
	SetSingleDemo = SetSingleDemo,
	GetSingleDemo = GetSingleDemo,
	SetTimingDemo = SetTimingDemo,
	GetTimingDemo = GetTimingDemo,
	SetTimingOptions = SetTimingOptions,
	GetTimingOptions = GetTimingOptions,
	GetLastError = GetLastError,
	GetLastStopReason = GetLastStopReason,

	StartRecording = StartRecording,
	BeginRecording = BeginRecording,
	WriteTiccmd = WriteTiccmd,
	WriteDemoTiccmd = WriteDemoTiccmd,
	FinishRecording = FinishRecording,
	IsRecording = IsRecording,
	GetRecordingName = GetRecordingName,
	GetRecordingBaseName = GetRecordingBaseName,
	GetRecordingHeader = GetRecordingHeader,
	GetRecordingOffset = GetRecordingOffset,
	GetRecordingSize = GetRecordingSize,
	GetRecordingStopReason = GetRecordingStopReason,
	GetRecordedBuffer = GetRecordedBuffer,

	CheckDemoStatus = CheckDemoStatus,
}
