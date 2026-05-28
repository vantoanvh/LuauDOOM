--!native
--!optimize 2

-- Port of Status.C, st_stuff.h
-- Status bar code.
-- Note: gameplay cheat input now lives in `Src/Engine/Cheats.luau`.
-- `Responder` still only handles automap enter/exit messages.

const Definitions = require("../Engine/Definitions")
const Geometry = require("../Renderer/Geometry")
const Interaction = require("../Play/Interaction")
const Setup = require("../Play/Setup")
const Random = require("../Miscellaneous/Random")
const Tables = require("../Engine/Tables")
const Video = require("../System/Video")
const VideoMode = require("../System/VideoMode")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const MenuRandom = Random.MenuRandom
const CopyRect = Video.CopyRect
const DrawPatch = Video.DrawPatch
const DrawPatchRender = Video.DrawPatchRender
const CacheLumpName = Wad.CacheLumpName
const STATIC = Zone.STATIC
const CACHE = Zone.CACHE

const StatusHeight = 32 * Definitions.SCREEN_MUL
const StatusWidth = Definitions.SCREENWIDTH
const StatusY = Definitions.SCREENHEIGHT - StatusHeight
const BG = 4
const FG = 0

const AutomapMessageHeader = bit32.bor(97 * 16777216, 109 * 65536)
const AutomapMessageEntered = bit32.bor(AutomapMessageHeader, 101 * 256)
const AutomapMessageExited = bit32.bor(AutomapMessageHeader, 120 * 256)

const STARTREDPALS = 1
const STARTBONUSPALS = 9
const NUMREDPALS = 8
const NUMBONUSPALS = 4
const RADIATIONPAL = 13

const NumPainFaces = 5
const NumStraightFaces = 3
const NumTurnFaces = 2
const NumSpecialFaces = 3
const FaceStride = NumStraightFaces + NumTurnFaces + NumSpecialFaces

const TurnOffset = NumStraightFaces
const OuchOffset = TurnOffset + NumTurnFaces
const EvilGrinOffset = OuchOffset + 1
const RampageOffset = EvilGrinOffset + 1
const GodFace = NumPainFaces * FaceStride
const DeadFace = GodFace + 1

const EvilGrinCount = 2 * Definitions.TICRATE
const StraightFaceCount = Definitions.TICRATE // 2
const TurnCount = Definitions.TICRATE
const RampageDelay = 2 * Definitions.TICRATE
const MuchPain = 20

const AmmoWidth = 3
const AmmoX = 44
const AmmoY = 171
const HealthX = 90
const HealthY = 171
const ArmsX = 111
const ArmsY = 172
const ArmsBackgroundX = 104
const ArmsBackgroundY = 168
const ArmsXSpace = 12
const ArmsYSpace = 10
const ArmorX = 221
const ArmorY = 171
const Key0X = 239
const Key0Y = 171
const Key1X = 239
const Key1Y = 181
const Key2X = 239
const Key2Y = 191
const Ammo0X = 288
const Ammo0Y = 173
const Ammo1X = 288
const Ammo1Y = 179
const Ammo2X = 288
const Ammo2Y = 191
const Ammo3X = 288
const Ammo3Y = 185
const MaxAmmo0X = 314
const MaxAmmo0Y = 173
const MaxAmmo1X = 314
const MaxAmmo1Y = 179
const MaxAmmo2X = 314
const MaxAmmo2Y = 191
const MaxAmmo3X = 314
const MaxAmmo3Y = 185
const FacesX = 143
const FacesY = 168

type Event = {
	type: number,
	data1: number?,
}

type Mobj = {
	x: number,
	y: number,
	angle: number,
}

type Player = {
	health: number,
	armorpoints: number,
	powers: { [number]: number },
	cards: { [number]: boolean },
	readyweapon: number,
	weaponowned: { [number]: boolean },
	ammo: { [number]: number },
	maxammo: { [number]: number },
	attackdown: boolean,
	cheats: number,
	damagecount: number,
	bonuscount: number,
	attacker: Mobj | false,
	mo: Mobj | false,
}

type PatchList = { [number]: buffer }
type ArmsPatchList = { [number]: PatchList }
type BoolValue = boolean | (() -> boolean)
type NumberValue = number | (() -> number)

type NumberWidget = {
	x: number,
	y: number,
	oldnum: number,
	width: number,
	num: NumberValue,
	on: BoolValue,
	p: PatchList,
	data: number,
}

type PercentWidget = {
	n: NumberWidget,
	p: buffer | false,
}

type MultIconWidget = {
	x: number,
	y: number,
	oldinum: number,
	inum: NumberValue,
	on: BoolValue,
	p: PatchList,
	data: number,
}

type BinIconWidget = {
	x: number,
	y: number,
	oldval: boolean,
	val: BoolValue,
	on: BoolValue,
	p: buffer | false,
	data: number,
}

const tallnum: PatchList = {}
const shortnum: PatchList = {}
const keys: PatchList = {}
const faces: PatchList = {}
const arms: ArmsPatchList = {}

local sbar: buffer | false = false
local tallpercent: buffer | false = false
local armsbg: buffer | false = false

local w_ready: NumberWidget = ({} :: unknown) :: NumberWidget
local w_health: PercentWidget = { n = ({} :: unknown) :: NumberWidget } :: PercentWidget
local w_armsbg: BinIconWidget = ({} :: unknown) :: BinIconWidget
const w_arms: { [number]: MultIconWidget } = {}
local w_faces: MultIconWidget = ({} :: unknown) :: MultIconWidget
const w_keyboxes: { [number]: MultIconWidget } = {}
local w_armor: PercentWidget = { n = ({} :: unknown) :: NumberWidget } :: PercentWidget
const w_ammo: { [number]: NumberWidget } = {}
const w_maxammo: { [number]: NumberWidget } = {}

local players: { [number]: Player } = {}
local plyr: Player? = nil
local loaded = false
local started = false
local automapactive = false

local st_firsttime = true
local st_statusbaron = true
local st_armson = true
local st_faceindex = 0
local st_facecount = 0
local st_randomnumber = 0
local st_oldhealth = -1
local st_palette = 0
const keyboxes = {
	[0] = -1,
	-1,
	-1,
}
const oldweaponsowned: { [number]: boolean } = {}
local lastattackdown = -1
local facePriority = 0
local statusY = 168
local sttminus = false

const function ResolveWidgetValue<T>(value: T | (() -> T)): T
	if typeof(value) == "function" then
		return value()
	end

	return value
end

const function ResetStatusWidgets()
	sttminus = false
	statusY = 168
end

const function InitStatusWidgetLibrary()
	sttminus = CacheLumpName("STTMINUS", STATIC)
end

const function InitNumberWidget(n: NumberWidget, x: number, y: number, pl: PatchList, num: NumberValue, on: BoolValue, width: number)
	n.x = x
	n.y = y
	n.oldnum = 0
	n.width = width
	n.num = num
	n.on = on
	n.p = pl
	n.data = 0
end

const function DrawNumberWidget(n: NumberWidget, _refresh: boolean)
	local numdigits = n.width
	local num = ResolveWidgetValue(n.num)
	const digits = n.p
	const zeroPatch = digits[0]
	const w = buffer.readi16(zeroPatch, 0)
	const h = buffer.readi16(zeroPatch, 2)
	local x = n.x
	const neg = num < 0

	n.oldnum = num

	if neg then
		if numdigits == 2 and num < -9 then
			num = -9
		elseif numdigits == 3 and num < -99 then
			num = -99
		end

		num = -num
	end

	x = n.x - numdigits * w

	CopyRect(x, n.y - statusY, BG, w * numdigits, h, x, n.y, FG)

	if num == 1994 then
		return
	end

	x = n.x

	if num == 0 then
		DrawPatch(x - w, n.y, FG, zeroPatch)
	end

	while num ~= 0 and numdigits > 0 do
		x -= w
		DrawPatch(x, n.y, FG, digits[num % 10])
		num //= 10
		numdigits -= 1
	end

	if neg then
		DrawPatch(x - 8, n.y, FG, sttminus)
	end
end

const function UpdateNumberWidget(n: NumberWidget, refresh: boolean)
	if ResolveWidgetValue(n.on) then
		DrawNumberWidget(n, refresh)
	end
end

const function InitPercentWidget(
	p: PercentWidget,
	x: number,
	y: number,
	pl: PatchList,
	num: NumberValue,
	on: BoolValue,
	percent: buffer | false
)
	InitNumberWidget(p.n, x, y, pl, num, on, 3)
	p.p = percent
end

const function UpdatePercentWidget(per: PercentWidget, refresh: boolean)
	if refresh and ResolveWidgetValue(per.n.on) then
		DrawPatch(per.n.x, per.n.y, FG, per.p)
	end

	UpdateNumberWidget(per.n, refresh)
end

const function InitMultiIconWidget(i: MultIconWidget, x: number, y: number, il: PatchList, inum: NumberValue, on: BoolValue)
	i.x = x
	i.y = y
	i.oldinum = -1
	i.inum = inum
	i.on = on
	i.p = il
	i.data = 0
end

const function UpdateMultiIconWidget(mi: MultIconWidget, refresh: boolean)
	const on = ResolveWidgetValue(mi.on)
	const current = ResolveWidgetValue(mi.inum)

	if on and (mi.oldinum ~= current or refresh) and current ~= -1 then
		if mi.oldinum ~= -1 then
			const oldPatch = mi.p[mi.oldinum]
			const x = mi.x - buffer.readi16(oldPatch, 4)
			const y = mi.y - buffer.readi16(oldPatch, 6)
			const w = buffer.readi16(oldPatch, 0)
			const h = buffer.readi16(oldPatch, 2)

			CopyRect(x, y - statusY, BG, w, h, x, y, FG)
		end

		DrawPatch(mi.x, mi.y, FG, mi.p[current])
		mi.oldinum = current
	end
end

const function InitBinaryIconWidget(b: BinIconWidget, x: number, y: number, icon: buffer | false, val: BoolValue, on: BoolValue)
	b.x = x
	b.y = y
	b.oldval = false
	b.val = val
	b.on = on
	b.p = icon
	b.data = 0
end

const function UpdateBinaryIconWidget(bi: BinIconWidget, refresh: boolean)
	const on = ResolveWidgetValue(bi.on)
	const value = ResolveWidgetValue(bi.val)

	if on and (bi.oldval ~= value or refresh) then
		const patch = bi.p
		const x = bi.x - buffer.readi16(patch, 4)
		const y = bi.y - buffer.readi16(patch, 6)
		const w = buffer.readi16(patch, 0)
		const h = buffer.readi16(patch, 2)

		if value then
			DrawPatch(bi.x, bi.y, FG, patch)
		else
			CopyRect(x, y - statusY, BG, w, h, x, y, FG)
		end

		bi.oldval = value
	end
end

const function GetPrimaryPlayer(): Player
	return (players[0] or players[1]) :: Player
end

const function GetPlayerPower(player: Player, index: number): number
	return player.powers[index] or 0
end

const function IsSharewareStatusWeaponOwned(weaponIndex: number): boolean
	if not plyr.weaponowned[weaponIndex] then
		return false
	end

	if Setup.GetGameMode() == Definitions.shareware
		and (weaponIndex == Definitions.wp_plasma or weaponIndex == Definitions.wp_bfg) then
		return false
	end

	return true
end

const function ClearGraphics()
	table.clear(tallnum)
	table.clear(shortnum)
	table.clear(keys)
	table.clear(faces)
	table.clear(arms)

	sbar = false
	tallpercent = false
	armsbg = false
end

const function FillStatusStrip(screenIndex: number)
	const renderWidth = Video.GetScreenWidth()
	const viewportWidth = Video.GetViewportWidth()

	if renderWidth <= viewportWidth then
		return
	end

	const renderY, renderBottom = VideoMode.MapLogicalYRange(StatusY, StatusHeight)
	const renderHeight = renderBottom - renderY
	const screen = Video.GetScreenBuffer(screenIndex)
	const flatName = if Setup.GetGameMode() == Definitions.commercial then "GRNROCK" else "FLOOR7_2"
	const flat = CacheLumpName(flatName, CACHE)

	const tileRemainder = bit32.band(renderWidth, 63)
	const widthDivided = renderWidth // 64

	for y = 0, renderHeight - 1 do
		local destOffset = (renderY + y) * renderWidth
		const srcOffset = bit32.band(renderY + y, 63) * 64

		for _ = 1, widthDivided do
			buffer.copy(screen, destOffset, flat, srcOffset, 64)
			destOffset += 64
		end

		if tileRemainder ~= 0 then
			buffer.copy(screen, destOffset, flat, srcOffset, tileRemainder)
		end
	end
end

const function DrawStatusStripTop(screenIndex: number)
	const renderWidth = Video.GetScreenWidth()
	const viewportX = Video.GetViewportX()
	const viewportWidth = Video.GetViewportWidth()

	if renderWidth <= viewportWidth then
		return
	end

	const patch = CacheLumpName("brdr_t", CACHE)
	const patchWidth = buffer.readi16(patch, 0)
	const renderY = VideoMode.ScaleLogicalY(StatusY)
	const rightStart = VideoMode.ScaleLogicalX(StatusWidth)

	for x = 0, viewportX - patchWidth, patchWidth do
		DrawPatchRender(x, renderY, screenIndex, patch)
	end

	for x = rightStart, renderWidth - patchWidth, patchWidth do
		DrawPatchRender(x, renderY, screenIndex, patch)
	end
end

const function ResetWidgets()
	w_ready = ({} :: unknown) :: NumberWidget
	w_health = { n = ({} :: unknown) :: NumberWidget } :: PercentWidget
	w_armsbg = ({} :: unknown) :: BinIconWidget
	table.clear(w_arms)
	w_faces = ({} :: unknown) :: MultIconWidget
	table.clear(w_keyboxes)
	w_armor = { n = ({} :: unknown) :: NumberWidget } :: PercentWidget
	table.clear(w_ammo)
	table.clear(w_maxammo)
end

const function RefreshBackground()
	if st_statusbaron then
		FillStatusStrip(BG)
		FillStatusStrip(FG)
		DrawStatusStripTop(BG)
		DrawStatusStripTop(FG)
		DrawPatch(0, 0, BG, sbar)
		CopyRect(0, 0, BG, StatusWidth, StatusHeight, 0, StatusY, FG)
	end
end

local lastPainHealth = -1
local lastPainOffset = 0

const function CalcPainOffset(): number
	local health = plyr.health or 0

	if health > 100 then
		health = 100
	end

	if health ~= lastPainHealth then
		lastPainOffset = FaceStride * (((100 - health) * NumPainFaces) // 101)
		lastPainHealth = health
	end

	return lastPainOffset
end

const function UpdateFaceWidget()
	if facePriority < 10 then
		if (plyr.health or 0) <= 0 then
			facePriority = 9
			st_faceindex = DeadFace
			st_facecount = 1
		end
	end

	if facePriority < 9 and (plyr.bonuscount or 0) ~= 0 then
		local doevilgrin = false

		for i = 0, Definitions.NUMWEAPONS - 1 do
			const owned = plyr.weaponowned[i] == true

			if oldweaponsowned[i] ~= owned then
				doevilgrin = true
				oldweaponsowned[i] = owned
			end
		end

		if doevilgrin then
			facePriority = 8
			st_facecount = EvilGrinCount
			st_faceindex = CalcPainOffset() + EvilGrinOffset
		end
	end

	if facePriority < 8 then
		const attacker = plyr.attacker
		const mo = plyr.mo

		if (plyr.damagecount or 0) ~= 0 and attacker ~= nil and attacker ~= false and attacker ~= mo and mo ~= nil and mo ~= false then
			facePriority = 7

			if (plyr.health or 0) - st_oldhealth > MuchPain then
				st_facecount = TurnCount
				st_faceindex = CalcPainOffset() + OuchOffset
			else
				const badguyangle = Geometry.PointToAngle2(mo.x, mo.y, attacker.x, attacker.y)
				local diffang = 0
				local turnRight = false

				if badguyangle > mo.angle then
					diffang = badguyangle - mo.angle
					turnRight = diffang > Tables.ANG180
				else
					diffang = mo.angle - badguyangle
					turnRight = diffang <= Tables.ANG180
				end

				st_facecount = TurnCount
				st_faceindex = CalcPainOffset()

				if diffang < Tables.ANG45 then
					st_faceindex += RampageOffset
				elseif turnRight then
					st_faceindex += TurnOffset
				else
					st_faceindex += TurnOffset + 1
				end
			end
		end
	end

	if facePriority < 7 and (plyr.damagecount or 0) ~= 0 then
		if (plyr.health or 0) - st_oldhealth > MuchPain then
			facePriority = 7
			st_facecount = TurnCount
			st_faceindex = CalcPainOffset() + OuchOffset
		else
			facePriority = 6
			st_facecount = TurnCount
			st_faceindex = CalcPainOffset() + RampageOffset
		end
	end

	if facePriority < 6 then
		if plyr.attackdown then
			if lastattackdown == -1 then
				lastattackdown = RampageDelay
			else
				lastattackdown -= 1

				if lastattackdown == 0 then
					facePriority = 5
					st_faceindex = CalcPainOffset() + RampageOffset
					st_facecount = 1
					lastattackdown = 1
				end
			end
		else
			lastattackdown = -1
		end
	end

	if facePriority < 5 then
		if bit32.btest(plyr.cheats or 0, Interaction.GODMODE)
			or GetPlayerPower(plyr, Definitions.pw_invulnerability) ~= 0 then
			facePriority = 4
			st_faceindex = GodFace
			st_facecount = 1
		end
	end

	if st_facecount == 0 then
		st_faceindex = CalcPainOffset() + (st_randomnumber % 3)
		st_facecount = StraightFaceCount
		facePriority = 0
	end

	st_facecount -= 1
end

const function GetReadyAmmoValue(): number
	const player = plyr
	const info = Interaction.weaponinfo[player.readyweapon]

	if info == nil or info.ammo == Definitions.am_noammo then
		return 1994
	end

	return player.ammo[info.ammo] or 0
end

const function UpdateWidgets()
	w_ready.data = plyr.readyweapon or 0

	for i = 0, 2 do
		keyboxes[i] = if plyr.cards[i] then i else -1

		if plyr.cards[i + 3] then
			keyboxes[i] = i + 3
		end
	end

	UpdateFaceWidget()
	st_armson = st_statusbaron
end

const function Ticker()
	if not started then
		return
	end

	st_randomnumber = MenuRandom()
	UpdateWidgets()
	st_oldhealth = plyr.health or 0
end

const function ApplyPalette()
	local palette = 0
	local cnt = plyr.damagecount or 0

	if GetPlayerPower(plyr, Definitions.pw_strength) ~= 0 then
		const bzc = 12 - bit32.rshift(GetPlayerPower(plyr, Definitions.pw_strength), 6)

		if bzc > cnt then
			cnt = bzc
		end
	end

	if cnt ~= 0 then
		palette = bit32.rshift(cnt + 7, 3)

		if palette >= NUMREDPALS then
			palette = NUMREDPALS - 1
		end

		palette += STARTREDPALS
	elseif (plyr.bonuscount or 0) ~= 0 then
		palette = bit32.rshift((plyr.bonuscount or 0) + 7, 3)

		if palette >= NUMBONUSPALS then
			palette = NUMBONUSPALS - 1
		end

		palette += STARTBONUSPALS
	elseif GetPlayerPower(plyr, Definitions.pw_ironfeet) > 4 * 32
		or bit32.btest(GetPlayerPower(plyr, Definitions.pw_ironfeet), 8) then
		palette = RADIATIONPAL
	end

	st_palette = palette
end

const function DrawWidgets(refresh: boolean)
	if not started then
		return
	end

	st_armson = st_statusbaron

	UpdateNumberWidget(w_ready, refresh)

	for i = 0, 3 do
		UpdateNumberWidget(w_ammo[i], refresh)
		UpdateNumberWidget(w_maxammo[i], refresh)
	end

	UpdatePercentWidget(w_health, refresh)
	UpdatePercentWidget(w_armor, refresh)
	UpdateBinaryIconWidget(w_armsbg, refresh)

	for i = 0, 5 do
		UpdateMultiIconWidget(w_arms[i], refresh)
	end

	UpdateMultiIconWidget(w_faces, refresh)

	for i = 0, 2 do
		UpdateMultiIconWidget(w_keyboxes[i], refresh)
	end
end

const function RefreshStatusBar()
	st_firsttime = false
	RefreshBackground()
	DrawWidgets(true)
end

const function DrawDiff()
	DrawWidgets(false)
end

const function Drawer(fullscreen: boolean, refresh: boolean)
	if not started then
		return
	end

	st_statusbaron = (not fullscreen) or automapactive

	st_firsttime = st_firsttime or refresh

	ApplyPalette()

	if st_firsttime then
		RefreshStatusBar()
	else
		DrawDiff()
	end
end

const function LoadGraphics()
	local namebuf = ""
	local facenum = 0

	for i = 0, 9 do
		namebuf = `STTNUM{i}`
		tallnum[i] = CacheLumpName(namebuf, STATIC)
		namebuf = `STYSNUM{i}`
		shortnum[i] = CacheLumpName(namebuf, STATIC)
	end

	tallpercent = CacheLumpName("STTPRCNT", STATIC)

	for i = 0, Definitions.NUMCARDS - 1 do
		namebuf = `STKEYS{i}`
		keys[i] = CacheLumpName(namebuf, STATIC)
	end

	armsbg = CacheLumpName("STARMS", STATIC)
	sbar = CacheLumpName("STBAR", STATIC)

	for i = 0, 5 do
		arms[i] = {}
		namebuf = `STGNUM{i + 2}`
		arms[i][0] = CacheLumpName(namebuf, STATIC)
		arms[i][1] = shortnum[i + 2]
	end

	for i = 0, NumPainFaces - 1 do
		for j = 0, NumStraightFaces - 1 do
			namebuf = `STFST{i}{j}`
			faces[facenum] = CacheLumpName(namebuf, STATIC)
			facenum += 1
		end

		faces[facenum] = CacheLumpName(`STFTR{i}0`, STATIC)
		facenum += 1
		faces[facenum] = CacheLumpName(`STFTL{i}0`, STATIC)
		facenum += 1
		faces[facenum] = CacheLumpName(`STFOUCH{i}`, STATIC)
		facenum += 1
		faces[facenum] = CacheLumpName(`STFEVL{i}`, STATIC)
		facenum += 1
		faces[facenum] = CacheLumpName(`STFKILL{i}`, STATIC)
		facenum += 1
	end

	faces[facenum] = CacheLumpName("STFGOD0", STATIC)
	facenum += 1
	faces[facenum] = CacheLumpName("STFDEAD0", STATIC)
	facenum += 1

end

const function LoadData()
	LoadGraphics()
end

const function UnloadGraphics()
	ClearGraphics()
end

const function UnloadData()
	UnloadGraphics()
end

const function InitData()
	plyr = GetPrimaryPlayer()
	st_firsttime = true
	st_statusbaron = true
	st_armson = true
	st_faceindex = 0
	st_palette = 0
	st_oldhealth = -1
	st_facecount = 0
	st_randomnumber = 0
	lastattackdown = -1
	facePriority = 0
	lastPainHealth = -1
	lastPainOffset = 0

	for i = 0, Definitions.NUMWEAPONS - 1 do
		oldweaponsowned[i] = plyr.weaponowned[i] == true
	end

	for i = 0, 2 do
		keyboxes[i] = -1
	end

	ResetStatusWidgets()
	statusY = StatusY
	InitStatusWidgetLibrary()
end

const function CreateWidgets()
	InitNumberWidget(
		w_ready,
		AmmoX,
		AmmoY,
		tallnum,
		GetReadyAmmoValue,
		function()
			return st_statusbaron
		end,
		AmmoWidth
	)

	InitPercentWidget(
		w_health,
		HealthX,
		HealthY,
		tallnum,
		function()
			return plyr.health or 0
		end,
		function()
			return st_statusbaron
		end,
		tallpercent
	)

	InitBinaryIconWidget(
		w_armsbg,
		ArmsBackgroundX,
		ArmsBackgroundY,
		armsbg,
		function()
			return st_statusbaron
		end,
		function()
			return st_statusbaron
		end
	)

	for i = 0, 5 do
		const weaponIndex = i + 1

		w_arms[i] = ({} :: unknown) :: MultIconWidget
		InitMultiIconWidget(
			w_arms[i],
			ArmsX + (i % 3) * ArmsXSpace,
			ArmsY + i // 3 * ArmsYSpace,
			arms[i],
			function()
				return if IsSharewareStatusWeaponOwned(weaponIndex) then 1 else 0
			end,
			function()
				return st_armson
			end
		)
	end

	InitMultiIconWidget(
		w_faces,
		FacesX,
		FacesY,
		faces,
		function()
			return st_faceindex
		end,
		function()
			return st_statusbaron
		end
	)

	InitPercentWidget(
		w_armor,
		ArmorX,
		ArmorY,
		tallnum,
		function()
			return plyr.armorpoints or 0
		end,
		function()
			return st_statusbaron
		end,
		tallpercent
	)

	const keyPositions = {
		[0] = { x = Key0X, y = Key0Y },
		{ x = Key1X, y = Key1Y },
		{ x = Key2X, y = Key2Y },
	}

	for i = 0, 2 do
		const keySlot = i

		w_keyboxes[i] = ({} :: unknown) :: MultIconWidget
		InitMultiIconWidget(
			w_keyboxes[i],
			keyPositions[i].x,
			keyPositions[i].y,
			keys,
			function()
				return keyboxes[keySlot]
			end,
			function()
				return st_statusbaron
			end
		)
	end

	const ammoPositions = {
		[0] = { x = Ammo0X, y = Ammo0Y },
		{ x = Ammo1X, y = Ammo1Y },
		{ x = Ammo2X, y = Ammo2Y },
		{ x = Ammo3X, y = Ammo3Y },
	}
	const maxAmmoPositions = {
		[0] = { x = MaxAmmo0X, y = MaxAmmo0Y },
		{ x = MaxAmmo1X, y = MaxAmmo1Y },
		{ x = MaxAmmo2X, y = MaxAmmo2Y },
		{ x = MaxAmmo3X, y = MaxAmmo3Y },
	}

	for i = 0, 3 do
		const ammoIndex = i

		w_ammo[i] = ({} :: unknown) :: NumberWidget
		w_maxammo[i] = ({} :: unknown) :: NumberWidget

		InitNumberWidget(
			w_ammo[i],
			ammoPositions[i].x,
			ammoPositions[i].y,
			shortnum,
			function()
				return plyr.ammo[ammoIndex] or 0
			end,
			function()
				return st_statusbaron
			end,
			3
		)

		InitNumberWidget(
			w_maxammo[i],
			maxAmmoPositions[i].x,
			maxAmmoPositions[i].y,
			shortnum,
			function()
				return plyr.maxammo[ammoIndex] or 0
			end,
			function()
				return st_statusbaron
			end,
			3
		)
	end
end

const function Start()
	if not loaded then
		return
	end

	if started then
		started = false
	end

	InitData()
	ResetWidgets()
	CreateWidgets()
	started = true
end

const function Stop()
	started = false
	st_palette = 0
end

const function Init()
	if loaded then
		return
	end

	Video.SetScreenBuffer(BG, buffer.create(VideoMode.GetRenderPixelCount()))
	LoadData()
	loaded = true
end

const function Responder(ev: Event): boolean
	if ev.type == 1 and bit32.band(ev.data1 or 0, 0xFFFF0000) == AutomapMessageHeader then
		if ev.data1 == AutomapMessageEntered then
			automapactive = true
			st_firsttime = true
			return true
		end

		if ev.data1 == AutomapMessageExited then
			automapactive = false
			return true
		end
	end

	return false
end

const function SetPlayers(value: { [number]: Player })
	players = value
	plyr = GetPrimaryPlayer()
end

const function SetAutomapActive(value: boolean)
	automapactive = value
end

const function GetAutomapActive(): boolean
	return automapactive
end

const function GetPaletteIndex(): number
	return if started then st_palette else 0
end

const function IsStarted(): boolean
	return started
end

const function Reset()
	Stop()
	UnloadData()
	ResetStatusWidgets()
	ResetWidgets()
	table.clear(oldweaponsowned)
	players = {}
	plyr = nil
	automapactive = false
	loaded = false
end

return {
	StatusHeight = StatusHeight,
	StatusWidth = StatusWidth,
	StatusY = StatusY,

	Reset = Reset,
	SetPlayers = SetPlayers,
	SetAutomapActive = SetAutomapActive,
	GetAutomapActive = GetAutomapActive,
	GetPaletteIndex = GetPaletteIndex,
	IsStarted = IsStarted,

	Responder = Responder,
	Ticker = Ticker,
	Drawer = Drawer,
	Start = Start,
	Stop = Stop,
	Init = Init,
}
