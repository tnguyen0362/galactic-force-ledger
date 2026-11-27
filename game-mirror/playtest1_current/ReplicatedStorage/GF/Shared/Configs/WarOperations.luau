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

return WarOperations
