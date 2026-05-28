--!native
--!optimize 2

-- Port of r_data.c, r_data.h
-- Refresh module, data I/O, caching, retrieval of graphics
-- by name.
-- `R_PrecacheLevel` prefers thinker-driven sprite discovery when play code has
-- populated the shared renderer host bridge; otherwise it falls back to sector
-- thinglists.
-- COLORMAP pointer alignment from C is not meaningful for Luau buffers.

const Wad = require("../System/Wad")
const Zone = require("../System/Zone")
const Host = require("./Host")
const Sky = require("./Sky")
const State = require("./State")

const EMPTY_BUFFER = buffer.create(0)
const FRACUNIT = 65536
const CacheLumpNum = Wad.CacheLumpNum
const CacheLumpName = Wad.CacheLumpName
const CheckNumForName = Wad.CheckNumForName
const GetNumForName = Wad.GetNumForName
const LumpLength = Wad.LumpLength
const CACHE = Zone.CACHE
const STATIC = Zone.STATIC
const SkyGetSkyTexture = Sky.GetSkyTexture

type Texture = {
	name: string,
	canonicalName: string,
	width: number,
	height: number,
	patchcount: number,
	widthmask: number,
	patchoriginx: buffer,
	patchoriginy: buffer,
	patchlump: buffer,
	patchwidth: buffer,
	patchdata: { [number]: buffer },
	coveredscratch: buffer,
	maskedpixelsscratch: buffer,
	linearcachedata: buffer,
	linearcachebuilt: boolean,
	columnlump: buffer,
	columnofs: buffer,
	columncache: { [number]: buffer },
}

local lastflat = 0
local numflats = 0

local numtextures = 0
const textures: { [number]: Texture } = {}
const maskedcompositecolumn: { [number]: { [number]: buffer } } = {}
local colormapsAllocated = false

const function CanonicalizeName(name: string): string
	local length = #name

	if length > 8 then
		length = 8
	end

	local canonical = ""

	for index = 1, length do
		local byte = string.byte(name, index)

		if byte == nil or byte == 0 then
			break
		end

		if byte >= 97 and byte <= 122 then
			byte -= 32
		end

		canonical ..= string.char(byte)
	end

	return canonical
end

const function ReadLumpName(data: buffer, offset: number): string
	local name = ""

	for index = 0, 7 do
		const byte = buffer.readu8(data, offset + index)

		if byte == 0 then
			break
		end

		name ..= string.char(byte)
	end

	return CanonicalizeName(name)
end

const function ReadPatchHeader(patch: buffer): (number, number, number, number)
	return buffer.readi16(patch, 0), buffer.readi16(patch, 2), buffer.readi16(patch, 4), buffer.readi16(patch, 6)
end

const function Reset()
	if colormapsAllocated then
		Zone.Free(State.colormaps)
		colormapsAllocated = false
	end

	lastflat = 0
	numflats = 0
	numtextures = 0

	table.clear(textures)
	table.clear(maskedcompositecolumn)

	State.textureheight = {}
	State.firstflat = 0
	State.texturetranslation = {}
	State.flattranslation = {}
	State.firstspritelump = 0
	State.lastspritelump = 0
	State.numspritelumps = 0
	State.spritewidth = {}
	State.spriteoffset = {}
	State.spritetopoffset = {}
	State.numsprites = 0
	State.sprites = {}
	State.colormaps = EMPTY_BUFFER
end

-- Graphics.
-- DOOM graphics for walls and sprites
-- is stored in vertical runs of opaque pixels (posts).
-- A column is composed of zero or more posts,
-- a patch or sprite is composed of zero or more columns.

-- Texture definition.
-- Each texture is composed of one or more patches,
-- with patches being lumps stored in the WAD.
-- The lumps are referenced by number, and patched
-- into the rectangular texture space using origin
-- and possibly other attributes.

-- Texture definition.
-- A DOOM wall texture is a list of patches
-- which are to be combined in a predefined order.

-- MAPTEXTURE_T CACHING
-- When a texture is first needed,
--  it counts the number of composite columns
--  required in the texture and allocates space
--  for a column directory and any new columns.
-- The directory will simply point inside other patches
--  if there is only one patch in a given column,
--  but any columns with multiple patches
--  will have new column_ts generated.

const function BuildMaskedCompositeColumn(texnum: number, col: number): (buffer, number)
	const perTextureCache = maskedcompositecolumn[texnum]
	const cacheIndex = col + 1
	const cached = perTextureCache[cacheIndex]

	if cached ~= nil then
		return cached, 0
	end

	const texture = textures[texnum]
	const height = texture.height
	const patchcount = texture.patchcount
	const patchoriginx = texture.patchoriginx
	const patchoriginy = texture.patchoriginy
	const patchwidth = texture.patchwidth
	const patchdata = texture.patchdata
	const covered = texture.coveredscratch
	const pixels = texture.maskedpixelsscratch
	buffer.fill(covered, 0, 0, height)

	local patchIndex = 0
	local patchOriginOffset = 0

	for _ = 1, patchcount do
		const originx = buffer.readi16(patchoriginx, patchOriginOffset)
		const width = buffer.readi16(patchwidth, patchOriginOffset)
		const patchColumn = col - originx

		if patchColumn >= 0 and patchColumn < width then
			const patch: buffer = patchdata[patchIndex]
			const originy = buffer.readi16(patchoriginy, patchOriginOffset)
			local patchOffset = buffer.readi32(patch, 8 + patchColumn * 4)

			while true do
				const topdelta = buffer.readu8(patch, patchOffset)

				if topdelta == 0xFF then
					break
				end

				const count = buffer.readu8(patch, patchOffset + 1)
				local position = originy + topdelta
				local sourceOffset = patchOffset + 3
				local copyCount = count

				if position < 0 then
					sourceOffset -= position
					copyCount += position
					position = 0
				end

				if position + copyCount > height then
					copyCount = height - position
				end

				if copyCount > 0 then
					buffer.copy(pixels, position, patch, sourceOffset, copyCount)
					buffer.fill(covered, position, 1, copyCount)
				end

				patchOffset += count + 4
			end
		end

		patchIndex += 1
		patchOriginOffset += 2
	end

	local encodedSize = 1
	local row = 0

	while row < height do
		if buffer.readu8(covered, row) ~= 0 then
			const start = row

			repeat
				row += 1
			until row >= height or buffer.readu8(covered, row) == 0

			encodedSize += (row - start) + 4
		else
			row += 1
		end
	end

	const encoded = buffer.create(encodedSize)
	local writeOffset = 0
	row = 0

	while row < height do
		if buffer.readu8(covered, row) ~= 0 then
			const start = row

			repeat
				row += 1
			until row >= height or buffer.readu8(covered, row) == 0

			const length = row - start
			buffer.writeu8(encoded, writeOffset, start)
			buffer.writeu8(encoded, writeOffset + 1, length)
			buffer.writeu8(encoded, writeOffset + 2, 0)
			buffer.copy(encoded, writeOffset + 3, pixels, start, length)
			buffer.writeu8(encoded, writeOffset + 3 + length, 0)
			writeOffset += length + 4
		else
			row += 1
		end
	end

	buffer.writeu8(encoded, writeOffset, 0xFF)
	perTextureCache[cacheIndex] = encoded
	return encoded, 0
end

const function BuildLinearCompositeTexture(texnum: number): buffer
	const texture = textures[texnum]
	local linearcachedata = texture.linearcachedata

	if linearcachedata == EMPTY_BUFFER then
		linearcachedata = buffer.create(math.max(texture.width * texture.height, 1))
		texture.linearcachedata = linearcachedata
	end

	if texture.linearcachebuilt then
		return linearcachedata
	end

	const height = texture.height
	const width = texture.width
	const patchcount = texture.patchcount
	const patchoriginx = texture.patchoriginx
	const patchoriginy = texture.patchoriginy
	const patchwidth = texture.patchwidth
	const patchdata = texture.patchdata

	local patchIndex = 0
	local patchOriginOffset = 0

	for _ = 1, patchcount do
		const originx = buffer.readi16(patchoriginx, patchOriginOffset)
		const patchColumnWidth = buffer.readi16(patchwidth, patchOriginOffset)
		const x1 = if originx < 0 then 0 else originx
		local x2 = originx + patchColumnWidth

		if x2 > width then
			x2 = width
		end

		if x1 < x2 then
			const patch: buffer = patchdata[patchIndex]
			const originy = buffer.readi16(patchoriginy, patchOriginOffset)
			const patchColumnEndOffset = 8 + (x2 - originx) * 4 - 4
			local columnOffset = x1 * height

			for patchColumnOffset = 8 + (x1 - originx) * 4, patchColumnEndOffset, 4 do
				local patchOffset = buffer.readi32(patch, patchColumnOffset)

				while true do
					const topdelta = buffer.readu8(patch, patchOffset)

					if topdelta == 0xFF then
						break
					end

					const count = buffer.readu8(patch, patchOffset + 1)
					local position = originy + topdelta
					local sourceOffset = patchOffset + 3
					local copyCount = count

					if position < 0 then
						sourceOffset -= position
						copyCount += position
						position = 0
					end

					if position + copyCount > height then
						copyCount = height - position
					end

					if copyCount > 0 then
						buffer.copy(linearcachedata, columnOffset + position, patch, sourceOffset, copyCount)
					end

					patchOffset += count + 4
				end

				columnOffset += height
			end
		end

		patchIndex += 1
		patchOriginOffset += 2
	end

	texture.linearcachebuilt = true

	-- Raw single-patch columns preserve Doom's sky behavior, but normal wall
	-- textures need post composition or patch holes/offsets leak as columns.
	if texnum == SkyGetSkyTexture() then
		const columnlump = texture.columnlump
		const columnofs = texture.columnofs
		local columnOffset = 0
		const widthByteEnd = width * 4 - 4

		for columnByteOffset = 0, widthByteEnd, 4 do
			const lump = buffer.readi32(columnlump, columnByteOffset)

			if lump >= 0 then
				const patch = CacheLumpNum(lump, CACHE)
				const sourceOffset = buffer.readi32(columnofs, columnByteOffset)
				local copyCount = height
				const available = buffer.len(patch) - sourceOffset

				if copyCount > available then
					copyCount = available
				end

				if copyCount > 0 then
					buffer.copy(linearcachedata, columnOffset, patch, sourceOffset, copyCount)
				end
			end

			columnOffset += height
		end
	end

	return linearcachedata
end

-- GenerateLookup
const function GenerateLookup(texnum: number)
	const texture = textures[texnum]

	const collump = buffer.create(texture.width * 4)
	const colofs = buffer.create(texture.width * 4)
	const columnpatchcount = buffer.create(texture.width * 2)
	const patchoriginx = texture.patchoriginx
	const patchwidth = texture.patchwidth
	const patchdata = texture.patchdata
	local compositeSize = 0

	texture.columnlump = collump
	texture.columnofs = colofs

	local patchIndex = 0
	local patchOriginOffset = 0
	local patchLumpOffset = 0

	for _ = 1, texture.patchcount do
		const patchLump = buffer.readi32(texture.patchlump, patchLumpOffset)
		const realpatch: buffer = patchdata[patchIndex]
		const width = buffer.readi16(patchwidth, patchOriginOffset)
		const x1 = buffer.readi16(patchoriginx, patchOriginOffset)
		local x2 = x1 + width
		const x = if x1 < 0 then 0 else x1

		if x2 > texture.width then
			x2 = texture.width
		end

		local patchcountOffset = x * 2
		local byteOffset = x * 4
		const patchColumnOffset = 8 + (x - x1) * 4
		const patchColumnEndOffset = patchColumnOffset + (x2 - x) * 4 - 4

		for patchColumnByteOffset = patchColumnOffset, patchColumnEndOffset, 4 do
			buffer.writeu16(columnpatchcount, patchcountOffset, buffer.readu16(columnpatchcount, patchcountOffset) + 1)
			buffer.writei32(collump, byteOffset, patchLump)
			buffer.writei32(colofs, byteOffset, buffer.readi32(realpatch, patchColumnByteOffset) + 3)
			patchcountOffset += 2
			byteOffset += 4
		end

		patchIndex += 1
		patchOriginOffset += 2
		patchLumpOffset += 4
	end

	local patchcountOffset = 0
	const textureWidthByteEnd = texture.width * 4 - 4

	for byteOffset = 0, textureWidthByteEnd, 4 do
		const patchcount = buffer.readu16(columnpatchcount, patchcountOffset)

		if patchcount == 0 then
			buffer.writei32(collump, byteOffset, -1)
			buffer.writei32(colofs, byteOffset, compositeSize)
			continue
		end

		if patchcount > 1 then
			buffer.writei32(collump, byteOffset, -1)
			buffer.writei32(colofs, byteOffset, compositeSize)
			compositeSize += texture.height
		end

		patchcountOffset += 2
	end
end

-- GetColumn
const function GetColumn(tex: number, col: number): (buffer, number)
	const texture = textures[tex]
	col = bit32.band(col, texture.widthmask)

	const cacheIndex = col + 1
	const columncache = texture.columncache
	const cached = columncache[cacheIndex]

	if cached ~= nil then
		return cached, 0
	end

	const byteOffset = col * 4
	const lump = buffer.readi32(texture.columnlump, byteOffset)
	const ofs = buffer.readi32(texture.columnofs, byteOffset)
	local source = EMPTY_BUFFER
	local sourceOffset = 0

	if lump >= 0 then
		source = CacheLumpNum(lump, CACHE)
		sourceOffset = ofs
	else
		source = BuildLinearCompositeTexture(tex)
		sourceOffset = col * texture.height
	end

	const column = buffer.create(128)
	local available = buffer.len(source) - sourceOffset

	if available > 128 then
		available = 128
	end

	if available > 0 then
		buffer.copy(column, 0, source, sourceOffset, available)
		const fill = buffer.readu8(column, available - 1)

		if available < 128 then
			buffer.fill(column, available, fill, 128 - available)
		end
	end

	columncache[cacheIndex] = column
	return column, 0
end

const function GetLinearColumnSource(tex: number): (buffer, number, number)
	const texture = textures[tex]

	return BuildLinearCompositeTexture(tex), texture.widthmask, texture.height
end

const function GetMaskedColumn(tex: number, col: number): (buffer, number)
	const texture = textures[tex]
	col = bit32.band(col, texture.widthmask)

	const byteOffset = col * 4
	const lump = buffer.readi32(texture.columnlump, byteOffset)
	const ofs = buffer.readi32(texture.columnofs, byteOffset)

	if lump >= 0 then
		return CacheLumpNum(lump, CACHE), ofs - 3
	end

	return BuildMaskedCompositeColumn(tex, col)
end

-- InitTextures
-- Initializes the texture list
--  with the textures from the world map.
const function InitTextures()
	const names = CacheLumpName("PNAMES", STATIC)
	const nummappatches = buffer.readi32(names, 0)
	const patchlookup: { [number]: number } = {}

	local patchNameIndex = 0
	const patchNameByteEnd = nummappatches * 8 - 4

	for nameOffset = 4, patchNameByteEnd, 8 do
		const name = ReadLumpName(names, nameOffset)
		patchlookup[patchNameIndex] = CheckNumForName(name)
		patchNameIndex += 1
	end

	const maptex = CacheLumpName("TEXTURE1", STATIC)
	const numtextures1 = buffer.readi32(maptex, 0)
	local maptex2 = EMPTY_BUFFER
	local numtextures2 = 0

	if CheckNumForName("TEXTURE2") ~= -1 then
		maptex2 = CacheLumpName("TEXTURE2", STATIC)
		numtextures2 = buffer.readi32(maptex2, 0)
	end

	numtextures = numtextures1 + numtextures2
	State.textureheight = {}
	State.texturetranslation = {}
	
	for textureIndex = 0, numtextures - 1 do
		local activeMaptex = maptex
		local localIndex = textureIndex

		if textureIndex >= numtextures1 then
			activeMaptex = maptex2
			localIndex = textureIndex - numtextures1
		end

		const offset = buffer.readi32(activeMaptex, 4 + localIndex * 4)

		const name = ReadLumpName(activeMaptex, offset)
		const width = buffer.readi16(activeMaptex, offset + 12)
		const height = buffer.readi16(activeMaptex, offset + 14)
		const patchcount = buffer.readi16(activeMaptex, offset + 20)

		const texture = {
			name = name,
			canonicalName = CanonicalizeName(name),
			width = width,
			height = height,
			patchcount = patchcount,
			widthmask = bit32.lshift(1, (31 - bit32.countlz(math.max(width, 1)))) - 1,
			patchoriginx = buffer.create(patchcount * 2),
			patchoriginy = buffer.create(patchcount * 2),
			patchlump = buffer.create(patchcount * 4),
			patchwidth = buffer.create(patchcount * 2),
			patchdata = table.create(patchcount),
			coveredscratch = buffer.create(math.max(height, 1)),
			maskedpixelsscratch = buffer.create(math.max(height, 1)),
			linearcachedata = EMPTY_BUFFER,
			linearcachebuilt = false,
			columnlump = EMPTY_BUFFER,
			columnofs = EMPTY_BUFFER,
			columncache = table.create(width),
		}

		local patchDataIndex = 0
		local patchShortOffset = 0
		local patchLumpOffset = 0

		for patchOffset = offset + 22, offset + 22 + patchcount * 10 - 10, 10 do
			const patchLump = patchlookup[buffer.readi16(activeMaptex, patchOffset + 4)]
			const patch = CacheLumpNum(patchLump, CACHE)
			const patchWidth = ReadPatchHeader(patch)

			buffer.writei16(texture.patchoriginx, patchShortOffset, buffer.readi16(activeMaptex, patchOffset))
			buffer.writei16(texture.patchoriginy, patchShortOffset, buffer.readi16(activeMaptex, patchOffset + 2))
			buffer.writei32(texture.patchlump, patchLumpOffset, patchLump)
			buffer.writei16(texture.patchwidth, patchShortOffset, patchWidth)
			texture.patchdata[patchDataIndex] = patch

			patchDataIndex += 1
			patchShortOffset += 2
			patchLumpOffset += 4
		end

		textures[textureIndex] = texture
		maskedcompositecolumn[textureIndex] = table.create(width)

		State.textureheight[textureIndex] = height * FRACUNIT
	end

	for textureIndex = 0, numtextures - 1 do
		GenerateLookup(textureIndex)
		State.texturetranslation[textureIndex] = textureIndex
	end
end

-- InitFlats
const function InitFlats()
	State.firstflat = GetNumForName("F_START") + 1
	lastflat = GetNumForName("F_END") - 1
	numflats = lastflat - State.firstflat + 1

	-- Create translation table for global animation.
	State.flattranslation = {}

	for index = 0, numflats - 1 do
		State.flattranslation[index] = index
	end
end

-- InitSpriteLumps
-- Finds the width and hoffset of all sprites in the wad,
--  so the sprite does not need to be cached completely
--  just for having the header info ready during rendering.
const function InitSpriteLumps()
	State.firstspritelump = GetNumForName("S_START") + 1
	State.lastspritelump = GetNumForName("S_END") - 1

	State.numspritelumps = State.lastspritelump - State.firstspritelump + 1
	State.spritewidth = {}
	State.spriteoffset = {}
	State.spritetopoffset = {}

	for index = 0, State.numspritelumps - 1 do
		const patch = CacheLumpNum(State.firstspritelump + index, CACHE)
		const width, _, leftoffset, topoffset = ReadPatchHeader(patch)

		State.spritewidth[index] = width * FRACUNIT
		State.spriteoffset[index] = leftoffset * FRACUNIT
		State.spritetopoffset[index] = topoffset * FRACUNIT
	end
end

-- InitColormaps
const function InitColormaps()
	const lump = GetNumForName("COLORMAP")
	const length = LumpLength(lump)

	State.colormaps = Zone.Malloc(length, STATIC)
	Wad.ReadLump(lump, State.colormaps)
	colormapsAllocated = true
end

-- R_InitData
-- Locates all the lumps
--  that will be used by all views
-- Must be called after Wad.Init.
const function InitData()
	Reset()
	InitTextures()
	InitFlats()
	InitSpriteLumps()
	InitColormaps()
end

-- R_PrecacheLevel
-- Preloads all relevant graphics for the level.
const function PrecacheLevel()
	if State.demoplayback == true then
		return
	end

	const flatpresent: { [number]: boolean } = {}

	for index = 0, State.numsectors - 1 do
		const sector = State.sectors[index]

		flatpresent[sector.floorpic] = true
		flatpresent[sector.ceilingpic] = true
	end

	for index = 0, numflats - 1 do
		if flatpresent[index] then
			const lump = State.firstflat + index

			CacheLumpNum(lump, CACHE)
		end
	end

	const texturepresent: { [number]: boolean } = {}

	for index = 0, State.numsides - 1 do
		const side = State.sides[index]

		texturepresent[side.toptexture] = true
		texturepresent[side.midtexture] = true
		texturepresent[side.bottomtexture] = true
	end

	const skyTexture = SkyGetSkyTexture()
	texturepresent[skyTexture] = true

	for index = 0, numtextures - 1 do
		if texturepresent[index] then
			const texture = textures[index]
			const patchlump = texture.patchlump
			const patchLumpByteEnd = texture.patchcount * 4 - 4

			for patchLumpOffset = 0, patchLumpByteEnd, 4 do
				const lump = buffer.readi32(patchlump, patchLumpOffset)

				CacheLumpNum(lump, CACHE)
			end
		end
	end

	const spritepresent: { [number]: boolean } = {}

	const thinkerCapGetter = Host.getThinkerCap
	const mobjThinker = Host.mobjThinker

	if thinkerCapGetter ~= nil and mobjThinker ~= nil then
		const thinkercap = thinkerCapGetter()
		local thinker = thinkercap.next

		while thinker ~= thinkercap do
			const thinkerFunction = thinker["function"]

			if thinkerFunction.acp1 == mobjThinker then
				const thing = thinker.owner or thinker

				spritepresent[thing.sprite] = true
			end

			thinker = thinker.next
		end
	else
		for index = 0, State.numsectors - 1 do
			const sector = State.sectors[index]

			local thing = sector.thinglist

			while thing do
				spritepresent[thing.sprite] = true
				thing = thing.snext
			end
		end
	end

	for index = 0, State.numsprites - 1 do
		if spritepresent[index] then
			const sprite = State.sprites[index]

			for frameIndex = 0, sprite.numframes - 1 do
				const spriteframe = sprite.spriteframes[frameIndex]

				for rotation = 0, 7 do
					local lump = spriteframe.lump[rotation]

					lump += State.firstspritelump
					CacheLumpNum(lump, CACHE)
				end
			end
		end
	end
end

-- R_FlatNumForName
-- Retrieval, get a flat number for a flat name.
const function FlatNumForName(name: string): number
	const lump = CheckNumForName(name)

	return lump - State.firstflat
end

-- R_CheckTextureNumForName
-- Check whether texture is available.
-- Filter out NoTexture indicator.
const function CheckTextureNumForName(name: string): number
	if string.byte(name, 1) == 45 then
		return 0
	end

	const canonicalName = CanonicalizeName(name)

	for index = 0, numtextures - 1 do
		if textures[index].canonicalName == canonicalName then
			return index
		end
	end

	return -1
end

-- R_TextureNumForName
-- Calls R_CheckTextureNumForName,
--  aborts with error message.
const function TextureNumForName(name: string): number
	const texture = CheckTextureNumForName(name)

	if texture == -1 then
		error(`TextureNumForName: missing texture {CanonicalizeName(name)}`)
	end

	return texture
end

Reset()

return {
	Reset = Reset,

	GetColumn = GetColumn,
	GetLinearColumnSource = GetLinearColumnSource,
	GetMaskedColumn = GetMaskedColumn,

	InitData = InitData,
	PrecacheLevel = PrecacheLevel,
	FlatNumForName = FlatNumForName,
	CheckTextureNumForName = CheckTextureNumForName,
	TextureNumForName = TextureNumForName,
}
