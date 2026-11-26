--!strict
-- AugmentResolver: canonical modifier algebra implementation (MODIFIER_ALGEBRA.md).
-- Server-authoritative effective-stat resolution. Mirrors augment_core.py exactly.
-- Resolution timing per spec §94: resolve on equip/migration/conditional-state change; cache.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AugmentTraits = require(ReplicatedStorage.GF.Shared.Configs.AugmentTraits)

local Stats = AugmentTraits.Stats
local Traits = AugmentTraits.Traits

local AugmentResolver = {}

-- Steps 2-3: deterministic conflict resolution, then additive aggregation with coupled atomicity.
-- Conflict ordering: |value| desc, traitId asc — first member per group wins, rest inert.
function AugmentResolver.aggregateStats(traitRows: { any }): ({ [string]: number }, { string })
	local sorted = table.create(#traitRows)
	for _, row in traitRows do
		table.insert(sorted, row)
	end
	table.sort(sorted, function(a, b)
		local av, bv = math.abs(a.value or 0), math.abs(b.value or 0)
		if av ~= bv then
			return av > bv
		end
		return tostring(a.traitId) < tostring(b.traitId)
	end)
	local groupSeen = {}
	local active = {}
	for _, row in sorted do
		local tdef = Traits[row.traitId]
		local grp = tdef and tdef.conflictGroup
		local skip = false
		if grp then
			if groupSeen[grp] then
				skip = true
			else
				groupSeen[grp] = true
			end
		end
		if not skip then
			table.insert(active, row)
		end
	end
	local out = {}
	for _, row in active do
		local stat = row.key
		if type(stat) == "string" and type(row.value) == "number" and row.value == row.value then
			out[stat] = (out[stat] or 0) + row.value
			local coupled = row.coupled
			if type(coupled) == "table" and type(coupled.drawbackStat) == "string" then
				local ratio = tonumber(coupled.drawbackRatio) or 0
				out[coupled.drawbackStat] = (out[coupled.drawbackStat] or 0) + row.value * ratio
			end
		end
	end
	local activeIds = {}
	for _, row in active do
		table.insert(activeIds, row.traitId)
	end
	return out, activeIds
end

-- Steps 4-9: transform -> clamp -> domain guardrail -> quantize-last.
-- base: table of base weapon stats; statSums from aggregateStats.
function AugmentResolver.resolveWeapon(base: { [string]: number }, statSums: { [string]: number }): { [string]: number }
	local eff = {}
	for k, v in base do
		eff[k] = v
	end
	for stat, summed in statSums do
		local sdef = Stats[stat]
		if sdef and base[stat] ~= nil then
			local x0 = base[stat]
			local cap = sdef.cap
			local s
			if sdef.signed then
				s = math.clamp(summed, -cap, cap)
			else
				s = math.clamp(summed, 0, cap)
			end
			local x
			if sdef.transform == "rateSpeed" then
				x = x0 / (1 + s)
			elseif sdef.inverseBenefit then
				x = x0 * (1 - s)
			else
				x = x0 * (1 + s)
			end
			-- domain guardrail: multiplicative stats bounded to [20%, 200%] of base
			x = math.max(x0 * 0.2, math.min(x0 * 2.0, x))
			if sdef.quantization == "nearest" then
				x = math.max(1, math.floor(x + 0.5))
			end
			eff[stat] = x
		end
	end
	return eff
end

-- Convenience: full pipeline from trait rows to effective stats.
function AugmentResolver.resolve(base: { [string]: number }, traitRows: { any }): ({ [string]: number }, { string })
	local sums, activeIds = AugmentResolver.aggregateStats(traitRows)
	return AugmentResolver.resolveWeapon(base, sums), activeIds
end

return AugmentResolver
