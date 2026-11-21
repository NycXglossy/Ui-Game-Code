--!strict
-- Club Neon client-local adaptive visual quality.
-- Combines each player's saved graphics quality/device class with this server's
-- local adaptive-load mode. No remotes, telemetry, UI, persistence, or cross-server state.
-- Supports both established tags and the optional aliases:
--   ClubEffect / ClubVFX (ParticleEmitter and Beam)
--   StageClubLight / ClubLight (Light descendants; only Shadows are changed)
-- Stage & Club Lighting remains authoritative for Enabled/Color/Brightness.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

type ParticleSnapshot = {
	baseRate: number,
	lastAppliedRate: number,
	baseEnabled: boolean,
	lastAppliedEnabled: boolean,
}
type BeamSnapshot = {baseEnabled: boolean, lastAppliedEnabled: boolean}
type ShadowSnapshot = {baseShadows: boolean, lastApplied: boolean}

local particleSnapshots: {[ParticleEmitter]: ParticleSnapshot} = setmetatable({}, {__mode = "k"})
local beamSnapshots: {[Beam]: BeamSnapshot} = setmetatable({}, {__mode = "k"})
local shadowSnapshots: {[Light]: ShadowSnapshot} = setmetatable({}, {__mode = "k"})

local currentMode = "Normal"
local isLowEndDevice = false

local function refreshDeviceQuality()
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local qualityValue = 0
	local ok, value = pcall(function()
		return UserGameSettings.SavedQualityLevel.Value
	end)
	if ok and type(value) == "number" then
		qualityValue = value
	end
	-- Automatic (0) is left to Roblox; explicit levels 1-3 are treated as low.
	isLowEndDevice = isMobile or (qualityValue > 0 and qualityValue <= 3)
end

local function particleMultiplier(): number
	if currentMode == "Critical" then return 0.1 end
	if currentMode == "Reduced" then return 0.5 end
	return 1
end

local function applyParticle(emitter: ParticleEmitter)
	if not emitter:IsDescendantOf(Workspace) then return end
	local snapshot = particleSnapshots[emitter]
	if not snapshot then
		snapshot = {
			baseRate = emitter.Rate,
			lastAppliedRate = emitter.Rate,
			baseEnabled = emitter.Enabled,
			lastAppliedEnabled = emitter.Enabled,
		}
		particleSnapshots[emitter] = snapshot
	else
		if math.abs(emitter.Rate - snapshot.lastAppliedRate) > 0.001 then
			snapshot.baseRate = emitter.Rate
		end
		if emitter.Enabled ~= snapshot.lastAppliedEnabled then
			snapshot.baseEnabled = emitter.Enabled
		end
	end

	local nextRate = math.max(0, snapshot.baseRate * particleMultiplier())
	local nextEnabled = snapshot.baseEnabled and not isLowEndDevice
	if math.abs(emitter.Rate - nextRate) > 0.001 then emitter.Rate = nextRate end
	if emitter.Enabled ~= nextEnabled then emitter.Enabled = nextEnabled end
	snapshot.lastAppliedRate = nextRate
	snapshot.lastAppliedEnabled = nextEnabled
end

local function restoreParticle(emitter: ParticleEmitter)
	local snapshot = particleSnapshots[emitter]
	if not snapshot then return end
	pcall(function()
		if math.abs(emitter.Rate - snapshot.lastAppliedRate) <= 0.001 then
			emitter.Rate = snapshot.baseRate
		end
		if emitter.Enabled == snapshot.lastAppliedEnabled then
			emitter.Enabled = snapshot.baseEnabled
		end
	end)
	particleSnapshots[emitter] = nil
end

local function applyBeam(beam: Beam)
	if not beam:IsDescendantOf(Workspace) then return end
	local snapshot = beamSnapshots[beam]
	if not snapshot then
		snapshot = {baseEnabled = beam.Enabled, lastAppliedEnabled = beam.Enabled}
		beamSnapshots[beam] = snapshot
	elseif beam.Enabled ~= snapshot.lastAppliedEnabled then
		snapshot.baseEnabled = beam.Enabled
	end
	local nextEnabled = snapshot.baseEnabled and not isLowEndDevice and currentMode ~= "Critical"
	if beam.Enabled ~= nextEnabled then beam.Enabled = nextEnabled end
	snapshot.lastAppliedEnabled = nextEnabled
end

local function restoreBeam(beam: Beam)
	local snapshot = beamSnapshots[beam]
	if not snapshot then return end
	pcall(function()
		if beam.Enabled == snapshot.lastAppliedEnabled then
			beam.Enabled = snapshot.baseEnabled
		end
	end)
	beamSnapshots[beam] = nil
end

local function applyLight(light: Light)
	if not light:IsDescendantOf(Workspace) then return end
	local snapshot = shadowSnapshots[light]
	if not snapshot then
		snapshot = {baseShadows = light.Shadows, lastApplied = light.Shadows}
		shadowSnapshots[light] = snapshot
	elseif light.Shadows ~= snapshot.lastApplied then
		snapshot.baseShadows = light.Shadows
	end
	local nextShadows = snapshot.baseShadows and not isLowEndDevice and currentMode == "Normal"
	if light.Shadows ~= nextShadows then light.Shadows = nextShadows end
	snapshot.lastApplied = nextShadows
end

local function restoreLight(light: Light)
	local snapshot = shadowSnapshots[light]
	if not snapshot then return end
	pcall(function()
		if light.Shadows == snapshot.lastApplied then
			light.Shadows = snapshot.baseShadows
		end
	end)
	shadowSnapshots[light] = nil
end

local function collectRoot(root: Instance, apply: (Instance) -> ())
	apply(root)
	for _, descendant in ipairs(root:GetDescendants()) do apply(descendant) end
end

local function hasTaggedAncestor(instance: Instance, tags: {string}): boolean
	local current: Instance? = instance
	while current and current ~= Workspace do
		for _, tagName in ipairs(tags) do
			if CollectionService:HasTag(current, tagName) then return true end
		end
		current = current.Parent
	end
	return false
end

local EFFECT_TAGS = {"ClubEffect", "ClubVFX"}
local LIGHT_TAGS = {"StageClubLight", "ClubLight"}

local function applyEffect(instance: Instance)
	if instance:IsA("ParticleEmitter") then
		applyParticle(instance)
	elseif instance:IsA("Beam") then
		applyBeam(instance)
	end
end

local function restoreEffect(instance: Instance)
	if not hasTaggedAncestor(instance, EFFECT_TAGS) then
		if instance:IsA("ParticleEmitter") then restoreParticle(instance) end
		if instance:IsA("Beam") then restoreBeam(instance) end
	end
end

local function applyStageLight(instance: Instance)
	if instance:IsA("Light") then applyLight(instance) end
end

local function restoreStageLight(instance: Instance)
	if instance:IsA("Light") and not hasTaggedAncestor(instance, LIGHT_TAGS) then
		restoreLight(instance)
	end
end

local function applyAll()
	currentMode = Workspace:GetAttribute("ClubNeonAdaptiveLoadMode") or "Normal"
	if currentMode ~= "Normal" and currentMode ~= "Reduced" and currentMode ~= "Critical" then
		currentMode = "Normal"
	end
	for emitter in pairs(particleSnapshots) do applyParticle(emitter) end
	for beam in pairs(beamSnapshots) do applyBeam(beam) end
	for light in pairs(shadowSnapshots) do applyLight(light) end
	for _, tagName in ipairs(EFFECT_TAGS) do
		for _, root in ipairs(CollectionService:GetTagged(tagName)) do
			collectRoot(root, applyEffect)
		end
	end
	for _, tagName in ipairs(LIGHT_TAGS) do
		for _, root in ipairs(CollectionService:GetTagged(tagName)) do
			collectRoot(root, applyStageLight)
		end
	end
end

refreshDeviceQuality()
for _, tagName in ipairs(EFFECT_TAGS) do
	for _, root in ipairs(CollectionService:GetTagged(tagName)) do
		collectRoot(root, applyEffect)
	end
end
for _, tagName in ipairs(LIGHT_TAGS) do
	for _, root in ipairs(CollectionService:GetTagged(tagName)) do
		collectRoot(root, applyStageLight)
	end
end

local connections = {
	Workspace:GetAttributeChangedSignal("ClubNeonAdaptiveLoadMode"):Connect(applyAll),
	UserGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
		refreshDeviceQuality()
		applyAll()
	end),
	CollectionService:GetInstanceAddedSignal("ClubEffect"):Connect(function(root)
		collectRoot(root, applyEffect)
	end),
	CollectionService:GetInstanceAddedSignal("ClubVFX"):Connect(function(root)
		collectRoot(root, applyEffect)
	end),
	CollectionService:GetInstanceRemovedSignal("ClubEffect"):Connect(function(root)
		collectRoot(root, restoreEffect)
	end),
	CollectionService:GetInstanceRemovedSignal("ClubVFX"):Connect(function(root)
		collectRoot(root, restoreEffect)
	end),
	CollectionService:GetInstanceAddedSignal("StageClubLight"):Connect(function(root)
		collectRoot(root, applyStageLight)
	end),
	CollectionService:GetInstanceAddedSignal("ClubLight"):Connect(function(root)
		collectRoot(root, applyStageLight)
	end),
	CollectionService:GetInstanceRemovedSignal("StageClubLight"):Connect(function(root)
		collectRoot(root, restoreStageLight)
	end),
	CollectionService:GetInstanceRemovedSignal("ClubLight"):Connect(function(root)
		collectRoot(root, restoreStageLight)
	end),
	Workspace.DescendantAdded:Connect(function(instance)
		if (instance:IsA("ParticleEmitter") or instance:IsA("Beam"))
			and hasTaggedAncestor(instance, EFFECT_TAGS) then
			applyEffect(instance)
		elseif instance:IsA("Light") and hasTaggedAncestor(instance, LIGHT_TAGS) then
			applyLight(instance)
		end
	end),
}

applyAll()

script.Destroying:Connect(function()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for emitter in pairs(particleSnapshots) do restoreParticle(emitter) end
	for beam in pairs(beamSnapshots) do restoreBeam(beam) end
	for light in pairs(shadowSnapshots) do restoreLight(light) end
end)

print("[Club Neon][AdaptiveVisualQuality] Client-local graphics quality and adaptive load scaling ready; no remotes or telemetry.")
