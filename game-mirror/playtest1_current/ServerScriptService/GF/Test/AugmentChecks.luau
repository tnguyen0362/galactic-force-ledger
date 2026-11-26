--!strict
-- GF.Test.AugmentChecks: verification battery for the augment v2 program.
-- Covers socket migration, per-weapon resolution, clamps, generator statistics,
-- resolver algebra, and legacy lifecycle integrity. Interface-verified against the
-- committed modules. Run: require(game.ServerScriptService.GF.Test.AugmentChecks).run()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.GF.Services
local AugmentService = require(Services.AugmentService)
local AugmentGenerator = require(Services.AugmentGenerator)
local AugmentResolver = require(Services.AugmentResolver)
local AugmentTraits = require(ReplicatedStorage.GF.Shared.Configs.AugmentTraits)

local AugmentChecks = {}

local errors: { string } = {}
local passed = 0

local function ok(condition: boolean, message: string)
	if condition then
		passed += 1
	else
		table.insert(errors, message)
	end
end

local function approx(a: number, b: number, eps: number): boolean
	return math.abs(a - b) <= eps
end

local function syntheticProfile()
	return {
		augmentItems = {
			{ uid = "u1", archetypeId = "legacy-x", traits = { { key = "healthDamage", value = 0.05 } } },
			{ uid = "u2", archetypeId = "legacy-y", traits = { { key = "fireRate", value = 0.5 } } },
		},
		augmentInventory = {},
		weaponMastery = { AR01 = 700, P01 = 700 },
		ownedWeapons = { AR01 = true, P01 = true },
		selectedLoadout = {
			primary = "AR01",
			secondary = "P01",
			weaponAugments = {},
		},
		savedLoadouts = {},
	}
end

local TEST_DEFINITION = { definitionId = "TEST_DEF" }

function AugmentChecks.run()
	errors = {}
	passed = 0

	-- 1. legacy socket migration is lossless ---------------------------------
	local profile = syntheticProfile()
	profile.selectedLoadout.weaponAugments = { [1] = "u1", [2] = "u2" }
	AugmentService.migrateSockets(profile)
	local wa = profile.selectedLoadout.weaponAugments
	ok(wa[1] == nil and wa[2] == nil, "migration: numeric keys must be cleared")
	ok(type(wa.AR01) == "table", "migration: primary weapon table must exist")
	if type(wa.AR01) == "table" then
		ok(wa.AR01[1] == "u1" and wa.AR01[2] == "u2", "migration: refs rehomed losslessly under primary")
	end

	-- 2. per-weapon resolution isolates sockets -------------------------------
	local ar = AugmentService.forProfileWeapon(profile, "AR01")
	local pi = AugmentService.forProfileWeapon(profile, "P01")
	ok((ar.healthDamage or 0) > 0, "resolution: AR01 socket trait present for AR01")
	ok((pi.healthDamage or 0) == 0, "resolution: AR01 socket trait absent for P01")

	-- 3. clamps engage: fireRate 0.5 must clamp to the signed cap 0.12 ---------
	ok(approx(ar.fireRate or 0, 0.12, 1e-6), "resolution: fireRate must clamp to +0.12, got " .. tostring(ar.fireRate))

	-- 4. registry integrity ----------------------------------------------------
	local traitCount = 0
	local families: { [string]: number } = {}
	for id, def in pairs(AugmentTraits.Traits) do
		traitCount += 1
		families[def.family] = (families[def.family] or 0) + 1
		ok(type(def.stat) == "string" and def.stat ~= "", "registry: trait " .. id .. " missing stat")
		ok(type(def.bands) == "table" and def.bands.C ~= nil, "registry: trait " .. id .. " missing bands")
	end
	ok(traitCount == 30, "registry: expected 30 traits, got " .. traitCount)
	local familyCount = 0
	for _ in pairs(families) do
		familyCount += 1
	end
	ok(familyCount == 6, "registry: expected 6 families, got " .. familyCount)

	-- 5. generator statistics: exact counts, no duplicates (200 per rarity) -----
	local EXPECT = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
	for rarity, want in pairs(EXPECT) do
		local countViolations = 0
		local dupeViolations = 0
		for _ = 1, 200 do
			local item = AugmentGenerator.generateItem(TEST_DEFINITION, rarity, "Rifle")
			if #item.traits ~= want then
				countViolations += 1
			end
			local seen: { [string]: boolean } = {}
			for _, trait in ipairs(item.traits) do
				if seen[trait.traitId] then
					dupeViolations += 1
				end
				seen[trait.traitId] = true
			end
		end
		ok(countViolations == 0, "generator: " .. rarity .. " count violations " .. countViolations .. "/200")
		ok(dupeViolations == 0, "generator: " .. rarity .. " duplicate violations " .. dupeViolations .. "/200")
	end

	-- 6. coupled packages carry atomic drawback specs ---------------------------
	local coupledSeen = 0
	local shapeViolations = 0
	for _ = 1, 300 do
		local item = AugmentGenerator.generateItem(TEST_DEFINITION, "Legendary", "Rifle")
		for _, trait in ipairs(item.traits) do
			if trait.coupled ~= nil then
				coupledSeen += 1
				if type(trait.coupled.drawbackStat) ~= "string" or type(trait.coupled.drawbackRatio) ~= "number" then
					shapeViolations += 1
				end
			end
		end
	end
	ok(coupledSeen > 0, "generator: no coupled experimental rolls in 300 legendary items (pool suspect)")
	ok(shapeViolations == 0, "generator: coupled shape violations " .. shapeViolations)

	-- 7. resolver algebra: reload as rate division ------------------------------
	local resolved = AugmentResolver.resolve({ reloadSpeed = 2.2 }, {
		{ traitId = "T1", key = "reloadSpeed", value = 0.25 },
	})
	ok(approx(resolved.reloadSpeed or 0, 2.2 / 1.25, 1e-4), "resolver: rate division 2.2/1.25=1.76, got " .. tostring(resolved.reloadSpeed))

	-- 8. resolver magazine quantization ------------------------------------------
	local resolved2 = AugmentResolver.resolve({ magazine = 28 }, {
		{ traitId = "T1", key = "magazine", value = 0.2 },
	})
	ok(resolved2.magazine == 34, "resolver: magazine 28x1.2 must quantize to 34, got " .. tostring(resolved2.magazine))

	-- 9. conflict-group resolution keeps the larger magnitude --------------------
	-- TR_DAMAGE and TR_CLOSEDMG share conflict group damage_core: only the larger applies.
	local sums = AugmentResolver.aggregateStats({
		{ traitId = "TR_CLOSEDMG", key = "healthDamage", value = 0.05 },
		{ traitId = "TR_DAMAGE", key = "healthDamage", value = 0.12 },
	})
	ok(approx(sums.healthDamage or 0, 0.12, 1e-6), "resolver: conflict group keeps larger, got " .. tostring(sums.healthDamage))

	-- 10. coupled drawback atomicity in aggregation -------------------------------
	local sums2 = AugmentResolver.aggregateStats({
		{ traitId = "TR_EXP_GLASSCANNON", key = "healthDamage", value = 0.10, coupled = { drawbackStat = "fireRate", drawbackRatio = -0.6 } },
	})
	ok(approx(sums2.fireRate or 0, -0.06, 1e-6), "resolver: coupled drawback 0.10x-0.6=-0.06, got " .. tostring(sums2.fireRate))

	-- 11. legacy lifecycle: protection by uid --------------------------------------
	local profile2 = syntheticProfile()
	profile2.selectedLoadout.weaponAugments = { AR01 = { [1] = "u1" } }
	profile2.augmentItems[1].favorite = true
	ok(AugmentService.isProtected(profile2, "u1") == true, "lifecycle: favorited+equipped uid must be protected")
	ok(AugmentService.isProtected(profile2, "u2") == false, "lifecycle: unequipped unfavorited uid must not be protected")

	print(string.format("[AugmentChecks] passed=%d errors=%d", passed, #errors))
	for _, message in errors do
		warn("[AugmentChecks] FAIL: " .. message)
	end
	return passed, errors
end

return AugmentChecks
