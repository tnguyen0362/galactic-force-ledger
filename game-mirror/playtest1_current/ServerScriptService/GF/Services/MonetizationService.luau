--!strict
-- Receipt/entitlement boundary for the prototype shop. No client remote can invoke this module;
-- the only live entry point is MarketplaceService.ProcessReceipt, and the configured product is a
-- disabled placeholder. processTestReceipt is server-only so probes can prove validation, granting,
-- and idempotency without a real platform charge.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.GF.Shared.Configs.Monetization)
local ProfileService = require(script.Parent.ProfileService)
local RequisitionService = require(script.Parent.RequisitionService)

local MonetizationService = {}

local function ensureTables(profile: any)
	profile.entitlements = type(profile.entitlements) == "table" and profile.entitlements or {}
	profile.processedReceipts = type(profile.processedReceipts) == "table" and profile.processedReceipts or {}
	profile.unlockedRequisitions = type(profile.unlockedRequisitions) == "table" and profile.unlockedRequisitions or {}
end

local function normalizeReceipt(receiptInfo: any): (any?, string?)
	if type(receiptInfo) ~= "table" then
		return nil, "receipt must be a table"
	end
	local playerId = tonumber(receiptInfo.PlayerId)
	local productId = tonumber(receiptInfo.ProductId)
	local purchaseId = receiptInfo.PurchaseId
	if type(playerId) ~= "number" or playerId <= 0 then
		return nil, "receipt missing valid PlayerId"
	end
	if type(productId) ~= "number" or productId < 0 then
		return nil, "receipt missing valid ProductId"
	end
	if type(purchaseId) ~= "string" or purchaseId == "" then
		return nil, "receipt missing PurchaseId"
	end
	return {
		playerId = math.floor(playerId),
		productId = math.floor(productId),
		purchaseId = purchaseId,
	}
end

local function result(decision: Enum.ProductPurchaseDecision, ok: boolean, reason: string?, extra: any?)
	local row = extra or {}
	row.decision = decision
	row.ok = ok
	row.reason = reason
	return row
end

-- Access, not receipt provenance: a player who earned Siege Division with War Credits is entitled
-- to the same permanent non-random access as a future approved convenience purchaser.
function MonetizationService.isEntitled(profile: any, entitlementId: string): boolean
	if type(profile) ~= "table" or type(entitlementId) ~= "string" or entitlementId == "" then
		return false
	end
	ensureTables(profile)
	if profile.entitlements[entitlementId] ~= nil then
		return true
	end
	if entitlementId == "SiegeDivision" then
		return RequisitionService.isUnlocked(profile, "SiegeDivision")
	end
	return false
end

function MonetizationService.receiptStatus(profile: any, purchaseId: string): any?
	if type(profile) ~= "table" or type(purchaseId) ~= "string" or purchaseId == "" then
		return nil
	end
	ensureTables(profile)
	return profile.processedReceipts[purchaseId]
end

function MonetizationService.entitlementState(profile: any): { any }
	local rows = {}
	if type(profile) ~= "table" then
		return rows
	end
	ensureTables(profile)
	for _, product in ipairs(Monetization.Products) do
		local record = profile.entitlements[product.entitlement]
		table.insert(rows, {
			productKey = product.id,
			productId = product.productId,
			entitlement = product.entitlement,
			entitled = MonetizationService.isEntitled(profile, product.entitlement),
			recorded = record ~= nil,
			purchaseId = record and record.purchaseId or nil,
			test = record and record.test == true or false,
		})
	end
	return rows
end

local function grantProduct(profile: any, product: any, receipt: any, test: boolean): (boolean, boolean)
	ensureTables(profile)
	if product.kind ~= "requisitionUnlock" or type(product.grantRequisition) ~= "string" then
		return false, false
	end
	local alreadyEntitled = MonetizationService.isEntitled(profile, product.entitlement)
	profile.unlockedRequisitions[product.grantRequisition] = true
	if profile.entitlements[product.entitlement] == nil then
		profile.entitlements[product.entitlement] = {
			productKey = product.id,
			productId = product.productId,
			purchaseId = receipt.purchaseId,
			grantedAt = os.time(),
			test = test,
		}
	end
	return true, alreadyEntitled
end

-- Server-only transaction core. It validates platform-shaped receipt fields before touching the
-- profile, records purchase ids permanently, and treats an already-processed matching receipt as
-- granted without applying the entitlement twice.
function MonetizationService.processReceipt(player: Player, receiptInfo: any, opts: any?): any
	opts = opts or {}
	local test = opts.test == true
	local receipt, receiptError = normalizeReceipt(receiptInfo)
	if not receipt then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, receiptError)
	end
	if receipt.playerId ~= player.UserId then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "receipt player does not match")
	end
	local product = Monetization.productForId(receipt.productId)
	if not product then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "unknown product")
	end
	if product.nonRandom ~= true or product.approvedConvenience ~= true then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "product is not an approved non-random convenience item")
	end
	if not test and (Monetization.LivePaymentsEnabled ~= true or product.enabled ~= true or product.placeholder == true) then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "prototype placeholder product is not enabled for live payment")
	end
	local profile = ProfileService.ensure(player)
	if type(profile) ~= "table" then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "profile unavailable")
	end
	ensureTables(profile)
	local existing = profile.processedReceipts[receipt.purchaseId]
	if existing ~= nil then
		if tonumber(existing.productId) == receipt.productId then
			return result(Enum.ProductPurchaseDecision.PurchaseGranted, true, "receipt already processed", {
				duplicate = true,
				productKey = existing.productKey,
				entitlement = existing.entitlement,
			})
		end
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "purchase id conflict")
	end
	local granted, alreadyEntitled = grantProduct(profile, product, receipt, test)
	if not granted then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "unsupported product grant")
	end
	profile.processedReceipts[receipt.purchaseId] = {
		productKey = product.id,
		productId = product.productId,
		entitlement = product.entitlement,
		processedAt = os.time(),
		test = test,
	}
	ProfileService.recordTransaction(player, "receipt:" .. tostring(receipt.purchaseId))
	ProfileService.markDirty(player)
	ProfileService.saveWithRetry(player)
	workspace:SetAttribute("GF_MonetizationReceipt", string.format("%s:%s:%s", player.Name, product.id, test and "test" or "live"))
	return result(Enum.ProductPurchaseDecision.PurchaseGranted, true, nil, {
		duplicate = false,
		alreadyEntitled = alreadyEntitled,
		productKey = product.id,
		entitlement = product.entitlement,
	})
end

-- Server-only mock receipt helper for Studio/probe verification. It uses the configured placeholder
-- product id and never invokes MarketplaceService or any real payment surface.
function MonetizationService.processTestReceipt(player: Player, purchaseId: string?, productKey: string?): any
	local product = Monetization.get(productKey or "SiegeDivisionAccess")
	if not product then
		return result(Enum.ProductPurchaseDecision.NotProcessedYet, false, "unknown test product")
	end
	return MonetizationService.processReceipt(player, {
		PlayerId = player.UserId,
		ProductId = product.productId,
		PurchaseId = purchaseId or ("TEST-" .. tostring(player.UserId) .. "-" .. tostring(os.time())),
	}, { test = true })
end

function MonetizationService.start()
	if MonetizationService._started then
		return
	end
	MonetizationService._started = true
	local ok, err = pcall(function()
		MarketplaceService.ProcessReceipt = function(receiptInfo)
			local playerId = tonumber(receiptInfo and receiptInfo.PlayerId) or 0
			local player = Players:GetPlayerByUserId(playerId)
			if not player then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			local okProcess, processed = pcall(function()
				return MonetizationService.processReceipt(player, receiptInfo, { test = false })
			end)
			if okProcess and type(processed) == "table" and processed.decision then
				return processed.decision
			end
			warn("[GF] receipt processing failed: " .. tostring(processed))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end)
	if not ok then
		warn("[GF] ProcessReceipt binding failed: " .. tostring(err))
	end
end

return MonetizationService
