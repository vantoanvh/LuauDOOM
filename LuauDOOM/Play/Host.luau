--!optimize 2
--!native

--[[
	Host.luau

	Exports host callback stubs for play systems when no platform host handlers are installed.
]]

const function startSound(...: unknown)
end

const function startSoundSystem(...: unknown)
end

const function startStatus(...: unknown)
end

const function startHUD(...: unknown)
end

const function stopAutomap(...: unknown)
end

const function getAutomapActive(): boolean
	return false
end

const function tactile(...: unknown)
end

const function exitLevel(...: unknown)
end

const function secretExitLevel(...: unknown)
end

const function reloadWad(...: unknown)
end

return {
	playerThink = nil,
	startSound = startSound,
	startSoundSystem = startSoundSystem,
	stopSound = nil,
	playerReborn = nil,
	startStatus = startStatus,
	startHUD = startHUD,
	dropWeapon = nil,
	stopAutomap = stopAutomap,
	getAutomapActive = getAutomapActive,
	tactile = tactile,
	useLines = nil,
	exitLevel = exitLevel,
	secretExitLevel = secretExitLevel,
	reloadWad = reloadWad,
}
