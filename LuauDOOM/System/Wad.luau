--!native
--!optimize 2

-- Port of w_wad.c, w_wad.h
-- Handles WAD file header, directory, lump I/O.
-- Buffer-based WAD directory parsing and lump access.
-- TODO: Add an InitMultipleFiles-style buffer wrapper if higher-level boot code wants it.
-- TODO: Add a Reload equivalent if live map/WAD replacement is needed.
-- TODO: Expose lump table metadata in a form future renderer ports can inspect like `lumpinfo`.

const Zone = require("./Zone")

const DIRECTORY_ENTRY_SIZE = 16
const LUMP_NAME_SIZE = 8

-- GLOBALS

-- Location of each lump in source buffers.
local numlumps = 0
local iwadLumpCount = 0
local iwadSourceCount = 0
local sourceCount = 0

const sourceBuffers: { [number]: buffer } = {}

const lumpNames: { [number]: string } = {}
const lumpPositions: { [number]: number } = {}
const lumpSizes: { [number]: number } = {}
const lumpSources: { [number]: number } = {}
const lumpCache: { [number]: buffer } = {}
const lumpCacheTag: { [number]: number } = {}
const nameToLump: { [string]: number } = {}

const function CanonicalizeName(name: string): string
	local length = #name

	if length > LUMP_NAME_SIZE then
		length = LUMP_NAME_SIZE
	end

	const zero = string.find(name, "\0", 1, true)

	if zero ~= nil and zero <= length then
		length = zero - 1
	end

	return string.upper(string.sub(name, 1, length))
end

const function ReadLumpName(data: buffer, offset: number): string
	local name = ""

	for index = 0, LUMP_NAME_SIZE - 1 do
		local byte = buffer.readu8(data, offset + index)

		if byte == 0 then
			break
		end

		if byte >= 97 and byte <= 122 then
			byte -= 32
		end

		name ..= string.char(byte)
	end

	return name
end

const function RebuildNameLookup()
	table.clear(nameToLump)

	-- Lump names can appear multiple times.
	-- The name searcher looks backwards, so a later file
	-- does override all earlier ones.
	for lump = 0, numlumps - 1 do
		nameToLump[lumpNames[lump]] = lump
	end
end

const function FreeCachedLump(lump: number)
	const cached = lumpCache[lump]

	if cached ~= nil then
		Zone.Free(cached)
	end

	lumpCache[lump] = nil
	lumpCacheTag[lump] = nil
end

const function Reset()
	for lump = 0, numlumps - 1 do
		FreeCachedLump(lump)
	end

	numlumps = 0
	iwadLumpCount = 0
	iwadSourceCount = 0
	sourceCount = 0

	table.clear(sourceBuffers)

	table.clear(lumpNames)
	table.clear(lumpPositions)
	table.clear(lumpSizes)
	table.clear(lumpSources)
	table.clear(lumpCache)
	table.clear(lumpCacheTag)
	table.clear(nameToLump)
end

-- LUMP BASED ROUTINES.

-- AddFile
-- All files are optional, but at least one file must be
--  found (PWAD, if all required lumps are present).
-- Files with a .wad extension are wadlink files
--  with multiple lumps.
-- This Luau port only accepts already-provided WAD buffers.
-- Single-lump loose files and the reload hack are intentionally omitted.
const function AppendWAD(data: buffer, label: string?): (number, number)
	const sourceLabel = label or "WAD"

	const dataLength = buffer.len(data)
	const wadNumLumps = buffer.readi32(data, 4)
	const infoTableOfs = buffer.readi32(data, 8)

	const sourceIndex = sourceCount + 1
	const startLump = numlumps
	sourceCount = sourceIndex

	sourceBuffers[sourceIndex] = data

	for index = 0, wadNumLumps - 1 do
		const directoryOffset = infoTableOfs + index * DIRECTORY_ENTRY_SIZE
		const filepos = buffer.readi32(data, directoryOffset)
		const lumpSize = buffer.readi32(data, directoryOffset + 4)
		const lumpName = ReadLumpName(data, directoryOffset + 8)
		const lumpIndex = startLump + index

		if lumpSize ~= 0 and filepos + lumpSize > dataLength then
			error(`{sourceLabel}: lump {lumpIndex} overruns the source buffer`)
		end

		lumpNames[lumpIndex] = lumpName
		lumpPositions[lumpIndex] = filepos
		lumpSizes[lumpIndex] = lumpSize
		lumpSources[lumpIndex] = sourceIndex
		lumpCache[lumpIndex] = nil
		lumpCacheTag[lumpIndex] = nil
		nameToLump[lumpName] = lumpIndex
	end

	numlumps += wadNumLumps

	return startLump, wadNumLumps
end

-- InitFile
-- Just initialize from a single file.
const function LoadIWAD(data: buffer, label: string?): (number, number)
	Reset()

	const startLump, wadNumLumps = AppendWAD(data, label or "IWAD")

	iwadLumpCount = numlumps
	iwadSourceCount = sourceCount

	return startLump, wadNumLumps
end

-- Appends one PWAD on top of the current lump directory.
const function LoadPWAD(data: buffer, label: string?): (number, number)
	const startLump, wadNumLumps = AppendWAD(data, label or "PWAD")
	return startLump, wadNumLumps
end

-- Removes mod WAD state while keeping the current IWAD.
const function ClearPWADs()
	if numlumps == iwadLumpCount and sourceCount == iwadSourceCount then
		return
	end

	for lump = iwadLumpCount, numlumps - 1 do
		FreeCachedLump(lump)
		lumpNames[lump] = nil
		lumpPositions[lump] = nil
		lumpSizes[lump] = nil
		lumpSources[lump] = nil
	end

	for sourceIndex = sourceCount, iwadSourceCount + 1, -1 do
		sourceBuffers[sourceIndex] = nil
	end

	numlumps = iwadLumpCount
	sourceCount = iwadSourceCount

	RebuildNameLookup()
end

const function GetLumpName(lump: number): string
	return lumpNames[lump]
end

-- CheckNumForName
-- Returns -1 if name not found.
const function CheckNumForName(name: string): number
	const lump = nameToLump[CanonicalizeName(name)]

	return if lump == nil then -1 else lump
end

const function GetNumForName(name: string): number
	return CheckNumForName(name)
end

-- LumpLength
-- Returns the buffer size needed to load the given lump.
const function LumpLength(lump: number): number
	return lumpSizes[lump]
end

-- ReadLump
-- Loads the lump into the given buffer,
--  which must be >= LumpLength().
const function ReadLump(lump: number, dest: buffer?, destOffset: number?): buffer
	const lumpSize = lumpSizes[lump]
	const lumpSource = sourceBuffers[lumpSources[lump]]
	const lumpPosition = lumpPositions[lump]
	local output = dest
	local writeOffset = destOffset or 0

	if output == nil then
		output = buffer.create(lumpSize)
		writeOffset = 0
	elseif writeOffset + lumpSize > buffer.len(output) then
		error(`ReadLump: destination buffer too small for lump {lump}`)
	end

	buffer.copy(output, writeOffset, lumpSource, lumpPosition, lumpSize)

	return output
end

-- CacheLumpNum
const function CacheLumpNum(lump: number, tag: number?): buffer
	if lump < 0 or lumpSizes[lump] == nil then
		error(`CacheLumpNum: invalid lump {lump}`)
	end

	const cacheTag = if tag ~= nil then tag else Zone.STATIC
	local cached = lumpCache[lump]

	if cached ~= nil then
		if lumpCacheTag[lump] ~= cacheTag then
			Zone.ChangeTag(cached, cacheTag)
			lumpCacheTag[lump] = cacheTag
		end

		return cached
	end

	const lumpSize = lumpSizes[lump]
	const lumpSource = sourceBuffers[lumpSources[lump]]
	const lumpPosition = lumpPositions[lump]

	cached = Zone.Malloc(lumpSize, cacheTag, lumpCache, lump)
	lumpCacheTag[lump] = cacheTag
	buffer.copy(cached, 0, lumpSource, lumpPosition, lumpSize)

	return cached
end

-- CacheLumpName
const function CacheLumpName(name: string, tag: number?): buffer
	const lump = CheckNumForName(name)

	if lump < 0 then
		error(`CacheLumpName: missing lump {CanonicalizeName(name)}`)
	end

	return CacheLumpNum(lump, tag)
end

return {
	Reset = Reset,
	LoadIWAD = LoadIWAD,
	LoadPWAD = LoadPWAD,
	ClearPWADs = ClearPWADs,

	GetLumpName = GetLumpName,

	CheckNumForName = CheckNumForName,
	GetNumForName = GetNumForName,
	LumpLength = LumpLength,
	ReadLump = ReadLump,
	CacheLumpNum = CacheLumpNum,
	CacheLumpName = CacheLumpName,
}
