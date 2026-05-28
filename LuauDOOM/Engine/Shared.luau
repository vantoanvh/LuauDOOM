--!optimize 2
--!native

--[[
	Shared.luau

	Provides shared mutable engine callback slots used to break module cycles.
]]

const Demo = {
	advanceDemo = nil,
	quit = nil,
	writeRecordedDemo = nil,
	getRecordingHeader = nil,
	getGameTic = nil,
	getRealTime = nil,
	onTimingDemoComplete = nil,
	applyPlaybackHeader = nil,
}

const Title = {
	changeMusic = nil,
	playDemo = nil,
	setDemoScreen = nil,
}

const Finale = {
	changeMusic = nil,
	startSound = nil,
	requestWipe = nil,
	worldDone = nil,
}

const Intermission = {
	changeMusic = nil,
	startSound = nil,
	worldDone = nil,
}

const Menu = {
	startSound = nil,
	startNewGame = nil,
	getSaveDescription = nil,
	getGameTic = nil,
	getSfxVolume = nil,
	getMusicVolume = nil,
	takeScreenshot = nil,
	saveGame = nil,
	loadGame = nil,
	startTitle = nil,
	quitGame = nil,
	setSfxVolume = nil,
	setMusicVolume = nil,
	isUserGame = nil,
	isLevelGameState = nil,
	isDevParm = nil,
}

const Cheats = {
	warpToLevel = nil,
}

const Sound = {
	startSound = nil,
	stopSound = nil,
	isSoundPlaying = nil,
	updateSoundParams = nil,
	changeMusic = nil,
	stopMusic = nil,
	pauseSound = nil,
	resumeSound = nil,
	updateSounds = nil,
	setSfxVolume = nil,
	setMusicVolume = nil,
}

const System = {
	takeScreenshot = nil,
}

const function Reset()
	Demo.advanceDemo = nil
	Demo.quit = nil
	Demo.writeRecordedDemo = nil
	Demo.getRecordingHeader = nil
	Demo.getGameTic = nil
	Demo.getRealTime = nil
	Demo.onTimingDemoComplete = nil
	Demo.applyPlaybackHeader = nil

	Title.changeMusic = nil
	Title.playDemo = nil
	Title.setDemoScreen = nil

	Finale.changeMusic = nil
	Finale.startSound = nil
	Finale.requestWipe = nil
	Finale.worldDone = nil

	Intermission.changeMusic = nil
	Intermission.startSound = nil
	Intermission.worldDone = nil

	Menu.startSound = nil
	Menu.startNewGame = nil
	Menu.getSaveDescription = nil
	Menu.getGameTic = nil
	Menu.getSfxVolume = nil
	Menu.getMusicVolume = nil
	Menu.takeScreenshot = nil
	Menu.saveGame = nil
	Menu.loadGame = nil
	Menu.startTitle = nil
	Menu.quitGame = nil
	Menu.setSfxVolume = nil
	Menu.setMusicVolume = nil
	Menu.isUserGame = nil
	Menu.isLevelGameState = nil
	Menu.isDevParm = nil

	Cheats.warpToLevel = nil

	Sound.startSound = nil
	Sound.stopSound = nil
	Sound.isSoundPlaying = nil
	Sound.updateSoundParams = nil
	Sound.changeMusic = nil
	Sound.stopMusic = nil
	Sound.pauseSound = nil
	Sound.resumeSound = nil
	Sound.updateSounds = nil
	Sound.setSfxVolume = nil
	Sound.setMusicVolume = nil

	System.takeScreenshot = nil
end

return {
	Demo = Demo,
	Title = Title,
	Finale = Finale,
	Intermission = Intermission,
	Menu = Menu,
	Cheats = Cheats,
	Sound = Sound,
	System = System,
	Reset = Reset,
}
