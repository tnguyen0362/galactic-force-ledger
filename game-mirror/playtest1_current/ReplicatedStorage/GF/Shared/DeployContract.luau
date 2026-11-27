--!strict
-- DeployContract: the teleport data contract for the place-split migration (step 3).
-- Deploy intent crosses the lobby->mission teleport boundary inside TeleportOptions joinData.
-- Both places share this module so the contract can never drift between writer and reader.
-- Schema v1: additive-only evolution — new fields optional, never repurpose old ones.

local HttpService = game:GetService("HttpService")

local DeployContract = {}

export type DeployIntent = {
	v: number, -- schema version, always 1 for now
	seed: number,
	difficulty: string,
	template: string,
	squadUserIds: { number },
	lobbyPlaceId: number, -- where extraction return-teleport sends the squad
}

function DeployContract.encode(intent: DeployIntent): string
	-- joinData size is limited; keep the payload flat and small. JSON rather than binary:
	-- debuggable in telemetry, and the size cost is trivial at this field count.
	return HttpService:JSONEncode(intent)
end

function DeployContract.decode(joinData: string?): DeployIntent?
	if type(joinData) ~= "string" or #joinData == 0 then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, joinData)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	if decoded.v ~= 1 then
		return nil -- unknown schema: mission server falls back to pinned/random intent
	end
	return decoded :: DeployIntent
end

-- teleport data arrives per-player; the mission server reads it from the first arrival's
-- PlayerJoinData. In Studio local test there is no join data — callers must tolerate nil.
function DeployContract.fromPlayer(player: Player): DeployIntent?
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil
	end
	local td = (joinData :: any).TeleportData
	if type(td) ~= "string" then
		return nil
	end
	return DeployContract.decode(td)
end

return DeployContract
