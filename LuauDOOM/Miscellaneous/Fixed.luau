--!native
--!optimize 2

-- Port of m_fixed.c, m_fixed.h
-- Fixed point implementation.

const function ToSigned32(value: number): number
	value = bit32.band(value, 0xFFFFFFFF)
	return if value >= 2147483648 then value - 4294967296 else value
end

const function FixedMul(a: number, b: number): number
	a = ToSigned32(a)
	b = ToSigned32(b)

	if a == 0 or b == 0 then return 0 end

	const absoluteA = a < 0 and -a or a
	const absoluteB = b < 0 and -b or b

	const aHigh = absoluteA // 65536
	const bHigh = absoluteB // 65536
	const aLow = absoluteA - aHigh * 65536
	const bLow = absoluteB - bHigh * 65536
	const lowProduct = aLow * bLow
	local shifted = aHigh * bHigh * 65536
	
	shifted += aHigh * bLow
	shifted += aLow * bHigh
	shifted += lowProduct // 65536

	return (a < 0) ~= (b < 0)
	and ToSigned32(bit32.btest(lowProduct, 65535) and -shifted - 1 or -shifted)
	or ToSigned32(shifted)
end

const function FixedDiv2(a: number, b: number): number
	const quotient = math.modf(a / b * 65536)
	return ToSigned32(quotient)
end

const function FixedDiv(a: number, b: number): number
	a = ToSigned32(a)
	b = ToSigned32(b)

	return if bit32.rshift(math.abs(a), 14) >= math.abs(b)
		then bit32.btest(bit32.bxor(a, b), 0x80000000) and -2147483648 or 2147483647
		else FixedDiv2(a, b)
end

return {
	FRACBITS = 16,
	FRACUNIT = 65536,

	ToSigned32 = ToSigned32,
	FixedMul = FixedMul,
	FixedDiv = FixedDiv,
}
