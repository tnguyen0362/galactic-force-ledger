--!nonstrict
-- Voss dispatch lines. The DialogueEvent remote existed with no sender and no receiver, so the
-- commander never spoke. This is the sender; the client portrait/subtitle is the receiver.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueService = {}
local lastLine = ""
local lastAt = 0

function DialogueService.say(text: string, kind: string?)
	if type(text) ~= "string" or text == "" then
		return false
	end
	local now = os.clock()
	if text == lastLine and now - lastAt < 8 then
		return false
	end
	lastLine = text
	lastAt = now
	local remote = ReplicatedStorage.GF.Remotes:FindFirstChild("DialogueEvent")
	if remote then
		remote:FireAllClients({ speaker = "VOSS", text = text, kind = kind or "dispatch" })
	end
	workspace:SetAttribute("GF_LastVossLine", text)
	workspace:SetAttribute("GF_VossLines", (workspace:GetAttribute("GF_VossLines") or 0) + 1)
	return true
end

function DialogueService.start()
	-- Mission brief on deploy and dispatch on foot.
	local station = require(script.Parent.StationService)
	DialogueService.say("Command, Voss. Boots on the ground — keep your head down and your mags full.", "intro")
	local hook = require(script.Parent.ObjectiveService)
	if hook and hook.onStage then
		return
	end
	station.publishBriefing = function(missionName, difficulty)
		DialogueService.say(string.format("%s on %s. Get in, finish the job, get out.", tostring(missionName), tostring(difficulty)), "brief")
	end
end

return DialogueService

