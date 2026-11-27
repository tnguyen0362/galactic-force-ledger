--!strict
-- Semantic action layer. Game logic never reads a physical button directly;
-- glyphs are derived from the same binding table so prompts cannot drift from behaviour.
local UserInputService = game:GetService("UserInputService")

local Input = {}

type Device = "kbm" | "gamepad" | "touch"

local BINDINGS = {
	Fire = { kbm = Enum.UserInputType.MouseButton1, gamepad = Enum.KeyCode.ButtonR2, label = { kbm = "LMB", gamepad = "RT" } },
	Aim = { kbm = Enum.UserInputType.MouseButton2, gamepad = Enum.KeyCode.ButtonL2, label = { kbm = "RMB", gamepad = "LT" } },
	Jump = { kbm = Enum.KeyCode.Space, gamepad = Enum.KeyCode.ButtonA, label = { kbm = "Space", gamepad = "A" } },
	Sprint = { kbm = Enum.KeyCode.LeftShift, gamepad = Enum.KeyCode.ButtonL3, label = { kbm = "Shift", gamepad = "LS" } },
	Dodge = { kbm = Enum.KeyCode.LeftControl, gamepad = Enum.KeyCode.ButtonB, label = { kbm = "Ctrl", gamepad = "B" } },
	Reload = { kbm = Enum.KeyCode.R, gamepad = Enum.KeyCode.ButtonX, label = { kbm = "R", gamepad = "X" } },
	Interact = { kbm = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonX, label = { kbm = "E", gamepad = "X" } },
	SwapWeapon = { kbm = Enum.KeyCode.One, gamepad = Enum.KeyCode.ButtonY, label = { kbm = "1", gamepad = "Y" } },
	Grenade = { kbm = Enum.KeyCode.G, gamepad = Enum.KeyCode.DPadDown, label = { kbm = "G", gamepad = "Dpad v" } },
	-- one support ability (Counteroffensive contract revision). the freed F/R1 binding is
	-- RESERVED for Emergency Dispatch quick-response (Stage 6) — do not reassign casually
	SupportAbility = { kbm = Enum.KeyCode.Q, gamepad = Enum.KeyCode.ButtonL1, label = { kbm = "Q", gamepad = "LB" } },
	TacticalMap = { kbm = Enum.KeyCode.M, gamepad = Enum.KeyCode.DPadUp, label = { kbm = "M", gamepad = "Dpad ^" } },
	Ping = { kbm = Enum.UserInputType.MouseButton3, gamepad = Enum.KeyCode.DPadRight, label = { kbm = "MMB", gamepad = "Dpad >" } },
	ShoulderSwap = { kbm = Enum.KeyCode.V, gamepad = Enum.KeyCode.ButtonR3, label = { kbm = "V", gamepad = "RS" } },
	MenuBack = { kbm = Enum.KeyCode.Escape, gamepad = Enum.KeyCode.ButtonB, label = { kbm = "Esc", gamepad = "B" } },
}

local device: Device = "kbm"
local held: { [string]: boolean } = {}
local pressHandlers: { [string]: { (any) -> () } } = {}
local releaseHandlers: { [string]: { (any) -> () } } = {}

local function normalize(kind: Enum.UserInputType): Device
	if kind == Enum.UserInputType.Gamepad1 or kind == Enum.UserInputType.Gamepad2
		or kind == Enum.UserInputType.Gamepad3 or kind == Enum.UserInputType.Gamepad4 then
		return "gamepad"
	elseif kind == Enum.UserInputType.Touch then
		return "touch"
	end
	return "kbm"
end

function Input.setDevice(kind: any)
	if typeof(kind) == "EnumItem" then
		device = normalize(kind)
	elseif kind == "gamepad" or kind == "touch" or kind == "kbm" then
		device = kind
	end
end

function Input.getDevice(): Device
	return device
end

function Input.isHeld(action: string): boolean
	return held[action] == true
end

function Input.onPress(action: string, fn: (any) -> ())
	pressHandlers[action] = pressHandlers[action] or {}
	table.insert(pressHandlers[action], fn)
end

function Input.onRelease(action: string, fn: (any) -> ())
	releaseHandlers[action] = releaseHandlers[action] or {}
	table.insert(releaseHandlers[action], fn)
end

function Input.glyph(action: string): string
	local binding = BINDINGS[action]
	if not binding then
		return "?"
	end
	if device == "touch" then
		return binding.label.touch or binding.label.kbm
	end
	return binding.label[device] or binding.label.kbm
end

function Input.setHeld(action: string, value: boolean, source: any)
	if held[action] == value then
		return
	end
	held[action] = value
	local list = value and pressHandlers[action] or releaseHandlers[action]
	if list then
		for _, fn in list do
			local ok, err = pcall(fn, source)
			if not ok then
				warn("[GF] input handler error (" .. action .. "): " .. tostring(err))
			end
		end
	end
end

local function actionForKey(keyCode: Enum.KeyCode, inputType: Enum.UserInputType): string?
	local wanted = normalize(inputType)
	for action, binding in BINDINGS do
		local key = binding[wanted]
		if key == nil and wanted == "touch" then
			key = binding.kbm
		end
		if key == keyCode or key == inputType then
			-- Reload/Interact share a physical button on gamepad: contextual resolution happens in Weapon/HUD
			if action == "Interact" and wanted == "gamepad" then
				return "Interact"
			end
			return action
		end
	end
	return nil
end

function Input.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local action = actionForKey(input.KeyCode, input.UserInputType)
		if action then
			Input.setDevice(input.UserInputType)
			Input.setHeld(action, true, input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local action = actionForKey(input.KeyCode, input.UserInputType)
		if action then
			Input.setHeld(action, false, input)
		end
	end)
end

return Input

