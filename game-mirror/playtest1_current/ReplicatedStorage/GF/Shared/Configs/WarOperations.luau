--!strict
-- WarOperations — binding from game mission templates to Theater of War operation instances.
-- TRANSITION SEAM: each template resolves to its PRIMARY region binding until the deploy
-- flow becomes region-aware (Stage 4/7). At that point resolution becomes exact per-deploy
-- and this table shrinks to template family metadata. Operation instances are defined in
-- WarModel.OPERATIONS; names here are the canonical roster (mandate sec.61 alignment pending
-- on display names — ids are persistence keys and must not change).
local WarOperations = {}

-- templateId -> operationInstanceId (primary binding)
WarOperations.ByTemplate = {
	SABOTAGE_RELAY = "SEVER_SIGNAL",       -- Sever the Signal (canonical rename pending)
	RECOVERY_ARCHIVE = "SILENT_ARCHIVE",   -- Silent Archive
	SABOTAGE_ARSENAL = "BURN_ARSENAL",     -- Burn the Arsenal
	DEFENSE_POWER = "POWER_UNDER_FIRE",    -- Power Under Fire
	RECOVERY_CONVOY = "FALLEN_CONVOY",     -- Fallen Convoy
	DEFENSE_UPLINK = "LAST_TRANSMISSION",  -- Last Transmission
	SABOTAGE_AEGIS = "SHATTERED_AEGIS",    -- Shattered Aegis
	RECOVER_TECH = "ALIEN_LEGACY",         -- Alien Legacy (canonical rename pending)
	DEFEND_BEACON = "HOLD_THE_LINE",       -- Hold the Line (canonical rename pending)
	ELIM_COMMANDER = "HEAD_OF_SPEAR",      -- Head of the Spear
	ELIM_WALKER = "SIEGE_BREAKER",         -- Siege Breaker
	CONQUEST_DOMINION = "FORWARD_DOMINION",-- Forward Dominion
	CONQUEST_FOUNDRY = "IRON_FOUNDRY",     -- Iron Foundry
	CONQUEST_THRONEFALL = "THRONEFALL",    -- Thronefall
	ELIM_TALON = "BROKEN_TALON",           -- Broken Talon
	-- FIRST_SPEAR tutorial deliberately unmapped: training operations do not move the war
}

function WarOperations.operationFor(templateId: string?): string?
	if type(templateId) ~= "string" then
		return nil
	end
	return WarOperations.ByTemplate[templateId]
end

-- operationInstanceId -> game template id. EXACT per operation: templates are reusable across
-- regions (several operation instances fly the same template in different theatres), so this
-- is the authoritative direction for deployment — the deploy flow resolves the template from
-- the chosen operation server-side and the client never asserts it.
WarOperations.TemplateFor = {
	FORWARD_DOMINION = "CONQUEST_DOMINION",
	ALIEN_LEGACY = "RECOVER_TECH",
	BROKEN_TALON = "ELIM_TALON",
	FALLEN_CONVOY = "RECOVERY_CONVOY",
	HEAD_OF_SPEAR = "ELIM_COMMANDER",
	SEVER_SIGNAL_TB = "SABOTAGE_RELAY",
	SEVER_SIGNAL = "SABOTAGE_RELAY",
	HOLD_THE_LINE = "DEFEND_BEACON",
	SHATTERED_AEGIS = "SABOTAGE_AEGIS",
	SIEGE_BREAKER = "ELIM_WALKER",
	SILENT_ARCHIVE = "RECOVERY_ARCHIVE",
	BURN_ARSENAL_FR = "SABOTAGE_ARSENAL",
	BROKEN_TALON_FR = "ELIM_TALON",
	LAST_TRANSMISSION = "DEFENSE_UPLINK",
	THRONEFALL = "CONQUEST_THRONEFALL",
	HEAD_OF_SPEAR_WR = "ELIM_COMMANDER",
	BURN_ARSENAL = "SABOTAGE_ARSENAL",
	SIEGE_BREAKER_IM = "ELIM_WALKER",
	POWER_UNDER_FIRE = "DEFENSE_POWER",
	IRON_FOUNDRY = "CONQUEST_FOUNDRY",
	SHATTERED_AEGIS_FB = "SABOTAGE_AEGIS",
}

function WarOperations.templateFor(operationId: string?): string?
	if type(operationId) ~= "string" then
		return nil
	end
	return WarOperations.TemplateFor[operationId]
end

-- canonical display names for the operation instances (player-facing; ids never change)
WarOperations.DisplayName = {
	FORWARD_DOMINION = "Forward Dominion",
	ALIEN_LEGACY = "Alien Legacy",
	BROKEN_TALON = "Broken Talon",
	FALLEN_CONVOY = "Fallen Convoy",
	HEAD_OF_SPEAR = "Head of the Spear",
	SEVER_SIGNAL_TB = "Sever the Signal",
	SEVER_SIGNAL = "Sever the Signal",
	HOLD_THE_LINE = "Hold the Line",
	SHATTERED_AEGIS = "Shattered Aegis",
	SIEGE_BREAKER = "Siege Breaker",
	SILENT_ARCHIVE = "Silent Archive",
	BURN_ARSENAL_FR = "Burn the Arsenal",
	BROKEN_TALON_FR = "Broken Talon",
	LAST_TRANSMISSION = "Last Transmission",
	THRONEFALL = "Thronefall",
	HEAD_OF_SPEAR_WR = "Head of the Spear",
	BURN_ARSENAL = "Burn the Arsenal",
	SIEGE_BREAKER_IM = "Siege Breaker",
	POWER_UNDER_FIRE = "Power Under Fire",
	IRON_FOUNDRY = "Iron Foundry",
	SHATTERED_AEGIS_FB = "Shattered Aegis",
}

return WarOperations
