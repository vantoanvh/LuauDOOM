--!native
--!optimize 2

-- Port of doomdef.c, doomdef.h
-- basic defines for DOOM, e.g. Version, game mode
-- and skill level, and display parameters.

return {
	-- Global parameters/defines.

	-- DOOM version
	VERSION = 110,
	DEMO_VERSION = 109,
	DOOM_191_VERSION = 111,

	-- Game mode handling - identify IWAD version
	-- to handle IWAD dependend animations etc.
	shareware = 0,
	registered = 1,
	commercial = 2,
	retail = 3,
	indetermined = 4,

	-- Mission packs - might be useful for TC stuff?
	doom = 0,
	doom2 = 1,
	pack_tnt = 2,
	pack_plut = 3,
	none = 4,

	-- Identify language to use, software localization.
	english = 0,
	french = 1,
	german = 2,
	unknown = 3,

	-- Do or do not use external soundserver.
	-- The sndserver binary to be run separately
	-- has been introduced by Dave Taylor.
	SNDSERV = 1,

	-- For resize of screen, at start of game.
	-- It will not work dynamically, see visplanes.
	BASE_WIDTH = 320,
	BASE_HEIGHT = 200,

	-- It is educational but futile to change this
	-- scaling e.g. to 2. Drawing of status bar,
	-- menues etc. is tied to the scale implied
	-- by the graphics.
	SCREEN_MUL = 1,
	INV_ASPECT_RATIO = 0.625,
	-- Legacy compatibility dimensions during the native-resolution migration.
	-- Do not treat these as the runtime framebuffer size.
	SCREENWIDTH = 320,
	SCREENHEIGHT = 200,

	-- DOOM keyboard definition.
	-- This is the stuff configured by Setup.Exe.
	-- Most key data are simple ascii (uppercased).
	KEY_RIGHTARROW = 0xAE,
	KEY_LEFTARROW = 0xAC,
	KEY_UPARROW = 0xAD,
	KEY_DOWNARROW = 0xAF,
	KEY_ESCAPE = 27,
	KEY_ENTER = 13,
	KEY_TAB = 9,
	KEY_F1 = 0xBB,
	KEY_F2 = 0xBC,
	KEY_F3 = 0xBD,
	KEY_F4 = 0xBE,
	KEY_F5 = 0xBF,
	KEY_F6 = 0xC0,
	KEY_F7 = 0xC1,
	KEY_F8 = 0xC2,
	KEY_F9 = 0xC3,
	KEY_F10 = 0xC4,
	KEY_F11 = 0xD7,
	KEY_F12 = 0xD8,
	KEY_BACKSPACE = 127,
	KEY_PAUSE = 0xFF,
	KEY_EQUALS = 0x3D,
	KEY_MINUS = 0x2D,
	KEY_RSHIFT = 0xB6,
	KEY_RCTRL = 0x9D,
	KEY_RALT = 0xB8,
	KEY_LALT = 0xB8,

	-- State updates, number of tics / second.
	TICRATE = 35,

	-- If rangecheck is undefined,
	-- most parameter validation debugging code will not be compiled
	RANGECHECK = true,

	-- The original engine's fixed player capacity.
	MAXPLAYERS = 4,

	-- The current state of the game: whether we are
	-- playing, gazing at the intermission screen,
	-- the game final animation, or a demo.
	LEVEL = 0,
	INTERMISSION = 1,
	FINALE = 2,
	DEMOSCREEN = 3,

	-- Difficulty/skill settings/filters.

	-- Skill flags.
	MTF_EASY = 1,
	MTF_NORMAL = 2,
	MTF_HARD = 4,

	-- Deaf monsters/do not react to sound.
	MTF_AMBUSH = 8,

	sk_baby = 0,
	sk_easy = 1,
	sk_medium = 2,
	sk_hard = 3,
	sk_nightmare = 4,

	-- Key cards.
	it_bluecard = 0,
	it_yellowcard = 1,
	it_redcard = 2,
	it_blueskull = 3,
	it_yellowskull = 4,
	it_redskull = 5,

	NUMCARDS = 6,

	-- The defined weapons,
	-- including a marker indicating
	-- user has not changed weapon.
	wp_fist = 0,
	wp_pistol = 1,
	wp_shotgun = 2,
	wp_chaingun = 3,
	wp_missile = 4,
	wp_plasma = 5,
	wp_bfg = 6,
	wp_chainsaw = 7,
	wp_supershotgun = 8,

	NUMWEAPONS = 9,

	-- No pending weapon change.
	wp_nochange = 10,

	-- Ammunition types defined.
	am_clip = 0,
	am_shell = 1,
	am_cell = 2,
	am_misl = 3,

	NUMAMMO = 4,

	-- Unlimited for chainsaw / fist.
	am_noammo = 5,

	-- Power up artifacts.
	pw_invulnerability = 0,
	pw_strength = 1,
	pw_invisibility = 2,
	pw_ironfeet = 3,
	pw_allmap = 4,
	pw_infrared = 5,
	
	NUMPOWERS = 6,

	-- Power up durations,
	-- how many seconds till expiration,
	-- assuming TICRATE is 35 ticks/second.
	INVULNTICS = 1050,
	INVISTICS = 2100,
	INFRATICS = 4200,
	IRONTICS = 2100,
}
