--!strict
-- ReturnTeleportService: end-of-mission return to the lobby place (migration step 6).
-- In the split architecture extraction completion teleports the squad BACK instead of
-- repositioning them inside one shared place. Inert in the shared place: no-op unless
-- GF_LobbyPlaceId is set AND the current place differs from it.

local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ReturnTeleportService = {}

function ReturnTeleportService.enabled(): boolean
	local lobbyId = Workspace:GetAttribute("GF_LobbyPlaceId")
	return type(lobbyId) == "number" and lobbyId > 0 and lobbyId ~= game.PlaceId
end

-- teleport the given players back to the lobby. Failure is non-fatal: callers treat it as
-- a lost return (players stay in the mission server, which will empty and shut down anyway).
function ReturnTeleportService.sendHome(players: { Player }): boolean
	if not ReturnTeleportService.enabled() then
		return false
	end
	if #players == 0 then
		return false
	end
	local lobbyId = Workspace:GetAttribute("GF_LobbyPlaceId")
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(lobbyId, players)
	end)
	if not ok then
		warn("ReturnTeleportService: teleport failed:", err)
		return false
	end
	print(string.format("ReturnTeleportService: %d players returning to lobby", #players))
	return true
end

return ReturnTeleportService
