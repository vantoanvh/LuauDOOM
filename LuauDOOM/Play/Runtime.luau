--!native
--!optimize 2

-- Shared play runtime services. Setup owns wiring; play modules read from here.

const function NoOp(...: unknown)
end

const function GetAutomapActive(): boolean
	return false
end

const Runtime = {
	addThinker = nil,
	removeThinker = nil,
	getThinkerCap = nil,
	movePlane = nil,
	changeSector = nil,
	startSound = NoOp,
	stopSound = nil,
	getLevelTime = nil,
	damageMobj = nil,
	spawnMobj = nil,
	spawnPlayerMissile = nil,
	setMobjState = nil,
	removeMobj = nil,
	spawnPuff = nil,
	spawnBlood = nil,
	touchSpecialThing = nil,
	crossSpecialLine = nil,
	useLines = nil,
	useSpecialLine = nil,
	shootSpecialLine = nil,
	checkSight = nil,
	getMapNumber = nil,
	noiseAlert = nil,
	playerThink = nil,
	respawnSpecials = nil,
	rebornPlayer = nil,
	specialButtons = nil,
	setupPsprites = nil,
	playerReborn = nil,
	startStatus = nil,
	startHUD = nil,
	dropWeapon = NoOp,
	stopAutomap = NoOp,
	getAutomapActive = GetAutomapActive,
	tactile = NoOp,
	addTotalKills = nil,
	addTotalItems = nil,
	verticalDoor = nil,
	buildStairs = nil,
	doDonut = nil,
	exitLevel = nil,
	secretExitLevel = nil,
	doFloor = nil,
	doPlat = nil,
	doCeiling = nil,
	doDoor = nil,
	doLockedDoor = nil,
	lightTurnOn = nil,
}

const function Configure(values: { [string]: unknown })
	for name, value in values do
		Runtime[name] = value
	end
end

Runtime.Configure = Configure

return Runtime
