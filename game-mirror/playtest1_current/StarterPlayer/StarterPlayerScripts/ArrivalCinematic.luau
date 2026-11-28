--!strict
-- Arrival cinematic: the dropship descent. Server fires GF_ArrivalCine once per player when the
-- mission terrain is ready; everything after is client-side theatre — zero replication cost, full
-- 60fps animation. The ship is a local clone, the camera is keyframed, articulation (nacelle tilt,
-- gear compression, ramp) is computed per-frame about runtime-measured pivots.
--
-- Choreography is fixed-length and shared with the server: players are positioned at the ramp
-- mouth at RAMP_DROP_T, and control returns at HANDOFF_T. Beats:
--   0.0-5.0  dive chase: ship screams in nose-first, camera behind-above, shake building
--   5.0-7.5  flare: nacelles rotate forward->hover, ship yaws 180 so the ramp faces the objective
--   7.5-10.0 INSIDE the troop bay: red alarm light, shaking cabin, touchdown thud
--  10.4      ramp drops, daylight floods the bay
--  10.7-11.8 camera glides down the ramp and out to the squad; control returns
-- The ship does NOT leave: it stays parked, ramp down, as a solid landmark at the squad's back.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.GF.Shared.Remotes)

local player = Players.LocalPlayer

-- ---------- choreography timing (must mirror ArrivalService) ----------
local DIVE_END_T = 5.0
local FLARE_END_T = 7.5
local TOUCHDOWN_T = 10.0
local RAMP_DROP_T = 10.4
local HANDOFF_T = 11.8
local GLIDE_T = 10.7

-- ---------- ship frame calibration (verified against the imported asset) ----------
-- Template frame (verified by raycast against v7): nose +Z, rear ramp -Z, up +Y.
-- (no size constants: the asset is scaled in-place, so the choreography measures the clone)

-- ---------- small helpers ----------
local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function easeOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

local function easeIn(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t
end

local function lerpCFrame(a: CFrame, b: CFrame, t: number): CFrame
	return a:Lerp(b, t)
end

-- ---------- ship assembly ----------
type ShipRig = {
	model: Model,
	root: BasePart,
	parts: { BasePart },
	localCF: { [BasePart]: CFrame },
	nacelles: { { parts: { BasePart }, pivot: Vector3, side: string } },
	gearParts: { BasePart },
	rampParts: { BasePart },
	rampPivotLocal: Vector3,
}

local function classifyShip(model: Model): ShipRig?
	local hull: BasePart? = nil
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			table.insert(parts, d)
			if string.sub(d.Name, 1, 7) == "DS_Hull" and (hull == nil or d.Size.Magnitude > hull.Size.Magnitude) then
				hull = d
			end
		end
	end
	if hull == nil then
		hull = parts[1]
	end
	if hull == nil then
		return nil
	end
	model.PrimaryPart = hull

	-- freeze reference frame: every part's offset from the hull at import pose
	local hullCF = hull.CFrame
	local localCF: { [BasePart]: CFrame } = {}
	for _, p in parts do
		localCF[p] = hullCF:ToObjectSpace(p.CFrame)
	end

	-- cluster nacelles / gear / ramp by name prefix (semantic datablock names survive import
	-- with numeric suffixes after the material split: DS_NacelleFL, DS_NacelleFL2, ...)
	local function cluster(prefix: string): { BasePart }
		local out = {}
		for _, p in parts do
			if string.sub(p.Name, 1, #prefix) == prefix then
				table.insert(out, p)
			end
		end
		return out
	end

	local nacelles = {}
	for _, tag in ipairs({ "FL", "FR", "RL", "RR" }) do
		local members = cluster("DS_Nacelle" .. tag)
		if #members > 0 then
			-- pivot: centroid of the cluster in hull-local space (the drum centre — visually exact)
			local acc = Vector3.zero
			for _, p in members do
				acc += localCF[p].Position
			end
			table.insert(nacelles, {
				parts = members,
				pivot = acc / #members,
				side = tag,
			})
		end
	end

	local gearParts = {}
	for _, tag in ipairs({ "FL", "FR", "RL", "RR" }) do
		for _, p in cluster("DS_Gear" .. tag) do
			table.insert(gearParts, p)
		end
	end

	local rampParts = cluster("DS_Ramp")
	local rampPivotLocal = Vector3.zero
	if #rampParts > 0 then
		-- hinge: bottom-forward edge of the ramp in hull-local space. The ramp closes up against
		-- the tail face; its hinge runs along the bottom lip of the tail opening.
		local acc = Vector3.zero
		for _, p in rampParts do
			acc += localCF[p].Position
		end
		local centre = acc / #rampParts
		rampPivotLocal = centre + Vector3.new(0, -1.1, 0.9) -- tuned in Studio verification
	end

	return {
		model = model,
		root = hull,
		parts = parts,
		localCF = localCF,
		nacelles = nacelles,
		gearParts = gearParts,
		rampParts = rampParts,
		rampPivotLocal = rampPivotLocal,
	}
end

-- pose the whole assembly: shipCF is the hull's target CFrame; articulation angles in radians
local function poseShip(rig: ShipRig, shipCF: CFrame, nacelleTilt: number, gearCompress: number, rampOpen: number)
	for _, p in rig.parts do
		local base = rig.localCF[p]
		local finalLocal = base
		-- nacelle tilt: rotate the part's local frame about its cluster pivot (X axis in hull space)
		for _, nac in rig.nacelles do
			if table.find(nac.parts, p) then
				local rel = base.Position - nac.pivot
				local rot = CFrame.Angles(nacelleTilt, 0, 0)
				local newRel = rot:VectorToWorldSpace(rel)
				local newPos = nac.pivot + newRel
				finalLocal = CFrame.new(newPos) * rot * (base - base.Position)
				break
			end
		end
		-- gear compression: legs shift upward slightly in hull space (struts absorb)
		if gearCompress > 0 and table.find(rig.gearParts, p) then
			finalLocal = finalLocal + Vector3.new(0, gearCompress * 0.55, 0)
		end
		-- ramp: rotate about the hinge pivot (X axis), opening downward-aft
		if rampOpen > 0 and table.find(rig.rampParts, p) then
			local rel = base.Position - rig.rampPivotLocal
			local rot = CFrame.Angles(-rampOpen, 0, 0)
			local newRel = rot:VectorToWorldSpace(rel)
			local newPos = rig.rampPivotLocal + newRel
			finalLocal = CFrame.new(newPos) * rot * (base - base.Position)
		end
		p.CFrame = shipCF * finalLocal
	end
end

-- ---------- dust + audio theatre ----------
local function makeDustEmitter(parent: Instance): ParticleEmitter
	local a = Instance.new("Part")
	a.Name = "GF_ArrivalDustHost"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1)
	a.Parent = parent

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Dust"
	pe.Texture = "rbxassetid://258128463" -- soft smoke puff (roblox shared)
	pe.Color = ColorSequence.new(Color3.fromRGB(122, 110, 94))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(1, 18),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(1.2, 2.2)
	pe.Rate = 0
	pe.Speed = NumberRange.new(14, 26)
	pe.SpreadAngle = Vector2.new(160, 25)
	pe.RotSpeed = NumberRange.new(-40, 40)
	pe.Acceleration = Vector3.new(0, 4, 0)
	pe.Parent = a
	return pe
end

local function playSound(parent: Instance, id: string, volume: number, looped: boolean?, playbackSpeed: number?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped or false
	s.PlaybackSpeed = playbackSpeed or 1
	s.Parent = parent
	s:Play()
	return s
end

-- ---------- thrust vfx: ion plumes + glow, parented to the nacelle drums ----------
local function attachThrustVFX(rig: ShipRig): ({ ParticleEmitter }, { PointLight })
	local emitters = {}
	local lights = {}
	for _, nac in rig.nacelles do
		-- biggest member is the drum; emission directions are part-local, so the plume aims
		-- wherever the tilted drum points its belly — correct in hover AND forward flight.
		local drum: BasePart? = nil
		for _, pt in nac.parts do
			if not drum or pt.Size.Magnitude > drum.Size.Magnitude then
				drum = pt
			end
		end
		if drum then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "IonPlume"
			pe.Texture = "rbxassetid://258128463"
			pe.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255))
			pe.LightEmission = 1
			pe.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 2.5),
				NumberSequenceKeypoint.new(1, 7),
			})
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Lifetime = NumberRange.new(0.25, 0.5)
			pe.Rate = 0
			pe.Speed = NumberRange.new(38, 55)
			pe.SpreadAngle = Vector2.new(7, 7)
			pe.EmissionDirection = Enum.NormalId.Bottom
			pe.Parent = drum
			table.insert(emitters, pe)

			local lt = Instance.new("PointLight")
			lt.Color = Color3.fromRGB(90, 200, 255)
			lt.Range = 26
			lt.Brightness = 0
			lt.Parent = drum
			table.insert(lights, lt)
		end
	end
	return emitters, lights
end

-- ---------- the cinematic ----------
local playing = false
local shipModel: Model? = nil -- the parked ship outlives the cinematic: it never flies away

local function terrainTop(x: number, z: number, fallbackY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, fallbackY + 400, z), Vector3.new(0, -900, 0), params)
	return if hit then hit.Position.Y else fallbackY
end

local function playCinematic(lzPos: Vector3, heading: number)
	if playing then
		return
	end
	playing = true

	local artFolder = ReplicatedStorage:FindFirstChild("GF")
	artFolder = artFolder and artFolder:FindFirstChild("Art")
	local template = artFolder and artFolder:FindFirstChild("GF_Dropship")
	if not template then
		warn("ArrivalCinematic: GF_Dropship template missing — skipping theatre")
		playing = false
		return
	end

	if shipModel then
		shipModel:Destroy()
		shipModel = nil
	end
	local model = template:Clone()
	model.Name = "GF_ArrivalDropshipLive"
	-- anchor everything; we drive every transform explicitly
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.Parent = Workspace

	local rig = classifyShip(model)
	if not rig then
		model:Destroy()
		playing = false
		return
	end
	local plumes, plumeLights = attachThrustVFX(rig)

	-- Template frame: nose +Z, rear ramp -Z, bay floor/ceiling measured from the asset. `bay` turns
	-- a point in template coordinates into hull-local space so interior shots survive re-poses.
	local hullCF0 = rig.root.CFrame
	local function bay(x: number, y: number, z: number): Vector3
		return hullCF0:PointToObjectSpace(Vector3.new(x, y, z))
	end

	-- Rest pose: the ramp end (ship -Z) faces the objective and its tail sits just behind the LZ
	-- anchor, so the squad steps out of the ramp mouth and the ship is parked at their back.
	local lzCF = CFrame.new(lzPos) * CFrame.Angles(0, heading, 0)
	local restZ = 4 + rig.root.Size.Z / 2
	local baseCF = lzCF * CFrame.new(0, 0, restZ)
	-- settle on the highest of the four feet so no strut sinks into a slope
	local restTop = -math.huge
	for _, tag in ipairs({ "FL", "FR", "RL", "RR" }) do
		local lowest = math.huge
		local acc = Vector3.zero
		local count = 0
		for _, gp in rig.gearParts do
			if string.sub(gp.Name, 1, 9) == "DS_Gear" .. tag then
				local cf = rig.localCF[gp]
				local half = (math.abs(cf.RightVector.Y) * gp.Size.X + math.abs(cf.UpVector.Y) * gp.Size.Y + math.abs(cf.LookVector.Y) * gp.Size.Z) / 2
				lowest = math.min(lowest, cf.Position.Y - half)
				acc += cf.Position
				count += 1
			end
		end
		if count > 0 then
			local c = acc / count
			local w = baseCF:PointToWorldSpace(Vector3.new(c.X, 0, c.Z))
			restTop = math.max(restTop, terrainTop(w.X, w.Z, lzPos.Y) - lowest)
		end
	end
	if restTop == -math.huge then
		restTop = lzPos.Y + 20
	end
	local restY = restTop - 0.6 - lzPos.Y -- slight settle so the struts visibly take the weight
	local function restRel(y: number): number
		return restY + y
	end
	local restCF = lzCF * CFrame.new(0, restY, restZ)

	-- camera control
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70

	-- dust host at the LZ
	local dustHost = Instance.new("Folder")
	dustHost.Name = "GF_ArrivalDust"
	dustHost.Parent = Workspace
	local dust = makeDustEmitter(dustHost)
	dust.Parent.CFrame = CFrame.new(lzPos + Vector3.new(0, 1, 0))

	local audioRoot = Instance.new("Folder")
	audioRoot.Name = "GF_ArrivalAudio"
	audioRoot.Parent = Workspace

	-- cabin lights: invisible anchors that ride the hull (posed per frame)
	local cabinLights: { { part: BasePart, light: PointLight, z: number } } = {}
	for _, z in ipairs({ -40, -24, -8 }) do
		local host = Instance.new("Part")
		host.Name = "DS_CabinLight"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.Transparency = 1
		host.Size = Vector3.new(1, 1, 1)
		host.Parent = model
		local lt = Instance.new("PointLight")
		lt.Range = 44
		lt.Brightness = 0
		lt.Color = Color3.fromRGB(255, 60, 40)
		lt.Parent = host
		table.insert(cabinLights, { part = host, light = lt, z = z })
	end

	local t0 = os.clock()
	local conn: RBXScriptConnection

	-- ship path: nose-first dive down the approach line (lzCF +Z is behind the LZ), a VTOL yaw of
	-- 180 degrees in the flare so the ramp ends up facing the objective, vertical touchdown, ramp.
	local function shipPoseAt(t: number): (CFrame, number, number, number)
		-- returns hull CFrame, nacelleTilt, gearCompress, rampOpen
		local function frame(pos: Vector3, yaw: number, pitch: number): CFrame
			return lzCF * CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
		if t < DIVE_END_T then
			local k = smoothstep(t / DIVE_END_T)
			local pos = Vector3.new(0, restRel(340 - 220 * k), restZ + 683 - 570 * k)
			return frame(pos, math.pi, math.rad(14 - 8 * k)), math.rad(82), 0, 0
		elseif t < FLARE_END_T then
			local k = smoothstep((t - DIVE_END_T) / (FLARE_END_T - DIVE_END_T))
			local pos = Vector3.new(0, restRel(120 - 96 * k), restZ + 113 - 113 * k)
			return frame(pos, math.pi * (1 - k), math.rad(6 - 6 * k)), math.rad(82 - 82 * k), 0, 0
		elseif t < TOUCHDOWN_T then
			local k = easeIn((t - FLARE_END_T) / (TOUCHDOWN_T - FLARE_END_T))
			return frame(Vector3.new(0, restRel(24 * (1 - k)), restZ), 0, 0), 0, 0, 0
		else
			-- on the ground for good: gear takes the weight, then the ramp opens and stays open
			local settle = math.clamp((t - TOUCHDOWN_T) / 0.6, 0, 1)
			local gear = math.sin(settle * math.pi) * 0.9
			local ramp = 0
			if t > RAMP_DROP_T then
				ramp = math.rad(72) * easeOut((t - RAMP_DROP_T) / 0.9)
			end
			return restCF, 0, gear, ramp
		end
	end

	local function shake(t: number, amp: number): Vector3
		return Vector3.new(math.noise(t * 17.3, 1.7) * amp, math.noise(5.1, t * 15.1) * amp, 0)
	end

	-- camera: exterior chase and 3/4 flare, then INSIDE the troop bay for the landing, then a glide
	-- out of the ramp mouth to the squad at handoff.
	local function cameraPoseAt(t: number, shipCF: CFrame): CFrame
		local sp = shipCF.Position
		local function rel(v: Vector3): Vector3
			return lzCF:VectorToWorldSpace(v)
		end
		if t < DIVE_END_T then
			local k = math.clamp(t / (DIVE_END_T - 0.8), 0, 1)
			local camPos = sp + rel(Vector3.new(30, 26, 105))
			local s = shake(t, k * 2.2)
			return CFrame.lookAt(camPos + s, sp + lzCF.LookVector * 40)
		elseif t < FLARE_END_T then
			local k = smoothstep((t - DIVE_END_T) / (FLARE_END_T - DIVE_END_T))
			local chasePos = sp + rel(Vector3.new(30, 26, 105))
			local sidePos = sp + rel(Vector3.new(-95, 14, 20))
			return CFrame.lookAt(chasePos:Lerp(sidePos, k), sp)
		elseif t < GLIDE_T then
			-- seat position at the forward end of the bay, looking down the cabin at the ramp
			local seat = shipCF:PointToWorldSpace(bay(0, 1.0, -3.5))
			local door = shipCF:PointToWorldSpace(bay(0, 0.4, -46))
			local k = math.clamp((t - FLARE_END_T) / (TOUCHDOWN_T - FLARE_END_T), 0, 1)
			local amp = 0.1 + 0.45 * k
			if t > TOUCHDOWN_T then
				amp += 1.8 * math.exp(-(t - TOUCHDOWN_T) * 6)
			end
			return CFrame.lookAt(seat + shake(t, amp), door)
		else
			local k = smoothstep((t - GLIDE_T) / (HANDOFF_T - GLIDE_T))
			local p0 = shipCF:PointToWorldSpace(bay(0, 1.0, -3.5))
			local p1 = shipCF:PointToWorldSpace(bay(0, -1.0, -50))
			local p2 = lzCF:PointToWorldSpace(Vector3.new(0, 7, -2))
			local a = p0:Lerp(p1, k)
			local b = p1:Lerp(p2, k)
			local look = lzCF:PointToWorldSpace(Vector3.new(0, 3, -60))
			return CFrame.lookAt(a:Lerp(b, k), look)
		end
	end

	-- fade-in overlay
	local gui = Instance.new("ScreenGui")
	gui.Name = "GF_ArrivalCineOverlay"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local veil = Instance.new("Frame")
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.Size = UDim2.new(1, 0, 1, 0)
	veil.BorderSizePixel = 0
	veil.Parent = gui
	veil.BackgroundTransparency = 0.3
	TweenService:Create(veil, TweenInfo.new(0.65), { BackgroundTransparency = 1 }):Play()

	local dustBurstDone = false
	local cutDone = false
	local handoffDone = false

	conn = RunService.RenderStepped:Connect(function()
		-- GF_CineScrub (number) pins the clock: lets a debug session frame any beat deterministically
		local scrub = Workspace:GetAttribute("GF_CineScrub")
		local t = if type(scrub) == "number" then scrub else os.clock() - t0

		local shipCF, tilt, gear, ramp = shipPoseAt(t)
		poseShip(rig, shipCF, tilt, gear, ramp)
		camera.CFrame = cameraPoseAt(t, shipCF)
		camera.FieldOfView = if t >= FLARE_END_T and t < HANDOFF_T then 82 else 70

		-- cabin: red alarm wash during the descent, cold daylight spill once the ramp is dropping
		for _, cl in cabinLights do
			cl.part.CFrame = shipCF * CFrame.new(bay(0, 3, cl.z))
			if t >= FLARE_END_T - 0.5 and t < RAMP_DROP_T then
				cl.light.Color = Color3.fromRGB(255, 60, 40)
				cl.light.Brightness = 2.4 + 1.4 * (0.5 + 0.5 * math.sin(t * 9))
			elseif t >= RAMP_DROP_T then
				cl.light.Color = Color3.fromRGB(205, 225, 255)
				cl.light.Brightness = math.min(2.6, 1.4 + (t - RAMP_DROP_T) * 3)
			else
				cl.light.Brightness = 0
			end
		end

		-- hard cut from the exterior flare into the bay, softened by a quick dip
		if t >= FLARE_END_T and not cutDone then
			cutDone = true
			veil.BackgroundTransparency = 0.45
			TweenService:Create(veil, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end

		-- throttle: cruise in the dive, full power through flare/hover, spooled down on the ground
		local throttle = 0.65
		if t >= FLARE_END_T - 1.2 and t < TOUCHDOWN_T + 0.6 then
			throttle = 1
		elseif t >= TOUCHDOWN_T + 0.6 then
			throttle = if t >= HANDOFF_T then 0 else 0.12
		end
		for _, pe in plumes do
			pe.Rate = 110 * throttle
		end
		for _, lt in plumeLights do
			lt.Brightness = 2.6 * throttle
		end

		-- hover dust wash builds during flare/descent, big burst at touchdown
		if t > FLARE_END_T - 0.5 and t < TOUCHDOWN_T then
			dust.Rate = 70
		end
		if t >= TOUCHDOWN_T and not dustBurstDone then
			dustBurstDone = true
			dust:Emit(90)
			dust.Rate = 12
		end
		if t > TOUCHDOWN_T + 2.5 then
			dust.Rate = 0
		end

		if t >= HANDOFF_T and not handoffDone then
			handoffDone = true
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
		end

		if t >= HANDOFF_T + 4 then
			conn:Disconnect()
			-- the ship stays: parked, ramp down, engines cold. Solid so nobody walks through the hull.
			for _, e in plumes do
				e:Destroy()
			end
			for _, l in plumeLights do
				l:Destroy()
			end
			for _, p in rig.parts do
				if not table.find(rig.rampParts, p) and string.sub(p.Name, 1, 11) ~= "DS_Interior" then
					p.CanCollide = true
					p.CanQuery = true
				end
			end
			shipModel = model
			dustHost:Destroy()
			audioRoot:Destroy()
			gui:Destroy()
			playing = false
		end
	end)
end

-- server signals: lzPos (Vector3), heading (number, radians). The static instance can replicate
-- after this script boots on a fresh mission server, so acquire it patiently instead of asserting.
task.spawn(function()
	local gf = ReplicatedStorage:WaitForChild("GF", 30)
	local container = gf and gf:WaitForChild("Remotes", 30)
	local remote = container and container:WaitForChild("ArrivalCineStart", 30)
	if not remote then
		warn("ArrivalCinematic: ArrivalCineStart remote never appeared — theatre disabled")
		return
	end
	remote.OnClientEvent:Connect(function(lzPos: Vector3, heading: number)
		if typeof(lzPos) ~= "Vector3" then
			return
		end
		playCinematic(lzPos, heading or 0)
	end)
end)

print("ArrivalCinematic: ready")
