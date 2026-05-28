--!native
--!optimize 2

-- Port of d_englsh.h
-- Printed strings for translation.
-- English language support (default).

return {
	-- D_Main.C
	DEVSTR = "Development mode ON.\n",
	CDROM = "CD-ROM Version: default.cfg from c:\\doomdata\n",

	--	M_Menu.C
	PRESSKEY = "press a key.",
	PRESSYN = "press y or n.",

	QUITMSG = "are you sure you want to\nquit this great game?",
	LOADNET = "you can't do load while in a net game!\n\npress a key.",
	QLOADNET = "you can't quickload during a netgame!\n\npress a key.",
	QSAVESPOT = "you haven't picked a quicksave slot yet!\n\npress a key.",
	SAVEDEAD = "you can't save if you aren't playing!\n\npress a key.",
	QSPROMPT = "quicksave over your game named\n\n'%s'?\n\npress y or n.",
	QLPROMPT = "do you want to quickload the game named\n\n'%s'?\n\npress y or n.",
	NEWGAME = "you can't start a new game\nwhile in a network game.\n\npress a key.",
	
	NIGHTMARE = "are you sure? this skill level\nisn't even remotely fair.\n\npress y or n.",
	SWSTRING = "this is the shareware version of doom.\n\nyou need to order the entire trilogy.\n\npress a key.",

	MSGOFF = "Messages OFF",
	MSGON = "Messages ON",

	NETEND = "you can't end a netgame!\n\npress a key.",
	ENDGAME = "are you sure you want to end the game?\n\npress y or n.",

	DOSY = "(press y to quit)",

	DETAILHI = "High detail",
	DETAILLO = "Low detail",

	GAMMALVL0 = "Gamma correction OFF",
	GAMMALVL1 = "Gamma correction level 1",
	GAMMALVL2 = "Gamma correction level 2",
	GAMMALVL3 = "Gamma correction level 3",
	GAMMALVL4 = "Gamma correction level 4",

	EMPTYSTRING = "empty slot",

	--	Interaction.C
	GOTARMOR = "Picked up the armor.",
	GOTMEGA = "Picked up the MegaArmor!",
	GOTHTHBONUS = "Picked up a health bonus.",
	GOTARMBONUS = "Picked up an armor bonus.",
	GOTSTIM = "Picked up a stimpack.",
	GOTMEDINEED = "Picked up a medikit that you REALLY need!",
	GOTMEDIKIT = "Picked up a medikit.",
	GOTSUPER = "Supercharge!",
	GOTBLUECARD = "Picked up a blue keycard.",
	GOTYELWCARD = "Picked up a yellow keycard.",
	GOTREDCARD = "Picked up a red keycard.",
	GOTBLUESKUL = "Picked up a blue skull key.",
	GOTYELWSKUL = "Picked up a yellow skull key.",
	GOTREDSKULL = "Picked up a red skull key.",
	GOTINVUL = "Invulnerability!",
	GOTBERSERK = "Berserk!",
	GOTINVIS = "Partial Invisibility",
	GOTSUIT = "Radiation Shielding Suit",
	GOTMAP = "Computer Area Map",
	GOTVISOR = "Light Amplification Visor",
	GOTMSPHERE = "MegaSphere!",
	GOTCLIP = "Picked up a clip.",
	GOTCLIPBOX = "Picked up a box of bullets.",
	GOTROCKET = "Picked up a rocket.",
	GOTROCKBOX = "Picked up a box of rockets.",
	GOTCELL = "Picked up an energy cell.",
	GOTCELLBOX = "Picked up an energy cell pack.",
	GOTSHELLS = "Picked up 4 shotgun shells.",
	GOTSHELLBOX = "Picked up a box of shotgun shells.",
	GOTBACKPACK = "Picked up a backpack full of ammo!",
	GOTBFG9000 = "You got the BFG9000!  Oh, yes.",
	GOTCHAINGUN = "You got the chaingun!",
	GOTCHAINSAW = "A chainsaw!  Find some meat!",
	GOTLAUNCHER = "You got the rocket launcher!",
	GOTPLASMA = "You got the plasma gun!",
	GOTSHOTGUN = "You got the shotgun!",
	GOTSHOTGUN2 = "You got the super shotgun!",

	-- Doors.C
	BLUEO = "You need a blue key to activate this object",
	REDO = "You need a red key to activate this object",
	YELLOWO = "You need a yellow key to activate this object",
	BLUEK = "You need a blue key to open this door",
	REDK = "You need a red key to open this door",
	YELLOWK = "You need a yellow key to open this door",

	--	G_game.C
	GGSAVED = "game saved.",

	--	HU_stuff.C
	HUSTR_MSGU = "[Message unsent]",
	HUSTR_E1M1 = "E1M1: Hangar",
	HUSTR_E1M2 = "E1M2: Nuclear Plant",
	HUSTR_E1M3 = "E1M3: Toxin Refinery",
	HUSTR_E1M4 = "E1M4: Command Control",
	HUSTR_E1M5 = "E1M5: Phobos Lab",
	HUSTR_E1M6 = "E1M6: Central Processing",
	HUSTR_E1M7 = "E1M7: Computer Station",
	HUSTR_E1M8 = "E1M8: Phobos Anomaly",
	HUSTR_E1M9 = "E1M9: Military Base",
	HUSTR_E2M1 = "E2M1: Deimos Anomaly",
	HUSTR_E2M2 = "E2M2: Containment Area",
	HUSTR_E2M3 = "E2M3: Refinery",
	HUSTR_E2M4 = "E2M4: Deimos Lab",
	HUSTR_E2M5 = "E2M5: Command Center",
	HUSTR_E2M6 = "E2M6: Halls of the Damned",
	HUSTR_E2M7 = "E2M7: Spawning Vats",
	HUSTR_E2M8 = "E2M8: Tower of Babel",
	HUSTR_E2M9 = "E2M9: Fortress of Mystery",
	HUSTR_E3M1 = "E3M1: Hell Keep",
	HUSTR_E3M2 = "E3M2: Slough of Despair",
	HUSTR_E3M3 = "E3M3: Pandemonium",
	HUSTR_E3M4 = "E3M4: House of Pain",
	HUSTR_E3M5 = "E3M5: Unholy Cathedral",
	HUSTR_E3M6 = "E3M6: Mt. Erebus",
	HUSTR_E3M7 = "E3M7: Limbo",
	HUSTR_E3M8 = "E3M8: Dis",
	HUSTR_E3M9 = "E3M9: Warrens",
	HUSTR_E4M1 = "E4M1: Hell Beneath",
	HUSTR_E4M2 = "E4M2: Perfect Hatred",
	HUSTR_E4M3 = "E4M3: Sever The Wicked",
	HUSTR_E4M4 = "E4M4: Unruly Evil",
	HUSTR_E4M5 = "E4M5: They Will Repent",
	HUSTR_E4M6 = "E4M6: Against Thee Wickedly",
	HUSTR_E4M7 = "E4M7: And Hell Followed",
	HUSTR_E4M8 = "E4M8: Unto The Cruel",
	HUSTR_E4M9 = "E4M9: Fear",

	HUSTR_1 = "level 1: entryway",
	HUSTR_2 = "level 2: underhalls",
	HUSTR_3 = "level 3: the gantlet",
	HUSTR_4 = "level 4: the focus",
	HUSTR_5 = "level 5: the waste tunnels",
	HUSTR_6 = "level 6: the crusher",
	HUSTR_7 = "level 7: dead simple",
	HUSTR_8 = "level 8: tricks and traps",
	HUSTR_9 = "level 9: the pit",
	HUSTR_10 = "level 10: refueling base",
	HUSTR_11 = "level 11: 'o' of destruction!",
	HUSTR_12 = "level 12: the factory",
	HUSTR_13 = "level 13: downtown",
	HUSTR_14 = "level 14: the inmost dens",
	HUSTR_15 = "level 15: industrial zone",
	HUSTR_16 = "level 16: suburbs",
	HUSTR_17 = "level 17: tenements",
	HUSTR_18 = "level 18: the courtyard",
	HUSTR_19 = "level 19: the citadel",
	HUSTR_20 = "level 20: gotcha!",
	HUSTR_21 = "level 21: nirvana",
	HUSTR_22 = "level 22: the catacombs",
	HUSTR_23 = "level 23: barrels o' fun",
	HUSTR_24 = "level 24: the chasm",
	HUSTR_25 = "level 25: bloodfalls",
	HUSTR_26 = "level 26: the abandoned mines",
	HUSTR_27 = "level 27: monster condo",
	HUSTR_28 = "level 28: the spirit world",
	HUSTR_29 = "level 29: the living end",
	HUSTR_30 = "level 30: icon of sin",
	HUSTR_31 = "level 31: wolfenstein",
	HUSTR_32 = "level 32: grosse",

	PHUSTR_1 = "level 1: congo",
	PHUSTR_2 = "level 2: well of souls",
	PHUSTR_3 = "level 3: aztec",
	PHUSTR_4 = "level 4: caged",
	PHUSTR_5 = "level 5: ghost town",
	PHUSTR_6 = "level 6: baron's lair",
	PHUSTR_7 = "level 7: caughtyard",
	PHUSTR_8 = "level 8: realm",
	PHUSTR_9 = "level 9: abattoire",
	PHUSTR_10 = "level 10: onslaught",
	PHUSTR_11 = "level 11: hunted",
	PHUSTR_12 = "level 12: speed",
	PHUSTR_13 = "level 13: the crypt",
	PHUSTR_14 = "level 14: genesis",
	PHUSTR_15 = "level 15: the twilight",
	PHUSTR_16 = "level 16: the omen",
	PHUSTR_17 = "level 17: compound",
	PHUSTR_18 = "level 18: neurosphere",
	PHUSTR_19 = "level 19: nme",
	PHUSTR_20 = "level 20: the death domain",
	PHUSTR_21 = "level 21: slayer",
	PHUSTR_22 = "level 22: impossible mission",
	PHUSTR_23 = "level 23: tombstone",
	PHUSTR_24 = "level 24: the final frontier",
	PHUSTR_25 = "level 25: the temple of darkness",
	PHUSTR_26 = "level 26: bunker",
	PHUSTR_27 = "level 27: anti-christ",
	PHUSTR_28 = "level 28: the sewers",
	PHUSTR_29 = "level 29: odyssey of noises",
	PHUSTR_30 = "level 30: the gateway of hell",
	PHUSTR_31 = "level 31: cyberden",
	PHUSTR_32 = "level 32: go 2 it",

	THUSTR_1 = "level 1: system control",
	THUSTR_2 = "level 2: human bbq",
	THUSTR_3 = "level 3: power control",
	THUSTR_4 = "level 4: wormhole",
	THUSTR_5 = "level 5: hanger",
	THUSTR_6 = "level 6: open season",
	THUSTR_7 = "level 7: prison",
	THUSTR_8 = "level 8: metal",
	THUSTR_9 = "level 9: stronghold",
	THUSTR_10 = "level 10: redemption",
	THUSTR_11 = "level 11: storage facility",
	THUSTR_12 = "level 12: crater",
	THUSTR_13 = "level 13: nukage processing",
	THUSTR_14 = "level 14: steel works",
	THUSTR_15 = "level 15: dead zone",
	THUSTR_16 = "level 16: deepest reaches",
	THUSTR_17 = "level 17: processing area",
	THUSTR_18 = "level 18: mill",
	THUSTR_19 = "level 19: shipping/respawning",
	THUSTR_20 = "level 20: central processing",
	THUSTR_21 = "level 21: administration center",
	THUSTR_22 = "level 22: habitat",
	THUSTR_23 = "level 23: lunar mining project",
	THUSTR_24 = "level 24: quarry",
	THUSTR_25 = "level 25: baron's den",
	THUSTR_26 = "level 26: ballistyx",
	THUSTR_27 = "level 27: mount pain",
	THUSTR_28 = "level 28: heck",
	THUSTR_29 = "level 29: river styx",
	THUSTR_30 = "level 30: last call",
	THUSTR_31 = "level 31: pharaoh",
	THUSTR_32 = "level 32: caribbean",

	HUSTR_CHATMACRO1 = "I'm ready to kick butt!",
	HUSTR_CHATMACRO2 = "I'm OK.",
	HUSTR_CHATMACRO3 = "I'm not looking too good!",
	HUSTR_CHATMACRO4 = "Help!",
	HUSTR_CHATMACRO5 = "You suck!",
	HUSTR_CHATMACRO6 = "Next time, scumbag...",
	HUSTR_CHATMACRO7 = "Come here!",
	HUSTR_CHATMACRO8 = "I'll take care of it.",
	HUSTR_CHATMACRO9 = "Yes",
	HUSTR_CHATMACRO0 = "No",
	HUSTR_TALKTOSELF1 = "You mumble to yourself",
	HUSTR_TALKTOSELF2 = "Who's there?",
	HUSTR_TALKTOSELF3 = "You scare yourself",
	HUSTR_TALKTOSELF4 = "You start to rave",
	HUSTR_TALKTOSELF5 = "You've lost it...",
	HUSTR_MESSAGESENT = "[Message Sent]",
	HUSTR_PLRGREEN = "Green: ",
	HUSTR_PLRINDIGO = "Indigo: ",
	HUSTR_PLRBROWN = "Brown: ",
	HUSTR_PLRRED = "Red: ",

	-- The following should NOT be changed unless it seems
	-- just AWFULLY necessary
	HUSTR_KEYGREEN = 103,
	HUSTR_KEYINDIGO = 105,
	HUSTR_KEYBROWN = 98,
	HUSTR_KEYRED = 114,

	--	Automap text
	AMSTR_FOLLOWON = "Follow Mode ON",
	AMSTR_FOLLOWOFF = "Follow Mode OFF",
	AMSTR_GRIDON = "Grid ON",
	AMSTR_GRIDOFF = "Grid OFF",
	AMSTR_MARKEDSPOT = "Marked Spot",
	AMSTR_MARKSCLEARED = "All Marks Cleared",

	--	Status.C
	STSTR_MUS = "Music Change",
	STSTR_NOMUS = "IMPOSSIBLE SELECTION",
	STSTR_DQDON = "Degreelessness Mode On",
	STSTR_DQDOFF = "Degreelessness Mode Off",
	STSTR_KFAADDED = "Very Happy Ammo Added",
	STSTR_FAADDED = "Ammo (no keys) Added",
	STSTR_NCON = "No Clipping Mode ON",
	STSTR_NCOFF = "No Clipping Mode OFF",
	STSTR_BEHOLD = "inVuln, Str, Inviso, Rad, Allmap, or Lite-amp",
	STSTR_BEHOLDX = "Power-up Toggled",
	STSTR_CHOPPERS = "... doesn't suck - GM",
	STSTR_CLEV = "Changing Level...",

	--	F_Finale.C
	E1TEXT = [[
Once you beat the big badasses and
clean out the moon base you're supposed
to win, aren't you? Aren't you? Where's
your fat reward and ticket home? What
the hell is this? It's not supposed to
end this way!

It stinks like rotten meat, but looks
like the lost Deimos base.  Looks like
you're stuck on The Shores of Hell.
The only way out is through.

To continue the DOOM experience, play
The Shores of Hell and its amazing
sequel, Inferno!]],

	E2TEXT = [[
You've done it! The hideous cyber-
demon lord that ruled the lost Deimos
moon base has been slain and you
are triumphant! But ... where are
you? You clamber to the edge of the
moon and look down to see the awful
truth.

Deimos floats above Hell itself!
You've never heard of anyone escaping
from Hell, but you'll make the bastards
sorry they ever heard of you! Quickly,
you rappel down to  the surface of
Hell.

Now, it's on to the final chapter of
DOOM! -- Inferno.]],

	E3TEXT = [[
The loathsome spiderdemon that
masterminded the invasion of the moon
bases and caused so much death has had
its ass kicked for all time.

A hidden doorway opens and you enter.
You've proven too tough for Hell to
contain, and now Hell at last plays
fair -- for you emerge from the door
to see the green fields of Earth!
Home at last.

You wonder what's been happening on
Earth while you were battling evil
unleashed. It's good that no Hell-
spawn could have come through that
door with you ...]],

	E4TEXT = [[
the spider mastermind must have sent forth
its legions of hellspawn before your
final confrontation with that terrible
beast from hell.  but you stepped forward
and brought forth eternal damnation and
suffering upon the horde as a true hero
would in the face of something so evil.

besides, someone was gonna pay for what
happened to daisy, your pet rabbit.

but now, you see spread before you more
potential pain and gibbitude as a nation
of demons run amok among our cities.

next stop, hell on earth!]],

	-- after level 6, put this:
	C1TEXT = [[
YOU HAVE ENTERED DEEPLY INTO THE INFESTED
STARPORT. BUT SOMETHING IS WRONG. THE
MONSTERS HAVE BROUGHT THEIR OWN REALITY
WITH THEM, AND THE STARPORT'S TECHNOLOGY
IS BEING SUBVERTED BY THEIR PRESENCE.

AHEAD, YOU SEE AN OUTPOST OF HELL, A
FORTIFIED ZONE. IF YOU CAN GET PAST IT,
YOU CAN PENETRATE INTO THE HAUNTED HEART
OF THE STARBASE AND FIND THE CONTROLLING
SWITCH WHICH HOLDS EARTH'S POPULATION
HOSTAGE.]],

	-- After level 11, put this:
	C2TEXT = [[
YOU HAVE WON! YOUR VICTORY HAS ENABLED
HUMANKIND TO EVACUATE EARTH AND ESCAPE
THE NIGHTMARE.  NOW YOU ARE THE ONLY
HUMAN LEFT ON THE FACE OF THE PLANET.
CANNIBAL MUTATIONS, CARNIVOROUS ALIENS,
AND EVIL SPIRITS ARE YOUR ONLY NEIGHBORS.
YOU SIT BACK AND WAIT FOR DEATH, CONTENT
THAT YOU HAVE SAVED YOUR SPECIES.

BUT THEN, EARTH CONTROL BEAMS DOWN A
MESSAGE FROM SPACE: "SENSORS HAVE LOCATED
THE SOURCE OF THE ALIEN INVASION. IF YOU
GO THERE, YOU MAY BE ABLE TO BLOCK THEIR
ENTRY.  THE ALIEN BASE IS IN THE HEART OF
YOUR OWN HOME CITY, NOT FAR FROM THE
STARPORT." SLOWLY AND PAINFULLY YOU GET
UP AND RETURN TO THE FRAY.]],

	-- After level 20, put this:
	C3TEXT = [[
YOU ARE AT THE CORRUPT HEART OF THE CITY,
SURROUNDED BY THE CORPSES OF YOUR ENEMIES.
YOU SEE NO WAY TO DESTROY THE CREATURES'
ENTRYWAY ON THIS SIDE, SO YOU CLENCH YOUR
TEETH AND PLUNGE THROUGH IT.

THERE MUST BE A WAY TO CLOSE IT ON THE
OTHER SIDE. WHAT DO YOU CARE IF YOU'VE
GOT TO GO THROUGH HELL TO GET TO IT?]],

	-- After level 29, put this:
	C4TEXT = [[
THE HORRENDOUS VISAGE OF THE BIGGEST
DEMON YOU'VE EVER SEEN CRUMBLES BEFORE
YOU, AFTER YOU PUMP YOUR ROCKETS INTO
HIS EXPOSED BRAIN. THE MONSTER SHRIVELS
UP AND DIES, ITS THRASHING LIMBS
DEVASTATING UNTOLD MILES OF HELL'S
SURFACE.

YOU'VE DONE IT. THE INVASION IS OVER.
EARTH IS SAVED. HELL IS A WRECK. YOU
WONDER WHERE BAD FOLKS WILL GO WHEN THEY
DIE, NOW. WIPING THE SWEAT FROM YOUR
FOREHEAD YOU BEGIN THE LONG TREK BACK
HOME. REBUILDING EARTH OUGHT TO BE A
LOT MORE FUN THAN RUINING IT WAS.
]],

	-- Before level 31, put this:
	C5TEXT = [[
CONGRATULATIONS, YOU'VE FOUND THE SECRET
LEVEL! LOOKS LIKE IT'S BEEN BUILT BY
HUMANS, RATHER THAN DEMONS. YOU WONDER
WHO THE INMATES OF THIS CORNER OF HELL
WILL BE.]],

	-- Before level 32, put this:
	C6TEXT = [[
CONGRATULATIONS, YOU'VE FOUND THE
SUPER SECRET LEVEL!  YOU'D BETTER
BLAZE THROUGH THIS ONE!
]],

	-- after map 06
	P1TEXT = [[
You gloat over the steaming carcass of the
Guardian.  With its death, you've wrested
the Accelerator from the stinking claws
of Hell.  You relax and glance around the
room.  Damn!  There was supposed to be at
least one working prototype, but you can't
see it. The demons must have taken it.

You must find the prototype, or all your
struggles will have been wasted. Keep
moving, keep fighting, keep killing.
Oh yes, keep living, too.]],

	-- after map 11
	P2TEXT = [[
Even the deadly Arch-Vile labyrinth could
not stop you, and you've gotten to the
prototype Accelerator which is soon
efficiently and permanently deactivated.

You're good at that kind of thing.]],

	-- after map 20
	P3TEXT = [[
You've bashed and battered your way into
the heart of the devil-hive.  Time for a
Search-and-Destroy mission, aimed at the
Gatekeeper, whose foul offspring is
cascading to Earth.  Yeah, he's bad. But
you know who's worse!

Grinning evilly, you check your gear, and
get ready to give the bastard a little Hell
of your own making!]],

	-- after map 30
	P4TEXT = [[
The Gatekeeper's evil face is splattered
all over the place.  As its tattered corpse
collapses, an inverted Gate forms and
sucks down the shards of the last
prototype Accelerator, not to mention the
few remaining demons.  You're done. Hell
has gone back to pounding bad dead folks 
instead of good live ones.  Remember to
tell your grandkids to put a rocket
launcher in your coffin. If you go to Hell
when you die, you'll need it for some
final cleaning-up ...]],

	-- before map 31
	P5TEXT = [[
You've found the second-hardest level we
got. Hope you have a saved game a level or
two previous.  If not, be prepared to die
aplenty. For master marines only.]],

	-- before map 32
	P6TEXT = [[
Betcha wondered just what WAS the hardest
level we had ready for ya?  Now you know.
No one gets out alive.]],

	T1TEXT = [[
You've fought your way out of the infested
experimental labs.   It seems that UAC has
once again gulped it down.  With their
high turnover, it must be hard for poor
old UAC to buy corporate health insurance
nowadays..

Ahead lies the military complex, now
swarming with diseased horrors hot to get
their teeth into you. With luck, the
complex still has some warlike ordnance
laying around.]],

	T2TEXT = [[
You hear the grinding of heavy machinery
ahead.  You sure hope they're not stamping
out new hellspawn, but you're ready to
ream out a whole herd if you have to.
They might be planning a blood feast, but
you feel about as mean as two thousand
maniacs packed into one mad killer.

You don't plan to go down easy.]],

	T3TEXT = [[
The vista opening ahead looks real damn
familiar. Smells familiar, too -- like
fried excrement. You didn't like this
place before, and you sure as hell ain't
planning to like it now. The more you
brood on it, the madder you get.
Hefting your gun, an evil grin trickles
onto your face. Time to take some names.]],

	T4TEXT = [[
Suddenly, all is silent, from one horizon
to the other. The agonizing echo of Hell
fades away, the nightmare sky turns to
blue, the heaps of monster corpses start 
to evaporate along with the evil stench 
that filled the air. Jeeze, maybe you've
done it. Have you really won?

Something rumbles in the distance.
A blue light begins to glow inside the
ruined skull of the demon-spitter.]],

	T5TEXT = [[
What now? Looks totally different. Kind
of like King Tut's condo. Well,
whatever's here can't be any worse
than usual. Can it?  Or maybe it's best
to let sleeping gods lie..]],

	T6TEXT = [[
Time for a vacation. You've burst the
bowels of hell and by golly you're ready
for a break. You mutter to yourself,
Maybe someone else can kick Hell's ass
next time around. Ahead lies a quiet town,
with peaceful flowing water, quaint
buildings, and presumably no Hellspawn.

As you step off the transport, you hear
the stomp of a cyberdemon's iron shoe.]],

	-- Character cast strings FINALE.C
	ZOMBIE = "ZOMBIEMAN",
	SHOTGUN = "SHOTGUN GUY",
	HEAVY = "HEAVY WEAPON DUDE",
	IMP = "IMP",
	DEMON = "DEMON",
	LOST = "LOST SOUL",
	CACO = "CACODEMON",
	HELL = "HELL KNIGHT",
	BARON = "BARON OF HELL",
	ARACH = "ARACHNOTRON",
	PAIN = "PAIN ELEMENTAL",
	REVEN = "REVENANT",
	MANCU = "MANCUBUS",
	ARCH = "ARCH-VILE",
	SPIDER = "THE SPIDER MASTERMIND",
	CYBER = "THE CYBERDEMON",
	HERO = "OUR HERO",
}
