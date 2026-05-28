--!native
--!optimize 2

-- Port of wi_stuff.c, wi_stuff.h.
-- Current scope is the real single-player intermission path used by this
-- project. Netgame and deathmatch tables are intentionally left out until the
-- rest of multiplayer exists.

const Definitions = require("../Engine/Definitions")
const Host = require("../Engine/Shared").Intermission
const Random = require("../Miscellaneous/Random")
const Setup = require("../Play/Setup")
const Sounds = require("../Doom/Sounds")
const Video = require("../System/Video")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const MenuRandom = Random.MenuRandom
const ClearScreen = Video.ClearScreen
const CopyRect = Video.CopyRect
const DrawPatch = Video.DrawPatch
const CacheLumpName = Wad.CacheLumpName
const ChangeTag = Zone.ChangeTag
const STATIC = Zone.STATIC
const CACHE = Zone.CACHE

const NUMMAPS = 9
const TitleY = 2
const STATSX = 50
const STATSY = 50
const TIMEX = 16
const TIMEY = Definitions.SCREENHEIGHT - 32
const SHOWNEXTLOCDELAY = 4
const TICRATE = Definitions.TICRATE
const ATTACK = 1
const USE = 2
const FB = 0

const NoState = -1
const StatCount = 0
const ShowNextLoc = 1

const ANIM_ALWAYS = 0
const ANIM_RANDOM = 1
const ANIM_LEVEL = 2

const lnodes = {
	[0] = {
		[0] = { x = 185, y = 164 },
		{ x = 148, y = 143 },
		{ x = 69, y = 122 },
		{ x = 209, y = 102 },
		{ x = 116, y = 89 },
		{ x = 166, y = 55 },
		{ x = 71, y = 56 },
		{ x = 135, y = 29 },
		{ x = 71, y = 24 },
	},
	[1] = {
		[0] = { x = 254, y = 25 },
		{ x = 97, y = 50 },
		{ x = 188, y = 64 },
		{ x = 128, y = 78 },
		{ x = 214, y = 92 },
		{ x = 133, y = 130 },
		{ x = 208, y = 136 },
		{ x = 148, y = 140 },
		{ x = 235, y = 158 },
	},
	[2] = {
		[0] = { x = 156, y = 168 },
		{ x = 48, y = 154 },
		{ x = 174, y = 95 },
		{ x = 265, y = 75 },
		{ x = 130, y = 48 },
		{ x = 279, y = 23 },
		{ x = 198, y = 48 },
		{ x = 140, y = 25 },
		{ x = 281, y = 136 },
	},
}

const epsd0animinfo = {
	[0] = { type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 224, y = 104 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 184, y = 160 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 112, y = 136 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 72, y = 112 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 88, y = 96 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 64, y = 48 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 192, y = 40 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 136, y = 16 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 80, y = 16 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 64, y = 24 }, p = {} },
}

const epsd1animinfo = {
	[0] = { type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 1, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 2, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 3, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 4, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 5, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 6, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 7, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 3, loc = { x = 192, y = 144 }, data1 = 8, p = {} },
	{ type = ANIM_LEVEL, period = TICRATE // 3, nanims = 1, loc = { x = 128, y = 136 }, data1 = 8, p = {} },
}

const epsd2animinfo = {
	[0] = { type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 104, y = 168 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 40, y = 136 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 160, y = 96 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 104, y = 80 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 3, nanims = 3, loc = { x = 120, y = 32 }, p = {} },
	{ type = ANIM_ALWAYS, period = TICRATE // 4, nanims = 3, loc = { x = 40, y = 0 }, p = {} },
}

const anims = {
	[0] = epsd0animinfo,
	[1] = epsd1animinfo,
	[2] = epsd2animinfo,
}

const NUMANIMS = {
	[0] = 10,
	[1] = 9,
	[2] = 6,
}

local active = false
local state = NoState
local wbs = false
local plrs = false
local me = 0
local cnt = 0
local bcnt = 0
local acceleratestage = 0
local snl_pointeron = false
local sp_state = 0
local cnt_kills = -1
local cnt_items = -1
local cnt_secret = -1
local cnt_time = -1
local cnt_par = -1
local cnt_pause = 0
local NUMCMAPS = 0

local bg = false
const yah: { [number]: buffer } = {}
local splat = false
local percent = false
local colon = false
const num: { [number]: buffer } = {}
local wiminus = false
local finished = false
local entering = false
local kills = false
local sp_secret = false
local items = false
local timePatch = false
local par = false
local sucks = false
const lnames: { [number]: buffer } = {}

const function StartSound(origin: unknown, sound: unknown)
	const callback = Host.startSound

	if callback ~= nil and typeof(sound) == "number" and sound ~= 0 then
		callback(origin, sound)
	end
end

const function ChangeMusic(music: number, looping: boolean)
	const callback = Host.changeMusic

	if callback ~= nil then
		callback(music, looping)
	end
end

const function CallWorldDone()
	const callback = Host.worldDone

	if callback ~= nil then
		callback()
	end
end

const function DemotePatchToCache(patch: unknown)
	if typeof(patch) == "buffer" then
		ChangeTag(patch, CACHE)
	end
end

const function SlamBackground()
	ClearScreen(0, 0)
	CopyRect(0, 0, 1, Definitions.SCREENWIDTH, Definitions.SCREENHEIGHT, 0, 0, 0)
end

const function Responder(_ev: unknown): boolean
	return false
end

const function DrawLevelFinished()
	local y = TitleY
	const lastName = lnames[wbs.last]

	DrawPatch((Definitions.SCREENWIDTH - buffer.readi16(lastName, 0)) // 2, y, FB, lastName)
	y += (5 * buffer.readi16(lastName, 2)) // 4
	DrawPatch((Definitions.SCREENWIDTH - buffer.readi16(finished :: buffer, 0)) // 2, y, FB, finished :: buffer)
end

const function DrawEnteringLevel()
	local y = TitleY
	const nextName = lnames[wbs.next]

	DrawPatch((Definitions.SCREENWIDTH - buffer.readi16(entering :: buffer, 0)) // 2, y, FB, entering :: buffer)
	y += (5 * buffer.readi16(nextName, 2)) // 4
	DrawPatch((Definitions.SCREENWIDTH - buffer.readi16(nextName, 0)) // 2, y, FB, nextName)
end

const function DrawOnLocationNode(n: number, candidates: { [number]: buffer })
	local fits = false
	local chosen: buffer? = nil
	local i = 0

	repeat
		const patch = candidates[i]

		if typeof(patch) == "buffer" then
			const node = lnodes[wbs.epsd][n]
			const left = node.x - buffer.readi16(patch, 4)
			const top = node.y - buffer.readi16(patch, 6)
			const right = left + buffer.readi16(patch, 0)
			const bottom = top + buffer.readi16(patch, 2)

			if left >= 0 and right < Definitions.SCREENWIDTH and top >= 0 and bottom < Definitions.SCREENHEIGHT then
				fits = true
				chosen = patch
			else
				i += 1
			end
		else
			break
		end
	until fits or i == 2

	if fits and chosen ~= nil then
		const node = lnodes[wbs.epsd][n]
		DrawPatch(node.x, node.y, FB, chosen)
	end
end

const function InitAnimatedBack()
	if Setup.GetGameMode() == Definitions.commercial or wbs.epsd > 2 then
		return
	end

	for i = 0, NUMANIMS[wbs.epsd] - 1 do
		const a = anims[wbs.epsd][i]
		a.ctr = -1

		if a.type == ANIM_ALWAYS then
			a.nexttic = bcnt + 1 + (MenuRandom() % a.period)
		elseif a.type == ANIM_RANDOM then
			a.nexttic = bcnt + 1 + a.data2 + (MenuRandom() % a.data1)
		else
			a.nexttic = bcnt + 1
		end
	end
end

const function UpdateAnimatedBack()
	if Setup.GetGameMode() == Definitions.commercial or wbs.epsd > 2 then
		return
	end

	for i = 0, NUMANIMS[wbs.epsd] - 1 do
		const a = anims[wbs.epsd][i]

		if bcnt == a.nexttic then
			if a.type == ANIM_ALWAYS then
				a.ctr += 1
				if a.ctr >= a.nanims then
					a.ctr = 0
				end

				a.nexttic = bcnt + a.period
			elseif a.type == ANIM_RANDOM then
				a.ctr += 1

				if a.ctr == a.nanims then
					a.ctr = -1
					a.nexttic = bcnt + a.data2 + (MenuRandom() % a.data1)
				else
					a.nexttic = bcnt + a.period
				end
			elseif state == StatCount and i == 7 then
				-- Original hack in wi_stuff.c.
				continue
			elseif wbs.next == a.data1 then
				a.ctr += 1
				if a.ctr == a.nanims then
					a.ctr -= 1
				end

				a.nexttic = bcnt + a.period
			end
		end
	end
end

const function DrawAnimatedBack()
	if Setup.GetGameMode() == Definitions.commercial or wbs.epsd > 2 then
		return
	end

	for i = 0, NUMANIMS[wbs.epsd] - 1 do
		const a = anims[wbs.epsd][i]

		if typeof(a.p[a.ctr]) == "buffer" then
			DrawPatch(a.loc.x, a.loc.y, FB, a.p[a.ctr])
		end
	end
end

const function DrawNumber(x: number, y: number, n: number, digits: number): number
	const fontwidth = buffer.readi16(num[0], 0)
	const neg = n < 0
	local temp = if n < 0 then -n else n

	if digits < 0 then
		if n == 0 then
			digits = 1
		else
			digits = 0
			while temp ~= 0 do
				temp //= 10
				digits += 1
			end
		end
	end

	if neg then
		n = -n
	end

	if n == 1994 then
		return 0
	end

	while digits > 0 do
		x -= fontwidth
		DrawPatch(x, y, FB, num[n % 10])
		n //= 10
		digits -= 1
	end

	if neg then
		x -= 8
		DrawPatch(x, y, FB, wiminus)
	end

	return x
end

const function DrawPercent(x: number, y: number, p: number)
	if p < 0 then
		return
	end

	DrawPatch(x, y, FB, percent)
	DrawNumber(x, y, p, -1)
end

const function DrawTime(x: number, y: number, t: number)
	if t < 0 then
		return
	end

	if t <= 61 * 59 then
		local div = 1

		repeat
			const n = (t // div) % 60
			x = DrawNumber(x, y, n, 2) - buffer.readi16(colon :: buffer, 0)
			div *= 60

			if div == 60 or t // div ~= 0 then
				DrawPatch(x, y, FB, colon)
			end
		until t // div == 0
	else
		DrawPatch(x - buffer.readi16(sucks :: buffer, 0), y, FB, sucks :: buffer)
	end
end

const function UnloadData()
	for _, patch in yah do
		DemotePatchToCache(patch)
	end

	for _, patch in num do
		DemotePatchToCache(patch)
	end

	for _, patch in lnames do
		DemotePatchToCache(patch)
	end

	DemotePatchToCache(splat)
	DemotePatchToCache(percent)
	DemotePatchToCache(colon)
	DemotePatchToCache(wiminus)
	DemotePatchToCache(finished)
	DemotePatchToCache(entering)
	DemotePatchToCache(kills)
	DemotePatchToCache(sp_secret)
	DemotePatchToCache(items)
	DemotePatchToCache(timePatch)
	DemotePatchToCache(sucks)
	DemotePatchToCache(par)

	for episode = 0, 2 do
		for index = 0, NUMANIMS[episode] - 1 do
			const a = anims[episode][index]

			for _, patch in a.p do
				DemotePatchToCache(patch)
			end
		end
	end

	bg = false
	table.clear(yah)
	splat = false
	percent = false
	colon = false
	table.clear(num)
	wiminus = false
	finished = false
	entering = false
	kills = false
	sp_secret = false
	items = false
	timePatch = false
	par = false
	sucks = false
	table.clear(lnames)

	for episode = 0, 2 do
		for index = 0, NUMANIMS[episode] - 1 do
			const a = anims[episode][index]
			table.clear(a.p)
			a.ctr = -1
			a.nexttic = 0
		end
	end
end

const function EndIntermission()
	UnloadData()
	active = false
end

const function InitNoState()
	state = NoState
	acceleratestage = 0
	cnt = 10
end

const function UpdateNoState()
	UpdateAnimatedBack()

	cnt -= 1
	if cnt <= 0 then
		EndIntermission()
		CallWorldDone()
	end
end

const function InitShowNextLocation()
	state = ShowNextLoc
	acceleratestage = 0
	cnt = SHOWNEXTLOCDELAY * TICRATE
	InitAnimatedBack()
end

const function UpdateShowNextLocation()
	UpdateAnimatedBack()
	cnt -= 1

	if cnt <= 0 or acceleratestage ~= 0 then
		InitNoState()
	else
		snl_pointeron = bit32.band(cnt, 31) < 20
	end
end

const function DrawShowNextLocation()
	SlamBackground()
	DrawAnimatedBack()

	if Setup.GetGameMode() ~= Definitions.commercial then
		if wbs.epsd > 2 then
			DrawEnteringLevel()
			return
		end

		const last = if wbs.last == 8 then wbs.next - 1 else wbs.last
		const splatCandidates: { [number]: buffer } = { [0] = splat :: buffer }

		for i = 0, last do
			DrawOnLocationNode(i, splatCandidates)
		end

		if wbs.didsecret then
			DrawOnLocationNode(8, splatCandidates)
		end

		if snl_pointeron then
			DrawOnLocationNode(wbs.next, yah)
		end
	end

	if Setup.GetGameMode() ~= Definitions.commercial or wbs.next ~= 30 then
		DrawEnteringLevel()
	end
end

const function DrawNoState()
	snl_pointeron = true
	DrawShowNextLocation()
end

const function InitStats()
	state = StatCount
	acceleratestage = 0
	sp_state = 1
	cnt_kills = -1
	cnt_items = -1
	cnt_secret = -1
	cnt_time = -1
	cnt_par = -1
	cnt_pause = TICRATE
	InitAnimatedBack()
end

const function SafePercent(value: number, maxValue: number): number
	if maxValue <= 0 then
		return 100
	end

	return (value * 100) // maxValue
end

const function UpdateStats()
	UpdateAnimatedBack()

	if acceleratestage ~= 0 and sp_state ~= 10 then
		acceleratestage = 0
		cnt_kills = SafePercent(plrs[me].skills, wbs.maxkills)
		cnt_items = SafePercent(plrs[me].sitems, wbs.maxitems)
		cnt_secret = SafePercent(plrs[me].ssecret, wbs.maxsecret)
		cnt_time = plrs[me].stime // TICRATE
		cnt_par = wbs.partime // TICRATE
		StartSound(nil, Sounds.sfx_barexp)
		sp_state = 10
	end

	if sp_state == 2 then
		cnt_kills += 2

		if bit32.band(bcnt, 3) == 0 then
			StartSound(nil, Sounds.sfx_pistol)
		end

		const target = SafePercent(plrs[me].skills, wbs.maxkills)

		if cnt_kills >= target then
			cnt_kills = target
			StartSound(nil, Sounds.sfx_barexp)
			sp_state += 1
		end
	elseif sp_state == 4 then
		cnt_items += 2

		if bit32.band(bcnt, 3) == 0 then
			StartSound(nil, Sounds.sfx_pistol)
		end

		const target = SafePercent(plrs[me].sitems, wbs.maxitems)

		if cnt_items >= target then
			cnt_items = target
			StartSound(nil, Sounds.sfx_barexp)
			sp_state += 1
		end
	elseif sp_state == 6 then
		cnt_secret += 2

		if bit32.band(bcnt, 3) == 0 then
			StartSound(nil, Sounds.sfx_pistol)
		end

		const target = SafePercent(plrs[me].ssecret, wbs.maxsecret)

		if cnt_secret >= target then
			cnt_secret = target
			StartSound(nil, Sounds.sfx_barexp)
			sp_state += 1
		end
	elseif sp_state == 8 then
		if bit32.band(bcnt, 3) == 0 then
			StartSound(nil, Sounds.sfx_pistol)
		end

		cnt_time += 3
		if cnt_time >= plrs[me].stime // TICRATE then
			cnt_time = plrs[me].stime // TICRATE
		end

		cnt_par += 3
		if cnt_par >= wbs.partime // TICRATE then
			cnt_par = wbs.partime // TICRATE

			if cnt_time >= plrs[me].stime // TICRATE then
				StartSound(nil, Sounds.sfx_barexp)
				sp_state += 1
			end
		end
	elseif sp_state == 10 then
		if acceleratestage ~= 0 then
			StartSound(nil, Sounds.sfx_sgcock)

			if Setup.GetGameMode() == Definitions.commercial then
				InitNoState()
			else
				InitShowNextLocation()
			end
		end
	elseif bit32.btest(sp_state, 1) then
		cnt_pause -= 1
		if cnt_pause <= 0 then
			sp_state += 1
			cnt_pause = TICRATE
		end
	end
end

const function DrawStats()
	const lh = (3 * buffer.readi16(num[0], 2)) // 2

	SlamBackground()
	DrawAnimatedBack()
	DrawLevelFinished()

	DrawPatch(STATSX, STATSY, FB, kills)
	DrawPercent(Definitions.SCREENWIDTH - STATSX, STATSY, cnt_kills)

	DrawPatch(STATSX, STATSY + lh, FB, items)
	DrawPercent(Definitions.SCREENWIDTH - STATSX, STATSY + lh, cnt_items)

	DrawPatch(STATSX, STATSY + 2 * lh, FB, sp_secret)
	DrawPercent(Definitions.SCREENWIDTH - STATSX, STATSY + 2 * lh, cnt_secret)

	DrawPatch(TIMEX, TIMEY, FB, timePatch)
	DrawTime(Definitions.SCREENWIDTH // 2 - TIMEX, TIMEY, cnt_time)

	if wbs.epsd < 3 then
		DrawPatch(Definitions.SCREENWIDTH // 2 + TIMEX, TIMEY, FB, par)
		DrawTime(Definitions.SCREENWIDTH - TIMEX, TIMEY, cnt_par)
	end
end

const function CheckForAccelerate()
	const players = Setup.GetPlayers()
	const player = players[0] or players[1]

	if typeof(player) ~= "table" or typeof(player.cmd) ~= "table" then
		return
	end

	if bit32.btest(player.cmd.buttons, ATTACK) then
		if not player.attackdown then
			acceleratestage = 1
		end

		player.attackdown = true
	else
		player.attackdown = false
	end

	if bit32.btest(player.cmd.buttons, USE) then
		if not player.usedown then
			acceleratestage = 1
		end

		player.usedown = true
	else
		player.usedown = false
	end
end

const function Ticker()
	if not active then
		return
	end

	bcnt += 1

	if bcnt == 1 then
		if Setup.GetGameMode() == Definitions.commercial then
			ChangeMusic(Sounds.mus_dm2int, true)
		else
			ChangeMusic(Sounds.mus_inter, true)
		end
	end

	CheckForAccelerate()

	if state == StatCount then
		UpdateStats()
	elseif state == ShowNextLoc then
		UpdateShowNextLocation()
	else
		UpdateNoState()
	end
end

const function LoadData()
	const gamemode = Setup.GetGameMode()
	local name = ""

	if gamemode == Definitions.commercial then
		name = "INTERPIC"
	elseif gamemode == Definitions.retail and wbs.epsd == 3 then
		name = "INTERPIC"
	else
		name = `WIMAP{wbs.epsd}`
	end

	bg = CacheLumpName(name, CACHE)
	DrawPatch(0, 0, 1, bg)

	if gamemode == Definitions.commercial then
		NUMCMAPS = 32
		for i = 0, NUMCMAPS - 1 do
			lnames[i] = CacheLumpName(string.format("CWILV%2.2d", i), STATIC)
		end
	else
		for i = 0, NUMMAPS - 1 do
			lnames[i] = CacheLumpName(string.format("WILV%d%d", wbs.epsd, i), STATIC)
		end

		yah[0] = CacheLumpName("WIURH0", STATIC)
		yah[1] = CacheLumpName("WIURH1", STATIC)
		splat = CacheLumpName("WISPLAT", STATIC)

		if wbs.epsd < 3 then
			for j = 0, NUMANIMS[wbs.epsd] - 1 do
				const a = anims[wbs.epsd][j]

				for i = 0, a.nanims - 1 do
					if wbs.epsd ~= 1 or j ~= 8 then
						a.p[i] = CacheLumpName(string.format("WIA%d%.2d%.2d", wbs.epsd, j, i), STATIC)
					else
						a.p[i] = anims[1][4].p[i]
					end
				end
			end
		end
	end

	wiminus = CacheLumpName("WIMINUS", STATIC)

	for i = 0, 9 do
		num[i] = CacheLumpName(`WINUM{i}`, STATIC)
	end

	percent = CacheLumpName("WIPCNT", STATIC)
	finished = CacheLumpName("WIF", STATIC)
	entering = CacheLumpName("WIENTER", STATIC)
	kills = CacheLumpName("WIOSTK", STATIC)
	sp_secret = CacheLumpName("WISCRT2", STATIC)
	items = CacheLumpName("WIOSTI", STATIC)
	colon = CacheLumpName("WICOLON", STATIC)
	timePatch = CacheLumpName("WITIME", STATIC)
	sucks = CacheLumpName("WISUCKS", STATIC)
	par = CacheLumpName("WIPAR", STATIC)
end

const function Drawer()
	if not active then
		return
	end

	if state == StatCount then
		DrawStats()
	elseif state == ShowNextLoc then
		DrawShowNextLocation()
	else
		DrawNoState()
	end
end

const function InitVariables(wbstartstruct: unknown)
	wbs = wbstartstruct
	acceleratestage = 0
	cnt = 0
	bcnt = 0
	me = 0
	plrs = wbs.plyr

	if wbs.maxkills == 0 then
		wbs.maxkills = 1
	end

	if wbs.maxitems == 0 then
		wbs.maxitems = 1
	end

	if wbs.maxsecret == 0 then
		wbs.maxsecret = 1
	end

	if Setup.GetGameMode() ~= Definitions.retail and wbs.epsd > 2 then
		wbs.epsd -= 3
	end
end

const function Start(wbstartstruct: unknown)
	active = true
	InitVariables(wbstartstruct)
	LoadData()
	InitStats()
end

const function Reset()
	active = false
	state = NoState
	wbs = false
	plrs = false
	me = 0
	cnt = 0
	bcnt = 0
	acceleratestage = 0
	snl_pointeron = false
	sp_state = 0
	cnt_kills = -1
	cnt_items = -1
	cnt_secret = -1
	cnt_time = -1
	cnt_par = -1
	cnt_pause = 0
	NUMCMAPS = 0
	UnloadData()
end

const function IsActive(): boolean
	return active
end

return {
	NoState = NoState,
	StatCount = StatCount,
	ShowNextLoc = ShowNextLoc,
	Reset = Reset,
	IsActive = IsActive,
	Responder = Responder,
	Ticker = Ticker,
	Drawer = Drawer,
	Start = Start,
}
