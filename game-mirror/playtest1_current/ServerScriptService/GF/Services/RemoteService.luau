--!strict
-- Idempotent remote creation from the single registry. Safe to call in Edit mode (GF.Check).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.GF.Shared.Remotes)

local RemoteService = {}

function RemoteService.ensureRemotes(): number
	local container = ReplicatedStorage.GF.Remotes
	local created = 0
	for _, name in Remotes.Names do
		if not container:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = container; created += 1
		end
	end
	for _, name in Remotes.Functions do
		if not container:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction"); r.Name = name; r.Parent = container; created += 1
		end
	end
	return created
end

return RemoteService

