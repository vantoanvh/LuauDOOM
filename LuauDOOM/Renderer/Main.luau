--!native
--!optimize 2

-- Port of r_main.c, r_main.h
-- Rendering main loop and setup functions,
-- utility functions (BSP, geometry, trigonometry).
-- See tables.c, too.
-- `RenderPlayerView` calls the renderer owners directly. Shared bridge state
-- is only used where direct requires would create cycles.

const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const Bsp = require("./Bsp")
const Data = require("./Data")
const Draw = require("./Draw")
const Geometry = require("./Geometry")
const Host = require("./Host")
const Plane = require("./Plane")
const Segs = require("./Segs")
const Sky = require("./Sky")
const State = require("./State")
const Things = require("./Things")
const Video = require("../System/Video")

-- Lighting LUT.
-- Used for z-depth cuing per column/row,
--  and other lighting effects (sector ambient, flash).

-- Lighting constants.
-- Now why not 32 levels here?
const LIGHTLEVELS = 16

const MAXLIGHTSCALE = 48
const LIGHTSCALESHIFT = 12
const MAXLIGHTZ = 128

-- Number of diminishing brightness levels.
-- There a 0-31, i.e. 32 LUT in the COLORMAP lump.
const NUMCOLORMAPS = 32

-- Fineangles in the SCREENWIDTH wide window.
const FIELDOFVIEW = 2048
const DISTMAP = 2

const SUBSECTOR = 0x8000

const FixedMul = Fixed.FixedMul
const FixedDiv = Fixed.FixedDiv

const function ToSigned32(value: number): number
	value = bit32.band(value, 0xFFFFFFFF)
	return if value >= 0x80000000 then value - 0x100000000 else value
end

const function SignedRightShift(value: number, shift: number): number
	return ToSigned32(bit32.arshift(value, shift))
end

const function ResolveSubsectorRef(value: number): number
	if value == -1 or value == 0xFFFF then
		return 0
	end

	return bit32.band(value, SUBSECTOR - 1)
end

const function Reset()
	State.validcount = 1
	State.linecount = 0
	State.loopcount = 0
	State.framecount = 0
	State.setsizeneeded = false
	State.setblocks = 10
	State.setdetail = 0
	State.viewangleoffset = 0
	State.colfunc = false
	State.basecolfunc = false
	State.fuzzcolfunc = false
	State.transcolfunc = false
	State.spanfunc = false
	State.walllights = false
	State.viewplayer = nil
	State.fixedcolormap = false
	State.extralight = 0
	State.sscount = 0
end

-- InitTextureMapping
const function InitTextureMapping()
	const finetangent = Tables.finetangent
	const viewangletox = State.viewangletox
	const xtoviewangle = State.xtoviewangle
	const centerxfrac = State.centerxfrac
	const viewwidth = State.viewwidth
	const viewwidthSentinel = viewwidth + 1

	const focallength = FixedDiv(
		centerxfrac,
		finetangent[8192 // 4 + FIELDOFVIEW // 2]
	)

	local angleIndex = 0

	for byteOffset = 0, 8192 * 2 - 4, 4 do
		local t
		const tangent = finetangent[angleIndex]

		if tangent > 65536 * 2 then
			t = -1
		elseif tangent < -65536 * 2 then
			t = viewwidthSentinel
		else
			t = FixedMul(tangent, focallength)
			t = SignedRightShift(ToSigned32(centerxfrac - t + 65536 - 1), 16)

			if t < -1 then
				t = -1
			elseif t > viewwidthSentinel then
				t = viewwidthSentinel
			end
		end

		buffer.writei32(viewangletox, byteOffset, t)
		angleIndex += 1
	end

	local x = 0
	const viewWidthSentinelByteEnd = viewwidth * 4

	for xByteOffset = 0, viewWidthSentinelByteEnd, 4 do
		local viewAngleOffset = 0

		while buffer.readi32(viewangletox, viewAngleOffset) > x do
			viewAngleOffset += 4
		end

		buffer.writeu32(xtoviewangle, xByteOffset, viewAngleOffset * 131072 - 0x40000000)
		x += 1
	end

	for byteOffset = 0, 8192 * 2 - 4, 4 do
		const value = buffer.readi32(viewangletox, byteOffset)

		if value == -1 then
			buffer.writei32(viewangletox, byteOffset, 0)
		elseif value == viewwidthSentinel then
			buffer.writei32(viewangletox, byteOffset, viewwidth)
		end
	end

	State.clipangle = buffer.readu32(xtoviewangle, 0)
end

-- InitLightTables
-- Only inits the zlight table,
--  because the scalelight table changes with view size.
const function InitLightTables()
	const halfLogicalWidth = Video.LogicalHalfWidth

	for levelIndex = 0, LIGHTLEVELS - 1 do
		const startmap = (LIGHTLEVELS - 1 - levelIndex) * 2 * NUMCOLORMAPS // LIGHTLEVELS
		local zlight = State.zlight[levelIndex]

		if zlight == nil then
			zlight = {}
			State.zlight[levelIndex] = zlight
		end

		for zIndex = 0, MAXLIGHTZ - 1 do
			local lightLevel = startmap - bit32.arshift(FixedDiv(
				halfLogicalWidth * 65536,
				(zIndex + 1) * 1048576
			), LIGHTSCALESHIFT) // DISTMAP

			if lightLevel < 0 then
				lightLevel = 0
			elseif lightLevel >= NUMCOLORMAPS then
				lightLevel = NUMCOLORMAPS - 1
			end

			zlight[zIndex] = lightLevel * 256
		end
	end
end

-- SetViewSize
-- Do not really change anything here,
--  because it might be in the middle of a refresh.
-- The change will take effect next refresh.
const function SetViewSize(blocks: number, detail: number)
	State.setsizeneeded = true
	State.setblocks = blocks
	State.setdetail = detail
end

-- ExecuteSetViewSize
const function ExecuteSetViewSize()
	const renderWidth = Video.Width
	const renderHeight = Video.Height
	const logicalWidth = Video.LogicalWidth
	const logicalHeight = Video.LogicalHeight
	const setblocks = State.setblocks
	const detailshift = State.setdetail

	State.setsizeneeded = false

	if setblocks == 11 then
		State.scaledviewwidth = renderWidth
		State.viewheight = renderHeight
	else
		State.scaledviewwidth = setblocks * 32 * renderWidth // logicalWidth
		State.viewheight = bit32.band(bit32.band(setblocks * 168 // 10, bit32.bnot(7)) * renderHeight // logicalHeight, bit32.bnot(7))
	end

	State.detailshift = detailshift
	State.viewwidth = bit32.arshift(State.scaledviewwidth, detailshift)

	State.centery = State.viewheight // 2
	State.centerx = State.viewwidth // 2
	State.centerxfrac = State.centerx * 65536
	State.centeryfrac = State.centery * 65536
	State.projection = State.centerxfrac

	if detailshift == 0 then
		State.colfunc = Draw.DrawColumn
		State.basecolfunc = Draw.DrawColumn
		State.fuzzcolfunc = Draw.DrawFuzzColumn
		State.transcolfunc = Draw.DrawTranslatedColumn
		State.spanfunc = Draw.DrawSpan
	else
		State.colfunc = Draw.DrawColumnLow
		State.basecolfunc = Draw.DrawColumnLow
		State.fuzzcolfunc = Draw.DrawFuzzColumnLow
		State.transcolfunc = Draw.DrawTranslatedColumnLow
		State.spanfunc = Draw.DrawSpanLow
	end

	Draw.InitBuffer(State.scaledviewwidth, State.viewheight)
	InitTextureMapping()

	if State.scaledviewwidth ~= renderWidth then
		Draw.FillBackScreen()
	end

	State.pspritescale = (65536 * State.viewwidth) // logicalWidth
	State.pspriteiscale = (65536 * logicalWidth) // State.viewwidth

	Things.UpdateViewClipArrays()

	const halfScaledViewWidth = State.scaledviewwidth // 2
	const halfViewHeight = State.viewheight // 2
	const yslope = State.yslope
	const distscale = State.distscale
	const xtoviewangle = State.xtoviewangle
	const viewheight = State.viewheight
	const viewwidth = State.viewwidth
	const viewHeightByteEnd = viewheight * 4 - 4
	const viewWidthByteEnd = viewwidth * 4 - 4

	local yDistance = -halfViewHeight * 65536 + 65536 // 2

	for yByteOffset = 0, viewHeightByteEnd, 4 do
		buffer.writei32(yslope, yByteOffset, FixedDiv(halfScaledViewWidth * 65536,
			math.abs(yDistance))
		)
		yDistance += 65536
	end

	const finecosine = Tables.finecosine

	for xByteOffset = 0, viewWidthByteEnd, 4 do
		buffer.writei32(distscale, xByteOffset, FixedDiv(65536, math.abs(
			finecosine[
				bit32.band(bit32.rshift(
					buffer.readu32(xtoviewangle, xByteOffset),
					19
				), 8191)
			]
		)))
	end

	const detailWidth = (viewwidth * (detailshift == 0 and 1 or 2))

	for levelIndex = 0, LIGHTLEVELS - 1 do
		const startmap = ((LIGHTLEVELS - 1 - levelIndex) * 2) * NUMCOLORMAPS // LIGHTLEVELS
		local scalelight = State.scalelight[levelIndex]

		if scalelight == nil then
			scalelight = {}
			State.scalelight[levelIndex] = scalelight
		end

		for scaleIndex = 0, MAXLIGHTSCALE - 1 do
			local lightLevel = startmap - (scaleIndex * logicalWidth // detailWidth // DISTMAP)

			if lightLevel < 0 then
				lightLevel = 0
			elseif lightLevel >= NUMCOLORMAPS then
				lightLevel = NUMCOLORMAPS - 1
			end

			scalelight[scaleIndex] = lightLevel * 256
		end
	end
end

-- Init
const function Init(config: { screenblocks: number?, detailLevel: number? }?)
	local screenBlocks = State.setblocks
	local detailLevel = State.setdetail

	if config ~= nil then
		if config.screenblocks ~= nil then
			screenBlocks = config.screenblocks
		end

		if config.detailLevel ~= nil then
			detailLevel = config.detailLevel
		end
	end

	Data.InitData()
	SetViewSize(screenBlocks, detailLevel)
	Segs.Install()
	Things.Install()

	InitLightTables()
	Sky.InitSkyMap()
	Draw.InitTranslationTables()

	State.framecount = 0
end

-- SetupFrame
const function SetupFrame(
	player: { mo: { x: number, y: number, angle: number }, viewz: number, extralight: number?, fixedcolormap: number? },
	viewOverride: { x: number, y: number, angle: number, z: number }?
)
	const mo = player.mo
	local viewX = mo.x
	local viewY = mo.y
	const viewangleoffset = State.viewangleoffset
	local viewAngle = bit32.band(mo.angle + viewangleoffset, 0xFFFFFFFF)
	local viewZ = player.viewz

	if viewOverride then
		viewX = math.modf(viewOverride.x)
		viewY = math.modf(viewOverride.y)
		viewAngle = bit32.band(math.modf(viewOverride.angle) + viewangleoffset, 0xFFFFFFFF)
		viewZ = math.modf(viewOverride.z)
	end

	State.viewplayer = player
	State.viewx = viewX
	State.viewy = viewY
	State.viewangle = viewAngle
	State.extralight = player.extralight or 0
	State.viewz = viewZ

	const fineAngle = bit32.band(bit32.rshift(viewAngle, 19), 8191)
	const finesine = Tables.finesine
	const finecosine = Tables.finecosine

	State.viewsin = finesine[fineAngle]
	State.viewcos = finecosine[fineAngle]
	State.sscount = 0

	const playerFixedColormap = player.fixedcolormap or 0

	if playerFixedColormap ~= 0 then
		const fixedcolormap = playerFixedColormap * 256
		State.fixedcolormap = fixedcolormap
		State.walllights = State.scalelightfixed

		for index = 0, MAXLIGHTSCALE - 1 do
			State.scalelightfixed[index] = fixedcolormap
		end
	else
		State.fixedcolormap = false
		State.walllights = false
	end

	State.framecount += 1
	State.validcount += 1
end

-- RenderView
const function RenderPlayerView(
	player: { mo: { x: number, y: number, angle: number }, viewz: number, extralight: number?, fixedcolormap: number? },
	viewOverride: { x: number, y: number, angle: number, z: number }?
)
	if State.setsizeneeded then
		ExecuteSetViewSize()
	end

	SetupFrame(player, viewOverride)

	Bsp.ClearClipSegs()
	Bsp.ClearDrawSegs()
	Plane.ClearPlanes()
	Things.ClearSprites()

	const netUpdate = Host.netUpdate

	if netUpdate == nil then
		Bsp.RenderBSPNode(State.numnodes - 1)
		Plane.DrawPlanes()
		Things.DrawMasked()
	else
		netUpdate()
		Bsp.RenderBSPNode(State.numnodes - 1)
		netUpdate()
		Plane.DrawPlanes()
		netUpdate()
		Things.DrawMasked()
		netUpdate()
	end
end

-- PointInSubsector
const function PointInSubsector(x: number, y: number)
	local side: number
	local nodenum: number

	-- single subsector is a special case
	if State.numnodes == 0 then

		return State.subsectors[0]
	end

	nodenum = State.numnodes - 1

	while bit32.band(nodenum, SUBSECTOR) == 0 do
		const node = State.nodes[nodenum]


		side = Geometry.PointOnSide(x, y, node)
		nodenum = node.children[side]
	end

	const subsectorIndex = ResolveSubsectorRef(nodenum)
	const subsector = State.subsectors[subsectorIndex]


	return subsector
end

return {
	Reset = Reset,
	Init = Init,
	SetViewSize = SetViewSize,
	RenderPlayerView = RenderPlayerView,

	PointInSubsector = PointInSubsector,
}
