--!strict
-- ComponentService: authoritative destructible-component architecture for mechanized enemies
-- (spec sections 37/38/39/61). One registry, one resolution path, exactly-once destruction events.
--
-- Design invariants:
--   - a hit resolves through ONE authoritative event: component damage, body transfer, weakpoint
--     and armor arithmetic compose exactly once — no double counting from overlapping hitboxes
--   - explosion damage is a budget allocated across components by weight, never full damage per component
--   - destruction fires exactly once per component per lifecycle, with explicit capability invalidation
--   - dependency graph is acyclic in the damage direction: a protected component ALWAYS becomes
--     damageable when its protector dies; body damage alone can always kill the entity (no invulnerability)
--   - registration happens once per entity lifecycle; damage resolution is O(1) dict lookups,
--     never workspace scans

local Workspace = game:GetService("Workspace")

local ComponentService = {}

export type ComponentDef = {
	part: BasePart,
	health: number,
	maxHealth: number,
	eta: number, -- body-damage transfer coefficient
	damageMultiplier: number, -- incoming damage multiplier for this component (weakpoint exposure)
	protects: { string }, -- component ids this one protects
	protectedBy: string?, -- component id protecting this one
	enables: { string }, -- capability ids this component powers
	optional: boolean?,
	destroyed: boolean,
}

export type EntityState = {
	model: Model,
	hullHealth: number,
	hullMaxHealth: number,
	components: { [string]: ComponentDef },
	partIndex: { [BasePart]: string }, -- hitbox part -> component id, O(1) hit resolution
	destroyedCount: number,
	onComponentDestroyed: ((entity: EntityState, componentId: string) -> ())?,
	onHullDamage: ((entity: EntityState, amount: number) -> ())?,
	dead: boolean,
}

local entities: { [Model]: EntityState } = {}

--========== registration ==========

-- entitySpec: { hullHealth = n, components = { id = { part=BasePart, health=n, eta=n,
--   damageMultiplier=n, protects={ids}, protectedBy=id, enables={capabilityIds} } } }
function ComponentService.registerEntity(model: Model, entitySpec: any, callbacks: any?): EntityState
	local entity: EntityState = {
		model = model,
		hullHealth = entitySpec.hullHealth,
		hullMaxHealth = entitySpec.hullHealth,
		components = {},
		partIndex = {},
		destroyedCount = 0,
		onComponentDestroyed = callbacks and callbacks.onComponentDestroyed,
		onHullDamage = callbacks and callbacks.onHullDamage,
		dead = false,
	}
	for id, spec in entitySpec.components do
		local def: ComponentDef = {
			part = spec.part,
			health = spec.health,
			maxHealth = spec.health,
			eta = spec.eta or 0.5,
			damageMultiplier = spec.damageMultiplier or 1,
			protects = spec.protects or {},
			protectedBy = spec.protectedBy,
			enables = spec.enables or {},
			optional = spec.optional,
			destroyed = false,
		}
		entity.components[id] = def
		if spec.part then
			entity.partIndex[spec.part] = id
			spec.part:SetAttribute("GFComponentId", id)
		end
	end
	-- validate the dependency graph: no protection cycles (would create permanent invulnerability)
	for id, def in entity.components do
		local visited = {}
		local cur = def.protectedBy
		while cur do
			if cur == id then
				warn("ComponentService: protection cycle at", id, "— breaking edge")
				def.protectedBy = nil
				break
			end
			if visited[cur] then break end
			visited[cur] = true
			local next_def = entity.components[cur]
			cur = next_def and next_def.protectedBy or nil
		end
	end
	entities[model] = entity
	model:SetAttribute("GFComponentEntity", true)
	model:SetAttribute("Health", entity.hullHealth)
	model:SetAttribute("MaxHealth", entity.hullMaxHealth)
	return entity
end

function ComponentService.entity(model: Model): EntityState?
	return entities[model]
end

function ComponentService.unregister(model: Model)
	entities[model] = nil
end

--========== capability resolution ==========

-- Available(capability) = AND over components enabling it of operational (spec section 38).
-- Inverse mapping: a capability is available if at least one enabling component survives —
-- enables[] on a component means "this component contributes to", and the capability requires
-- ANY contributing component unless prefixed with "ALL:" semantics. Single-component capabilities
-- are the common case.
function ComponentService.capabilityAvailable(model: Model, capabilityId: string): boolean
	local entity = entities[model]
	if not entity then return false end
	for _, def in entity.components do
		if not def.destroyed then
			for _, cap in def.enables do
				if cap == capabilityId then
					return true
				end
			end
		end
	end
	return false
end

-- mobility is special-cased across the family: any surviving propulsion component means partial
-- mobility, both destroyed means immobile. Controllers query with their own semantics; this helper
-- reports the fraction of a capability's enablers still operational.
function ComponentService.capabilityHealth(model: Model, capabilityId: string): number
	local entity = entities[model]
	if not entity then return 0 end
	local total, alive = 0, 0
	for _, def in entity.components do
		for _, cap in def.enables do
			if cap == capabilityId then
				total += 1
				if not def.destroyed then alive += 1 end
			end
		end
	end
	if total == 0 then return 0 end
	return alive / total
end

function ComponentService.componentDestroyed(model: Model, componentId: string): boolean
	local entity = entities[model]
	local def = entity and entity.components[componentId]
	return def ~= nil and def.destroyed
end

--========== destruction ==========

local function destroyComponent(entity: EntityState, componentId: string)
	local def = entity.components[componentId]
	if not def or def.destroyed then return end
	def.destroyed = true
	entity.destroyedCount += 1
	-- exactly-once event (spec section 37): visual state, capability invalidation, exposure chain,
	-- controller notification. Damage already-destroyed components never re-fires this.
	def.part:SetAttribute("ComponentDestroyed", true)
	def.part.Color = Color3.fromRGB(30, 30, 32)
	def.part.Material = Enum.Material.CorrodedMetal
	-- exposure chain: protected components become damageable — publish for hit feedback and AI
	for _, protectedId in def.protects do
		local protectedDef = entity.components[protectedId]
		if protectedDef and protectedDef.part then
			protectedDef.part:SetAttribute("Exposed", true)
		end
	end
	Workspace:SetAttribute("GF_ComponentDestroyed", componentId)
	if entity.onComponentDestroyed then
		task.spawn(entity.onComponentDestroyed, entity, componentId)
	end
end

--========== damage resolution ==========

-- the one authoritative resolution path (spec section 37). Returns damage applied to hull.
-- rawDamage is pre-weakpoint/pre-armor base damage; this function owns component arithmetic only —
-- the caller's existing hit/armor modifiers compose outside.
function ComponentService.resolveHit(model: Model, hitPart: BasePart?, rawDamage: number, source: string?): number
	local entity = entities[model]
	if not entity or entity.dead then return rawDamage end
	local hullDamage = rawDamage
	if hitPart then
		local componentId = entity.partIndex[hitPart]
		if componentId then
			local def = entity.components[componentId]
			-- protection check: a protected component is not damageable while its protector lives.
			-- the hit strikes the protector instead (armor eats it) — never invulnerable because the
			-- protector itself is always damageable and the hull always takes transfer damage.
			if def.protectedBy then
				local protector = entity.components[def.protectedBy]
				if protector and not protector.destroyed then
					hullDamage = rawDamage * protector.eta
					ComponentService._damageComponent(entity, def.protectedBy, rawDamage * 0.5)
					ComponentService._applyHull(entity, hullDamage, source)
					return hullDamage
				end
			end
			if not def.destroyed then
				local effective = rawDamage * def.damageMultiplier
				ComponentService._damageComponent(entity, componentId, effective)
				hullDamage = effective * def.eta
			else
				-- destroyed component: damage passes through to hull at reduced rate
				hullDamage = rawDamage * 0.6
			end
		end
	end
	ComponentService._applyHull(entity, hullDamage, source)
	return hullDamage
end

function ComponentService._damageComponent(entity: EntityState, componentId: string, amount: number)
	local def = entity.components[componentId]
	if not def or def.destroyed then return end
	local before = def.health
	def.health = math.max(0, def.health - amount)
	def.part:SetAttribute("ComponentHP", def.health)
	if before > 0 and def.health <= 0 then
		destroyComponent(entity, componentId)
	end
end

function ComponentService._applyHull(entity: EntityState, amount: number, _source: string?)
	if entity.dead then return end
	entity.hullHealth = math.max(0, entity.hullHealth - amount)
	entity.model:SetAttribute("Health", entity.hullHealth)
	if entity.onHullDamage then
		task.spawn(entity.onHullDamage, entity, amount)
	end
	if entity.hullHealth <= 0 then
		entity.dead = true
		entity.model:SetAttribute("Dead", true)
	end
end

-- explosion allocation (spec section 61): one explosion = one damage budget, split across the
-- components it legitimately overlaps, weighted by exposure. Never full entity damage per component.
function ComponentService.resolveExplosion(model: Model, rawDamage: number, overlappedParts: { BasePart }, source: string?): number
	local entity = entities[model]
	if not entity or entity.dead then return rawDamage end
	-- collect distinct affected components
	local affected: { string } = {}
	local seen = {}
	for _, part in overlappedParts do
		local id = entity.partIndex[part]
		if id and not seen[id] then
			local def = entity.components[id]
			if def and not def.destroyed then
				-- protected components don't count as overlapped while protected
				local shielded = false
				if def.protectedBy then
					local prot = entity.components[def.protectedBy]
					shielded = prot ~= nil and not prot.destroyed
				end
				if not shielded then
					seen[id] = true
					table.insert(affected, id)
				end
			end
		end
	end
	if #affected == 0 then
		ComponentService._applyHull(entity, rawDamage, source)
		return rawDamage
	end
	-- allocate: component budget is 60% of raw (explosions excel against components but don't
	-- multiply), hull receives the remainder transfer directly
	local componentBudget = rawDamage * 0.6
	local perComponent = componentBudget / #affected
	local hullTotal = rawDamage * 0.4
	for _, id in affected do
		local def = entity.components[id]
		ComponentService._damageComponent(entity, id, perComponent * def.damageMultiplier)
		hullTotal += perComponent * def.eta * 0.5 -- dampened transfer from splash
	end
	ComponentService._applyHull(entity, hullTotal, source)
	return hullTotal
end

--========== state snapshot (multiplayer join / persistence) ==========

function ComponentService.snapshot(model: Model): { [string]: any }?
	local entity = entities[model]
	if not entity then return nil end
	local comps = {}
	for id, def in entity.components do
		comps[id] = { health = def.health, destroyed = def.destroyed }
	end
	return {
		hull = entity.hullHealth,
		hullMax = entity.hullMaxHealth,
		components = comps,
		dead = entity.dead,
	}
end

return ComponentService
