--!optimize 2
--!native

--[[
	BoundingBox.luau

	Public API:
	- Module returns bounding box coordinate constants and buffer helpers.
	- Create returns an initialized bounding box buffer.
	- ClearBox resets a bounding box buffer.
	- AddToBox expands a bounding box buffer to include a point.

	Port of m_bbox.c and m_bbox.h.
]]

const function Create(): buffer
	const Box = buffer.create(16)

	buffer.writei32(Box, 0, -2147483648)
	buffer.writei32(Box, 4, 2147483647)
	buffer.writei32(Box, 8, 2147483647)
	buffer.writei32(Box, 12, -2147483648)

	return Box
end

const function ClearBox(Box: buffer)
	buffer.writei32(Box, 0, -2147483648)
	buffer.writei32(Box, 4, 2147483647)
	buffer.writei32(Box, 8, 2147483647)
	buffer.writei32(Box, 12, -2147483648)
end

const function AddToBox(Box: buffer, X: number, Y: number)
	if X < buffer.readi32(Box, 8) then
		buffer.writei32(Box, 8, X)
	elseif X > buffer.readi32(Box, 12) then
		buffer.writei32(Box, 12, X)
	end

	if Y < buffer.readi32(Box, 4) then
		buffer.writei32(Box, 4, Y)
	elseif Y > buffer.readi32(Box, 0) then
		buffer.writei32(Box, 0, Y)
	end
end

return {
	-- Bounding box coordinate storage.
	BOXTOP = 0,
	BOXBOTTOM = 1,
	BOXLEFT = 2,
	BOXRIGHT = 3,

	Create = Create,

	-- Bounding box functions.
	ClearBox = ClearBox,
	AddToBox = AddToBox,
}
