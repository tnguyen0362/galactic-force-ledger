--!strict
-- ArtService: central access to authored asset models (generated meshes), with
-- graceful fallback when an asset is unavailable so gameplay never hard-depends on art.

local ServerStorage = game:GetService("ServerStorage")

local ArtService = {}

local function library(): Instance?
	local gf = ServerStorage:FindFirstChild("GF")
	return gf and gf:FindFirstChild("Art")
end

function ArtService.exists(id: string): boolean
	local art = library()
	return art ~= nil and art:FindFirstChild(id) ~= nil
end

-- workspace.ActiveActors is created lazily by enemy spawning, but objective/outpost art
-- can build before the first enemy exists — indexing it directly crashed the relay build
-- at mission start ("ActiveActors is not a valid member of Workspace"). Find-or-create.
function ArtService.actorsFolder(): Instance
	local found = workspace:FindFirstChild("ActiveActors")
	if found then return found end
	local f = Instance.new("Folder")
	f.Name = "ActiveActors"
	f.Parent = workspace
	return f
end

-- First existing id from a preference list, or nil. Kit wiring uses this so legacy asset
-- names keep working wherever they are installed, with authored Kit_* pieces preferred.
function ArtService.firstExists(ids: { string }): string?
	for _, id in ids do
		if ArtService.exists(id) then return id end
	end
	return nil
end

-- Bounding-box size of a stored template without placing it (layout math needs piece
-- dimensions before committing to positions). Returns nil when the asset is missing.
function ArtService.measure(id: string): Vector3?
	local art = library()
	if not art then return nil end
	local template = art:FindFirstChild(id)
	if not template or not template:IsA("Model") then return nil end
	local _, bounds = template:GetBoundingBox()
	return bounds
end

function ArtService.clone(id: string): Model?
	local art = library()
	if not art then return nil end
	local template = art:FindFirstChild(id)
	if not template or not template:IsA("Model") then return nil end
	local copy = template:Clone()
	copy:SetAttribute("GF_ArtInstance", true)
	return copy
end

-- Places a scaled, oriented copy of an art model. `opts.height` fits the model to a
-- target height in studs; `opts.scale` multiplies uniformly instead.
function ArtService.place(id: string, position: Vector3, opts: {[string]: any}?): Model?
	local copy = ArtService.clone(id)
	if not copy then return nil end
	opts = opts or {}

	local _, bounds = copy:GetBoundingBox()
	local factor = 1
	if opts.height then
		factor = (opts.height :: number) / bounds.Y
	elseif opts.scale then
		factor = opts.scale :: number
	end
	if math.abs(factor - 1) > 0.001 then
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Size = d.Size * factor
			end
		end
	end

	local _, scaled = copy:GetBoundingBox()
	local yaw = opts.yaw or 0
	local sink = opts.sink or 0
	local target = position + Vector3.new(0, scaled.Y * 0.5 - sink, 0)
	copy:PivotTo(CFrame.new(target) * CFrame.Angles(0, yaw, 0))
	copy.Parent = (opts.parent :: Instance?) or ArtService.actorsFolder()
	return copy
end

-- Places an authored kit piece using its own pivot (bottom-centre for ground pieces per the
-- install contract), so PivotTo at ground level just works. NEVER reskins: kit pieces carry
-- authored palette textures that reskin() would strip. `opts.height` uniformly scales the
-- model to a target height (ScaleTo about the bottom pivot, so the base stays grounded);
-- omit it for native scale. `opts.spin` freely rotates around Y for scatter variety.
function ArtService.placeKit(id: string, position: Vector3, opts: {[string]: any}?): Model?
	local copy = ArtService.clone(id)
	if not copy then return nil end
	opts = opts or {}

	if opts.height then
		local _, bounds = copy:GetBoundingBox()
		if bounds.Y > 0.01 then
			local factor = (opts.height :: number) / bounds.Y
			if math.abs(factor - 1) > 0.001 then
				copy:ScaleTo(factor)
			end
		end
	end

	local yaw = opts.yaw or 0
	local sink = opts.sink or 0.35 -- slight embed so sloped ground never leaves floating edges
	copy:PivotTo(CFrame.new(position - Vector3.new(0, sink, 0)) * CFrame.Angles(0, yaw, 0))
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if opts.collide ~= nil then
				d.CanCollide = opts.collide :: boolean
			end
		end
	end
	copy.Parent = (opts.parent :: Instance?) or ArtService.actorsFolder()
	return copy
end

-- Recolors an art model and removes baked textures, so imported meshes obey the
-- project palette instead of carrying their own saturated artwork.
function ArtService.reskin(model: Instance, color: Color3, material: Enum.Material?)
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			d.TextureID = ""
			for _, child in d:GetChildren() do
				if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") then
					child:Destroy()
				end
			end
			d.Color = color
			d.Material = material or Enum.Material.SmoothPlastic
		elseif d:IsA("BasePart") then
			d.Color = color
			if material then d.Material = material end
		end
	end
end

function ArtService.tint(model: Instance, color: Color3, material: Enum.Material?)
	ArtService.reskin(model, color, material)
end

return ArtService

