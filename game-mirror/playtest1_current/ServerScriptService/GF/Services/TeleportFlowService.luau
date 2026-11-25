--!strict
-- S02-006/007 multi-place flow: one universe, OrbitalStation start place, PlanetaryMission place
-- with reserved server instances per squad. The places themselves are created in the creator
-- dashboard (Open Cloud place-write is not grantable programmatically); this service carries the
-- full flow logic so the moment place IDs are configured the architecture is live:
--   deploy = reserve a mission server, teleport the squad with mission payload
--   extraction = teleport back to the station with results payload
-- Profile ownership never crosses a universe boundary — same universe throughout (S02-007).
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local TeleportFlowService = {}

-- place IDs live as attributes so wiring them is a configuration step, not a code change
local function missionPlaceId(): number?
	return tonumber(workspace:GetAttribute("GF_MissionPlaceId"))
end

function TeleportFlowService.deploySquad(players: { Player }, missionPayload: { [string]: any }): boolean
	local placeId = missionPlaceId()
	if not placeId then
		-- single-place fallback: missions run in-instance (current architecture); the flow is ready
		workspace:SetAttribute("GF_TeleportMode", "single-place-fallback")
		return false
	end
	-- reserved server per squad: no strangers drop into a mission instance mid-op
	local reserveCode = TeleportService:ReserveServer(placeId)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = reserveCode
	options:SetTeleportData(missionPayload)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players, options)
	end)
	if not ok then
		warn("[GF] mission teleport failed: " .. tostring(err))
	end
	return ok
end

function TeleportFlowService.returnToStation(players: { Player }, resultsPayload: { [string]: any }): boolean
	local stationId = tonumber(workspace:GetAttribute("GF_StationPlaceId"))
	if not stationId then
		return false
	end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(resultsPayload)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(stationId, players, options)
	end)
	if not ok then
		warn("[GF] station return teleport failed: " .. tostring(err))
	end
	return ok
end

-- arrival side: read the teleport payload that accompanied the squad
function TeleportFlowService.arrivalPayload(player: Player): { [string]: any }?
	local joinData = player:GetJoinData()
	if joinData and joinData.TeleportData then
		return joinData.TeleportData
	end
	return nil
end

function TeleportFlowService.start()
	Players.PlayerAdded:Connect(function(player)
		local payload = TeleportFlowService.arrivalPayload(player)
		if payload and payload.missionId then
			workspace:SetAttribute("GF_ArrivedWithMission", tostring(payload.missionId))
		end
	end)
end

return TeleportFlowService
