--!native
--!optimize 2

-- Shared play-world state for modules that need map/block/reject data
-- without bouncing through per-field indirection.

const WorldState = {
	bmapwidth = 0,
	bmapheight = 0,
	blockmap = {},
	blockmaplump = {},
	bmaporgx = 0,
	bmaporgy = 0,
	blocklinks = {},
	rejectmatrix = buffer.create(0),
}

const function Reset()
	WorldState.bmapwidth = 0
	WorldState.bmapheight = 0
	WorldState.blockmap = {}
	WorldState.blockmaplump = {}
	WorldState.bmaporgx = 0
	WorldState.bmaporgy = 0
	WorldState.blocklinks = {}
	WorldState.rejectmatrix = buffer.create(0)
end

WorldState.Reset = Reset

return WorldState
