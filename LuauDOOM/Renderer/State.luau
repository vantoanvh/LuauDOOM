--!native
--!optimize 2

-- Port of r_state.h
-- Refresh/render internal state variables (global).
-- Some values intentionally stay unset until their owning renderer module runs:
-- `colormaps` from `Renderer/Data`, `viewplayer` from `Renderer/Main`,
-- `sprites` from `Renderer/Things`, and `floorplane` / `ceilingplane`
-- from BSP+plane traversal.

const Video = require("../System/Video")

type State = { [string]: unknown }

const state: State = {}
const EMPTY_BUFFER = buffer.create(0)

const function Reset()
	const renderWidth = Video.Width
	const renderHeight = Video.Height

	-- Refresh internal data structures,
	--  for rendering.

	-- needed for texture pegging
	state.textureheight = {}

	-- needed for pre rendering (fracs)
	state.spritewidth = {}
	state.spriteoffset = {}
	state.spritetopoffset = {}

	-- Filled by `Renderer/Data` from the COLORMAP lump.
	state.colormaps = EMPTY_BUFFER

	state.viewwidth = renderWidth
	state.scaledviewwidth = renderWidth
	state.viewheight = renderHeight
	state.viewwindowx = 0
	state.viewwindowy = 0
	state.viewangleoffset = 0

	state.viewcos = 0
	state.viewsin = 0

	state.centerx = Video.CENTERX
	state.centery = Video.CENTERY
	state.centerxfrac = state.centerx * 65536
	state.centeryfrac = state.centery * 65536
	state.projection = state.centerxfrac

	state.validcount = 1
	state.linecount = 0
	state.loopcount = 0
	state.framecount = 0
	state.demoplayback = false

	state.extralight = 0
	-- Optional override colormap. Keep this optional semantic as false.
	state.fixedcolormap = false
	state.detailshift = 0
	state.pspritescale = 0
	state.pspriteiscale = 0

	state.firstflat = 0

	-- for global animation
	state.flattranslation = {}
	state.texturetranslation = {}

	-- Sprite....
	state.firstspritelump = 0
	state.lastspritelump = 0
	state.numspritelumps = 0

	-- Lookup tables for map data.
	state.numsprites = 0
	state.sprites = {}

	state.numvertexes = 0
	state.vertexes = {}

	state.numsegs = 0
	state.segs = {}

	state.numsectors = 0
	state.sectors = {}

	state.numsubsectors = 0
	state.subsectors = {}

	state.numnodes = 0
	state.nodes = {}

	state.numlines = 0
	state.lines = {}

	state.numsides = 0
	state.sides = {}

	-- POV data.
	state.viewx = 0
	state.viewy = 0
	state.viewz = 0

	state.viewangle = 0
	-- Filled by `Renderer/Main.SetupFrame`.
	state.viewplayer = nil
	state.interpolationAlpha = 0

	-- ?
	state.clipangle = 0

	state.viewangletox = buffer.create(4096 * 4)
	state.xtoviewangle = buffer.create((renderWidth + 1) * 4)
	state.yslope = buffer.create(renderHeight * 4)
	state.distscale = buffer.create(renderWidth * 4)

	state.scalelight = {}
	state.scalelightfixed = {}
	state.zlight = {}
	state.walllights = false
	state.maxdrawsegs = 2048
	state.drawsegindex = 0
	state.colfunc = false
	state.basecolfunc = false
	state.fuzzcolfunc = false
	state.transcolfunc = false
	state.spanfunc = false
	state.drawsegindex = 0
	state.setsizeneeded = false
	state.setblocks = 10
	state.setdetail = 0

	state.rw_distance = 0
	state.rw_normalangle = 0

	-- angle to line origin
	state.rw_angle1 = 0

	-- Segs count?
	state.sscount = 0

	-- Set during BSP/plane traversal for the current subsector.
	state.floorplane = nil
	state.ceilingplane = nil
end

Reset()

state.Reset = Reset

return state
