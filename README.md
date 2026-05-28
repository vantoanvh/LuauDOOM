# LuauDOOM
Fully ported the original DOOM engine to a luau modern source port.

av
```luau
local UserInputService = game:GetService("UserInputService")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local DOOM = require("@game/ReplicatedStorage/LuauDOOM") -- Requires the module

local IWAD = require("@game/ReplicatedStorage/DOOM2") -- Load the IWAD
local PWAD = require("@game/ReplicatedStorage/marine") -- Load the PWAD (optional)

local Size = Vector2.new(320, 200) -- Customize the sizes, recommended only using sizes (320, 200); (640, 400); (960, 600)

const Screen = AssetService:CreateEditableImage({Size = Size})
script.Parent.ImageContent = Content.fromObject(Screen)

-- Sets the size
DOOM.init({screenWidth = Size.X, screenHeight = Size.Y})

DOOM.loadIWAD(IWAD)
DOOM.loadPWAD(PWAD)

DOOM.setSound(uploaded_wav_file_from_iwad, IWAD)

-- Adding OST:
--[[
  DOOM.addOST(`e1m1`, e1m1_soundid)
  DOOM.addOST(`e1m2`, e1m2_soundid)

  DOOM.addOST("intro", intrp_soundid)
  DOOM.addOST("inter", inter_soundid)
]]

const function InputBegan(input: InputObject)
	const userInputType = input.UserInputType
	const keyCode = input.KeyCode

	if userInputType == Enum.UserInputType.MouseButton1 then
		DOOM.setInput("MOUSEBUTTONS", 1) -- Shoot!
	elseif keyCode == Enum.KeyCode.Period then
		DOOM.setInput("ESCAPE", 1) -- Open DOOM Menu
	elseif keyCode == Enum.KeyCode.Escape then
		return -- Safer. because opening roblox menu breaks things
	elseif keyCode ~= Enum.KeyCode.Unknown then
		DOOM.keyDown(keyCode.Name)
	end
end

const function InputEnded(input: InputObject)
	const userInputType = input.UserInputType
	const keyCode = input.KeyCode

	if userInputType == Enum.UserInputType.MouseButton1 then
		DOOM.setInput("MOUSEBUTTONS", 0)
	elseif keyCode == Enum.KeyCode.Period then
		DOOM.setInput("ESCAPE", 0)
	elseif keyCode == Enum.KeyCode.Escape then
		return -- Safer. The reason on the top
	elseif keyCode ~= Enum.KeyCode.Unknown then
		DOOM.keyUp(keyCode.Name)
	end
	
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		DOOM.setMouseDelta(0, 0)
	end
end

local LastPosition = UserInputService:GetMouseLocation()

const function InputChanged(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		DOOM.setMouseDelta(input.Delta.X * 3, 0)
		LastPosition = UserInputService:GetMouseLocation()
	end
end

local MouseIdleDuration = 0

const function onRendered(dt: number)
	Screen:WritePixelsBuffer(Vector2.zero, Size, DOOM.advanceFrame(dt))
	UserInputService.MouseIconEnabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	if LastPosition == UserInputService:GetMouseLocation() then
		MouseIdleDuration += dt
		if MouseIdleDuration > 0.03 then
			MouseIdleDuration = 0
			DOOM.setMouseDelta(0, 0)
		end
	else
		MouseIdleDuration = 0
	end
end

UserInputService.InputBegan:Connect(InputBegan)
UserInputService.InputEnded:Connect(InputEnded)
UserInputService.InputChanged:Connect(InputChanged)
RunService.PreRender:Connect(onRendered)
```
