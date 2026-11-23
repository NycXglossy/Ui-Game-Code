-- HazeBeamFX: client-side haze modulation and beam enhancement for server-owned StageHazeRig.
local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local hazeFolder = workspace:WaitForChild("StageHazeRig")
local emitters = {}
local function collectEmitters()
	table.clear(emitters)
	for _, item in ipairs(hazeFolder:GetDescendants()) do
		if item:IsA("ParticleEmitter") and item.Name == "SoftStageHaze" then
			table.insert(emitters, item)
		end
	end
end
collectEmitters()
hazeFolder.DescendantAdded:Connect(function(item)
	if item:IsA("ParticleEmitter") and item.Name == "SoftStageHaze" then table.insert(emitters, item) end
end)
hazeFolder.DescendantRemoving:Connect(function(item)
	if item:IsA("ParticleEmitter") then
		for i = #emitters, 1, -1 do if emitters[i] == item then table.remove(emitters, i) end end
	end
end)

-- Beam properties are client-rendered so each client can apply local quality policy.
local function enhanceBeams(root)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Beam") and item:GetAttribute("HazeBeamEnhanced") ~= true then
			item:SetAttribute("HazeBeamEnhanced", true)
			item.LightEmission = 1
			item.LightInfluence = 0
			item.Width0 = math.clamp(item.Width0 * 1.06, 0.06, 1.1)
			item.Width1 = math.clamp(item.Width1 * 1.04, 0.1, 2.8)
		end
	end
end
local function refresh()
	for _, name in ipairs({"MovingHeadRig", "LaserRig"}) do
		local root = workspace:FindFirstChild(name)
		if root then enhanceBeams(root) end
	end
end
refresh()
workspace.ChildAdded:Connect(function(child)
	if child.Name == "MovingHeadRig" or child.Name == "LaserRig" then task.defer(refresh) end
end)

local lastT = os.clock()
local scanAge = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	scanAge += dt
	if scanAge >= 5 then scanAge = 0; refresh() end
	local beat = ClubAudioSync.getBeatState()
	local lift = math.clamp(beat.energy, 0, 1)
	local beatBreath = 0.5 + 0.5 * math.cos(beat.beatPhase * math.pi * 2)
	for _, emitter in ipairs(emitters) do
		if emitter.Parent then emitter.Rate = 0.35 + lift * 0.55 + beatBreath * beat.pulse * 0.65 end
	end
end)
