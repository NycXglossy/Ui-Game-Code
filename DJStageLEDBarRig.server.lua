--!strict
-- DJStageLEDBarRig: server-owned geometry for the dual-script DJ booth LED bar system.
-- The client controller animates these replicated segments using ClubAudioSync.
-- Add a Part named DJStageLEDBarAnchor behind the DJ booth and orient its LookVector
-- toward the audience. The bars are built behind it (local -Z). A Model named DJBooth
-- is accepted as a fallback; its pivot LookVector is treated as audience-facing.

local Workspace = game:GetService("Workspace")

local RIG_NAME = "DJStageLEDBarRig"
local ANCHOR_NAME = "DJStageLEDBarAnchor"

local function findAnchor(): (CFrame?, Vector3?, string?)
	local explicit = Workspace:FindFirstChild(ANCHOR_NAME, true)
	if explicit and explicit:IsA("BasePart") then
		return explicit.CFrame, explicit.Size, explicit:GetFullName()
	end

	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("Model") and item.Name == "DJBooth" then
			local ok, boxCFrame, boxSize = pcall(function()
					local cf, size = item:GetBoundingBox()
					return cf, size
				end)
			if ok then return boxCFrame, boxSize, item:GetFullName() end
		end
	end
	return nil, nil, nil
end

local oldRig = Workspace:FindFirstChild(RIG_NAME)
if oldRig then oldRig:Destroy() end

local anchorCFrame, anchorSize, anchorPath = findAnchor()
if not anchorCFrame or not anchorSize then
	warn("[ClubNeon][DJStageLEDBarRig] No DJStageLEDBarAnchor or exact DJBooth model found. Add a Part named DJStageLEDBarAnchor behind the booth, facing the audience. No rig was created.")
	return
end

local rig = Instance.new("Folder")
rig.Name = RIG_NAME
rig:SetAttribute("Ready", false)
rig:SetAttribute("AnchorSource", anchorPath or "unknown")
rig.Parent = Workspace

local width = math.clamp(math.max(anchorSize.X, 12) + 4, 12, 32)
local barDepth = math.clamp(anchorSize.Z * 0.25, 0.5, 2)
local rearOffset = anchorSize.Z * 0.5 + 3
local baseY = math.max(2.5, anchorSize.Y * 0.5 + 2)
local horizontalRows = 3
local horizontalCount = 12
local verticalCount = 8

local function makeSegment(name: string, localCFrame: CFrame, size: Vector3, row: number, index: number, orientation: string)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(40, 180, 255)
	part.Transparency = 0.82
	part.CFrame = anchorCFrame * CFrame.new(0, 0, -rearOffset) * localCFrame
	part:SetAttribute("BarOrientation", orientation)
	part:SetAttribute("BarRow", row)
	part:SetAttribute("BarIndex", index)
	part.Parent = rig
end

-- Three horizontal pixel bars span the DJ backdrop.
for row = 1, horizontalRows do
	local y = baseY + (row - 1) * 2.15
	for index = 1, horizontalCount do
		local x = -width * 0.5 + (index - 0.5) * (width / horizontalCount)
		makeSegment(
			"HBar_R" .. row .. "_S" .. index,
			CFrame.new(x, y, 0),
			Vector3.new(width / horizontalCount * 0.82, 0.42, barDepth),
			row, index, "Horizontal"
		)
	end
end

-- Two vertical pixel bars frame the horizontal array.
for side = 1, 2 do
	local x = (side == 1 and -1 or 1) * (width * 0.5 + 0.65)
	for index = 1, verticalCount do
		local y = baseY - 0.7 + (index - 0.5) * 1.25
		makeSegment(
			"VBar_S" .. side .. "_S" .. index,
			CFrame.new(x, y, 0),
			Vector3.new(0.48, 0.92, barDepth),
			 side, index, "Vertical"
		)
	end
end

rig:SetAttribute("HorizontalBars", horizontalRows)
rig:SetAttribute("HorizontalSegmentsPerBar", horizontalCount)
rig:SetAttribute("VerticalBars", 2)
rig:SetAttribute("VerticalSegmentsPerBar", verticalCount)
rig:SetAttribute("SegmentCount", horizontalRows * horizontalCount + 2 * verticalCount)
rig:SetAttribute("Ready", true)

print("[ClubNeon][DJStageLEDBarRig] Ready; horizontal=3x12 vertical=2x8 segments="
	.. tostring(rig:GetAttribute("SegmentCount")) .. " anchor=" .. tostring(anchorPath))
