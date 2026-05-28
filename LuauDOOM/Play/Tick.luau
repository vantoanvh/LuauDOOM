--!native
--!optimize 2

-- Port of p_tick.c
-- Thinker list management and per-tic play updates.

const Runtime = require("./Runtime")
const Specials = require("./Specials")
const State = require("../Renderer/State")

const PST_REBORN = 2

type PlayerSlot = {
	[string]: unknown,
	playerstate: number,
	viewz: number,
}

type ThinkerFunction = {
	acp1: ((unknown) -> ())?,
	acv: number?,
}

type Thinker = {
	[string]: unknown,
	owner: unknown?,
	prev: Thinker?,
	next: Thinker?,
	["function"]: ThinkerFunction,
}

type ThinkerCap = {
	prev: Thinker | ThinkerCap,
	next: Thinker | ThinkerCap,
}

const thinkercap: ThinkerCap = {}
local players: { [number]: PlayerSlot } = {}
local paused = false
local menuactive = false
local leveltime = 0

const function GetPrimaryPlayer(): PlayerSlot
	return players[0]
end

--
-- InitThinkers
--
const function InitThinkers()
	table.clear(thinkercap)
	thinkercap.prev = thinkercap
	thinkercap.next = thinkercap
end

--
-- AddThinker
-- Adds a new thinker at the end of the list.
--
const function AddThinker(thinker: Thinker)
	const tail = thinkercap.prev

	tail.next = thinker
	thinker.next = thinkercap
	thinker.prev = tail
	thinkercap.prev = thinker
end

--
-- RemoveThinker
-- Deallocation is lazy -- it will not actually be removed
-- until its thinking turn comes up.
--
const function RemoveThinker(thinker: Thinker)
	thinker["function"].acp1 = nil
	thinker["function"].acv = -1
end

--
-- AllocateThinker
-- Empty in this source snapshot too.
--
const function AllocateThinker(_thinker: Thinker)
end

--
-- RunThinkers
--
const function RunThinkers()
	local currentthinker = thinkercap.next

	while currentthinker ~= thinkercap do
		const thinkerFunction = currentthinker["function"]

		if thinkerFunction.acv == -1 then
			const nextthinker = currentthinker.next
			const prevthinker = currentthinker.prev

			nextthinker.prev = prevthinker
			prevthinker.next = nextthinker
			currentthinker.next = nil
			currentthinker.prev = nil
			currentthinker = nextthinker
		else
			const action = thinkerFunction.acp1

			if action ~= nil then
				action(currentthinker.owner or currentthinker)
			end

			currentthinker = currentthinker.next
		end
	end
end

--
-- Ticker
--
const function Ticker()
	local player = GetPrimaryPlayer()

	if player.playerstate == PST_REBORN then
		Runtime.rebornPlayer(0, player)
		player = GetPrimaryPlayer()

		if player.playerstate == PST_REBORN then
			return
		end
	end

	const specialButtons = Runtime.specialButtons

	if specialButtons ~= nil then
		specialButtons(player)
	end

	if paused then
		return
	end

	if menuactive and State.demoplayback ~= true and player.viewz ~= 1 then
		return
	end

	Runtime.playerThink(player)

	RunThinkers()
	Specials.UpdateSpecials()
	Runtime.respawnSpecials()

	leveltime += 1
end

const function Reset()
	players = {}
	paused = false
	menuactive = false
	leveltime = 0
	State.demoplayback = false
	InitThinkers()
end

Reset()

const function SetPlayers(value: { [number]: PlayerSlot })
	players = value
end

const function GetPlayers(): { [number]: PlayerSlot }
	return players
end

const function SetPaused(value: boolean)
	paused = value
end

const function GetPaused(): boolean
	return paused
end

const function SetMenuActive(value: boolean)
	menuactive = value
end

const function GetMenuActive(): boolean
	return menuactive
end

const function SetDemoPlayback(value: boolean)
	State.demoplayback = value
end

const function GetDemoPlayback(): boolean
	return State.demoplayback == true
end

const function SetLevelTime(value: number)
	leveltime = value
end

const function GetLevelTime(): number
	return leveltime
end

const function GetThinkerCap(): ThinkerCap
	return thinkercap
end

const Tick = {
	Reset = Reset,
	SetPlayers = SetPlayers,
	GetPlayers = GetPlayers,
	SetPaused = SetPaused,
	GetPaused = GetPaused,
	SetMenuActive = SetMenuActive,
	GetMenuActive = GetMenuActive,
	SetDemoPlayback = SetDemoPlayback,
	GetDemoPlayback = GetDemoPlayback,
	SetLevelTime = SetLevelTime,
	GetLevelTime = GetLevelTime,
	GetThinkerCap = GetThinkerCap,
}

Tick.InitThinkers = InitThinkers
Tick.AddThinker = AddThinker
Tick.RemoveThinker = RemoveThinker
Tick.AllocateThinker = AllocateThinker
Tick.RunThinkers = RunThinkers
Tick.Ticker = Ticker

return Tick
