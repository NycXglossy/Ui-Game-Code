-- CeilingFXScript: publishes authoritative full-floor bounds from the server-owned panel layout.
-- PixelMatrixFX (StarterPlayerScripts) owns all per-client panel color animation.
-- Clients must not infer the complete dance-floor bounds from streamed-in panel subsets.

local folder = workspace:WaitForChild("CeilingFX")
folder:SetAttribute("ClientMatrixChoreography", true)

local floorCount, ceilingCount = 0, 0
local minX, maxX, minZ, maxZ, floorY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
for _, item in ipairs(folder:GetChildren()) do
	if item:IsA("BasePart") then
		if item.Name == "FloorPanel" then
			floorCount += 1
			local p = item.Position
			minX = math.min(minX, p.X)
			maxX = math.max(maxX, p.X)
			minZ = math.min(minZ, p.Z)
			maxZ = math.max(maxZ, p.Z)
			floorY = math.max(floorY, p.Y)
		end
		if item.Name == "CeilingPanel" then ceilingCount += 1 end
	end
end

if floorCount > 0 and minX < maxX and minZ < maxZ then
	folder:SetAttribute("FloorBoundsMinX", minX)
	folder:SetAttribute("FloorBoundsMaxX", maxX)
	folder:SetAttribute("FloorBoundsMinZ", minZ)
	folder:SetAttribute("FloorBoundsMaxZ", maxZ)
	folder:SetAttribute("FloorBoundsY", floorY)
	folder:SetAttribute("FloorPanelCount", floorCount)
	folder:SetAttribute("FloorBoundsReady", true)
else
	folder:SetAttribute("FloorBoundsReady", false)
	warn("[ClubNeon][CeilingFXScript] Could not publish authoritative floor bounds; valid FloorPanel layout was not found.")
end

print("[ClubNeon][CeilingFXScript] Replicated panel layout ready; client-local matrix owns animation. floor="
	.. floorCount .. " ceiling=" .. ceilingCount .. " authoritativeBounds="
	.. tostring(folder:GetAttribute("FloorBoundsReady")))
