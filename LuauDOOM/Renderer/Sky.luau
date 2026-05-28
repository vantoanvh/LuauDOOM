--!optimize 2
--!native

--[[
	Sky.luau

	Provides sky renderer state accessors and resets sky texture midpoint for view changes.
]]

const SKYFLATNAME = "F_SKY1"
const ANGLETOSKYSHIFT = 22

-- sky mapping
-- `skyflatnum` is assigned by play/setup code after flats are initialized.
local skyflatnum = 0
local skytexture = 0
local skytexturemid = 0

const function InitSkyMap()
	skytexturemid = 6553600
end

const function SetSkyFlatNum(flatnum: number)
	skyflatnum = flatnum
end

const function GetSkyFlatNum(): number
	return skyflatnum
end

const function SetSkyTexture(texture: number)
	skytexture = texture
end

const function GetSkyTexture(): number
	return skytexture
end

const function GetSkyTextureMid(): number
	return skytexturemid
end

return {
	SKYFLATNAME = SKYFLATNAME,
	ANGLETOSKYSHIFT = ANGLETOSKYSHIFT,

	SetSkyFlatNum = SetSkyFlatNum,
	GetSkyFlatNum = GetSkyFlatNum,
	SetSkyTexture = SetSkyTexture,
	GetSkyTexture = GetSkyTexture,
	GetSkyTextureMid = GetSkyTextureMid,
	InitSkyMap = InitSkyMap,
}
