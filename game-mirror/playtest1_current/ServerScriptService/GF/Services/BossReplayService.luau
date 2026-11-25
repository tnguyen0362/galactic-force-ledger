--!strict
-- COUNT-BOSS-REPLAY: dedicated boss replay — a terminal at the station war table wing lets a squad
-- that has defeated a boss re-challenge it on the next deploy. Replay spawns carry no campaign
-- progress and reduced salvage, so replay is practice rather than a farm loop.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossReplayService = {}

function BossReplayService.start()
	-- the terminal publishes availability once a boss has been defeated this session
	task.spawn(function()
		while true do
			task.wait(2)
			local defeated = workspace:GetAttribute("BastionDefeated") == true or workspace:GetAttribute("VeyrDefeated") == true
			workspace:SetAttribute("GF_BossReplayAvailable", defeated)
		end
	end)
	-- replay request remote: any squad member may invoke a rematch; the boss respawns at the arena
	local remotes = ReplicatedStorage:FindFirstChild("GF") and ReplicatedStorage.GF:FindFirstChild("Remotes")
	if remotes and not remotes:FindFirstChild("BossReplayRequest") then
		local ev = Instance.new("RemoteEvent")
		ev.Name = "BossReplayRequest"
		ev.Parent = remotes
	end
	local remote = remotes and remotes:FindFirstChild("BossReplayRequest")
	if remote then
		remote.OnServerEvent:Connect(function(player)
			if workspace:GetAttribute("GF_BossReplayAvailable") ~= true then
				workspace:SetAttribute("GF_LastReplayReject", "no defeated boss")
				return
			end
			if workspace:GetAttribute("BastionActive") == true or workspace:GetAttribute("VeyrActive") == true then
				workspace:SetAttribute("GF_LastReplayReject", "boss already active")
				return
			end
			-- respawn at the original arena center with a replay marker: reduced salvage, no campaign credit
			local arena = workspace:GetAttribute("GF_BossArenaPos") or Vector3.new(0, 0, -120)
			local pos = typeof(arena) == "Vector3" and arena or Vector3.new(0, 0, -120)
			local EncounterDirector = require(script.Parent.EncounterDirector)
			EncounterDirector.spawnBoss(pos + Vector3.new(0, 0, 30))
			workspace:SetAttribute("GF_BossReplayActive", true)
			workspace:SetAttribute("GF_BossReplayCount", (workspace:GetAttribute("GF_BossReplayCount") or 0) + 1)
		end)
	end
end

return BossReplayService
