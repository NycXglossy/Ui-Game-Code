--!strict
-- UtilityBarExtendedActions.server.lua
-- Install as a Script in ServerScriptService. Independent from ClubMusic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ClubAudioSync = require(ReplicatedStorage:WaitForChild("ClubAudioSync"))

-- Reuse the server-only shared validator without adding a new polling service.
local SanityValidation: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
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
-- Companion clones are owned and cleaned up by this server script, not inferred
-- from a replicated Workspace name lookup.
local companionByPlayer: {[number]: Model} = {}
local playerLifecycleConnections: {[number]: {RBXScriptConnection}} = {}
local lifecycleConnections: {RBXScriptConnection} = {}
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
	local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
	local authority = ServerStorage:FindFirstChild("ClubNeonMovementAuthority")
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
		warn("[UtilityBar] ClubNeonMovementAuthority is unavailable; install the RegularCommandsSecurityServer add-on to enable movement authorization tracking.")
	end

	return true, string.format("Character size set to %.2f×.", factor)
end

-- Mount templates are deliberately server-only. Add the reviewed Model to
-- ServerStorage.ClubNeonMounts; when multiple models exist, exactly one must
-- have DefaultMount=true. No client-supplied name or asset ID is accepted.
local MOUNT_FOLDER_NAME = "ClubNeonMounts"
local MAX_MOUNT_DESCENDANTS = 500
local activeMounts: {[number]: {model: Model, connections: {RBXScriptConnection}}} = {}
local mountBusy: {[number]: boolean} = {}
local mountFolder = ServerStorage:FindFirstChild(MOUNT_FOLDER_NAME)
if mountFolder and not mountFolder:IsA("Folder") then
	warn("[UtilityBar] ServerStorage.ClubNeonMounts exists but is not a Folder; mount spawning is disabled.")
	mountFolder = nil
elseif not mountFolder then
	local created = Instance.new("Folder")
	created.Name = MOUNT_FOLDER_NAME
	created.Parent = ServerStorage
	mountFolder = created
end

local function disconnectMountRecord(record: {model: Model, connections: {RBXScriptConnection}})
	for _, connection in ipairs(record.connections) do connection:Disconnect() end
	table.clear(record.connections)
end

local function despawnMount(userId: number, destroyModel: boolean): boolean
	local record = activeMounts[userId]
	if not record then return false end
	activeMounts[userId] = nil
	disconnectMountRecord(record)
	if destroyModel and record.model.Parent then
		pcall(function() record.model:Destroy() end)
	end
	local owner = Players:GetPlayerByUserId(userId)
	if owner then owner:SetAttribute("HasActiveIslandMount", false) end
	return true
end

local function resolveMountTemplate(): (Model?, string?)
	if not mountFolder or not mountFolder.Parent then
		return nil, "The server mount catalog is unavailable."
	end
	local models = {}
	for _, child in ipairs(mountFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("ClubNeonApprovedMount") == true then
			table.insert(models, child)
		end
	end
	if #models == 0 then
		return nil, "Island Mount is not configured yet. Add an approved Model with ClubNeonApprovedMount=true to ServerStorage.ClubNeonMounts."
	end
	if #models == 1 then return models[1], nil end
	local defaultModel: Model? = nil
	for _, model in ipairs(models) do
		if model:GetAttribute("DefaultMount") == true then
			if defaultModel then return nil, "The mount catalog has more than one DefaultMount." end
			defaultModel = model
		end
	end
	if not defaultModel then return nil, "Choose exactly one approved DefaultMount in the server mount catalog." end
	return defaultModel, nil
end

local function spawnMount(player: Player): (boolean, string)
	if activeMounts[player.UserId] and activeMounts[player.UserId].model.Parent then
		player:SetAttribute("HasActiveIslandMount", true)
		return true, "Your Island Mount is already spawned."
	end
	despawnMount(player.UserId, true)
	local character, humanoid = getCharacter(player)
	if not character or not humanoid then return false, "Your character is not ready." end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false, "Your character root is unavailable." end
	local template, templateError = resolveMountTemplate()
	if not template then return false, templateError or "No approved mount is configured." end
	local descendants = template:GetDescendants()
	if #descendants > MAX_MOUNT_DESCENDANTS then
		return false, "The configured mount exceeds the allowed model complexity."
	end
	local hasPart, hasSeat = false, false
	for _, descendant in ipairs(descendants) do
		if descendant:IsA("BasePart") then hasPart = true end
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then hasSeat = true end
	end
	if not hasPart or not hasSeat then
		return false, "The approved mount must contain BaseParts and at least one Seat or VehicleSeat."
	end
	local cloneOk, cloned = pcall(function() return template:Clone() end)
	if not cloneOk or not cloned or not cloned:IsA("Model") then
		return false, "The server could not create the approved mount."
	end
	local mount = cloned :: Model
	mount.Name = "ClubNeonMount_" .. tostring(player.UserId)
	mount:SetAttribute("OwnerId", player.UserId) -- metadata only; activeMounts is authoritative.
	local spawnCharacter = character
	local spawnRoot = root
	local targetCFrame = spawnRoot.CFrame * CFrame.new(0, 0, -8)
	local pivotOk = pcall(function() mount:PivotTo(targetCFrame) end)
	if not pivotOk or player.Parent ~= Players or player.Character ~= spawnCharacter
		or not spawnCharacter.Parent or spawnRoot.Parent ~= spawnCharacter
		or humanoid.Health <= 0 then
		mount:Destroy()
		return false, "Your character changed before the mount could spawn."
	end
	local record: {model: Model, connections: {RBXScriptConnection}} = {model = mount, connections = {}}
	for _, descendant in ipairs(mount:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			local seat: any = descendant
			-- Default policy is owner-only driving/riding until a passenger policy
			-- is deliberately configured and tested for the actual mount model.
			table.insert(record.connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				local occupant = seat.Occupant
				if not occupant then
					local canSet = false
					pcall(function() canSet = seat:CanSetNetworkOwnership() end)
					if canSet then pcall(function() seat:SetNetworkOwner(nil) end) end
					return
				end
				local occupantCharacter = occupant.Parent
				local rider: Player? = nil
				if occupantCharacter and occupantCharacter:IsA("Model") then
					rider = Players:GetPlayerFromCharacter(occupantCharacter)
				end
				if not rider or rider.UserId ~= player.UserId or activeMounts[player.UserId] ~= record then
					pcall(function() occupant.Sit = false end)
					if rider and rider.UserId ~= player.UserId then
						reportUtilitySignal(rider, "mount_seat_unauthorized_occupant")
					end
					return
				end
				local canSet = false
				pcall(function() canSet = seat:CanSetNetworkOwnership() end)
				if canSet then
					local ownershipOk = pcall(function() seat:SetNetworkOwner(rider) end)
					if not ownershipOk then reportUtilitySignal(rider, "mount_network_owner_assignment_failed") end
				end
			end))
		end
	end
	activeMounts[player.UserId] = record
	table.insert(record.connections, mount.AncestryChanged:Connect(function(_, parent)
		if parent == nil and activeMounts[player.UserId] == record then
			despawnMount(player.UserId, false)
		end
	end))
	local parentOk, parentError = pcall(function() mount.Parent = workspace end)
	if not parentOk then
		despawnMount(player.UserId, true)
		warn("[UtilityBar] Mount parenting failed: " .. tostring(parentError))
		return false, "The server could not place the mount into the world."
	end
	-- Set ownership only after the assemblies are in Workspace, so Roblox can
	-- validate each actual assembly. Keep them server-owned until the owner sits.
	local initializedAssemblies: {[BasePart]: boolean} = {}
	for _, descendant in ipairs(mount:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			local assemblyRoot = part.AssemblyRootPart or part
			if not initializedAssemblies[assemblyRoot] then
				initializedAssemblies[assemblyRoot] = true
				local canSet = false
				pcall(function() canSet = part:CanSetNetworkOwnership() end)
				if canSet then pcall(function() part:SetNetworkOwner(nil) end) end
			end
		end
	end
	player:SetAttribute("HasActiveIslandMount", true)
	return true, "Your Island Mount has spawned. Use the Mount button again to despawn it."
end

local function handleMountRequest(player: Player, operation: any): (boolean, string)
	if operation ~= "Spawn" and operation ~= "Despawn" then
		return false, "Choose Spawn or Despawn."
	end
	if mountBusy[player.UserId] then return false, "Your mount is already changing state." end
	mountBusy[player.UserId] = true
	local ok, success, message = pcall(function()
		if operation == "Despawn" then
			local removed = despawnMount(player.UserId, true)
			return true, if removed then "Your Island Mount has been despawned." else "You do not have an active mount."
		end
		return spawnMount(player)
	end)
	mountBusy[player.UserId] = nil
	if not ok then
		warn("[UtilityBar] Mount lifecycle failed for userId " .. tostring(player.UserId) .. ": " .. tostring(success))
		return false, "The mount service could not complete that request."
	end
	return success == true, if typeof(message) == "string" then message else "Mount request completed."
end

local function destroyCompanion(userId: number)
	local clone = companionByPlayer[userId]
	companionByPlayer[userId] = nil
	if clone and clone.Parent then
		clone:Destroy()
	end
end

local function createClone(player: Player): (boolean, string)
	local character = player.Character
	if not character or not character.Parent then return false, "Your character is not ready." end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false, "Character root is unavailable." end
	destroyCompanion(player.UserId)
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
	companionByPlayer[player.UserId] = clone
	clone.Parent = workspace
	-- Keep the visual clone beside its owner so it behaves like a temporary
	-- companion rather than a stationary duplicate left at the spawn point.
	task.spawn(function()
		local expiresAt = os.clock() + CLONE_LIFETIME
		while companionByPlayer[player.UserId] == clone and clone.Parent and player.Parent == Players and player.Character == character and os.clock() < expiresAt do
			local currentRoot = character:FindFirstChild("HumanoidRootPart")
			if currentRoot and currentRoot:IsA("BasePart") then
				clone:PivotTo(currentRoot.CFrame * CFrame.new(4, 0, 2))
			end
			task.wait(0.12)
		end
		if companionByPlayer[player.UserId] == clone then
			companionByPlayer[player.UserId] = nil
			if clone.Parent then clone:Destroy() end
		end
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
		["Club Neon"] = {fill=Color3.fromRGB(119, 196, 203), outline=Color3.fromRGB(226, 194, 132)},
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

-- Live Music Sync only touches explicitly tagged StageClubLight fixtures.
-- It never edits Workspace-wide Lighting, atmosphere, bloom, or unrelated FX.
local LIVE_SHOW_HUES = {
	Color3.fromRGB(255, 0, 200),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(255, 200, 0),
	Color3.fromRGB(0, 255, 200),
}
local liveShowConnection: RBXScriptConnection? = nil
local liveShowLights: {Light} = {}
local liveShowBeams: {Beam} = {}
local liveShowIntensity = 0.75

local function stopLiveShow(restore: boolean): boolean
	local connection = liveShowConnection
	liveShowConnection = nil
	if connection then connection:Disconnect() end
	local restoredAny = false
	if restore then
		for _, light in ipairs(liveShowLights) do
			local snapshot = originalLightState[light]
			if snapshot then
				if light.Parent and light.Enabled == snapshot.lastEnabled
					and light.Color == snapshot.lastColor
					and math.abs(light.Brightness - snapshot.lastBrightness) <= 0.001 then
					light.Enabled = snapshot.enabled
					light.Color = snapshot.color
					light.Brightness = snapshot.brightness
					restoredAny = true
				end
				originalLightState[light] = nil
			end
		end
		for _, beam in ipairs(liveShowBeams) do
			local snapshot = originalBeamState[beam]
			if snapshot then
				if beam.Parent and beam.Color == snapshot.lastApplied then
					beam.Color = snapshot.original
					restoredAny = true
				end
				originalBeamState[beam] = nil
			end
		end
	end
	table.clear(liveShowLights)
	table.clear(liveShowBeams)
	return connection ~= nil or restoredAny
end

local function startLiveShow(lights: {Light}, beams: {Beam}): boolean
	stopLiveShow(true)
	for _, light in ipairs(lights) do
		originalLightState[light] = {
			enabled = light.Enabled, color = light.Color, brightness = light.Brightness,
			lastEnabled = light.Enabled, lastColor = light.Color, lastBrightness = light.Brightness,
		}
	end
	for _, beam in ipairs(beams) do
		originalBeamState[beam] = {original = beam.Color, lastApplied = beam.Color}
	end
	liveShowLights = lights
	liveShowBeams = beams
	local lastBeatCount = -1
	liveShowConnection = RunService.Heartbeat:Connect(function()
		local beat = ClubAudioSync.getBeatState()
		if not beat.playing or beat.beatCount == lastBeatCount then return end
		lastBeatCount = beat.beatCount
		local color = LIVE_SHOW_HUES[(beat.beatCount % #LIVE_SHOW_HUES) + 1]
		local sequence = ColorSequence.new(color)
		for _, light in ipairs(liveShowLights) do
			local snapshot = originalLightState[light]
			if light.Parent and snapshot then
				local brightness = math.clamp(snapshot.brightness * liveShowIntensity, 0, 10)
				light.Enabled = true
				light.Color = color
				light.Brightness = brightness
				snapshot.lastEnabled = true
				snapshot.lastColor = color
				snapshot.lastBrightness = brightness
			end
		end
		for _, beam in ipairs(liveShowBeams) do
			local snapshot = originalBeamState[beam]
			if beam.Parent and snapshot then
				beam.Color = sequence
				snapshot.lastApplied = sequence
			end
		end
	end)
	return true
end

local function setStageClubLighting(_player: Player, request: any): (boolean, string)
	if typeof(request) ~= "table" or typeof(request.preset) ~= "string" then
		return false, "Choose Live Music Sync or Restore Defaults."
	end
	if request.preset == "LiveShow" then
		if request.intensity ~= nil then
			if typeof(request.intensity) ~= "number" or request.intensity ~= request.intensity
				or request.intensity == math.huge or request.intensity == -math.huge
				or request.intensity < 0.1 or request.intensity > 1.5 then
				return false, "Sync intensity must be between 10% and 150%."
			end
			liveShowIntensity = request.intensity
		end
		local lights, beams = collectStageClubLights()
		if #lights == 0 and #beams == 0 then
			return false, "No stage/club lights are tagged yet. Tag the fixtures 'StageClubLight'."
		end
		startLiveShow(lights, beams)
		return true, string.format("Live Music Sync enabled at %d%% intensity.", math.floor(liveShowIntensity * 100 + 0.5))
	elseif request.preset == "Off" then
		local restored = stopLiveShow(true)
		if restored then return true, "Live Music Sync stopped. Tagged fixtures restored to their defaults." end
		return true, "Live Music Sync is already off; fixture defaults were left unchanged."
	end
	return false, "That lighting option is not available."
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
	if actionName == "Mount" then return handleMountRequest(player, value) end
	if actionName == "Size" then return setSize(player, value) end
	if actionName == "Clone" then return createClone(player) end
	if actionName == "LightingControl" then return setStageClubLighting(player, value) end
	if actionName == "ClearAura" then
		clearAura(player.UserId)
		return true, "Aura cleared."
	end
	return setAura(player, value)
end


local function bindPlayerLifecycle(player: Player)
	local existing = playerLifecycleConnections[player.UserId]
	if existing then
		for _, connection in ipairs(existing) do connection:Disconnect() end
	end
	player:SetAttribute("HasActiveIslandMount", activeMounts[player.UserId] ~= nil)
	local connections = {}
	table.insert(connections, player.CharacterAdded:Connect(function()
		destroyCompanion(player.UserId)
		despawnMount(player.UserId, true)
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		clearAura(player.UserId)
		destroyCompanion(player.UserId)
		despawnMount(player.UserId, true)
	end))
	playerLifecycleConnections[player.UserId] = connections
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayerLifecycle(player)
end
table.insert(lifecycleConnections, Players.PlayerAdded:Connect(bindPlayerLifecycle))

table.insert(lifecycleConnections, Players.PlayerRemoving:Connect(function(player)
	lastRequest[player.UserId] = nil
	sizeStep[player.UserId] = nil
	sizeBaseline[player.UserId] = nil
	clearAura(player.UserId)
	destroyCompanion(player.UserId)
	despawnMount(player.UserId, true)
	mountBusy[player.UserId] = nil
	player:SetAttribute("HasActiveIslandMount", false)
	local connections = playerLifecycleConnections[player.UserId]
	if connections then
		for _, connection in ipairs(connections) do connection:Disconnect() end
		playerLifecycleConnections[player.UserId] = nil
	end
end))

game:BindToClose(function()
	for userId in pairs(activeMounts) do despawnMount(userId, true) end
	for userId in pairs(companionByPlayer) do destroyCompanion(userId) end
	for userId in pairs(auraByPlayer) do clearAura(userId) end
end)

script.Destroying:Connect(function()
	for _, connection in ipairs(lifecycleConnections) do connection:Disconnect() end
	table.clear(lifecycleConnections)
	for userId, connections in pairs(playerLifecycleConnections) do
		for _, connection in ipairs(connections) do connection:Disconnect() end
		playerLifecycleConnections[userId] = nil
	end
	for userId in pairs(companionByPlayer) do destroyCompanion(userId) end
	for userId in pairs(activeMounts) do despawnMount(userId, true) end
	for userId in pairs(auraByPlayer) do clearAura(userId) end
end)

print("[UtilityBar] Pass-gated Spawn/Despawn Mount, Clone Companion, scoped Stage/Club Lighting, Size, and Aura actions ready.")
