--!native
--!optimize 2

--[[
	Input.luau

	Tracks normalized keyboard, mouse, joystick, menu, automap, finale, and title input state.
]]

const Automap = require("../Interface/Automap")
const Definitions = require("./Definitions")
const Finale = require("../Interface/Finale")
const Menu = require("../Interface/Menu")

const ATTACK = 1
const USE = 2
const CHANGE = 4
const WEAPONMASK = 8 + 16 + 32
const SPECIAL = 128
const BTS_PAUSE = 1
const BTS_SAVEGAME = 2

const SLOWTURNTICS = 6
const MAXPLMOVE = 0x32
const FORWARDMOVE = { 0x19, 0x32 }
const SIDEMOVE = { 0x18, 0x28 }
const ANGLETURN = { 640, 1280, 320 }

const MOUSE_BUTTON_FIRE = 0
const MOUSE_BUTTON_STRAFE = 1
const MOUSE_BUTTON_FORWARD = 2
const JOY_BUTTON_FIRE = 0
const JOY_BUTTON_STRAFE = 1
const JOY_BUTTON_SPEED = 2
const JOY_BUTTON_USE = 3

const KeyDownEvent = 0
const KeyUpEvent = 1
const MouseEvent = 2
const JoystickEvent = 3

type InputValue = boolean | number
type ActionList = { string }
type MenuKeyBinding = {
	id: string,
	key: number,
	actions: ActionList,
}
type TicCommand = {
	forwardmove: number,
	sidemove: number,
	angleturn: number,
	consistancy: number,
	chatchar: number,
	buttons: number,
}
type PlayerCommandOwner = {
	cmd: TicCommand,
}

const inputState: { [string]: InputValue } = {}
const automapInputState: { [string]: boolean } = {}
const automapConsumedActions: { [string]: boolean } = {}
const automapConsumedState: { [string]: boolean? } = {}
const finaleInputState: { [string]: boolean? } = {}
const gameplayKeyState: { [string]: boolean? } = {}
const gameplayKeyQueue: { number } = {}
const menuInputState: { [string]: boolean } = {}
const menuRepeatState: { [string]: number? } = {}
const titleInputState: { [string]: boolean? } = {}
const frameConsumedNumericInput: { [string]: boolean } = {}
const frameDistributedNumericInput: { [string]: number } = {}
const frameDistributedNumericSteps: { [string]: number } = {}
local frameTicBudget = 1
const titleButtonState = {
	BUTTONS = 0,
	MOUSEBUTTONS = 0,
	JOYBUTTONS = 0,
}

local turnHeld = 0
local dclickTime = 0
local dclickState = false
local dclicks = 0
local dclickTime2 = 0
local dclickState2 = false
local dclicks2 = 0
local pauseInputDown = false
local saveInputDown = false

const WEAPON_HOTKEYS = {
	{ actions = { "1", "ONE", "WEAPON1", "WEAPON_1" }, weapon = Definitions.wp_fist },
	{ actions = { "2", "TWO", "WEAPON2", "WEAPON_2" }, weapon = Definitions.wp_pistol },
	{ actions = { "3", "THREE", "WEAPON3", "WEAPON_3" }, weapon = Definitions.wp_shotgun },
	{ actions = { "4", "FOUR", "WEAPON4", "WEAPON_4" }, weapon = Definitions.wp_chaingun },
	{ actions = { "5", "FIVE", "WEAPON5", "WEAPON_5" }, weapon = Definitions.wp_missile },
	{ actions = { "6", "SIX", "WEAPON6", "WEAPON_6" }, weapon = Definitions.wp_plasma },
	{ actions = { "7", "SEVEN", "WEAPON7", "WEAPON_7" }, weapon = Definitions.wp_bfg },
}

const AUTOMAP_KEY_BINDINGS = {
	{
		id = "TAB",
		key = Definitions.KEY_TAB,
		actions = { "TAB", "AUTOMAP" },
	},
	{
		id = "LEFT",
		key = Definitions.KEY_LEFTARROW,
		actions = { "LEFT", "omapPanLeft" },
	},
	{
		id = "RIGHT",
		key = Definitions.KEY_RIGHTARROW,
		actions = { "RIGHT", "omapPanRight" },
	},
	{
		id = "UP",
		key = Definitions.KEY_UPARROW,
		actions = { "UP", "omapPanUp" },
	},
	{
		id = "DOWN",
		key = Definitions.KEY_DOWNARROW,
		actions = { "DOWN", "omapPanDown" },
	},
	{
		id = "EQUALS",
		key = 61,
		actions = { "EQUALS", "PLUS", "ZOOMIN", "omapZoomIn" },
	},
	{
		id = "MINUS",
		key = 45,
		actions = { "MINUS", "ZOOMOUT", "omapZoomOut" },
	},
	{
		id = "ZERO",
		key = 48,
		actions = { "ZERO", "GOBIG", "omapGoBig" },
	},
	{
		id = "F",
		key = 70,
		actions = { "F", "FOLLOW", "omapFollow" },
	},
	{
		id = "G",
		key = 71,
		actions = { "G", "GRID", "omapGrid" },
	},
	{
		id = "M",
		key = 77,
		actions = { "M", "MARK", "omapMark" },
	},
	{
		id = "C",
		key = 67,
		actions = { "C", "CLEARMARK", "omapClearMark" },
	},
}

const MENU_KEY_BINDINGS: { MenuKeyBinding } = {}
const KEYCODE_ACTIONS = {
	BACKSPACE = { "BACKSPACE" },
	COMMA = { "STRAFELEFT" },
	DOWN = { "DOWN" },
	EQUALS = { "EQUALS" },
	ESCAPE = { "ESCAPE" },
	KEYPADENTER = { "ENTER" },
	LEFT = { "LEFT" },
	LEFTALT = { "ALT", "STRAFE" },
	LEFTCONTROL = { "CTRL", "ATTACK" },
	LEFTSHIFT = { "SHIFT", "SPEED" },
	MINUS = { "MINUS" },
	PERIOD = { "STRAFERIGHT" },
	RETURN = { "ENTER" },
	RIGHT = { "RIGHT" },
	RIGHTALT = { "ALT", "STRAFE" },
	RIGHTCONTROL = { "CTRL", "ATTACK" },
	RIGHTSHIFT = { "RSHIFT", "SPEED" },
	SPACE = { "SPACE", "USE" },
	TAB = { "TAB" },
	UP = { "UP" },
}
const KEYCODE_DIGITS = {
	EIGHT = "8",
	FIVE = "5",
	FOUR = "4",
	KEYPADEIGHT = "8",
	KEYPADFIVE = "5",
	KEYPADFOUR = "4",
	KEYPADNINE = "9",
	KEYPADONE = "1",
	KEYPADSEVEN = "7",
	KEYPADSIX = "6",
	KEYPADTHREE = "3",
	KEYPADTWO = "2",
	KEYPADZERO = "0",
	NINE = "9",
	ONE = "1",
	SEVEN = "7",
	SIX = "6",
	THREE = "3",
	TWO = "2",
	ZERO = "0",
}
const AUTOMAP_CHEAT_SEQUENCE = { 68, 73, 68, 84 }
const CONSUME_ONCE_NUMERIC_INPUTS = {
	MOUSEX = true,
	MOUSEY = true,
	MENU_MOUSEX = true,
	MENU_MOUSEY = true,
}

const function NormalizeAction(action: string): string
	return string.upper(action)
end

const function NormalizeKeyCode(keyCode: string): string
	const normalized = NormalizeAction(keyCode)

	if string.sub(normalized, 1, 13) == "ENUM.KEYCODE." then
		return string.sub(normalized, 14)
	end

	return normalized
end

const function TryQueueGameplayKey(action: string, value: InputValue, previousValue: InputValue?)
	if typeof(value) ~= "boolean" or value ~= true or previousValue == true then
		return
	end

	local codepoint: number? = nil

	if string.sub(action, 1, 4) == "RAW_" and #action == 5 then
		const suffix = string.sub(action, 5, 5)

		if string.find(suffix, "[A-Z0-9]") then
			codepoint = string.byte(suffix)
		end
	elseif #action == 1 and string.find(action, "[A-Z0-9]") then
		if inputState[`RAW_{action}`] ~= true then
			codepoint = string.byte(action)
		end
	end

	if codepoint ~= nil then
		gameplayKeyQueue[#gameplayKeyQueue + 1] = codepoint
	end
end

const function SetInput(action: string, value: InputValue)
	const normalizedAction = NormalizeAction(action)
	const previousValue = inputState[normalizedAction]
	TryQueueGameplayKey(normalizedAction, value, previousValue)
	inputState[normalizedAction] = value
end

const function SetMappedActions(actions: ActionList, value: InputValue)
	for _, action in actions do
		SetInput(action, value)
	end
end

const function IsSingleLetter(value: string): boolean
	return #value == 1 and string.find(value, "[A-Z]") ~= nil
end

const function SetKeyCode(keyCode: string, isPressed: boolean)
	const normalizedKeyCode = NormalizeKeyCode(keyCode)
	const digit = KEYCODE_DIGITS[normalizedKeyCode]

	if digit ~= nil then
		SetInput(`RAW_{digit}`, isPressed)
		SetInput(digit, isPressed)
		SetInput(normalizedKeyCode, isPressed)
		return
	end

	if IsSingleLetter(normalizedKeyCode) then
		SetInput(`RAW_{normalizedKeyCode}`, isPressed)
		SetInput(normalizedKeyCode, isPressed)
		return
	end

	const actions = KEYCODE_ACTIONS[normalizedKeyCode]

	if actions ~= nil then
		SetMappedActions(actions, isPressed)
		return
	end

	if string.sub(normalizedKeyCode, 1, 1) == "F" then
		const numberText = string.sub(normalizedKeyCode, 2)
		const numberValue = tonumber(numberText)

		if numberValue ~= nil and numberValue >= 1 and numberValue <= 12 then
			SetInput(normalizedKeyCode, isPressed)
		end
	end
end

const function SetMouseDelta(deltaX: number, deltaY: number)
	if Menu.GetMenuActive() then
		SetInput("MOUSEX", 0)
		SetInput("MOUSEY", 0)
		SetInput("MENU_MOUSEX", deltaX)
		SetInput("MENU_MOUSEY", deltaY)
	else
		SetInput("MOUSEX", deltaX)
		SetInput("MOUSEY", deltaY)
		SetInput("MENU_MOUSEX", 0)
		SetInput("MENU_MOUSEY", 0)
	end
end

const function QueueGameplayKeyCodepoint(codepoint: number)
	gameplayKeyQueue[#gameplayKeyQueue + 1] = codepoint
end

const function ResetGameplayInputTracking()
	turnHeld = 0
	dclickTime = 0
	dclickState = false
	dclicks = 0
	dclickTime2 = 0
	dclickState2 = false
	dclicks2 = 0
	pauseInputDown = false
	saveInputDown = false
end

const function ResetTitleInputState()
	table.clear(titleInputState)
	titleButtonState.BUTTONS = 0
	titleButtonState.MOUSEBUTTONS = 0
	titleButtonState.JOYBUTTONS = 0
end

const function IsPressed(action: string): boolean
	const value = inputState[action]

	if typeof(value) == "boolean" then
		return value
	end

	if typeof(value) == "number" then
		return value ~= 0
	end

	return false
end

const function GetStoredNumericInput(action: string): number
	const value = inputState[action]

	if typeof(value) == "number" then
		return value
	end

	return 0
end

const function GetNumericInput(action: string): number
	if CONSUME_ONCE_NUMERIC_INPUTS[action] == true and frameConsumedNumericInput[action] == true then
		return 0
	end

	return GetStoredNumericInput(action)
end

const function ClampMenuAxis(value: number): number
	if value < 0 then
		return -1
	end

	if value > 0 then
		return 1
	end

	return 0
end

const function ScaleMouseDelta(value: number): number
	const sensitivity = Menu.GetMouseSensitivity() + 5

	if value >= 0 then
		return value * sensitivity // 10
	end

	return -((-value) * sensitivity // 10)
end

const function IsBitButtonPressed(buttons: number, index: number): boolean
	return bit32.btest(buttons, bit32.lshift(1, index))
end

const function IsAnyPressed(actions: ActionList): boolean
	for _, action in actions do
		if IsPressed(action) then
			return true
		end
	end

	return false
end

const function ConsumeNumericInput(action: string): number
	if CONSUME_ONCE_NUMERIC_INPUTS[action] == true and frameTicBudget > 1 then
		local steps = frameDistributedNumericSteps[action]
		local remaining = frameDistributedNumericInput[action]

		if typeof(steps) ~= "number" or typeof(remaining) ~= "number" then
			steps = frameTicBudget
			remaining = GetStoredNumericInput(action)
			frameDistributedNumericSteps[action] = steps
			frameDistributedNumericInput[action] = remaining
		end

		if remaining == 0 or steps <= 0 then
			frameConsumedNumericInput[action] = true
			return 0
		end

		local value

		if remaining > 0 then
			value = (remaining + steps - 1) // steps
		else
			value = -(((-remaining) + steps - 1) // steps)
		end

		frameDistributedNumericInput[action] = remaining - value
		frameDistributedNumericSteps[action] = steps - 1

		if frameDistributedNumericSteps[action] <= 0 or frameDistributedNumericInput[action] == 0 then
			frameConsumedNumericInput[action] = true
		end

		return value
	end

	const value = GetNumericInput(action)

	if value ~= 0 and CONSUME_ONCE_NUMERIC_INPUTS[action] == true then
		frameConsumedNumericInput[action] = true
	end

	return value
end

const function GetFirstNumericInput(actions: ActionList, consumeOnce: boolean?): number
	for _, action in actions do
		const value = if consumeOnce == true then ConsumeNumericInput(action) else GetNumericInput(action)

		if value ~= 0 then
			return value
		end
	end

	return 0
end

const function DispatchAutomapEvent(key: number, isPressed: boolean): boolean
	return Automap.Responder({
		type = if isPressed then KeyDownEvent else KeyUpEvent,
		data1 = key,
		data2 = 0,
		data3 = 0,
	})
end

const function DispatchMenuEvent(key: number, isPressed: boolean): boolean
	return Menu.Responder({
		type = if isPressed then KeyDownEvent else KeyUpEvent,
		data1 = key,
		data2 = 0,
		data3 = 0,
	})
end

const function DispatchMenuRawEvent(eventType: number, data1: number, data2: number, data3: number): boolean
	return Menu.Responder({
		type = eventType,
		data1 = data1,
		data2 = data2,
		data3 = data3,
	})
end

const function AddMenuBinding(id: string, key: number, actions: ActionList)
	MENU_KEY_BINDINGS[#MENU_KEY_BINDINGS + 1] = {
		id = id,
		key = key,
		actions = actions,
	}
end

AddMenuBinding("ESCAPE", Definitions.KEY_ESCAPE, { "ESC", "ESCAPE" })
AddMenuBinding("ENTER", Definitions.KEY_ENTER, { "ENTER", "RETURN" })
AddMenuBinding("BACKSPACE", Definitions.KEY_BACKSPACE, { "BACKSPACE", "BS" })
AddMenuBinding("SPACE", 32, { "SPACE" })
AddMenuBinding("UP", Definitions.KEY_UPARROW, { "UP" })
AddMenuBinding("DOWN", Definitions.KEY_DOWNARROW, { "DOWN" })
AddMenuBinding("LEFT", Definitions.KEY_LEFTARROW, { "LEFT" })
AddMenuBinding("RIGHT", Definitions.KEY_RIGHTARROW, { "RIGHT" })
AddMenuBinding("MINUS", Definitions.KEY_MINUS, { "MINUS" })
AddMenuBinding("EQUALS", Definitions.KEY_EQUALS, { "EQUALS", "PLUS" })

for index = 1, 11 do
	AddMenuBinding(`F{index}`, Definitions[`KEY_F{index}`], { `F{index}` })
end

for codepoint = 65, 90 do
	const letter = string.char(codepoint)
	AddMenuBinding(letter, codepoint, { letter })
end

for codepoint = 48, 57 do
	const digit = string.char(codepoint)
	AddMenuBinding(digit, codepoint, { digit })
end

for codepoint = 33, 126 do
	const isDigit = codepoint >= 48 and codepoint <= 57
	const isUpper = codepoint >= 65 and codepoint <= 90
	const isLower = codepoint >= 97 and codepoint <= 122

	if not isDigit and not isUpper and not isLower and codepoint ~= 45 and codepoint ~= 61 then
		const ch = string.char(codepoint)
		AddMenuBinding(`CHAR_{codepoint}`, codepoint, { ch })
	end
end

const function IsGameplayPressed(action: string, automapActive: boolean): boolean
	if automapActive and automapConsumedActions[action] == true then
		return false
	end

	return IsPressed(action)
end

const function IsAnyGameplayPressed(actions: ActionList, automapActive: boolean): boolean
	for _, action in actions do
		if IsGameplayPressed(action, automapActive) then
			return true
		end
	end

	return false
end

const function AddWeaponChangeButton(buttons: number, weapon: number): number
	const weaponBits = bit32.band(weapon * 8, WEAPONMASK)
	return bit32.bor(buttons, CHANGE, weaponBits)
end

const function ApplyWeaponHotkeys(cmd: TicCommand, automapActive: boolean)
	for _, binding in WEAPON_HOTKEYS do
		if IsAnyGameplayPressed(binding.actions, automapActive) then
			cmd.buttons = AddWeaponChangeButton(cmd.buttons, binding.weapon)
			break
		end
	end
end

const function ApplyPauseAndSaveButtons(cmd: TicCommand, automapActive: boolean)
	const pausePressed = IsGameplayPressed("PAUSE", automapActive)

	if pausePressed and not pauseInputDown then
		cmd.buttons = bit32.bor(SPECIAL, BTS_PAUSE)
	end

	pauseInputDown = pausePressed

	const savePressed = IsGameplayPressed("SAVE", automapActive)

	if savePressed and not saveInputDown then
		const slot = math.clamp(GetNumericInput("SAVEGAMESLOT"), 0, 5)
		cmd.buttons = bit32.bor(SPECIAL, BTS_SAVEGAME, slot * 4)
	end

	saveInputDown = savePressed
end

const function Reset()
	table.clear(inputState)
	table.clear(automapInputState)
	table.clear(automapConsumedActions)
	table.clear(automapConsumedState)
	table.clear(finaleInputState)
	table.clear(gameplayKeyState)
	table.clear(gameplayKeyQueue)
	table.clear(menuInputState)
	table.clear(menuRepeatState)
	table.clear(frameConsumedNumericInput)
	table.clear(frameDistributedNumericInput)
	table.clear(frameDistributedNumericSteps)
	ResetTitleInputState()
	ResetGameplayInputTracking()
end

const function BeginFrame(ticBudget: number?)
	table.clear(frameConsumedNumericInput)
	table.clear(frameDistributedNumericInput)
	table.clear(frameDistributedNumericSteps)
	frameTicBudget = if typeof(ticBudget) == "number" and ticBudget > 0 then ticBudget // 1 else 1
end

const function ClearInput(clearPlayerCommand: (() -> ())?)
	Reset()

	if clearPlayerCommand ~= nil then
		clearPlayerCommand()
	end
end

const function ApplyInput(player: PlayerCommandOwner)
	if typeof(player) ~= "table" or typeof(player.cmd) ~= "table" then
		return
	end

	const cmd = player.cmd

	if Menu.IsVisible() then
		cmd.forwardmove = 0
		cmd.sidemove = 0
		cmd.angleturn = 0
		cmd.consistancy = 0
		cmd.chatchar = 0
		cmd.buttons = 0
		return
	end

	cmd.forwardmove = GetNumericInput("FORWARDMOVE")
	cmd.sidemove = GetNumericInput("SIDEMOVE")
	cmd.angleturn = GetNumericInput("ANGLETURN")
	cmd.consistancy = 0
	cmd.chatchar = 0
	cmd.buttons = GetNumericInput("BUTTONS")
	local forward = 0
	local side = 0

	const automapActive = Automap.IsActive()
	const mouseButtons = GetNumericInput("MOUSEBUTTONS")
	const joyButtons = GetNumericInput("JOYBUTTONS")
	const strafe = IsGameplayPressed("STRAFE", automapActive)
		or IsGameplayPressed("ALT", automapActive)
		or IsBitButtonPressed(mouseButtons, MOUSE_BUTTON_STRAFE)
		or IsBitButtonPressed(joyButtons, JOY_BUTTON_STRAFE)
	const speed = IsGameplayPressed("SHIFT", automapActive)
		or IsGameplayPressed("RSHIFT", automapActive)
		or IsGameplayPressed("SPEED", automapActive)
		or IsBitButtonPressed(joyButtons, JOY_BUTTON_SPEED)
	const speedIndex = if speed then 1 else 0
	const mouseX = ScaleMouseDelta(ConsumeNumericInput("MOUSEX"))
	const mouseY = ScaleMouseDelta(ConsumeNumericInput("MOUSEY"))
	const joyX = ClampMenuAxis(GetNumericInput("JOYX"))
	const joyY = ClampMenuAxis(GetNumericInput("JOYY"))
	const turning = joyX ~= 0
		or (
			not strafe
			and (
				IsGameplayPressed("LEFT", automapActive)
				or IsGameplayPressed("TURNLEFT", automapActive)
				or IsGameplayPressed("RIGHT", automapActive)
				or IsGameplayPressed("TURNRIGHT", automapActive)
			)
		)

	if turning then
		turnHeld += 1
	else
		turnHeld = 0
	end

	const turnSpeedIndex = if turnHeld < SLOWTURNTICS then 3 else speedIndex + 1

	if IsGameplayPressed("W", automapActive) or IsGameplayPressed("UP", automapActive) or IsGameplayPressed("FORWARD", automapActive) then
		forward += FORWARDMOVE[speedIndex + 1]
	end

	if IsGameplayPressed("S", automapActive) or IsGameplayPressed("DOWN", automapActive) or IsGameplayPressed("BACK", automapActive) then
		forward -= FORWARDMOVE[speedIndex + 1]
	end

	if IsGameplayPressed("A", automapActive) or IsGameplayPressed("STRAFELEFT", automapActive) or IsGameplayPressed("LEFTSTRAFE", automapActive) then
		side -= SIDEMOVE[speedIndex + 1]
	end

	if IsGameplayPressed("D", automapActive) or IsGameplayPressed("STRAFERIGHT", automapActive) or IsGameplayPressed("RIGHTSTRAFE", automapActive) then
		side += SIDEMOVE[speedIndex + 1]
	end

	if strafe then
		if IsGameplayPressed("LEFT", automapActive) or IsGameplayPressed("TURNLEFT", automapActive) then
			side -= SIDEMOVE[speedIndex + 1]
		end

		if IsGameplayPressed("RIGHT", automapActive) or IsGameplayPressed("TURNRIGHT", automapActive) then
			side += SIDEMOVE[speedIndex + 1]
		end
	else
		if IsGameplayPressed("LEFT", automapActive) or IsGameplayPressed("TURNLEFT", automapActive) then
			cmd.angleturn += ANGLETURN[turnSpeedIndex]
		end

		if IsGameplayPressed("RIGHT", automapActive) or IsGameplayPressed("TURNRIGHT", automapActive) then
			cmd.angleturn -= ANGLETURN[turnSpeedIndex]
		end
	end

	if joyY < 0 then
		forward += FORWARDMOVE[speedIndex + 1]
	elseif joyY > 0 then
		forward -= FORWARDMOVE[speedIndex + 1]
	end

	if strafe then
		if joyX < 0 then
			side -= SIDEMOVE[speedIndex + 1]
		elseif joyX > 0 then
			side += SIDEMOVE[speedIndex + 1]
		end
	elseif joyX < 0 then
		cmd.angleturn += ANGLETURN[turnSpeedIndex]
	elseif joyX > 0 then
		cmd.angleturn -= ANGLETURN[turnSpeedIndex]
	end

	const mouseForward = IsBitButtonPressed(mouseButtons, MOUSE_BUTTON_FORWARD)

	if mouseForward then
		forward += FORWARDMOVE[speedIndex + 1]
	end

	if mouseForward ~= dclickState and dclickTime > 1 then
		dclickState = mouseForward

		if dclickState then
			dclicks += 1
		end

		if dclicks == 2 then
			cmd.buttons = bit32.bor(cmd.buttons, USE)
			dclicks = 0
		else
			dclickTime = 0
		end
	else
		dclickTime += 1

		if dclickTime > 20 then
			dclicks = 0
			dclickState = false
		end
	end

	const buttonStrafe = IsBitButtonPressed(mouseButtons, MOUSE_BUTTON_STRAFE) or IsBitButtonPressed(joyButtons, JOY_BUTTON_STRAFE)

	if buttonStrafe ~= dclickState2 and dclickTime2 > 1 then
		dclickState2 = buttonStrafe

		if dclickState2 then
			dclicks2 += 1
		end

		if dclicks2 == 2 then
			cmd.buttons = bit32.bor(cmd.buttons, USE)
			dclicks2 = 0
		else
			dclickTime2 = 0
		end
	else
		dclickTime2 += 1

		if dclickTime2 > 20 then
			dclicks2 = 0
			dclickState2 = false
		end
	end

	forward += mouseY

	if strafe then
		side += mouseX * 2
	else
		cmd.angleturn -= mouseX * 8
	end

	if IsGameplayPressed("CTRL", automapActive)
		or IsGameplayPressed("ATTACK", automapActive)
		or IsBitButtonPressed(mouseButtons, MOUSE_BUTTON_FIRE)
		or IsBitButtonPressed(joyButtons, JOY_BUTTON_FIRE) then
		cmd.buttons = bit32.bor(cmd.buttons, ATTACK)
	end

	if IsGameplayPressed("SPACE", automapActive)
		or IsGameplayPressed("E", automapActive)
		or (not (automapActive and automapConsumedActions["F"] == true) and IsGameplayPressed("USE", automapActive))
		or IsGameplayPressed("ENTER", automapActive)
		or IsBitButtonPressed(joyButtons, JOY_BUTTON_USE) then
		cmd.buttons = bit32.bor(cmd.buttons, USE)
		dclicks = 0
	end

	ApplyWeaponHotkeys(cmd, automapActive)

	if forward > MAXPLMOVE then
		forward = MAXPLMOVE
	elseif forward < -MAXPLMOVE then
		forward = -MAXPLMOVE
	end

	if side > MAXPLMOVE then
		side = MAXPLMOVE
	elseif side < -MAXPLMOVE then
		side = -MAXPLMOVE
	end

	cmd.forwardmove += forward
	cmd.sidemove += side

	ApplyPauseAndSaveButtons(cmd, automapActive)
end

const function PumpMenuInput(gameTic: number)
	const consumeMouseDeltas = Menu.IsVisible()
	const mouseButtons = GetFirstNumericInput({ "MENU_MOUSEBUTTONS", "MOUSEBUTTONS" })
	const mouseX = GetFirstNumericInput({ "MENU_MOUSEX", "MOUSEX" }, consumeMouseDeltas)
	const mouseY = GetFirstNumericInput({ "MENU_MOUSEY", "MOUSEY" }, consumeMouseDeltas)

	if mouseButtons ~= 0 or mouseX ~= 0 or mouseY ~= 0 then
		DispatchMenuRawEvent(MouseEvent, mouseButtons, mouseX, mouseY)
	end

	const joyButtons = GetFirstNumericInput({ "MENU_JOYBUTTONS", "JOYBUTTONS" })
	const joyX = ClampMenuAxis(GetFirstNumericInput({ "MENU_JOYX", "JOYX" }))
	const joyY = ClampMenuAxis(GetFirstNumericInput({ "MENU_JOYY", "JOYY" }))

	if joyButtons ~= 0 or joyX ~= 0 or joyY ~= 0 then
		DispatchMenuRawEvent(JoystickEvent, joyButtons, joyX, joyY)
	end

	for _, binding in MENU_KEY_BINDINGS do
		const pressed = IsAnyPressed(binding.actions)
		const wasPressed = menuInputState[binding.id] == true

		if pressed ~= wasPressed then
			menuInputState[binding.id] = pressed
			menuRepeatState[binding.id] = if pressed then gameTic + 15 else nil
			DispatchMenuEvent(binding.key, pressed)
		elseif pressed and Menu.IsVisible() then
			const repeatTick = menuRepeatState[binding.id]

			if typeof(repeatTick) == "number" and gameTic >= repeatTick then
				menuRepeatState[binding.id] = gameTic + 4
				DispatchMenuEvent(binding.key, true)
			end
		else
			menuRepeatState[binding.id] = nil
		end
	end
end

const function PumpAutomapInput()
	table.clear(automapConsumedActions)

	for _, binding in AUTOMAP_KEY_BINDINGS do
		const pressed = IsAnyPressed(binding.actions)
		const wasPressed = automapInputState[binding.id] == true
		local consumed = automapConsumedState[binding.id] == true

		if pressed ~= wasPressed then
			automapInputState[binding.id] = pressed
			consumed = DispatchAutomapEvent(binding.key, pressed)
			automapConsumedState[binding.id] = pressed and consumed
		elseif not pressed then
			automapConsumedState[binding.id] = nil
			consumed = false
		end

		if Automap.IsActive() and pressed and consumed then
			automapConsumedActions[binding.id] = true

			for _, action in binding.actions do
				automapConsumedActions[action] = true
			end
		end
	end

	const cheatPressed = IsAnyPressed({ "omapCheat", "IDDT" })
	const cheatWasPressed = automapInputState.omapCheat == true

	if cheatPressed ~= cheatWasPressed then
		if cheatPressed and Automap.IsActive() then
			for _, key in AUTOMAP_CHEAT_SEQUENCE do
				QueueGameplayKeyCodepoint(key)
			end

			automapConsumedState.omapCheat = true
		else
			automapConsumedState.omapCheat = nil
		end
	elseif not cheatPressed then
		automapConsumedState.omapCheat = nil
	end

	automapInputState.omapCheat = cheatPressed

	if Automap.IsActive() and cheatPressed and automapConsumedState.omapCheat == true then
		automapConsumedActions.omapCheat = true
		automapConsumedActions.IDDT = true
	end
end

const function ConsumeGameplayKeys(): { number }
	const keys: { number } = {}

	for index = 1, #gameplayKeyQueue do
		keys[#keys + 1] = gameplayKeyQueue[index]
	end

	table.clear(gameplayKeyQueue)

	for codepoint = 65, 90 do
		const id = string.char(codepoint)
		const rawAction = `RAW_{id}`
		const usesRawAction = typeof(inputState[rawAction]) == "boolean"
		const pressed = if usesRawAction then false else IsPressed(id)
		const wasPressed = gameplayKeyState[id] == true

		if pressed ~= wasPressed then
			gameplayKeyState[id] = pressed

			if pressed then
				keys[#keys + 1] = codepoint
			end
		elseif not pressed then
			gameplayKeyState[id] = nil
		end
	end

	for codepoint = 48, 57 do
		const id = string.char(codepoint)
		const rawAction = `RAW_{id}`
		const usesRawAction = typeof(inputState[rawAction]) == "boolean"
		const pressed = if usesRawAction then false else IsPressed(id)
		const wasPressed = gameplayKeyState[id] == true

		if pressed ~= wasPressed then
			gameplayKeyState[id] = pressed

			if pressed then
				keys[#keys + 1] = codepoint
			end
		elseif not pressed then
			gameplayKeyState[id] = nil
		end
	end

	return keys
end

const function PumpFinaleInput()
	for action, value in inputState do
		if typeof(value) == "boolean" then
			const wasPressed = finaleInputState[action] == true

			if value and not wasPressed then
				Finale.Responder({
					type = KeyDownEvent,
					data1 = 0,
					data2 = 0,
					data3 = 0,
				})
			end

			finaleInputState[action] = value
		end
	end

	for action, wasPressed in finaleInputState do
		if wasPressed == true and typeof(inputState[action]) ~= "boolean" then
			finaleInputState[action] = nil
		end
	end
end

const function PumpTitleInput(canOpenMenu: boolean)
	for action, value in inputState do
		const isPressed = typeof(value) == "boolean" and value == true

		if isPressed and canOpenMenu and titleInputState[action] ~= true then
			Menu.StartControlPanel()
			break
		end

		titleInputState[action] = isPressed
	end

	const function CheckTitleButtonEdge(id: string, actions: ActionList): boolean
		const current = GetFirstNumericInput(actions)
		const previous = titleButtonState[id]
		titleButtonState[id] = current
		return canOpenMenu and current ~= 0 and previous == 0
	end

	if CheckTitleButtonEdge("BUTTONS", { "BUTTONS" })
		or CheckTitleButtonEdge("MOUSEBUTTONS", { "MOUSEBUTTONS" })
		or CheckTitleButtonEdge("JOYBUTTONS", { "JOYBUTTONS" }) then
		Menu.StartControlPanel()
	end

	for action, wasPressed in titleInputState do
		const value = inputState[action]
		const isPressed = typeof(value) == "boolean" and value == true

		if wasPressed == true and not isPressed then
			titleInputState[action] = nil
		end
	end
end

const function ClearAutomapConsumedActions()
	table.clear(automapConsumedActions)
end

const function ClearFinaleInputState()
	table.clear(finaleInputState)
end

Reset()

return {
	Reset = Reset,
	BeginFrame = BeginFrame,
	SetInput = SetInput,
	SetKeyCode = SetKeyCode,
	SetMouseDelta = SetMouseDelta,
	ClearInput = ClearInput,
	ApplyInput = ApplyInput,
	PumpMenuInput = PumpMenuInput,
	PumpAutomapInput = PumpAutomapInput,
	ConsumeGameplayKeys = ConsumeGameplayKeys,
	PumpFinaleInput = PumpFinaleInput,
	PumpTitleInput = PumpTitleInput,
	ClearAutomapConsumedActions = ClearAutomapConsumedActions,
	ClearFinaleInputState = ClearFinaleInputState,
	ResetTitleInputState = ResetTitleInputState,
}
