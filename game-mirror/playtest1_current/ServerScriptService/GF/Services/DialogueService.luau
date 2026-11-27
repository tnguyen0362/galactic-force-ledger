--!nonstrict
-- Commander/PA dialogue, onboarding voice, and the server half of the first-join flow.
--
-- Ownership notes for the alpha lanes:
-- * CinematicUI owns the camera/letterbox/skip presentation. This service only offers the
--   per-player trigger through the existing IntroReplay remote and publishes onboarding state.
-- * ProfileService owns persistence. This service reads introWatched/tutorialCompleted but never
--   writes those fields.
-- * TutorialService owns First Spear progression. This service observes TutorialStep and supplies
--   Voss's tutorial voice lines without changing completion logic.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueService = {}

local VOSS_SPEAKER = "CMDR. ELARA VOSS"
local DEFAULT_KIND = "dispatch"
local DEDUP_SECONDS = 8
local AMBIENT_MIN_GAP_FROM_DIALOGUE = 24
local FIRST_AMBIENT_MIN = 70
local FIRST_AMBIENT_MAX = 110
local AMBIENT_MIN = 180
local AMBIENT_MAX = 300
local WELCOME_REPEAT_SECONDS = 600

local Campaign = nil
pcall(function()
	Campaign = require(ReplicatedStorage.GF.Shared.Configs.Campaign)
end)

local rng = Random.new()
local started = false
local ambientLoopStarted = false
local zoneWatcherStarted = false
local lastLineByScope = {}
local lastAnyAt = 0
local ambientCount = 0
local introServerTriggers = 0
local playerState = {}
local tutorialVoice = {}

local TUTORIAL_LINES = {
	[1] = "First Spear, this is Command. Your target is an Ascendancy relay. Follow your HUD and move to the objective.",
	[2] = "Ascendancy infantry ahead. Engage. Your combat shields will recover after you break contact.",
	[3] = "Reload before the next contact. Never carry an empty magazine into the assault.",
	[4] = "Incoming fire is telegraphed. Dodge clear, recover your bearings, and keep moving.",
	[5] = "Support systems authorized. Mark the strike zone.",
}
local TUTORIAL_COMPLETE_LINE = "First Spear complete. Welcome to the counteroffensive."
local FIRST_STATION_CLEARANCE_LINE = "Welcome back. Your clearance is active. Review the Galactic War table when you're ready."

local AMBIENT_ROTATION = {
	{
		id = "docking",
		speaker = "FLIGHT OPS",
		lines = {
			"Flight operations: courier Kestrel Nine cleared into Bay Two. Deck crews, secure loose equipment.",
			"Docking control: supply shuttle Meridian Dawn on final approach. Aft concourse may feel light vibration.",
			"Flight operations: departure pad beacon is green. Keep the drop lanes clear unless your squad is called.",
			"Docking control: ammunition pallets are inbound aboard Tressel Four. Manifest verification at the freight lift.",
		},
	},
	{
		id = "war",
		speaker = "COMMAND",
		dynamic = "war",
		lines = {},
	},
	{
		id = "operations",
		speaker = "OPERATIONS",
		lines = {
			"Operations broadcast: Ascendancy patrol density is rising across the Veyra highlands. Review landing-zone telemetry before departure.",
			"Operations broadcast: Priority Dispatch is monitoring reinforcement requests. Available squads report to the communications alcove.",
			"Operations broadcast: extraction craft turnaround is nominal. Do not crowd the departure pad during launch cycles.",
			"Operations broadcast: reconnaissance elements report increased relay shielding. Sabotage teams confirm charges before extraction.",
		},
	},
	{
		id = "personnel",
		speaker = "DECK CONTROL",
		lines = {
			"Personnel notice: armor maintenance is open in the armory. Return diagnostic cases to rack seven after use.",
			"Personnel notice: training archives are available beside the war table. Newly cleared operators may review the First Spear record.",
			"Deck crew notice: inspection detail to the forward observation rail. Secure all loose tools before the next docking cycle.",
			"Personnel notice: medical stations are open beside the armory. Report suit-seal faults before deployment, not after planetfall.",
		},
	},
	{
		id = "voss",
		speaker = VOSS_SPEAKER,
		lines = {
			"Earth is free because the fleet refused to disappear. The frontier is still occupied. We finish that work here.",
			"Every relay broken, every beacon held, every archive recovered weakens the Ascendancy's hold. Precision matters.",
			"The counteroffensive is not vengeance. It is the liberation of occupied worlds. Carry yourselves accordingly.",
			"You are not expendable assets. You are trained soldiers with a mission and a way home. Remember both.",
		},
	},
}
local ambientIndex = rng:NextInteger(1, #AMBIENT_ROTATION) - 1

local function remotesFolder(): Instance?
	local gf = ReplicatedStorage:FindFirstChild("GF")
	return gf and gf:FindFirstChild("Remotes")
end

local function dialogueRemote(): Instance?
	local remotes = remotesFolder()
	return remotes and remotes:FindFirstChild("DialogueEvent")
end

local function publishLine(text: string, speaker: string)
	workspace:SetAttribute("GF_LastDialogueLine", text)
	if speaker == VOSS_SPEAKER then
		workspace:SetAttribute("GF_LastVossLine", text)
		workspace:SetAttribute("GF_VossLines", (workspace:GetAttribute("GF_VossLines") or 0) + 1)
	end
end

local function shouldSend(scope: string, text: string): boolean
	local now = os.clock()
	local key = scope .. "|" .. text
	local previous = lastLineByScope[key]
	if previous and now - previous < DEDUP_SECONDS then
		return false
	end
	lastLineByScope[key] = now
	lastAnyAt = now
	return true
end

local function fireTo(player: Player, text: string, kind: string?, speaker: string?): boolean
	if type(text) ~= "string" or text == "" then
		return false
	end
	if not player or player.Parent == nil then
		return false
	end
	local remote = dialogueRemote()
	if not remote then
		return false
	end
	local chosenSpeaker = speaker or VOSS_SPEAKER
	if not shouldSend("player:" .. tostring(player.UserId), text) then
		return false
	end
	remote:FireClient(player, {
		speaker = chosenSpeaker,
		text = text,
		kind = kind or DEFAULT_KIND,
		at = os.time(),
	})
	publishLine(text, chosenSpeaker)
	return true
end

function DialogueService.sayTo(player: Player, text: string, kind: string?, speaker: string?): boolean
	return fireTo(player, text, kind, speaker)
end

function DialogueService.say(text: string, kind: string?, speaker: string?): boolean
	if type(text) ~= "string" or text == "" then
		return false
	end
	local remote = dialogueRemote()
	if not remote then
		return false
	end
	local chosenSpeaker = speaker or VOSS_SPEAKER
	if not shouldSend("broadcast", text) then
		return false
	end
	remote:FireAllClients({
		speaker = chosenSpeaker,
		text = text,
		kind = kind or DEFAULT_KIND,
		at = os.time(),
	})
	publishLine(text, chosenSpeaker)
	return true
end

local function profileModule()
	local ok, service = pcall(require, script.Parent.ProfileService)
	if ok then
		return service
	end
	return nil
end

local function profileFor(player: Player)
	local service = profileModule()
	if not service or type(service.get) ~= "function" then
		return nil
	end
	local ok, profile = pcall(service.get, player)
	if ok then
		return profile
	end
	return nil
end

local function ensureProfile(player: Player)
	local existing = profileFor(player)
	if existing then
		return existing
	end
	local service = profileModule()
	if not service or type(service.ensure) ~= "function" then
		return nil
	end
	pcall(service.ensure, player)
	return profileFor(player)
end

local function stationExists(): boolean
	return workspace:FindFirstChild("Station") ~= nil or workspace:FindFirstChild("Concourse") ~= nil
end

local function stationZoneOf(player: Player): string
	local ok, station = pcall(require, script.Parent.StationService)
	if ok and station and type(station.zoneOf) == "function" then
		local okZone, zone = pcall(station.zoneOf, player)
		if okZone and type(zone) == "string" then
			return zone
		end
	end
	return "Station"
end

-- Tutorial_Active is sticky in the legacy TutorialService (finish never resets it), so it cannot
-- be used as a lifetime gate. The reliable live signal is a positive per-player TutorialStep.
local function playerTutorialInProgress(player: Player): boolean
	local step = player:GetAttribute("TutorialStep")
	return type(step) == "number" and math.floor(step) > 0
end

local function tutorialInProgress(): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		if playerTutorialInProgress(player) then
			return true
		end
	end
	return false
end

local function stateFor(player: Player)
	local state = playerState[player]
	if not state then
		state = {}
		playerState[player] = state
	end
	return state
end

local function updateOnboardingState(player: Player): (any, string)
	local profile = profileFor(player)
	if not profile then
		player:SetAttribute("GF_OnboardingState", "profile_loading")
		return nil, "profile_loading"
	end

	local stateName = "station_ready"
	if profile.introWatched ~= true and profile.tutorialCompleted ~= true then
		stateName = "intro_pending"
	elseif profile.tutorialCompleted ~= true then
		stateName = "tutorial_pending"
	end
	player:SetAttribute("GF_OnboardingState", stateName)
	player:SetAttribute("GF_IntroGateProvisional", profile.introWatched ~= true)
	if profile.introWatched ~= true and profile.tutorialCompleted ~= true then
		player:SetAttribute("GF_FirstJoin", true)
	elseif player:GetAttribute("GF_FirstJoin") == nil then
		player:SetAttribute("GF_FirstJoin", false)
	end
	return profile, stateName
end

local function isStationReady(player: Player): boolean
	local stateName = player:GetAttribute("GF_OnboardingState")
	if type(stateName) == "string" then
		return stateName == "station_ready"
	end
	local profile = profileFor(player)
	return profile ~= nil and profile.tutorialCompleted == true
end

local function prettyTerritory(id: string): string
	if Campaign and Campaign.DisplayName and Campaign.DisplayName[id] then
		return Campaign.DisplayName[id]
	end
	local pretty = string.gsub(id, "(%u)", " %1")
	pretty = string.gsub(pretty, "^%s+", "")
	return pretty
end

local function activeWarFront()
	local packed = workspace:GetAttribute("GF_WarTerritories")
	if type(packed) ~= "string" or packed == "" then
		return nil
	end
	local fallback = nil
	for token in string.gmatch(packed, "[^;]+") do
		local parts = string.split(token, ":")
		local id = parts[1]
		local progress = tonumber(parts[2]) or 0
		local stateName = parts[3] or "Contested"
		local isFront = parts[4] == "FRONT"
		if type(id) == "string" and id ~= "" then
			local record = {
				id = id,
				displayName = prettyTerritory(id),
				progress = math.clamp(math.floor(progress + 0.5), 0, 100),
				state = stateName,
				front = isFront,
			}
			if isFront and stateName ~= "Human" then
				return record
			end
			if not fallback and stateName ~= "Human" then
				fallback = record
			end
		end
	end
	return fallback
end

local function warBroadcastLine(): string
	local defense = workspace:GetAttribute("GF_WarDefenseOpen")
	if type(defense) == "string" and defense ~= "" then
		return string.format(
			"Priority war traffic: %s is under Ascendancy counterattack. Defense operations are open to all cleared squads.",
			prettyTerritory(defense)
		)
	end
	local front = activeWarFront()
	if front then
		if front.state == "Human" then
			return string.format(
				"War table update: %s is secure. Ascendancy pressure continues along the outer territories.",
				front.displayName
			)
		end
		return string.format(
			"War table update: %s is %d percent liberated and still contested. Command is rotating fresh squads to the front.",
			front.displayName,
			front.progress
		)
	end
	local sector = workspace:GetAttribute("GF_WarSector")
	if type(sector) == "string" and sector ~= "" then
		return "War table update: " .. sector
	end
	return "War table update: the counteroffensive is active. Review the Galactic War table for the live front."
end

local function nextAmbientLine(): (string, string, string)
	ambientIndex = (ambientIndex % #AMBIENT_ROTATION) + 1
	local category = AMBIENT_ROTATION[ambientIndex]
	if category.dynamic == "war" then
		return warBroadcastLine(), category.speaker, "station-war"
	end
	local lines = category.lines
	return lines[rng:NextInteger(1, #lines)], category.speaker, "station-" .. tostring(category.id)
end

local function sendAmbientToStation(): number
	if not stationExists() then
		return 0
	end
	if os.clock() - lastAnyAt < AMBIENT_MIN_GAP_FROM_DIALOGUE then
		return 0
	end
	local text, speaker, kind = nextAmbientLine()
	local delivered = 0
	for _, player in ipairs(Players:GetPlayers()) do
		-- PA lines are targeted. One rookie running First Spear must not silence the ship for every
		-- veteran in the lobby; only the player whose own TutorialStep is live is excluded.
		if stationZoneOf(player) == "Station" and isStationReady(player) and not playerTutorialInProgress(player) then
			if fireTo(player, text, kind, speaker) then
				delivered += 1
			end
		end
	end
	if delivered > 0 then
		ambientCount += 1
		workspace:SetAttribute("GF_AmbientAnnouncements", ambientCount)
		workspace:SetAttribute("GF_LastAmbientAnnouncement", text)
		workspace:SetAttribute("GF_LastAmbientSpeaker", speaker)
	end
	return delivered
end

local function startAmbientLoop()
	if ambientLoopStarted then
		return
	end
	ambientLoopStarted = true
	task.spawn(function()
		while not stationExists() do
			task.wait(5)
		end
		task.wait(rng:NextInteger(FIRST_AMBIENT_MIN, FIRST_AMBIENT_MAX))
		while true do
			sendAmbientToStation()
			local waitFor = rng:NextInteger(AMBIENT_MIN, AMBIENT_MAX)
			workspace:SetAttribute("GF_NextAmbientIn", waitFor)
			task.wait(waitFor)
		end
	end)
end

-- A player who joins just after the server-wide PA cycle can otherwise wait up to five minutes
-- before hearing the ship feel alive. Give each newly welcomed station player one targeted,
-- non-repeating arrival announcement about two minutes later; the regular sparse cycle remains
-- the backbone and this never repeats on respawn.
local function scheduleArrivalAmbient(player: Player)
	local state = stateFor(player)
	if state.arrivalAmbientScheduled == true then
		return
	end
	state.arrivalAmbientScheduled = true
	task.delay(rng:NextInteger(115, 150), function()
		if player.Parent == nil or not stationExists() or playerTutorialInProgress(player) then
			return
		end
		if stationZoneOf(player) ~= "Station" or not isStationReady(player) then
			return
		end
		if os.clock() - lastAnyAt < AMBIENT_MIN_GAP_FROM_DIALOGUE then
			return
		end
		local text, speaker, kind = nextAmbientLine()
		if fireTo(player, text, kind, speaker) then
			ambientCount += 1
			workspace:SetAttribute("GF_AmbientAnnouncements", ambientCount)
			workspace:SetAttribute("GF_LastAmbientAnnouncement", text)
			workspace:SetAttribute("GF_LastAmbientSpeaker", speaker)
		end
	end)
end

local function welcomeText(player: Player): string
	local finishedAt = workspace:GetAttribute("Tutorial_FinishedAt")
	if type(finishedAt) == "number" and os.clock() - finishedAt < 180 then
		return FIRST_STATION_CLEARANCE_LINE
	end
	local front = activeWarFront()
	if front and front.state ~= "Human" then
		return string.format(
			"Welcome back to the GFS Vanguard. %s is %d%% liberated and still contested. The war table has the live front.",
			front.displayName,
			front.progress
		)
	end
	return "Welcome back to the GFS Vanguard. The counteroffensive is active. Review the Galactic War table when you're ready."
end

local function considerStationWelcome(player: Player, force: boolean?)
	if not stationExists() then
		return false
	end
	if not player or player.Parent == nil then
		return false
	end
	if stationZoneOf(player) ~= "Station" then
		return false
	end
	local character = player.Character
	if not character or character.Parent == nil then
		return false
	end
	local profile = profileFor(player)
	if not profile or profile.tutorialCompleted ~= true then
		return false
	end

	local state = stateFor(player)
	local now = os.clock()
	if force == true and state.postTutorialWelcomed == true then
		return false
	end
	if force ~= true then
		if state.welcomedOnce == true and now - (state.lastWelcomeAt or 0) < WELCOME_REPEAT_SECONDS then
			return false
		end
	end

	local sent = fireTo(player, welcomeText(player), "station-welcome", VOSS_SPEAKER)
	if sent then
		state.welcomedOnce = true
		state.lastWelcomeAt = now
		if force == true then
			state.postTutorialWelcomed = true
		end
		workspace:SetAttribute("GF_StationWelcomes", (workspace:GetAttribute("GF_StationWelcomes") or 0) + 1)
		scheduleArrivalAmbient(player)
	end
	return sent
end

local function introRemote(): Instance?
	local remotes = remotesFolder()
	return remotes and remotes:FindFirstChild("IntroReplay")
end

local function fireIntroTrigger(player: Player, reason: string): boolean
	local remote = introRemote()
	if not remote or player.Parent == nil then
		return false
	end
	-- TutorialService uses GF_CinematicStop as a one-way latch and never clears it. A server-side
	-- targeted intro offer is an intentional new playback request, so clear the latch first; the
	-- tutorial will assert it again when First Spear actually begins.
	workspace:SetAttribute("GF_CinematicStop", false)
	remote:FireClient(player)
	introServerTriggers += 1
	workspace:SetAttribute("GF_IntroServerTriggers", introServerTriggers)
	player:SetAttribute("GF_IntroTriggerCount", (player:GetAttribute("GF_IntroTriggerCount") or 0) + 1)
	player:SetAttribute("GF_IntroTriggerReason", reason)
	return true
end

local function offerIntro(player: Player)
	local state = stateFor(player)
	if state.introOffered == true then
		return
	end
	state.introOffered = true
	player:SetAttribute("GF_IntroOffered", true)
	-- Targeted offers cover normal replication timing without using the global GF_CinematicPlay
	-- attribute, which would incorrectly start the cinematic for every player in a populated lobby.
	-- The later fallbacks are guarded by the MarkIntroSeen listener below, so a completed/skipped
	-- cinematic is not restarted while the profile write is still settling.
	for _, delaySeconds in ipairs({ 2.2, 6.5, 18, 36 }) do
		task.delay(delaySeconds, function()
			if player.Parent == nil then
				return
			end
			local profile = profileFor(player)
			if (profile and profile.introWatched == true) or type(state.introCompletionAt) == "number" then
				return
			end
			if tutorialInProgress() then
				return
			end
			fireIntroTrigger(player, delaySeconds < 3 and "initial" or "replication-fallback")
		end)
	end
end

local function scheduleTutorialBackup(player: Player)
	local state = stateFor(player)
	if state.tutorialBackupScheduled == true then
		return
	end
	state.tutorialBackupScheduled = true
	task.spawn(function()
		-- ProfileService normally starts First Spear from MarkIntroSeen. This is only a safety net;
		-- it waits out another active tutorial because the legacy tutorial implementation is global.
		for attempt = 1, 12 do
			task.wait(10)
			if player.Parent == nil then
				return
			end
			local profile = profileFor(player)
			if not profile or profile.tutorialCompleted == true then
				return
			end
			if profile.introWatched ~= true then
				player:SetAttribute("GF_TutorialFallbackState", "waiting-for-intro")
			elseif tutorialInProgress() then
				player:SetAttribute("GF_TutorialFallbackState", "waiting-for-active-tutorial")
			else
				local ok, tutorial = pcall(require, script.Parent.TutorialService)
				if ok and tutorial and type(tutorial.begin) == "function" then
					player:SetAttribute("GF_TutorialFallbackState", "server-start")
					pcall(tutorial.begin, player)
				else
					player:SetAttribute("GF_TutorialFallbackState", "tutorial-service-unavailable")
				end
				return
			end
		end
		if player.Parent ~= nil then
			player:SetAttribute("GF_TutorialFallbackState", "blocked")
		end
	end)
end

local function sendFreshArrivalLine(player: Player)
	local state = stateFor(player)
	if state.freshArrivalLineSent == true then
		return
	end
	state.freshArrivalLineSent = fireTo(
		player,
		"Commander Elara Voss, Director of Field Operations. Welcome aboard the GFS Vanguard. Stand by for the counteroffensive record.",
		"station-arrival",
		VOSS_SPEAKER
	)
end

local function monitorOnboarding(player: Player)
	task.spawn(function()
		local deadline = os.clock() + 150
		while player.Parent ~= nil and os.clock() < deadline do
			ensureProfile(player)
			local _, stateName = updateOnboardingState(player)
			if stateName == "intro_pending" then
				sendFreshArrivalLine(player)
				offerIntro(player)
			elseif stateName == "tutorial_pending" then
				scheduleTutorialBackup(player)
			elseif stateName == "station_ready" then
				task.delay(2, function()
					considerStationWelcome(player, false)
				end)
				return
			end
			task.wait(2)
		end
		if player.Parent ~= nil and profileFor(player) == nil then
			player:SetAttribute("GF_OnboardingState", "profile_error")
		end
	end)
end

local function handleTutorialStep(player: Player)
	local rawStep = player:GetAttribute("TutorialStep")
	if type(rawStep) ~= "number" then
		return
	end
	local step = math.floor(rawStep)
	if step >= 1 and step <= #TUTORIAL_LINES then
		local record = tutorialVoice[player]
		if record and record.step == step then
			return
		end
		tutorialVoice[player] = { step = step, completed = false }
		task.delay(0.45, function()
			if player.Parent == nil then
				return
			end
			local current = player:GetAttribute("TutorialStep")
			if type(current) == "number" and math.floor(current) == step then
				fireTo(player, TUTORIAL_LINES[step], "tutorial", VOSS_SPEAKER)
			end
		end)
		return
	end

	if step == 0 then
		local record = tutorialVoice[player]
		-- Tutorial_Complete is another global sticky latch; a positive-step record followed by this
		-- player's own TutorialStep=0 is the reliable per-player completion transition.
		if record and record.completed ~= true then
			record.completed = true
			tutorialVoice[player] = nil
			fireTo(player, TUTORIAL_COMPLETE_LINE, "tutorial-complete", VOSS_SPEAKER)
			task.delay(1, function()
				updateOnboardingState(player)
			end)
			-- Let the completion line finish before the station clearance/welcome line enters the queue.
			task.delay(7.2, function()
				considerStationWelcome(player, true)
			end)
		end
	end
end

local function hookPlayer(player: Player)
	stateFor(player)
	player:SetAttribute("GF_OnboardingState", player:GetAttribute("GF_OnboardingState") or "profile_loading")

	-- Compatibility gate for the current CinematicUI: its local auto-play path persists
	-- MarkIntroSeen immediately after calling play(), which starts the tutorial and cancels the
	-- cinematic in the same second. Keeping the replicated IntroSeen attribute true while the
	-- authoritative profile still says introWatched=false suppresses only that broken auto-persist;
	-- the targeted IntroReplay trigger below still plays the cinematic, and MarkIntroSeen is still
	-- written at natural finish/skip. GF_OnboardingState/GF_IntroGateProvisional expose the truth.
	if player:GetAttribute("IntroSeen") ~= true then
		player:SetAttribute("IntroSeen", true)
	end
	player:SetAttribute("GF_IntroGateProvisional", true)
	player:GetAttributeChangedSignal("IntroSeen"):Connect(function()
		if player:GetAttribute("IntroSeen") == false then
			local profile = profileFor(player)
			if not profile or profile.introWatched ~= true then
				player:SetAttribute("IntroSeen", true)
				player:SetAttribute("GF_IntroGateProvisional", true)
			end
		end
	end)

	monitorOnboarding(player)

	player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
		handleTutorialStep(player)
	end)
	player.CharacterAdded:Connect(function()
		task.delay(2.5, function()
			considerStationWelcome(player, false)
		end)
	end)
	if player.Character then
		task.delay(2.5, function()
			considerStationWelcome(player, false)
		end)
	end
end

local function startZoneWatcher()
	if zoneWatcherStarted then
		return
	end
	zoneWatcherStarted = true
	task.spawn(function()
		while true do
			task.wait(2)
			if stationExists() then
				for _, player in ipairs(Players:GetPlayers()) do
					if stationZoneOf(player) == "Station" then
						considerStationWelcome(player, false)
					end
				end
			end
		end
	end)
end

function DialogueService.start()
	if started then
		return
	end
	started = true
	workspace:SetAttribute("GF_DialogueService", true)
	workspace:SetAttribute("GF_AmbientAnnouncements", 0)

	-- ProfileService remains the only writer of introWatched. This parallel listener merely gives
	-- the fallback cinematic-trigger logic a same-frame completion/skip signal, so a late retry
	-- cannot restart a cinematic the player just finished.
	local remotes = remotesFolder()
	local mark = remotes and remotes:FindFirstChild("MarkIntroSeen")
	if mark and mark:IsA("RemoteEvent") then
		mark.OnServerEvent:Connect(function(player)
			local state = stateFor(player)
			state.introCompletionAt = os.clock()
			task.delay(0.5, function()
				if player.Parent ~= nil then
					updateOnboardingState(player)
					scheduleTutorialBackup(player)
				end
			end)
		end)
	else
		warn("[GF] dialogue: MarkIntroSeen remote missing; intro fallback timing degraded")
	end

	-- The station archive/ProfileService replay path fires IntroReplay directly. Clear the
	-- tutorial latch for that explicit user action too; playback remains client-gated while a
	-- cinematic is already running, so this cannot stack replays.
	local replay = remotes and remotes:FindFirstChild("RequestIntroReplay")
	if replay and replay:IsA("RemoteEvent") then
		replay.OnServerEvent:Connect(function()
			workspace:SetAttribute("GF_CinematicStop", false)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerState[player] = nil
		tutorialVoice[player] = nil
	end)

	startAmbientLoop()
	startZoneWatcher()
	print("[GF] dialogue service online: onboarding triggers, Voss tutorial voice, station PA")
end

function DialogueService.status()
	return {
		started = started,
		ambientCount = ambientCount,
		introServerTriggers = introServerTriggers,
		lastAnyAt = lastAnyAt,
	}
end

return DialogueService
