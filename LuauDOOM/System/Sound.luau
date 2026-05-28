--!native
--!optimize 2

-- Port of the high-level s_sound.c/s_sound.h ownership layer.
-- Actual backend playback stays host-driven for the runtime.

const Definitions = require("../Engine/Definitions")
const Sounds = require("../Doom/Sounds")
const Fixed = require("../Miscellaneous/Fixed")
const Tables = require("../Engine/Tables")
const Geometry = require("../Renderer/Geometry")
const Setup = require("../Play/Setup")
const Host = require("../Engine/Shared").Sound

const NORM_PITCH = 128
const NORM_PRIORITY = 64
const NORM_SEP = 128
const SoundClippingDistance = 1200 * Fixed.FRACUNIT
const SoundCloseDistance = 160 * Fixed.FRACUNIT
const SoundAttenuator = bit32.rshift(SoundClippingDistance - SoundCloseDistance, Fixed.FRACBITS)
const SoundStereoSwing = 96 * Fixed.FRACUNIT

type Channel = {
	origin: unknown?,
	sfxinfo: number,
	handle: unknown?,
	priority: number,
	volume: number,
	sep: number,
	pitch: number,
}

type SoundInfo = {
	name: string,
	priority: number?,
	link: number?,
	volume: number?,
	range: { number }?,
}

type SoundModuleInfo = {
	sounds: { [number]: SoundInfo }?,
	ById: { [number]: SoundInfo },
	Resolve: ((number) -> SoundInfo?)?,
}

type SoundPosition = {
	x: number,
	y: number,
	angle: number,
}

local snd_SfxVolume = 15
local snd_MusicVolume = 15
local mus_paused = false
local mus_playing = Sounds.mus_None
local mus_looping = false
local numChannels = 8
const channels: { [number]: Channel } = {}
const soundPriorities: { [number]: number } = {}
const backendPriorities: { [number]: number } = {}
const soundVolumeOffsets: { [number]: number } = {}
const musicObjects: { [number]: Sound } = {}
local musicParent = game:GetService("SoundService")
local currentMusicObject: Sound? = nil

const function NormalizeSoundId(soundId: number): string
	return `rbxassetid://{soundId}`
end

const function ResolveMusicId(name: unknown): number
	if typeof(name) == "number" then
		return name
	end

	if typeof(name) ~= "string" then
		return Sounds.mus_None
	end

	local musicId = Sounds.ByName[name]

	if typeof(musicId) == "number" then
		return musicId
	end

	musicId = Sounds.ByName[`mus_{name}`]

	if typeof(musicId) == "number" then
		return musicId
	end

	return Sounds.mus_None
end

const function SetMusicObjectVolume(sound: Sound, volume: number)
	sound.Volume = volume / 15
end

const function ReparentMusicObjects(parent: Instance?)
	musicParent = if parent ~= nil then parent else game:GetService("SoundService")

	for _, sound in musicObjects do
		sound.Parent = musicParent
	end
end

const function StartMusicObject(sound: Sound, looping: boolean, volume: number)
	if currentMusicObject ~= nil and currentMusicObject ~= sound then
		currentMusicObject:Stop()
	end

	currentMusicObject = sound
	sound.Looped = looping
	SetMusicObjectVolume(sound, volume)
	sound.TimePosition = 0
	sound.Parent = musicParent
	sound:Play()
end

const function AddOST(name: unknown, soundId: number)
	const musicId = ResolveMusicId(name)

	if musicId == Sounds.mus_None then
		return nil
	end

	const previous = musicObjects[musicId]

	if previous ~= nil then
		previous:Stop()
		previous:Destroy()
	end

	const sound = Instance.new("Sound")
	sound.Name = if typeof(name) == "string" then name else tostring(musicId)
	sound.SoundId = NormalizeSoundId(soundId)
	sound.Looped = false
	SetMusicObjectVolume(sound, snd_MusicVolume)
	sound.Parent = musicParent
	musicObjects[musicId] = sound

	if mus_playing == musicId then
		currentMusicObject = nil

		if mus_paused then
			currentMusicObject = sound
			sound.Looped = mus_looping
		else
			StartMusicObject(sound, mus_looping, snd_MusicVolume)
		end
	end

	return sound
end

const function GetSoundTable(moduleInfo: SoundModuleInfo)
	return if moduleInfo.sounds ~= nil then moduleInfo.sounds else moduleInfo.ById
end

const function ResolveAtlasSound(moduleInfo: SoundModuleInfo, sfxId: number)
	if moduleInfo.Resolve ~= nil then
		return moduleInfo.Resolve(sfxId)
	end

	const sounds = GetSoundTable(moduleInfo)
	const info = sounds[sfxId]

	if info ~= nil and info.link ~= nil and info.link ~= 0 then
		return sounds[info.link]
	end

	return info
end

const function CreateSoundObjects(soundId: number, moduleInfo: SoundModuleInfo, parent: Instance?)
	const assetId = NormalizeSoundId(soundId)
	const soundParent = if parent ~= nil then parent else game:GetService("SoundService")
	const soundObjects: { [number]: Sound } = {}
	const sounds = GetSoundTable(moduleInfo)

	ReparentMusicObjects(soundParent)

	table.clear(soundPriorities)
	table.clear(backendPriorities)
	table.clear(soundVolumeOffsets)

	for sfxId, info in sounds do
		const resolved = ResolveAtlasSound(moduleInfo, sfxId)
		soundPriorities[sfxId] = if info.priority ~= nil then info.priority else 64
		backendPriorities[sfxId] = if info.link ~= nil and info.link ~= 0 and info.priority ~= nil then info.priority else NORM_PRIORITY
		soundVolumeOffsets[sfxId] = if info.link ~= nil and info.link ~= 0 and info.volume ~= nil then info.volume else 0

		if resolved ~= nil and resolved.range ~= nil then
			const sound = Instance.new("Sound")
			sound.Name = info.name
			sound.SoundId = assetId
			sound.Volume = 1
			sound.Looped = false
			sound.PlaybackRegionsEnabled = true
			sound.PlaybackRegion = NumberRange.new(resolved.range[1], resolved.range[2])
			sound.PlaybackSpeed = 1
			sound.Parent = soundParent
			soundObjects[sfxId] = sound
		end
	end

	return soundObjects, soundParent
end

const function CreateCallbacks(soundId: number, moduleInfo: SoundModuleInfo, parent: Instance?)
	const soundObjects, soundParent = CreateSoundObjects(soundId, moduleInfo, parent)
	local sfxVolume = snd_SfxVolume
	const idleSounds: { [number]: { Sound } } = {}
	const activeSounds: { [Sound]: boolean } = {}
	const soundSfxIds: { [Sound]: number } = {}

	const function ReleaseSound(sound: Sound)
		if activeSounds[sound] ~= true then
			return
		end

		activeSounds[sound] = nil
		sound.Volume = 0
		sound.Parent = nil

		const sfxId = soundSfxIds[sound]
		local idle = idleSounds[sfxId]

		if idle == nil then
			idle = {}
			idleSounds[sfxId] = idle
		end

		idle[#idle + 1] = sound
	end

	const function AllocateSound(sfxId: number, template: Sound)
		const idle = idleSounds[sfxId]
		local sound: Sound? = nil

		if idle ~= nil then
			const count = #idle

			if count > 0 then
				sound = idle[count]
				idle[count] = nil
			end
		end

		if sound == nil then
			sound = template:Clone()
			soundSfxIds[sound] = sfxId
			sound.Ended:Connect(function()
				ReleaseSound(sound)
			end)
		end

		activeSounds[sound] = true
		return sound
	end

	const function StartSound(_origin: unknown, sfxId: number, volume: number?)
		const template = soundObjects[sfxId]

		if template == nil then
			return nil
		end

		const sound = AllocateSound(sfxId, template)
		const sourceVolume = if typeof(volume) == "number" then volume else sfxVolume
		sound.Volume = sourceVolume / 3
		sound.PlaybackSpeed = 1
		sound.TimePosition = sound.PlaybackRegion.Min
		sound.Parent = soundParent
		
		sound:Play()

		return sound
	end

	const function UpdateSoundParams(handle: Sound?, volume: number)
		if handle ~= nil then
			handle.Volume = volume / 3
		end
	end

	const function StopSound(_origin: unknown, handle: Sound?, sfxId: number)
		const sound = if handle ~= nil then handle else soundObjects[sfxId]

		if sound ~= nil then
			sound.Volume = 0
			sound:Stop()

			if handle ~= nil then
				ReleaseSound(sound)
			end
		end
	end

	const function IsSoundPlaying(handle: Sound?): boolean
		return handle ~= nil and handle.IsPlaying
	end

	const function SetSfxVolume(volume: number)
		sfxVolume = volume

		for _, sound in soundObjects do
			sound.Volume = volume / 3
		end
	end

	const function ChangeMusic(musicId: number, looping: boolean, volume: number)
		const sound = musicObjects[musicId]

		if sound == nil then
			currentMusicObject = nil
			return
		end

		StartMusicObject(sound, looping, volume)
	end

	const function StopMusic(musicId: number)
		local sound = currentMusicObject

		if sound == nil then
			sound = musicObjects[musicId]
		end

		if sound ~= nil then
			sound:Stop()
		end

		currentMusicObject = nil
	end

	const function PauseSound(musicId: number)
		local sound = currentMusicObject

		if sound == nil then
			sound = musicObjects[musicId]
		end

		if sound ~= nil then
			sound:Pause()
		end
	end

	const function ResumeSound(musicId: number)
		local sound = currentMusicObject

		if sound == nil then
			sound = musicObjects[musicId]
		end

		if sound ~= nil then
			sound.Parent = musicParent
			sound:Resume()
		end
	end

	const function SetMusicVolume(volume: number)
		for _, sound in musicObjects do
			SetMusicObjectVolume(sound, volume)
		end
	end

	return {
		startSound = StartSound,
		stopSound = StopSound,
		isSoundPlaying = IsSoundPlaying,
		updateSoundParams = UpdateSoundParams,
		changeMusic = ChangeMusic,
		stopMusic = StopMusic,
		pauseSound = PauseSound,
		resumeSound = ResumeSound,
		setSfxVolume = SetSfxVolume,
		setMusicVolume = SetMusicVolume,
		soundObjects = soundObjects,
		musicObjects = musicObjects,
		parent = soundParent,
		moduleInfo = moduleInfo,
	}
end

const function Reset()
	if currentMusicObject ~= nil then
		currentMusicObject:Stop()
	end

	snd_SfxVolume = 15
	snd_MusicVolume = 15
	mus_paused = false
	mus_playing = Sounds.mus_None
	mus_looping = false
	numChannels = 8
	currentMusicObject = nil
	table.clear(channels)
end

const function PickLevelMusic(): number
	const gamemode = Setup.GetGameMode()
	const episode = Setup.GetCurrentEpisode()
	const map = Setup.GetCurrentMap()

	if gamemode == Definitions.commercial then
		return Sounds.mus_runnin + map - 1
	end

	const spmus = {
		Sounds.mus_e3m4,
		Sounds.mus_e3m2,
		Sounds.mus_e3m3,
		Sounds.mus_e1m5,
		Sounds.mus_e2m7,
		Sounds.mus_e2m4,
		Sounds.mus_e2m6,
		Sounds.mus_e2m5,
		Sounds.mus_e1m9,
	}

	if episode < 4 then
		return Sounds.mus_e1m1 + (episode - 1) * 9 + map - 1
	end

	return spmus[map]
end

const function ClearChannel(index: number)
	channels[index] = {
		origin = nil,
		sfxinfo = Sounds.sfx_None,
		handle = nil,
		priority = 0,
		volume = 0,
		sep = NORM_SEP,
		pitch = NORM_PITCH,
	}
end

const function StopChannel(index: number)
	const channel = channels[index]

	if typeof(channel) ~= "table" or channel.sfxinfo == Sounds.sfx_None then
		ClearChannel(index)
		return
	end

	const stopSound = Host.stopSound

	if stopSound ~= nil then
		stopSound(channel.origin, channel.handle, channel.sfxinfo)
	end

	ClearChannel(index)
end

const function FindChannel(origin: unknown): number
	for index = 1, numChannels do
		const channel = channels[index]

		if typeof(channel) == "table" and channel.origin == origin and channel.sfxinfo ~= Sounds.sfx_None then
			return index
		end
	end

	return 0
end

const function AllocChannel(origin: unknown, priority: number): number
	const originChannel = FindChannel(origin)

	if originChannel ~= 0 then
		StopChannel(originChannel)
		return originChannel
	end

	for index = 1, numChannels do
		const channel = channels[index]

		if typeof(channel) ~= "table" or channel.sfxinfo == Sounds.sfx_None then
			return index
		end
	end

	for index = 1, numChannels do
		const channel = channels[index]

		if typeof(channel) == "table" and channel.priority >= priority then
			StopChannel(index)
			return index
		end
	end

	return 0
end

const function SetSfxVolume(volume: number)
	snd_SfxVolume = volume

	const callback = Host.setSfxVolume

	if callback ~= nil then
		callback(volume)
	end
end

const function SetMusicVolume(volume: number)
	snd_MusicVolume = volume

	const callback = Host.setMusicVolume

	if callback ~= nil then
		callback(volume)
	end
end

const function Init(sfxVolume: number, musicVolume: number)
	SetSfxVolume(sfxVolume)
	SetMusicVolume(musicVolume)
	mus_paused = false
	mus_playing = Sounds.mus_None

	for index = 1, numChannels do
		ClearChannel(index)
	end
end

const function StopMusic()
	if mus_playing == Sounds.mus_None then
		mus_paused = false
		return
	end

	const callback = Host.stopMusic

	if callback ~= nil then
		callback(mus_playing)
	end

	mus_playing = Sounds.mus_None
	mus_paused = false
	mus_looping = false
end

const function ChangeMusic(musicId: number, looping: boolean?)
	if mus_playing == musicId then
		return
	end

	StopMusic()
	mus_playing = musicId
	mus_paused = false
	mus_looping = looping == true

	const callback = Host.changeMusic

	if callback ~= nil then
		callback(musicId, looping == true, snd_MusicVolume)
	end
end

const function StartMusic(musicId: number)
	ChangeMusic(musicId, false)
end

const function PauseSound()
	if mus_paused or mus_playing == Sounds.mus_None then
		return
	end

	mus_paused = true

	const callback = Host.pauseSound

	if callback ~= nil then
		callback(mus_playing)
	end
end

const function ResumeSound()
	if not mus_paused or mus_playing == Sounds.mus_None then
		return
	end

	mus_paused = false

	const callback = Host.resumeSound

	if callback ~= nil then
		callback(mus_playing)
	end
end

const function Start()
	for index = 1, numChannels do
		StopChannel(index)
	end

	mus_paused = false
	ChangeMusic(PickLevelMusic(), true)
end

const function GetSoundParams(sfxId: number, volume: number): (boolean, number, number)
	const volumeOffset = soundVolumeOffsets[sfxId] or 0

	if volumeOffset ~= 0 then
		volume += volumeOffset

		if volume < 1 then
			return false, volume, NORM_PITCH
		end

		if volume > snd_SfxVolume then
			volume = snd_SfxVolume
		end
	end

	return true, volume, NORM_PITCH
end

const function AdjustSoundParams(listener: SoundPosition, source: SoundPosition, volume: number, pitch: number): (boolean, number, number, number)
	local adx = listener.x - source.x
	local ady = listener.y - source.y

	if adx < 0 then
		adx = -adx
	end

	if ady < 0 then
		ady = -ady
	end

	const minDelta = if adx < ady then adx else ady
	local approxDist = adx + ady - minDelta // 2

	if Setup.GetCurrentMap() ~= 8 and approxDist > SoundClippingDistance then
		return false, volume, NORM_SEP, pitch
	end

	local angle = Geometry.PointToAngle2(listener.x, listener.y, source.x, source.y)

	if angle > listener.angle then
		angle -= listener.angle
	else
		angle += 0xFFFFFFFF - listener.angle
	end

	const fineAngle = bit32.rshift(bit32.band(angle, 0xFFFFFFFF), Tables.ANGLETOFINESHIFT)
	const sep = NORM_SEP - bit32.arshift(Fixed.FixedMul(SoundStereoSwing, Tables.finesine[fineAngle]), Fixed.FRACBITS)

	if approxDist < SoundCloseDistance then
		volume = snd_SfxVolume
	elseif Setup.GetCurrentMap() == 8 then
		if approxDist > SoundClippingDistance then
			approxDist = SoundClippingDistance
		end

		volume = 15 + (snd_SfxVolume - 15) * bit32.rshift(SoundClippingDistance - approxDist, Fixed.FRACBITS) // SoundAttenuator
	else
		volume = snd_SfxVolume * bit32.rshift(SoundClippingDistance - approxDist, Fixed.FRACBITS) // SoundAttenuator
	end

	return volume > 0, volume, sep, pitch
end

const function StartSoundAtVolume(origin: unknown, sfxId: number, volume: number)
	if origin == false then
		origin = nil
	end

	if typeof(sfxId) ~= "number" or sfxId < 0 or sfxId > Sounds.sfx_radio then
		--error(`StartSoundAtVolume: bad sfx id {sfxId}`)
		return -- No Id for now
	end

	if sfxId == Sounds.sfx_None or volume < 1 then
		return
	end

	local audible, adjustedVolume, pitch = GetSoundParams(sfxId, volume)

	if not audible then
		return
	end

	local sep = NORM_SEP
	const player = Setup.GetPlayers()[0]
	const playerMo = if player ~= nil then player.mo else nil

	if typeof(origin) == "table" and playerMo ~= nil and origin ~= playerMo then
		audible, adjustedVolume, sep, pitch = AdjustSoundParams(playerMo, origin, adjustedVolume, pitch)

		if origin.x == playerMo.x and origin.y == playerMo.y then
			sep = NORM_SEP
		end

		if not audible then
			return
		end
	end

	const priority = soundPriorities[sfxId] or 64
	const channelIndex = AllocChannel(origin, priority)

	if channelIndex == 0 then
		return
	end

	local handle: unknown? = nil
	const callback = Host.startSound

	if callback ~= nil then
		handle = callback(origin, sfxId, adjustedVolume, sep, pitch, backendPriorities[sfxId] or NORM_PRIORITY)
	end

	if handle == nil then
		return
	end

	channels[channelIndex] = {
		origin = origin,
		sfxinfo = sfxId,
		handle = handle,
		priority = priority,
		volume = adjustedVolume,
		sep = sep,
		pitch = pitch,
	}
end

const function StartSound(origin: unknown, sfxId: number)
	StartSoundAtVolume(origin, sfxId, snd_SfxVolume)
end

const function StopSound(origin: unknown)
	if origin == false then
		origin = nil
	end

	const channelIndex = FindChannel(origin)

	if channelIndex ~= 0 then
		StopChannel(channelIndex)
	end
end

const function UpdateSounds(listener: unknown)
	const isSoundPlaying = Host.isSoundPlaying
	const updateSoundParams = Host.updateSoundParams

	for index = 1, numChannels do
		const channel = channels[index]

		if typeof(channel) == "table" and channel.sfxinfo ~= Sounds.sfx_None then
			if isSoundPlaying ~= nil and not isSoundPlaying(channel.handle) then
				StopChannel(index)
			else
				local audible, volume, pitch = GetSoundParams(channel.sfxinfo, snd_SfxVolume)
				local sep = NORM_SEP

				if not audible then
					StopChannel(index)
				else
					if listener ~= nil and typeof(channel.origin) == "table" and listener ~= channel.origin then
						audible, volume, sep, pitch = AdjustSoundParams(listener, channel.origin, volume, pitch)

						if not audible then
							StopChannel(index)
						elseif updateSoundParams ~= nil then
							updateSoundParams(channel.handle, volume, sep, pitch)
							channel.volume = volume
							channel.sep = sep
							channel.pitch = pitch
						end
					end
				end
			end
		end
	end

	const callback = Host.updateSounds

	if callback ~= nil then
		callback(listener, channels, mus_playing, mus_paused)
	end
end

const function GetSfxVolume(): number
	return snd_SfxVolume
end

const function GetMusicVolume(): number
	return snd_MusicVolume
end

const function GetCurrentMusic(): number
	return mus_playing
end

const function IsMusicPaused(): boolean
	return mus_paused
end

return {
	Reset = Reset,
	GetSfxVolume = GetSfxVolume,
	GetMusicVolume = GetMusicVolume,
	GetCurrentMusic = GetCurrentMusic,
	IsMusicPaused = IsMusicPaused,
	Init = Init,
	Start = Start,
	StartSound = StartSound,
	StartSoundAtVolume = StartSoundAtVolume,
	StopSound = StopSound,
	StartMusic = StartMusic,
	ChangeMusic = ChangeMusic,
	StopMusic = StopMusic,
	PauseSound = PauseSound,
	ResumeSound = ResumeSound,
	UpdateSounds = UpdateSounds,
	SetMusicVolume = SetMusicVolume,
	SetSfxVolume = SetSfxVolume,
	CreateSoundObjects = CreateSoundObjects,
	CreateCallbacks = CreateCallbacks,
	AddOST = AddOST,
}
