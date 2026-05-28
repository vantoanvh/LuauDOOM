--!optimize 2
--!native

--[[
	SpriteState.luau

	Shared renderer sprite clipping and masked-column draw state.
]]

type SpriteState = {
	Reset: () -> (),
	negonearray: buffer | false,
	screenheightarray: buffer | false,
	maskedColumnDrawer: ((buffer, number) -> ())?,
	maskedFloorClip: buffer | false,
	maskedCeilingClip: buffer | false,
	maskedFloorClipBase: number,
	maskedCeilingClipBase: number,
	spriteYScale: number,
	spriteTopScreen: number,
	spriteTextureMid: number,
	spriteColumnX: number,
	spriteColFunc: (() -> ())?,
}

const spriteState: SpriteState = {} :: SpriteState

const function Reset()
	spriteState.negonearray = false
	spriteState.screenheightarray = false
	spriteState.maskedColumnDrawer = nil
	spriteState.maskedFloorClip = false
	spriteState.maskedCeilingClip = false
	spriteState.maskedFloorClipBase = 0
	spriteState.maskedCeilingClipBase = 0
	spriteState.spriteYScale = 0
	spriteState.spriteTopScreen = 0
	spriteState.spriteTextureMid = 0
	spriteState.spriteColumnX = 0
	spriteState.spriteColFunc = nil
end

Reset()

spriteState.Reset = Reset

return spriteState
