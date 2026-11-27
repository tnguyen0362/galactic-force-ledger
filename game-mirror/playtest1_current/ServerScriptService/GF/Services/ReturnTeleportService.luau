--!strict
-- ReturnTeleportService: end-of-mission return to the lobby place (migration step 6).
-- In the split architecture extraction completion teleports the squad BACK instead of
-- repositioning them inside one shared place. Inert in the shared place: no-op unless
-- GF_LobbyPlaceId is set AND the current place differs from it.
--
-- Additive return contract v1: callers may pass an encoded mission-results string. The outbound
-- DeployContract is unchanged; this payload flows only mission -> lobby and is evidence for the
-- after-action report, never a second economic grant.

local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ReturnTeleportService = {}

function ReturnTeleportService.enabled(): boolean
	local lobbyId = Workspace:GetAttribute("GF_LobbyPlaceId")
	return type(lobbyId) == "number" and lobbyId > 0 and lobbyId ~= game.PlaceId
end

function ReturnTeleportService.lobbyPlaceId(): number?
	local lobbyId = Workspace:GetAttribute("GF_LobbyPlaceId")
	if type(lobbyId) == "number" and lobbyId > 0 and lobbyId ~= game.PlaceId then
		return lobbyId
	end
	return nil
end

-- teleport the given players back to the lobby. Failure is non-fatal: extraction settlement is
-- already durable before this call, so a transport failure must never be treated as a lost reward.
function ReturnTeleportService.sendHome(players: { Player }, resultsPayload: any?): boolean
	if not ReturnTeleportService.enabled() then
		return false
	end
	if #players == 0 then
		return false
	end
	local lobbyId = ReturnTeleportService.lobbyPlaceId()
	if not lobbyId then
		return false
	end
	local options = nil
	if resultsPayload ~= nil then
		options = Instance.new("TeleportOptions")
		if type(resultsPayload) == "string" then
			options:SetTeleportData(resultsPayload)
		else
			local okEncode, encoded = pcall(function()
				return game:GetService("HttpService"):JSONEncode(resultsPayload)
			end)
			if okEncode and type(encoded) == "string" then
				options:SetTeleportData(encoded)
			else
				options = nil
			end
		end
	end
	local ok, err = pcall(function()
		if options then
			TeleportService:TeleportAsync(lobbyId, players, options)
		else
			TeleportService:TeleportAsync(lobbyId, players)
		end
	end)
	if not ok then
		warn("ReturnTeleportService: teleport failed:", err)
		return false
	end
	print(string.format("ReturnTeleportService: %d players returning to lobby", #players))
	return true
end

return ReturnTeleportService
