--!native
--!optimize 2

const runtime: {
	storeWallRange: unknown?,
	addSprites: unknown?,
	Reset: (() -> ())?,
} = {}

const function Reset()
	runtime.storeWallRange = nil
	runtime.addSprites = nil
end

Reset()

runtime.Reset = Reset

return runtime
