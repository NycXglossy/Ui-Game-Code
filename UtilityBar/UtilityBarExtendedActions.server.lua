--!strict
-- UtilityBarExtendedActions.server.lua
-- Install as a Script in ServerScriptService. Independent from ClubMusic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

-- Reuse the server-only shared validator without adding a new polling service.
local SanityValidation: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = core and core:IsA("Folder") and core:FindFirstChild("SanityValidation")
	if module and module:IsA("ModuleScript") then
		local ok, exported = pcall(require, module)
		if ok and typeof(exported) == "table" and type(exported.ValidateDataTree) == "function" then
			SanityValidation = exported
		end
	end
	if not SanityValidation then
		warn("[UtilityBar] Shared SanityValidation unavailable; bounded local request validation remains active.")
	end
end

local REMOTE_FOLDER = "UtilityBarRemotes"
local REMOTE_NAME = "ExecuteUtility"
local COOLDOWN = 1.25
local CLONE_LIFETIME = 12
local lastRequest: {[number]: number} = {}
local sizeStep: {[number]: number} = {}
local sizeBaseline: {[number]: {humanoid: Humanoid, height: number, width: number, depth: number, head: number}} = {}
local warnedMovementAuthorityMissing = false
local warnedMovementAuthorityFailure = false
local auraByPlayer: {[number]: {highlights: {Highlight}, connection: RBXScriptConnection?, character: Model}} = {}
local ingressTokens = 36
local ingressUpdatedAt = os.clock()
local INGRESS_CAPACITY = 36
local INGRESS_REFILL_PER_SECOND = 18

local function consumeIngressBudget(now: number): boolean
	local elapsed = math.max(0, now - ingressUpdatedAt)
	ingressUpdatedAt = now
	ingressTokens = math.min(INGRESS_CAPACITY, ingressTokens + elapsed * INGRESS_REFILL_PER_SECOND)
	if ingressTokens < 1 then return false end
	ingressTokens -= 1
	return true
end

local function validateUtilityValue(value: any): boolean
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" then return true end
	if kind == "number" then
		return value == value and value > -math.huge and value < math.huge
	end
	if kind == "string" then return #value <= 64 end
	if kind ~= "table" then return false end
	if SanityValidation then
		local ok = SanityValidation.ValidateDataTree(value, {maxDepth = 2, maxEntries = 8, maxStringLength = 64})
		return ok == true
	end
	local count = 0
	for key, child in pairs(value) do
		count += 1
		if count > 8 or typeof(key) ~= "string" or #key > 24 then return false end
		local childType = typeof(child)
		if childType == "string" then
			if #child > 64 then return false end
		elseif childType == "number" then
			if child ~= child or child == math.huge or child == -math.huge then return false end
		elseif childType ~= "boolean" then
			return false
		end
	end
	return true
end

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

local function reportUtilitySignal(player: Player, signal: string)
	local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
	local report = api and api:IsA("Folder") and api:FindFirstChild("ReportSignal")
	if report and report:IsA("BindableFunction") then
		local ok, accepted = pcall(function() return report:Invoke(player.UserId, signal) end)
		if ok and accepted == true then return end
	end
	local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function() replay:Invoke("Record", signal, player.UserId, 0, "Warning", "UtilityBarRemote", {}) end)
	end
end

local function getCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return nil, nil end
	return character, humanoid
end

local function setSize(player: Player, requestedFactor: any): (boolean, string)
	if typeof(requestedFactor) ~= "number" or requestedFactor ~= requestedFactor
		or requestedFactor == math.huge or requestedFactor == -math.huge
		or requestedFactor < 0.5 or requestedFactor > 5 then
		return false, "Character size must be between 0.5× and 5×."
	end
	local factor = requestedFactor
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
	height.Value = baseline.height * factor
	width.Value = baseline.width * factor
	depth.Value = baseline.depth * factor
	head.Value = baseline.head * factor

	-- Register this self-only, server-applied scale change with the shared
	-- server-local movement authority ledger used by Kohl's Admin and the
	-- future CharacterPhysicsGuard. No client-supplied target is accepted.
	local authority = ServerStorage:FindFirstChild("TikiTideMovementAuthority")
	if authority and authority:IsA("BindableFunction") then
		local authorityOk, registered = pcall(function()
			return authority:Invoke("Register", player.UserId, player.UserId, "BodyScale", factor, "UtilityBarSize", 120)
		end)
		if (not authorityOk or registered ~= true) and not warnedMovementAuthorityFailure then
			warnedMovementAuthorityFailure = true
			warn("[UtilityBar] Size change applied, but MovementAuthority registration failed.")
		end
	elseif not warnedMovementAuthorityMissing then
		warnedMovementAuthorityMissing = true
		warn("[UtilityBar] TikiTideMovementAuthority is unavailable; install the RegularCommandsSecurityServer add-on to enable movement authorization tracking.")
	end

	return true, string.format("Character size set to %.2f×.", factor)
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
		if not backpack then return false, "Your Backpack is not ready yet." end
		mountTool.Parent = backpack
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
	-- Keep the visual clone beside its owner so it behaves like a temporary
	-- companion rather than a stationary duplicate left at the spawn point.
	task.spawn(function()
		local expiresAt = os.clock() + CLONE_LIFETIME
		while clone.Parent and player.Parent == Players and player.Character == character and os.clock() < expiresAt do
			local currentRoot = character:FindFirstChild("HumanoidRootPart")
			if currentRoot and currentRoot:IsA("BasePart") then
				clone:PivotTo(currentRoot.CFrame * CFrame.new(4, 0, 2))
			end
			task.wait(0.12)
		end
		if clone.Parent then clone:Destroy() end
	end)
	return true, "Your character companion will follow beside you for 12 seconds."
end

local function clearAura(userId: number)
	local state = auraByPlayer[userId]
	if not state then return end
	if state.connection then state.connection:Disconnect() end
	for _, highlight in ipairs(state.highlights) do
		if highlight.Parent then highlight:Destroy() end
	end
	auraByPlayer[userId] = nil
end

local function setAura(player: Player, request: any): (boolean, string)
	if typeof(request) ~= "table" then return false, "Choose an aura style and target." end
	local preset, target = request.preset, request.target
	if typeof(preset) ~= "string" then return false, "Choose an aura style." end
	if target ~= "Character" and target ~= "Tools" and target ~= "Accessories" then return false, "Choose Character, Tools, or Accessories." end
	local styles = {
		["Teal Glow"] = {fill=Color3.fromRGB(75, 190, 196), outline=Color3.fromRGB(119, 224, 224)},
		["Royal Gold"] = {fill=Color3.fromRGB(190, 139, 55), outline=Color3.fromRGB(255, 218, 145)},
		["Tiki Tide"] = {fill=Color3.fromRGB(119, 196, 203), outline=Color3.fromRGB(226, 194, 132)},
	}
	local style = styles[preset]
	if not style then return false, "That aura style is not available." end
	local character = player.Character
	if not character or not character.Parent then return false, "Your character is not ready." end
	clearAura(player.UserId)
	local state = {highlights = {} :: {Highlight}, connection = nil :: RBXScriptConnection?, character = character}
	local function addHighlight(targetInstance: Instance, name: string)
		local highlight = Instance.new("Highlight")
		highlight.Name = name
		highlight.Adornee = targetInstance
		highlight.FillColor = style.fill
		highlight.OutlineColor = style.outline
		highlight.FillTransparency = 0.78
		highlight.OutlineTransparency = 0.12
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = character
		table.insert(state.highlights, highlight)
	end
	local function addTarget(descendant: Instance)
		if target == "Character" or not descendant:IsA("BasePart") or descendant.Name ~= "Handle" then return end
		local ancestor = descendant.Parent
		while ancestor and ancestor ~= character do
			if target == "Tools" and ancestor:IsA("Tool") then
				addHighlight(descendant, "UtilityAura_Tool"); return
			elseif target == "Accessories" and ancestor:IsA("Accessory") then
				addHighlight(descendant, "UtilityAura_Accessory"); return
			end
			ancestor = ancestor.Parent
		end
	end
	if target == "Character" then
		addHighlight(character, "UtilityAura")
	else
		for _, descendant in ipairs(character:GetDescendants()) do addTarget(descendant) end
		state.connection = character.DescendantAdded:Connect(addTarget)
	end
	auraByPlayer[player.UserId] = state
	return true, preset .. " aura applied to " .. string.lower(target) .. "."
end

-- Feature entitlements are populated by the main server controller after Roblox
-- ownership verification. Never trust a client-supplied pass ID or ownership flag.
local FEATURE_PASS_ATTRIBUTES: {[string]: string} = {
	Mount = "HasIslandMountPass",
	Clone = "HasIslandCompanionPass",
	LightingControl = "HasStageClubLightingPass",
}
local function ownsFeaturePass(player: Player, actionName: string): boolean
	local attribute = FEATURE_PASS_ATTRIBUTES[actionName]
	return attribute ~= nil and player:GetAttribute(attribute) == true
end

-- Only explicitly tagged StageClubLight instances are affected. This keeps the
-- controls away from Workspace-wide Lighting and unrelated island/environment lights.
type LightSnapshot = {
	enabled: boolean,
	color: Color3,
	brightness: number,
	lastEnabled: boolean,
	lastColor: Color3,
	lastBrightness: number,
}
local originalLightState: {[Instance]: LightSnapshot} = {}
type BeamSnapshot = {original: ColorSequence, lastApplied: ColorSequence}
local originalBeamState: {[Beam]: BeamSnapshot} = {}
local function collectStageClubLights(): ({Light}, {Beam})
	local lights: {Light} = {}
	local beams: {Beam} = {}
	local seen: {[Instance]: boolean} = {}
	local function collect(instance: Instance)
		if not instance:IsDescendantOf(workspace) then return end
		if (instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")) and not seen[instance] then
			seen[instance] = true
			table.insert(lights, instance :: Light)
		elseif instance:IsA("Beam") and not seen[instance] then
			seen[instance] = true
			table.insert(beams, instance :: Beam)
		end
	end
	for _, tagged in ipairs(CollectionService:GetTagged("StageClubLight")) do
		collect(tagged)
		for _, descendant in ipairs(tagged:GetDescendants()) do collect(descendant) end
	end
	return lights, beams
end

local LIGHT_PRESETS: {[string]: {color: Color3, brightness: number}} = {
	Ocean = {color = Color3.fromRGB(65, 190, 210), brightness = 1.15},
	Sunset = {color = Color3.fromRGB(255, 145, 82), brightness = 1.2},
	Royal = {color = Color3.fromRGB(226, 194, 132), brightness = 1.25},
	Tiki = {color = Color3.fromRGB(110, 220, 160), brightness = 1.1},
}
local function setStageClubLighting(player: Player, request: any): (boolean, string)
	if typeof(request) ~= "table" or typeof(request.preset) ~= "string" then
		return false, "Choose a lighting preset."
	end
	local lights, beams = collectStageClubLights()
	if #lights == 0 and #beams == 0 then
		return false, "No stage/club lights are tagged yet. Tag the club and stage light objects 'StageClubLight'."
	end
	if request.preset == "Off" then
		local restored, preserved = 0, 0
		for _, light in ipairs(lights) do
			local snapshot = originalLightState[light]
			if snapshot then
				-- Do not overwrite a fixture another authorized system changed
				-- after our last preset application.
				if light.Enabled == snapshot.lastEnabled
					and light.Color == snapshot.lastColor
					and math.abs(light.Brightness - snapshot.lastBrightness) <= 0.001 then
					light.Enabled = snapshot.enabled
					light.Color = snapshot.color
					light.Brightness = snapshot.brightness
					restored += 1
				else
					preserved += 1
				end
				originalLightState[light] = nil
			end
		end
		for _, beam in ipairs(beams) do
			local snapshot = originalBeamState[beam]
			if snapshot then
				if beam.Color == snapshot.lastApplied then
					beam.Color = snapshot.original
					restored += 1
				else
					preserved += 1
				end
				originalBeamState[beam] = nil
			end
		end
		if preserved > 0 then
			return true, string.format("Restored %d fixtures; preserved %d fixtures changed by another system.", restored, preserved)
		end
		return true, "Stage and club lighting restored to its original settings."
	end
	local preset = LIGHT_PRESETS[request.preset]
	if not preset then return false, "That lighting preset is not available." end
	local sequence = ColorSequence.new(preset.color)
	for _, light in ipairs(lights) do
		if not originalLightState[light] then
			originalLightState[light] = {
				enabled = light.Enabled, color = light.Color, brightness = light.Brightness,
				lastEnabled = light.Enabled, lastColor = light.Color, lastBrightness = light.Brightness,
			}
		end
		local snapshot = originalLightState[light]
		local appliedBrightness = math.clamp(snapshot.brightness * preset.brightness, 0, 10)
		light.Enabled = true
		light.Color = preset.color
		light.Brightness = appliedBrightness
		snapshot.lastEnabled = true
		snapshot.lastColor = preset.color
		snapshot.lastBrightness = appliedBrightness
	end
	for _, beam in ipairs(beams) do
		if not originalBeamState[beam] then
			originalBeamState[beam] = {original = beam.Color, lastApplied = beam.Color}
		end
		beam.Color = sequence
		originalBeamState[beam].lastApplied = sequence
	end
	return true, request.preset .. " lighting applied to the tagged club and stage fixtures."
end

execute.OnServerInvoke = function(player: Player, actionName: any, value: any): (boolean, string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "A live player is required."
	end
	local now = os.clock()
	-- A bounded per-server token bucket protects the validation and action path.
	if not consumeIngressBudget(now) then return false, "Utility service is busy. Please try again shortly." end
	if typeof(actionName) ~= "string" or #actionName < 1 or #actionName > 32 or not validateUtilityValue(value) then
		reportUtilitySignal(player, "utility_remote_invalid_envelope")
		return false, "Invalid utility request."
	end
	local allowed = actionName == "Mount" or actionName == "Size"
		or actionName == "Clone" or actionName == "Aura" or actionName == "ClearAura"
		or actionName == "LightingControl"
	if not allowed then
		reportUtilitySignal(player, "utility_action_unsupported")
		return false, "This utility action is not available."
	end
	if FEATURE_PASS_ATTRIBUTES[actionName] and not ownsFeaturePass(player, actionName) then
		return false, "The matching Game Pass is required for this feature."
	end
	if now - (lastRequest[player.UserId] or 0) < COOLDOWN then
		return false, "Please wait before using another utility."
	end
	lastRequest[player.UserId] = now
	if actionName == "Mount" then return toggleMount(player) end
	if actionName == "Size" then return setSize(player, value) end
	if actionName == "Clone" then return createClone(player) end
	if actionName == "LightingControl" then return setStageClubLighting(player, value) end
	if actionName == "ClearAura" then
		clearAura(player.UserId)
		return true, "Aura cleared."
	end
	return setAura(player, value)
end


local function clearPlayerAuraOnCharacterChange(player: Player)
	player.CharacterRemoving:Connect(function()
		clearAura(player.UserId)
	end)
end
for _, player in ipairs(Players:GetPlayers()) do clearPlayerAuraOnCharacterChange(player) end
Players.PlayerAdded:Connect(clearPlayerAuraOnCharacterChange)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player.UserId] = nil
	sizeStep[player.UserId] = nil
	sizeBaseline[player.UserId] = nil
	clearAura(player.UserId)
	local clone = workspace:FindFirstChild("UtilityClone_" .. player.UserId)
	if clone then clone:Destroy() end
end)
print("[UtilityBar] Pass-gated Mount, Clone Companion, scoped Stage/Club Lighting, Size, and Aura actions ready.")
