--!native
--!optimize 2

const Definitions = require("../Engine/Definitions")

const STATUSBAR_LOGICAL_HEIGHT = 32

const ALLOWED_RENDER_SIZES = {
	["320x200"] = 1,
	["640x400"] = 2,
	["960x600"] = 3,
}

const State = {
	LogicalWidth = Definitions.BASE_WIDTH,
	LogicalHeight = Definitions.BASE_HEIGHT,
	LogicalHalfWidth = Definitions.BASE_WIDTH // 2,
	LogicalHalfHeight = Definitions.BASE_HEIGHT // 2,
	Width = Definitions.BASE_WIDTH,
	Height = Definitions.BASE_HEIGHT,
	HalfWidth = Definitions.BASE_WIDTH // 2,
	HalfHeight = Definitions.BASE_HEIGHT // 2,
	PixelCount = Definitions.BASE_WIDTH * Definitions.BASE_HEIGHT,
	ViewportX = 0,
	ViewportY = 0,
	ViewportWidth = Definitions.BASE_WIDTH,
	ViewportHeight = Definitions.BASE_HEIGHT,
	LogicalToRenderScaleX = 1,
	LogicalToRenderScaleY = 1,
}

local exports

const function SyncExports()
	if exports == nil then
		return
	end

	exports.LogicalWidth = State.LogicalWidth
	exports.LogicalHeight = State.LogicalHeight
	exports.LogicalHalfWidth = State.LogicalHalfWidth
	exports.LogicalHalfHeight = State.LogicalHalfHeight
	exports.Width = State.Width
	exports.Height = State.Height
	exports.HalfWidth = State.HalfWidth
	exports.HalfHeight = State.HalfHeight
	exports.PixelCount = State.PixelCount
	exports.ViewportX = State.ViewportX
	exports.ViewportY = State.ViewportY
	exports.ViewportWidth = State.ViewportWidth
	exports.ViewportHeight = State.ViewportHeight
	exports.LogicalToRenderScaleX = State.LogicalToRenderScaleX
	exports.LogicalToRenderScaleY = State.LogicalToRenderScaleY
end

const function SyncDerived()
	State.LogicalHalfWidth = State.LogicalWidth // 2
	State.LogicalHalfHeight = State.LogicalHeight // 2
	State.HalfWidth = State.Width // 2
	State.HalfHeight = State.Height // 2
	State.PixelCount = State.Width * State.Height
	State.LogicalToRenderScaleX = State.ViewportWidth / State.LogicalWidth
	State.LogicalToRenderScaleY = State.ViewportHeight / State.LogicalHeight
	SyncExports()
end

const function GetLogicalWidth(): number
	return State.LogicalWidth
end

const function GetLogicalHeight(): number
	return State.LogicalHeight
end

const function GetRenderWidth(): number
	return State.Width
end

const function GetRenderHeight(): number
	return State.Height
end

const function GetRenderPixelCount(): number
	return State.PixelCount
end

const function GetStatusBarScale(): number
	return ALLOWED_RENDER_SIZES[`{State.Width}x{State.Height}`]
end

const function GetStatusBarWidth(): number
	return State.LogicalWidth * GetStatusBarScale()
end

const function GetStatusBarHeight(): number
	return STATUSBAR_LOGICAL_HEIGHT * GetStatusBarScale()
end

const function RebuildViewport()
	State.ViewportX = 0
	State.ViewportY = 0
	State.ViewportWidth = State.Width
	State.ViewportHeight = State.Height
	SyncDerived()
end

const function GetLogicalToRenderScaleX(): number
	return State.LogicalToRenderScaleX
end

const function GetLogicalToRenderScaleY(): number
	return State.LogicalToRenderScaleY
end

const function GetViewportX(): number
	return State.ViewportX
end

const function GetViewportY(): number
	return State.ViewportY
end

const function GetViewportWidth(): number
	return State.ViewportWidth
end

const function GetViewportHeight(): number
	return State.ViewportHeight
end

const function SetRenderSize(width: number, height: number)
	State.Width = width
	State.Height = height
	RebuildViewport()
end

const function Reset()
	State.Width = State.LogicalWidth
	State.Height = State.LogicalHeight
	RebuildViewport()
end

const function ScaleLogicalX(x: number): number
	return State.ViewportX + x * State.ViewportWidth // State.LogicalWidth
end

const function ScaleLogicalY(y: number): number
	return State.ViewportY + y * State.ViewportHeight // State.LogicalHeight
end

const function ScaleLogicalWidth(width: number): number
	return width * State.ViewportWidth // State.LogicalWidth
end

const function ScaleLogicalHeight(height: number): number
	return height * State.ViewportHeight // State.LogicalHeight
end

const function MapLogicalRect(x: number, y: number, width: number, height: number): (number, number, number, number)
	const left = State.ViewportX + x * State.ViewportWidth // State.LogicalWidth
	const top = State.ViewportY + y * State.ViewportHeight // State.LogicalHeight
	const right = State.ViewportX + (x + width) * State.ViewportWidth // State.LogicalWidth
	const bottom = State.ViewportY + (y + height) * State.ViewportHeight // State.LogicalHeight
	return left, top, right - left, bottom - top
end

const function MapLogicalXRange(x: number, width: number): (number, number)
	const left = State.ViewportX + x * State.ViewportWidth // State.LogicalWidth
	const right = State.ViewportX + (x + width) * State.ViewportWidth // State.LogicalWidth
	return left, right
end

const function MapLogicalYRange(y: number, height: number): (number, number)
	const top = State.ViewportY + y * State.ViewportHeight // State.LogicalHeight
	const bottom = State.ViewportY + (y + height) * State.ViewportHeight // State.LogicalHeight
	return top, bottom
end

const function ScaleScreenX(x: number): number
	return x * State.Width // State.LogicalWidth
end

const function ScaleScreenY(y: number): number
	return y * State.Height // State.LogicalHeight
end

const function MapScreenRect(x: number, y: number, width: number, height: number): (number, number, number, number)
	const left = x * State.Width // State.LogicalWidth
	const top = y * State.Height // State.LogicalHeight
	const right = (x + width) * State.Width // State.LogicalWidth
	const bottom = (y + height) * State.Height // State.LogicalHeight
	return left, top, right - left, bottom - top
end

const function MapScreenXRange(x: number, width: number): (number, number)
	const left = x * State.Width // State.LogicalWidth
	const right = (x + width) * State.Width // State.LogicalWidth
	return left, right
end

const function MapScreenYRange(y: number, height: number): (number, number)
	const top = y * State.Height // State.LogicalHeight
	const bottom = (y + height) * State.Height // State.LogicalHeight
	return top, bottom
end

exports = {
	State = State,
	LogicalWidth = State.LogicalWidth,
	LogicalHeight = State.LogicalHeight,
	LogicalHalfWidth = State.LogicalHalfWidth,
	LogicalHalfHeight = State.LogicalHalfHeight,
	Width = State.Width,
	Height = State.Height,
	HalfWidth = State.HalfWidth,
	HalfHeight = State.HalfHeight,
	PixelCount = State.PixelCount,
	ViewportX = State.ViewportX,
	ViewportY = State.ViewportY,
	ViewportWidth = State.ViewportWidth,
	ViewportHeight = State.ViewportHeight,
	LogicalToRenderScaleX = State.LogicalToRenderScaleX,
	LogicalToRenderScaleY = State.LogicalToRenderScaleY,

	GetLogicalWidth = GetLogicalWidth,
	GetLogicalHeight = GetLogicalHeight,
	GetRenderWidth = GetRenderWidth,
	GetRenderHeight = GetRenderHeight,
	GetRenderPixelCount = GetRenderPixelCount,
	GetStatusBarScale = GetStatusBarScale,
	GetStatusBarWidth = GetStatusBarWidth,
	GetStatusBarHeight = GetStatusBarHeight,
	GetLogicalToRenderScaleX = GetLogicalToRenderScaleX,
	GetLogicalToRenderScaleY = GetLogicalToRenderScaleY,
	GetViewportX = GetViewportX,
	GetViewportY = GetViewportY,
	GetViewportWidth = GetViewportWidth,
	GetViewportHeight = GetViewportHeight,
	SetRenderSize = SetRenderSize,
	Reset = Reset,
	ScaleLogicalX = ScaleLogicalX,
	ScaleLogicalY = ScaleLogicalY,
	ScaleLogicalWidth = ScaleLogicalWidth,
	ScaleLogicalHeight = ScaleLogicalHeight,
	MapLogicalRect = MapLogicalRect,
	MapLogicalXRange = MapLogicalXRange,
	MapLogicalYRange = MapLogicalYRange,
	ScaleScreenX = ScaleScreenX,
	ScaleScreenY = ScaleScreenY,
	MapScreenRect = MapScreenRect,
	MapScreenXRange = MapScreenXRange,
	MapScreenYRange = MapScreenYRange,
}

RebuildViewport()

return exports
