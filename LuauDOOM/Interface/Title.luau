--!native
--!optimize 2

-- Port of the D_Page*/D_AdvanceDemo/D_StartTitle slice from d_main.c.
-- Demo playback stays host-driven so the outer engine owns the transition
-- into gameplay demo sessions.

const Definitions = require("../Engine/Definitions")
const Setup = require("../Play/Setup")
const Sounds = require("../Doom/Sounds")
const Host = require("../Engine/Shared").Title
const Video = require("../System/Video")
const Wad = require("../System/Wad")
const Zone = require("../System/Zone")

const ClearScreen = Video.ClearScreen
const DrawPatch = Video.DrawPatch
const CacheLumpName = Wad.CacheLumpName
const CACHE = Zone.CACHE

const function Warn(...: unknown)
	warn(...)
end

local active = false
local demosequence = -1
local pagetic = 0
local pagename = "TITLEPIC"
local advancedemo = false

const function Reset()
	active = false
	demosequence = -1
	pagetic = 0
	pagename = "TITLEPIC"
	advancedemo = false
end

const function ChangeMusic(track: number)
	const changeMusic = Host.changeMusic

	if changeMusic ~= nil then
		changeMusic(track)
	end
end

const function SetDemoScreen()
	const setDemoScreen = Host.setDemoScreen

	if setDemoScreen ~= nil then
		setDemoScreen()
	end
end

const function PlayDemo(name: string)
	const playDemo = Host.playDemo

	if playDemo == nil then
		Warn(`Title: missing playDemo handler for {name}`)
		return false
	end

	if playDemo(name) == false then
		Warn(`Title: failed to play demo {name}`)
		return false
	end

	return true
end

const function AdvanceDemo()
	advancedemo = true
end

const function PageTicker()
	pagetic -= 1

	if pagetic < 0 then
		AdvanceDemo()
	end
end

const function PageDrawer()
	ClearScreen(0, 0)
	DrawPatch(0, 0, 0, CacheLumpName(pagename, CACHE))
end

const function GetPrimaryPlayer()
	const players = Setup.GetPlayers()
	local player = players[0]

	if player == nil then
		player = players[1]
	end

	if player ~= nil then
		return player
	end

	return nil
end

const function DoAdvanceDemo()
	const gamemode = Setup.GetGameMode()
	const player = GetPrimaryPlayer()

	active = true
	advancedemo = false
	Setup.SetPaused(false)

	if player ~= nil then
		player.playerstate = 0 -- PST_LIVE
	end

	if gamemode == Definitions.retail then
		demosequence = (demosequence + 1) % 7
	else
		demosequence = (demosequence + 1) % 6
	end

	if demosequence == 0 then
		if gamemode == Definitions.commercial then
			pagetic = 35 * 11
		else
			pagetic = 170
		end

		SetDemoScreen()
		pagename = "TITLEPIC"

		if gamemode == Definitions.commercial then
			ChangeMusic(Sounds.mus_dm2ttl)
		else
			ChangeMusic(Sounds.mus_intro)
		end
	elseif demosequence == 1 then
		PlayDemo("demo1")
	elseif demosequence == 2 then
		pagetic = 200
		SetDemoScreen()
		pagename = "CREDIT"
	elseif demosequence == 3 then
		PlayDemo("demo2")
	elseif demosequence == 4 then
		SetDemoScreen()

		if gamemode == Definitions.commercial then
			pagetic = 35 * 11
			pagename = "TITLEPIC"
			ChangeMusic(Sounds.mus_dm2ttl)
		else
			pagetic = 200

			if gamemode == Definitions.retail then
				pagename = "CREDIT"
			else
				pagename = "HELP2"
			end
		end
	elseif demosequence == 5 then
		PlayDemo("demo3")
	elseif demosequence == 6 then
		PlayDemo("demo4")
	end
end

const function ProcessAdvanceDemo()
	if advancedemo then
		DoAdvanceDemo()
	end
end

const function Ticker()
	PageTicker()
end

const function StartTitle()
	demosequence = -1
	AdvanceDemo()
end

const function IsActive(): boolean
	return active
end

const function GetPageName(): string
	return pagename
end

const function GetPageTic(): number
	return pagetic
end

const function GetDemoSequence(): number
	return demosequence
end

const function IsAdvancePending(): boolean
	return advancedemo
end

return {
	Reset = Reset,
	IsActive = IsActive,
	GetPageName = GetPageName,
	GetPageTic = GetPageTic,
	GetDemoSequence = GetDemoSequence,
	IsAdvancePending = IsAdvancePending,
	ProcessAdvanceDemo = ProcessAdvanceDemo,
	Ticker = Ticker,
	PageTicker = PageTicker,
	PageDrawer = PageDrawer,
	AdvanceDemo = AdvanceDemo,
	DoAdvanceDemo = DoAdvanceDemo,
	StartTitle = StartTitle,
}
