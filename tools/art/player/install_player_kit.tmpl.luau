-- Run in Studio EDIT datamodel (execute_luau) with a Studio claim held. Idempotent (replaces ServerStorage.GF.Art.PlayerKit).
-- Generated: make_install_player.sh = this template + player_kit_data.luau + asset id.
-- Builds ServerStorage.GF.Art.PlayerKit from the uploaded GLB: one template MeshPart per limb x colour group.
-- AppearanceService.dress clones these, scales by (limb.Size / refDims[limb]), welds to the limb and tints by suit.
-- Template attributes: GF_Limb ("UpperArm"), GF_Side ("R"/"L"/""), GF_Group (carrier/pouch/hardware/helmet/glove/boot),
--   GF_Center (limb-local bbox centre at reference scale). Folder attributes Ref_<Limb> = reference limb sizes.
local ASSET_ID = __ASSET_ID__
__DATA__
local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local gf = SS:FindFirstChild("GF") or Instance.new("Folder", SS)
gf.Name = "GF"
local art = gf:FindFirstChild("Art") or Instance.new("Folder", gf)
art.Name = "Art"
local old = art:FindFirstChild("PlayerKit")
if old then old:Destroy() end

local loaded = IS:LoadAsset(ASSET_ID)
local meshes, seen = {}, {}
for _, d in loaded:GetDescendants() do
	if d:IsA("MeshPart") then
		local n = d.Name:gsub("%.%d+$", "")
		meshes[n] = d
		table.insert(seen, n)
	end
end

local folder = Instance.new("Folder")
folder.Name = "PlayerKit"
for limb, v in DATA.refDims do folder:SetAttribute("Ref_" .. limb, v) end
local report = { missing = {}, sizeDev = {}, tris = 0 }
for name, def in DATA.parts do
	local src = meshes[name]
	if not src then table.insert(report.missing, name) continue end
	local p = src:Clone()
	p.Name = name
	for _, c in p:GetChildren() do c:Destroy() end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TextureID = ""
	p.CollisionFidelity = Enum.CollisionFidelity.Box
	p.RenderFidelity = Enum.RenderFidelity.Automatic
	p:SetAttribute("GF_Limb", def.limb)
	p:SetAttribute("GF_Side", def.side)
	p:SetAttribute("GF_Group", def.group)
	p:SetAttribute("GF_Center", def.center)
	p:SetAttribute("GF_KitTemplate", true)
	report.sizeDev[name] = (p.Size - def.size).Magnitude
	report.tris += def.tris
	p.Parent = folder
end
folder:SetAttribute("GF_AssetId", ASSET_ID)
folder.Parent = art
loaded:Destroy()

local lines = { string.format("PlayerKit built: parts=%d tris=%d missing=%s", #folder:GetChildren(), report.tris, table.concat(report.missing, ",")) }
for n, dev in report.sizeDev do if dev > 0.08 then table.insert(lines, string.format("SIZE DEV %s %.3f", n, dev)) end end
table.insert(lines, "meshes found in asset: " .. #seen)
warn(table.concat(lines, "\n"))
