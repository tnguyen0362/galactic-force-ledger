--!strict
-- GFAudioRuntime: drives ambient, locomotion, hurt and UI audio for the local player.
-- Presentation only. Never authoritative, never replicates.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local Audio = require(script.Parent.GFAudio)

local player = Players.LocalPlayer
local STRIDE_STUDS = 3.0
local gaitDist = 0
local frames, movingFrames, groundedFrames, stepPlays = 0, 0, 0, 0
local lastHealth: number? = nil
local connected: { [Instance]: boolean } = {}

-- Scene ambience direction. Beds stay allocated at level zero so zone changes crossfade
-- instead of clicking in and out. The lobby bed is station_ops + a very faint console
-- detail layer; mission_wind is the surface bed. Asset slots live at the top of GFAudio.
local AMBIENCE_FADE_SECONDS = 1.15
for _, loopName in ipairs({ "station_ops", "station_console", "mission_wind" }) do
	Audio.setLoopLevel(loopName, 0, 0)
	Audio.startLoop(loopName)
end

local ambienceScene: string? = nil
local zoneInMission: boolean? = nil
local function applySceneAmbience(inMission: boolean, instant: boolean?)
	local scene = inMission and "mission" or "station"
	if ambienceScene == scene then
		return
	end
	ambienceScene = scene
	local fade = instant == true and 0 or AMBIENCE_FADE_SECONDS
	Audio.setLoopLevel("station_ops", inMission and 0 or 1, fade)
	Audio.setLoopLevel("station_console", inMission and 0 or 0.75, fade)
	Audio.setLoopLevel("mission_wind", inMission and 1 or 0, fade)
	script:SetAttribute("gf_ambience_scene", scene)
end

local function refreshSceneAmbience(instant: boolean?)
	-- Before the first zone publish, GF_InMission is the only context available. After that,
	-- the player's zone wins: extraction/debrief can lower the global mission flag while the
	-- player is still physically on the surface, and another squadmate's mission must not set
	-- the lobby ambience for someone who already returned.
	local inMission = if zoneInMission ~= nil then zoneInMission else workspace:GetAttribute("GF_InMission") == true
	applySceneAmbience(inMission, instant)
end

refreshSceneAmbience(true)
workspace:GetAttributeChangedSignal("GF_InMission"):Connect(function()
	refreshSceneAmbience(false)
end)

-- Zone payloads are more precise than the global mission flag near extraction/debrief.
local deployStateForAudio = game:GetService("ReplicatedStorage").GF.Remotes:FindFirstChild("DeployStateChanged")
if deployStateForAudio then
	deployStateForAudio.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.zone) == "string" then
			zoneInMission = payload.zone == "Mission"
			refreshSceneAmbience(false)
		end
	end)
end

-- Long-running loops are mixed once when created; these listeners make the settings panel
-- affect them immediately rather than after a respawn or zone change.
for _, attr in ipairs({ "GF_Setting_Volume", "GF_Setting_MusicVolume", "GF_Setting_SfxVolume", "GF_Setting_VoiceVolume" }) do
	player:GetAttributeChangedSignal(attr):Connect(function()
		Audio.refreshLoopVolumes()
	end)
end

-- Roblox injects legacy character sounds locally, including the old uuhhh death cue. Those copies do
-- not exist in the server datamodel, so they must be sanitized client-side as soon as they appear.
-- Destroying only the legacy death cue preserves useful movement sounds while removing the stock-oof
-- presentation that conflicts with the authored sci-fi feedback layer.
local stockDeathSoundsRemoved = 0
local function sanitizeStockSound(inst: Instance)
	if not inst:IsA("Sound") then
		return
	end
	if inst.Name == "Died" or inst.SoundId == "rbxasset://sounds/uuhhh.mp3" then
		inst.Volume = 0
		inst:Destroy()
		stockDeathSoundsRemoved += 1
		script:SetAttribute("gf_stock_death_sounds_removed", stockDeathSoundsRemoved)
	end
end
for _, inst in workspace:GetDescendants() do
	sanitizeStockSound(inst)
end
workspace.DescendantAdded:Connect(sanitizeStockSound)

local function hookButtons(root: Instance)
	task.spawn(function()
		for _, d in root:GetDescendants() do
			if d:IsA("GuiButton") and not connected[d] then
				connected[d] = true
				d.Activated:Connect(function()
					Audio.play("ui_click")
				end)
			end
		end
	end)
end

hookButtons(player:WaitForChild("PlayerGui"))
player:WaitForChild("PlayerGui").DescendantAdded:Connect(function(d)
	if d:IsA("GuiButton") and not connected[d] then
		connected[d] = true
		d.Activated:Connect(function()
			Audio.play("ui_click")
		end)
	end
end)

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not rootPart then
		return
	end

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			Audio.play("land", rootPart.Position, 0.8)
		elseif new == Enum.HumanoidStateType.Jumping then
			Audio.play("jump", rootPart.Position, 0.8)
		end
	end)

	humanoid.Died:Connect(function()
		Audio.play("mission_fail")
	end)

	humanoid.HealthChanged:Connect(function(hp)
		if lastHealth and hp < lastHealth then
			Audio.play("player_hurt")
		end
		lastHealth = hp
	end)
	lastHealth = humanoid.Health

	local function step(dt: number)
		if not rootPart.Parent then
			return
		end
		frames += 1
		-- MoveDirection stays zero under this game's movement system, so gait is
		-- derived from actual horizontal travel instead of intent.
		local vel = rootPart.AssemblyLinearVelocity
		local speedNow = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local moving = speedNow > 3
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if moving then movingFrames += 1 end
		if grounded then groundedFrames += 1 end
		if not (moving and grounded) then
			gaitDist = 0
			return
		end
		gaitDist += speedNow * dt
		if gaitDist >= STRIDE_STUDS then
			gaitDist -= STRIDE_STUDS
			stepPlays += 1
			-- S07-010: surface-dependent footsteps — pitch/volume shift with floor material so
			-- rock, grass, metal and soil all read differently underfoot.
			local MATERIAL_TONE = {
				[Enum.Material.Rock] = { pitch = 0.7, vol = 1.0 },
				[Enum.Material.Basalt] = { pitch = 0.65, vol = 1.0 },
				[Enum.Material.Grass] = { pitch = 1.5, vol = 0.7 },
				[Enum.Material.Mud] = { pitch = 1.1, vol = 0.8 },
				[Enum.Material.Sand] = { pitch = 1.3, vol = 0.65 },
				[Enum.Material.Snow] = { pitch = 1.6, vol = 0.6 },
				[Enum.Material.Metal] = { pitch = 0.85, vol = 1.1 },
				[Enum.Material.DiamondPlate] = { pitch = 0.8, vol = 1.15 },
				[Enum.Material.Concrete] = { pitch = 0.9, vol = 1.0 },
			}
			local tone = MATERIAL_TONE[humanoid.FloorMaterial] or { pitch = 1.0, vol = 0.9 }
			Audio.play("footstep", rootPart.Position, tone.vol, tone.pitch)
		end
	end
	RunService.Heartbeat:Connect(step)
	script:SetAttribute("gf_frames", 0)
	script:SetAttribute("gf_steps", 0)
	RunService.Heartbeat:Connect(function()
		script:SetAttribute("gf_frames", frames)
		script:SetAttribute("gf_moving", movingFrames)
		script:SetAttribute("gf_grounded", groundedFrames)
		script:SetAttribute("gf_steps", stepPlays)
	end)
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

-- proximity loops: the relay hums while you stand at it, the dropship while it waits on the LZ.
-- Both cues existed in GFAudio and nothing ever started them.
task.spawn(function()
	local relayOn, shipOn = false, false
	while true do
		task.wait(0.5)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local nearRelay = false
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("GFInteract") == "Relay" and (d.Position - root.Position).Magnitude <= 26 then
					nearRelay = true
					break
				end
			end
			if nearRelay ~= relayOn then
				relayOn = nearRelay
				if relayOn then
					Audio.startLoop("relay_hum")
				else
					Audio.stopLoop("relay_hum")
				end
			end
			local actors = workspace:FindFirstChild("ActiveActors")
			local ship = actors and actors:FindFirstChild("ExtractionDropship")
			local hasShip = ship ~= nil
			if hasShip ~= shipOn then
				shipOn = hasShip
				if shipOn then
					Audio.startLoop("extraction_hum")
				else
					Audio.stopLoop("extraction_hum")
				end
			end
		end
	end
end)

-- mission failure cue: the server announces failure on MissionEvent kind="fail"
game:GetService("ReplicatedStorage").GF.Remotes.MissionEvent.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.kind == "fail" then
		Audio.play("mission_fail")
	end
end)

-- one confirmation cue when the mission goes live
local wasInMission = workspace:GetAttribute("GF_InMission") == true
workspace:GetAttributeChangedSignal("GF_InMission"):Connect(function()
	local live = workspace:GetAttribute("GF_InMission") == true
	if live then
		Audio.play("ui_confirm")
	elseif wasInMission then
		Audio.play("objective_done")
	end
	wasInMission = live
end)

