--!native
--!optimize 2

-- Shared renderer math helpers.
-- Keep these leaf-level so renderer modules do not require each other just for
-- pure calculations.

const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const State = require("./State")

const finesine = Tables.finesine

const MAXSCALE = 64 * 65536

const FixedMul = Fixed.FixedMul
const FixedDiv = Fixed.FixedDiv

const function ScaleFromGlobalAngle(visangle: number): number
	const viewangle = State.viewangle
	const rwNormalAngle = State.rw_normalangle
	const projection = State.projection
	const rwDistance = State.rw_distance
	const detailshift = State.detailshift

	local num = FixedMul(projection, finesine[bit32.rshift(bit32.band(0x40000000 + visangle - rwNormalAngle, 0xFFFFFFFF), 19)])

	if detailshift ~= 0 then
		num *= 2
	end

	const den = FixedMul(rwDistance, finesine[bit32.rshift(bit32.band(0x40000000 + visangle - viewangle, 0xFFFFFFFF), 19)])

	if den > bit32.arshift(num, 16) then
		const scale = FixedDiv(num, den)

		if scale > MAXSCALE then
			return MAXSCALE
		elseif scale < 256 then
			return 256
		end

		return scale
	else
		return MAXSCALE
	end
end

return ScaleFromGlobalAngle
