--!strict
-- UtilityBarExtendedActions.server.lua
-- Install as a Script in ServerScriptService. Independent from ClubMusic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_FOLDER = "UtilityBarRemotes"
local REMOTE_NAME = "ExecuteUtility"
local COOLDOWN = 1.25
local CLONE_LIFETIME = 12
local lastRequest: {[number]: number} = {}
local sizeStep: {[number]: number} = {}
local sizeBaseline: {[number]: {humanoid: Humanoid, height: number, width: number, depth: number, head: number}} = {}
local auraByPlayer: {[number]: Highlight} = {}

local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER)
if folder and not folder:IsA("Folder") then folder:Destroy(); folder = nil end
if not folder then
	folder = Instance.new("Folder")
	folder.Name = REMOTE_FOLDER
	folder.Parent = ReplicatedStorage
end
local remote = folder:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteFunction") then remote:Destroy(); remote = nil end
if not remote then
	local created = Instance.new("RemoteFunction")
	created.Name = REMOTE_NAME
	created.Parent = folder
	remote = created
end
local execute = remote :: RemoteFunction

local function getCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return nil, nil end
	return character, humanoid
end

local function setSize(player: Player, requestedFactor: any): (boolean, string)
	if typeof(requestedFactor) ~= "number" or requestedFactor ~= requestedFactor then
		return false, "Choose a valid character size."
	end
	local factor = math.clamp(requestedFactor, 0.65, 1.35)
	local character, humanoid = getCharacter(player)
	if not character or not humanoid then return false, "Your character is not ready." end
	local height = humanoid:FindFirstChild("BodyHeightScale")
	local width = humanoid:FindFirstChild("BodyWidthScale")
	local depth = humanoid:FindFirstChild("BodyDepthScale")
	local head = humanoid:FindFirstChild("HeadScale")
	if not (height and width and depth and head)
		or not (height:IsA("NumberValue") and width:IsA("NumberValue")
			and depth:IsA("NumberValue") and head:IsA("NumberValue")) then
		return false, "Adjustable size requires an R15 avatar."
	end
	local baseline = sizeBaseline[player.UserId]
	if not baseline or baseline.humanoid ~= humanoid then
		baseline = {humanoid=humanoid,height=height.Value,width=width.Value,depth=depth.Value,head=head.Value}
		sizeBaseline[player.UserId] = baseline
	end
	height.Value = math.clamp(baseline.height * factor, 0.5, 1.5)
	width.Value = math.clamp(baseline.width * factor, 0.5, 1.5)
	depth.Value = math.clamp(baseline.depth * factor, 0.5, 1.5)
	head.Value = math.clamp(baseline.head * factor, 0.5, 1.5)
	return true, string.format("Character size set to %d%%.", math.floor(factor * 100 + 0.5))
end

local function toggleMount(player: Player): (boolean, string)
	local character, humanoid = getCharacter(player)
	if not character or not humanoid then return false, "Your character is not ready." end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local mountTool: Tool? = nil
	for _, container in ipairs({character, backpack}) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and (item:GetAttribute("UtilityMount") == true
					or item.Name == "Mount" or item.Name == "MountTool") then
					mountTool = item
					break
				end
			end
		end
		if mountTool then break end
	end
	if not mountTool then
		return false, "Mount is ready for a mount Tool. Add a Tool named Mount or set UtilityMount=true."
	end
	if mountTool.Parent == character then
		humanoid:UnequipTools()
		return true, "Mount tool unequipped."
	end
	humanoid:EquipTool(mountTool)
	return true, "Mount tool equipped."
end

local function createClone(player: Player): (boolean, string)
	local character = player.Character
	if not character or not character.Parent then return false, "Your character is not ready." end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false, "Character root is unavailable." end
	local old = workspace:FindFirstChild("UtilityClone_" .. player.UserId)
	if old then old:Destroy() end
	local ok, clone = pcall(function() return character:Clone() end)
	if not ok or not clone then return false, "Roblox could not create the clone." end
	clone.Name = "UtilityClone_" .. player.UserId
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	if cloneRoot and cloneRoot:IsA("BasePart") then
		cloneRoot.Anchored = true
		clone:PivotTo(root.CFrame * CFrame.new(4, 0, 0))
	end
	local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
	if cloneHumanoid then
		cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		cloneHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	clone.Parent = workspace
	task.delay(CLONE_LIFETIME, function()
		if clone.Parent then clone:Destroy() end
	end)
	return true, "Temporary character clone created for 12 seconds."
end

local function setAura(player: Player, preset: any): (boolean, string)
	if typeof(preset) ~= "string" then return false, "Choose an aura style." end
	local styles = {
		["Teal Glow"] = {fill=Color3.fromRGB(75, 190, 196), outline=Color3.fromRGB(119, 224, 224)},
		["Royal Gold"] = {fill=Color3.fromRGB(190, 139, 55), outline=Color3.fromRGB(255, 218, 145)},
		["Tiki Tide"] = {fill=Color3.fromRGB(119, 196, 203), outline=Color3.fromRGB(226, 194, 132)},
	}
	local style = styles[preset]
	if not style then return false, "That aura style is not available." end
	local character = player.Character
	if not character or not character.Parent then return false, "Your character is not ready." end
	local highlight = auraByPlayer[player.UserId]
	if highlight and highlight.Parent then highlight:Destroy() end
	highlight = Instance.new("Highlight")
	highlight.Name = "UtilityAura"
	highlight.Adornee = character
	highlight.FillColor = style.fill
	highlight.OutlineColor = style.outline
	highlight.FillTransparency = 0.78
	highlight.OutlineTransparency = 0.12
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	auraByPlayer[player.UserId] = highlight
	return true, preset .. " aura applied."
end

execute.OnServerInvoke = function(player: Player, actionName: any, value: any): (boolean, string)
	if typeof(actionName) ~= "string" then return false, "Invalid utility request." end
	local allowed = actionName == "Mount" or actionName == "Size"
		or actionName == "Clone" or actionName == "Aura"
	if not allowed then return false, "This utility action is not available." end
	local now = os.clock()
	if now - (lastRequest[player.UserId] or 0) < COOLDOWN then
		return false, "Please wait before using another utility."
	end
	lastRequest[player.UserId] = now
	if actionName == "Mount" then return toggleMount(player) end
	if actionName == "Size" then return setSize(player, value) end
	if actionName == "Clone" then return createClone(player) end
	return setAura(player, value)
end


Players.PlayerRemoving:Connect(function(player)
	lastRequest[player.UserId] = nil
	sizeStep[player.UserId] = nil
	sizeBaseline[player.UserId] = nil
	local aura = auraByPlayer[player.UserId]
	if aura then aura:Destroy() end
	auraByPlayer[player.UserId] = nil
	local clone = workspace:FindFirstChild("UtilityClone_" .. player.UserId)
	if clone then clone:Destroy() end
end)

print("[UtilityBar] Extended Mount, Size, Clone, and Aura actions ready.")

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player.UserId] = nil
	sizeStep[player.UserId] = nil
	sizeBaseline[player.UserId] = nil
	local aura = auraByPlayer[player.UserId]
	if aura then aura:Destroy() end
	auraByPlayer[player.UserId] = nil
	local clone = workspace:FindFirstChild("UtilityClone_" .. player.UserId)
	if clone then clone:Destroy() end
end)

print("[UtilityBar] Extended Mount, Size, Clone, and Aura actions ready.")
