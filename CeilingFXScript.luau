-- CeilingFXScript: server-side marker for the existing replicated floor/ceiling panel layout.
-- PixelMatrixFX (StarterPlayerScripts) owns all per-client panel color animation.
-- Keeping this server Script avoids competing replicated color writes and server churn.

local folder = workspace:WaitForChild("CeilingFX")
folder:SetAttribute("ClientMatrixChoreography", true)

local floorCount, ceilingCount = 0, 0
for _, item in ipairs(folder:GetChildren()) do
	if item:IsA("BasePart") then
		if item.Name == "FloorPanel" then floorCount += 1 end
		if item.Name == "CeilingPanel" then ceilingCount += 1 end
	end
end
print("[ClubNeon][CeilingFXScript] Replicated panel layout ready; client-local matrix owns animation. floor="
	.. floorCount .. " ceiling=" .. ceilingCount)
