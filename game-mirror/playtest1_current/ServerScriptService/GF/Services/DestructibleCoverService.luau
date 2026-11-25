--!strict
-- S07-013 selective destruction of small cover: low cover pieces carry HP, break under fire into
-- capped pooled debris (never persistent physics), and their destruction updates LOS because the
-- blocking part itself shrinks away — enemy and player raycasts read live geometry.
local RunService = game:GetService("RunService")

local DestructibleCoverService = {}
local pieces: { { part: BasePart, hp: number, maxHp: number, fullSize: Vector3, debrisUntil: number } } = {}
local debrisPool: { BasePart } = {}
local MAX_DEBRIS = 12

function DestructibleCoverService.registerPiece(part: BasePart, hp: number)
	pieces[#pieces + 1] = { part = part, hp = hp, maxHp = hp, fullSize = part.Size, debrisUntil = 0 }
	part:SetAttribute("DestructibleCover", true)
end

local function spawnDebris(at: Vector3, color: Color3)
	-- pooled debris: reuse parts, cap the pool, anchored so zero physics cost
	local chunk
	if #debrisPool >= MAX_DEBRIS then
		chunk = debrisPool[1]
		table.remove(debrisPool, 1)
	else
		chunk = Instance.new("Part")
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.Material = Enum.Material.Concrete
	end
	chunk.Size = Vector3.new(0.7, 0.5, 0.6)
	chunk.Color = color
	chunk.CFrame = CFrame.new(at) * CFrame.Angles(0, math.random() * 3, 0)
	chunk.Parent = workspace
	debrisPool[#debrisPool + 1] = chunk
end

-- called from the combat damage path when a raycast hits cover
function DestructibleCoverService.damage(part: BasePart, amount: number)
	for _, piece in ipairs(pieces) do
		if piece.part == part and piece.hp > 0 then
			piece.hp -= amount
			if piece.hp <= 0 then
				-- break: cover collapses to a low remnant — LOS and nav update because the tall blocker is gone
				piece.part.Size = Vector3.new(piece.fullSize.X, piece.fullSize.Y * 0.22, piece.fullSize.Z)
				piece.part.CFrame = piece.part.CFrame * CFrame.new(0, -piece.fullSize.Y * 0.36, 0)
				piece.part.Transparency = 0.15
				for i = 1, 3 do
					spawnDebris(piece.part.Position + Vector3.new((math.random() - 0.5) * 4, 1, (math.random() - 0.5) * 4), piece.part.Color)
				end
				workspace:SetAttribute("GF_CoverDestroyed", (workspace:GetAttribute("GF_CoverDestroyed") or 0) + 1)
			end
			return true
		end
	end
	return false
end

function DestructibleCoverService.isDestructible(part: BasePart): boolean
	return part:GetAttribute("DestructibleCover") == true
end

return DestructibleCoverService
