--!strict
local Lighting = game:GetService("Lighting")
local UserSettings = game:GetService("UserSettings")
local level = 8
local ok = pcall(function()
	level = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
end)
local forced = workspace:GetAttribute("Vista_ForceLevel")
if forced then level = forced end
workspace:SetAttribute("Vista_Level", level)
workspace:SetAttribute("Vista_Readable", ok)
local station = workspace:FindFirstChild("Station")
for _ = 1, 30 do
	if station then break end
	task.wait(0.2)
	station = workspace:FindFirstChild("Station")
end
workspace:SetAttribute("Vista_StationFound", station ~= nil)
local total, visible = 0, 0
if station then
	for _, d in ipairs(station:GetDescendants()) do
		if d.Name == "VistaStar" then
			total = total + 1
			if level <= 3 and total % 3 ~= 0 then d.Transparency = 1 else visible = visible + 1 end
		elseif d.Name == "Veyra7Atmo" then
			d.Transparency = (level <= 3) and 0.55 or d.Transparency
			workspace:SetAttribute("Vista_LimbHeld", true)
		end
	end
end
workspace:SetAttribute("Vista_StarsTotal", total)
workspace:SetAttribute("Vista_StarsVisible", visible)
local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
if atmo and level <= 4 then atmo.Density = atmo.Density * 0.55 end
workspace:SetAttribute("Vista_AtmoScaled", (atmo ~= nil) and level <= 4)
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if bloom and level <= 2 then bloom.Intensity = 0 end
workspace:SetAttribute("Vista_BloomOff", (bloom ~= nil) and level <= 2)
