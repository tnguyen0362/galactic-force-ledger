--!strict
-- Schema + cross-reference validation. Used by GF.Check and at boot.
local Validate = {}

function Validate.isNumberInRange(v: any, min: number, max: number): (boolean, string?)
	if type(v) ~= "number" then return false, "not a number" end
	if v ~= v then return false, "NaN" end
	if v < min or v > max then return false, string.format("%s out of range [%s,%s]", tostring(v), tostring(min), tostring(max)) end
	return true, nil
end

function Validate.requiredFields(entry: { [string]: any }, fields: { string }): (boolean, string?)
	for _, field in fields do
		if entry[field] == nil then return false, "missing field: " .. field end
	end
	return true, nil
end

function Validate.uniqueIds(list: { any }, label: string): (boolean, string?)
	local seen: { [string]: boolean } = {}
	for _, entry in list do
		local id = entry.id
		if type(id) ~= "string" or id == "" then return false, label .. ": entry without id" end
		if seen[id] then return false, label .. ": duplicate id " .. id end
		seen[id] = true
	end
	return true, nil
end

-- Returns ok, errors[]
function Validate.collect(fn: () -> (boolean, string?)): (boolean, { string })
	local ok, err = fn()
	if ok then return true, {} end
	return false, { err or "unknown error" }
end

return Validate

