--!strict
-- Tiki Tide adaptive visual quality client.
-- Reads only the server-local Workspace load-mode attribute. No remotes,
-- telemetry, UI, gameplay authority, or cross-server state are used.
-- Only explicitly tagged club effects and stage/club light shadows are adjusted.
-- Light Enabled/Color/Brightness remain owned by the existing Stage & Club Lighting controls.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

type ParticleSnapshot = {baseRate: number, lastApplied: number}
type ShadowSnapshot = {baseShadows: boolean, lastApplied: boolean}

local particleSnapshots: {[ParticleEmitter]: ParticleSnapshot} = setmetatable({}, {__mode = "k"})
local shadowSnapshots: {[Light]: ShadowSnapshot} = setmetatable({}, {__mode = "k"})

local currentMode = "Normal"

local function particleMultiplier(): number
	if currentMode == "Critical" then return 0.1 end
	if currentMode == "Reduced" then return 0.5 end
	return 1
end

local function applyParticle(emitter: ParticleEmitter)
	if not emitter:IsDescendantOf(Workspace) then return end
	local snapshot = particleSnapshots[emitter]
	if not snapshot then
		snapshot = {baseRate = emitter.Rate, lastApplied = emitter.Rate}
		particleSnapshots[emitter] = snapshot
	elseif math.abs(emitter.Rate - snapshot.lastApplied) > 0.001 then
		-- Respect another authorized writer that changed the base emission rate.
		snapshot.baseRate = emitter.Rate
	end
	local nextRate = math.max(0, snapshot.baseRate * particleMultiplier())
	if math.abs(emitter.Rate - nextRate) > 0.001 then emitter.Rate = nextRate end
	snapshot.lastApplied = nextRate
end

local function restoreParticle(emitter: ParticleEmitter)
	local snapshot = particleSnapshots[emitter]
	if not snapshot then return end
	pcall(function()
		if math.abs(emitter.Rate - snapshot.lastApplied) <= 0.001 then
			emitter.Rate = snapshot.baseRate
		end
	end)
	particleSnapshots[emitter] = nil
end

local function applyLight(light: Light)
	if not light:IsDescendantOf(Workspace) then return end
	local snapshot = shadowSnapshots[light]
	if not snapshot then
		snapshot = {baseShadows = light.Shadows, lastApplied = light.Shadows}
		shadowSnapshots[light] = snapshot
	elseif light.Shadows ~= snapshot.lastApplied then
		-- Preserve a newer setting made by another authorized lighting system.
		snapshot.baseShadows = light.Shadows
	end
	local nextShadows = snapshot.baseShadows and currentMode == "Normal"
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

local function collectRoot(root: Instance, tagName: string, apply: (Instance) -> ())
	apply(root)
	for _, descendant in ipairs(root:GetDescendants()) do apply(descendant) end
end

local function applyClubEffect(instance: Instance)
	if instance:IsA("ParticleEmitter") then applyParticle(instance) end
end

local function applyStageLight(instance: Instance)
	if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
		applyLight(instance)
	end
end

local function restoreClubEffect(instance: Instance)
	if instance:IsA("ParticleEmitter") then restoreParticle(instance) end
end

local function restoreStageLight(instance: Instance)
	if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
		restoreLight(instance)
	end
end

local function applyMode()
	currentMode = Workspace:GetAttribute("TikiTideAdaptiveLoadMode") or "Normal"
	if currentMode ~= "Normal" and currentMode ~= "Reduced" and currentMode ~= "Critical" then
		currentMode = "Normal"
	end
	for emitter in pairs(particleSnapshots) do applyParticle(emitter) end
	for light in pairs(shadowSnapshots) do applyLight(light) end
	for _, root in ipairs(CollectionService:GetTagged("ClubEffect")) do
		collectRoot(root, "ClubEffect", applyClubEffect)
	end
	for _, root in ipairs(CollectionService:GetTagged("StageClubLight")) do
		collectRoot(root, "StageClubLight", applyStageLight)
	end
end

local function hasTaggedAncestor(instance: Instance, tagName: string): boolean
	local current: Instance? = instance
	while current and current ~= Workspace do
		if CollectionService:HasTag(current, tagName) then return true end
		current = current.Parent
	end
	return false
end

for _, root in ipairs(CollectionService:GetTagged("ClubEffect")) do
	collectRoot(root, "ClubEffect", applyClubEffect)
end
for _, root in ipairs(CollectionService:GetTagged("StageClubLight")) do
	collectRoot(root, "StageClubLight", applyStageLight)
end

local connections = {
	Workspace:GetAttributeChangedSignal("TikiTideAdaptiveLoadMode"):Connect(applyMode),
	CollectionService:GetInstanceAddedSignal("ClubEffect"):Connect(function(root)
		collectRoot(root, "ClubEffect", applyClubEffect)
	end),
	CollectionService:GetInstanceRemovedSignal("ClubEffect"):Connect(function(root)
		collectRoot(root, "ClubEffect", restoreClubEffect)
	end),
	CollectionService:GetInstanceAddedSignal("StageClubLight"):Connect(function(root)
		collectRoot(root, "StageClubLight", applyStageLight)
	end),
	CollectionService:GetInstanceRemovedSignal("StageClubLight"):Connect(function(root)
		collectRoot(root, "StageClubLight", restoreStageLight)
	end),
	Workspace.DescendantAdded:Connect(function(instance)
		if instance:IsA("ParticleEmitter") and hasTaggedAncestor(instance, "ClubEffect") then
			applyParticle(instance)
		elseif (instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight"))
			and hasTaggedAncestor(instance, "StageClubLight") then
			applyLight(instance)
		end
	end),
}

applyMode()

script.Destroying:Connect(function()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for emitter in pairs(particleSnapshots) do restoreParticle(emitter) end
	for light in pairs(shadowSnapshots) do restoreLight(light) end
end)

print("[Tiki Tide][AdaptiveVisualQuality] Local tagged-effect scaling ready; no remotes or client telemetry.")
