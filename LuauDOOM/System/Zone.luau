--!native
--!optimize 2

-- Port of z_zone.c, z_zone.h
-- Zone Memory Allocation. Neat.
-- This Luau port emulates Doom's memblock list and rover behavior.
-- Ownership still uses `ownerTable` + `ownerKey` instead of C pointers.

-- ZONE MEMORY
-- PU - purge tags.
-- Tags < 100 are not overwritten until freed.
const STATIC = 1 -- static entire execution time
const LEVEL = 50 -- static until level exited

-- Tags >= 100 are purgable whenever needed.
const PURGELEVEL = 100
const CACHE = 101

const MINFRAGMENT = 64

type OwnerKey = number | string
type OwnerTable = { [OwnerKey]: buffer? }
type MemBlock = {
	offset: number,
	size: number,
	tag: number,
	ptr: buffer | false,
	ownerTable: OwnerTable?,
	ownerKey: OwnerKey?,
	prev: MemBlock | false | nil,
	next: MemBlock | false | nil,
}

local zoneSize = 0
const blockByPtr: { [buffer]: MemBlock } = {}

const blocklist: MemBlock = {
	offset = 0,
	size = 0,
	tag = STATIC,
	ptr = false,
	ownerTable = nil,
	ownerKey = nil,
	prev = nil,
	next = nil,
}

blocklist.prev = blocklist
blocklist.next = blocklist

local rover = blocklist

const function UnlinkBlock(block: MemBlock)
	block.prev.next = block.next
	block.next.prev = block.prev
end

const function LinkBlockAfter(prevBlock: MemBlock, block: MemBlock)
	block.prev = prevBlock
	block.next = prevBlock.next
	prevBlock.next.prev = block
	prevBlock.next = block
end

const function FindBlockByPtr(ptr: buffer, context: string)
	const direct = blockByPtr[ptr]

	if direct ~= nil then
		return direct
	end

	local block = blocklist.next

	while block ~= blocklist do
		if block.ptr == ptr then
			return block
		end

		block = block.next
	end

	error(`{context}: freed a pointer without ZONEID`)
end

const function MergeAdjacentFreeBlocks(block: MemBlock)
	local other = block.prev

	if other ~= blocklist and other.ptr == false then
		other.size += block.size
		UnlinkBlock(block)

		if block == rover then
			rover = other
		end

		block = other
	end

	other = block.next

	if other ~= blocklist and other.ptr == false then
		block.size += other.size
		UnlinkBlock(other)

		if other == rover then
			rover = block
		end
	end

	return block
end

const function ReleaseBlock(block: MemBlock)
	const ptr = block.ptr

	if block.ownerTable and block.ownerKey then
		block.ownerTable[block.ownerKey] = nil
	end

	if ptr ~= false then
		blockByPtr[ptr] = nil
	end

	block.ptr = false
	block.tag = 0
	block.ownerTable = nil
	block.ownerKey = nil

	return MergeAdjacentFreeBlocks(block)
end

const function NewBlock(offset: number, size: number): MemBlock
	return {
		offset = offset,
		size = size,
		tag = 0,
		ptr = false,
		ownerTable = nil,
		ownerKey = nil,
		prev = false,
		next = false,
	}
end

const function AllocateBlock(
	block: MemBlock,
	requestedSize: number,
	accountedSize: number,
	tag: number,
	ownerTable: OwnerTable?,
	ownerKey: OwnerKey?
): buffer
	const extra = block.size - accountedSize

	if extra > MINFRAGMENT then
		const newblock = NewBlock(block.offset + accountedSize, extra)

		LinkBlockAfter(block, newblock)
		block.size = accountedSize
	end

	const ptr = buffer.create(requestedSize)

	block.ptr = ptr
	blockByPtr[ptr] = block
	block.tag = tag
	block.ownerTable = ownerTable
	block.ownerKey = ownerKey

	if ownerTable and ownerKey then
		ownerTable[ownerKey] = ptr
	end

	rover = block.next
	if rover == blocklist then
		rover = blocklist.next
	end

	return ptr
end

const function ScanRangeForFit(startBlock: MemBlock, stopBlock: MemBlock, requiredSize: number)
	local block = startBlock

	while block ~= stopBlock and block ~= blocklist do
		if block.ptr == false then
			if block.size >= requiredSize then
				return block
			end

			block = block.next
		elseif block.tag >= PURGELEVEL then
			const merged = ReleaseBlock(block)

			if merged.size >= requiredSize then
				return merged
			end

			block = merged.next
		else
			block = block.next
		end
	end

	return nil
end

const function FindReusableBlock(requiredSize: number)
	if blocklist.next == blocklist then
		return nil
	end

	local start = rover

	if start == blocklist then
		start = blocklist.next
	end

	if start == blocklist then
		return nil
	end

	const previous = start.prev

	if previous ~= blocklist and previous.ptr == false then
		start = previous
	end

	const block = ScanRangeForFit(start, blocklist, requiredSize)

	if block ~= nil then
		return block
	end

	return ScanRangeForFit(blocklist.next, start, requiredSize)
end

-- Init
const function Init(size: number?)
	local block = blocklist.next

	while block ~= blocklist do
		const nextBlock = block.next

		if block.ptr ~= false and block.ownerTable and block.ownerKey then
			block.ownerTable[block.ownerKey] = nil
		end

		block = nextBlock
	end

	blocklist.prev = blocklist
	blocklist.next = blocklist
	rover = blocklist
	table.clear(blockByPtr)
	const zoneCapacity = if size ~= nil and size > 0 then size else 0
	zoneSize = zoneCapacity

	if zoneCapacity > 0 then
		const freeBlock = NewBlock(0, zoneCapacity)
		LinkBlockAfter(blocklist.prev, freeBlock)
		rover = freeBlock
	end
end

-- Free
const function Free(ptr: buffer)
	ReleaseBlock(FindBlockByPtr(ptr, "Free"))
end

-- Malloc
-- You can pass a nil owner if the tag is < PURGELEVEL.
const function Malloc(size: number, tag: number, ownerTable: OwnerTable?, ownerKey: OwnerKey?): buffer
	const accountedSize = ((size + 3) // 4) * 4
	local base = FindReusableBlock(accountedSize)

	if base == nil then
		base = NewBlock(zoneSize, accountedSize)
		LinkBlockAfter(blocklist.prev, base)
		zoneSize += accountedSize
	end

	return AllocateBlock(base, size, accountedSize, tag, ownerTable, ownerKey)
end

-- FreeTags
const function FreeTags(lowtag: number, hightag: number)
	local block = blocklist.next

	while block ~= blocklist do
		const nextBlock = block.next

		if block.ptr ~= false and block.tag >= lowtag and block.tag <= hightag then
			ReleaseBlock(block)
		end

		block = nextBlock
	end
end

-- ChangeTag
const function ChangeTag(ptr: buffer, tag: number)
	FindBlockByPtr(ptr, "ChangeTag").tag = tag
end

Init()

return {
	STATIC = STATIC,
	LEVEL = LEVEL,
	PURGELEVEL = PURGELEVEL,
	CACHE = CACHE,

	Init = Init,
	Malloc = Malloc,
	Free = Free,
	FreeTags = FreeTags,
	ChangeTag = ChangeTag,
}
