--!strict
-- Client presentation only. ServerStorage module and server BindableFunction
-- remain the authority; local attributes only select the camera subject.
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local controls: any = nil

local active = false
local targetPlayer: Player? = nil
local targetCharacterConnection: RBXScriptConnection? = nil
local targetRemovingConnection: RBXScriptConnection? = nil

local function disconnectTarget()
	if targetCharacterConnection then targetCharacterConnection:Disconnect(); targetCharacterConnection = nil end
	if targetRemovingConnection then targetRemovingConnection:Disconnect(); targetRemovingConnection = nil end
	if targetPlayer then targetPlayer = nil end
end

local function setControlsEnabled(enabled: boolean)
	if not controls then
		local playerScripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
		local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if playerModule then
			local ok, module = pcall(require, playerModule)
			if ok and type(module) == "table" and type(module.GetControls) == "function" then
				local controlsOk, result = pcall(function() return module:GetControls() end)
				if controlsOk then controls = result end
			end
		end
	end
	if controls then
		pcall(function()
			if enabled then controls:Enable() else controls:Disable() end
		end)
	end
end

local function restoreOwnCamera()
	disconnectTarget()
	setControlsEnabled(true)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function watchTarget(player: Player)
	disconnectTarget()
	targetPlayer = player
	local function applyCharacter(character: Model?)
		if not active or targetPlayer ~= player or not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and camera then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
	end
	applyCharacter(player.Character)
	targetCharacterConnection = player.CharacterAdded:Connect(applyCharacter)
	targetRemovingConnection = player.CharacterRemoving:Connect(function()
		if active and targetPlayer == player then
			-- Wait for this same target's replacement character; do not change
			-- server authority or choose a different target client-side.
			if camera then camera.CameraSubject = nil end
		end
	end)
end

local function refresh()
	local enabled = localPlayer:GetAttribute("ClubNeonSpectatorActive") == true
	local targetId = localPlayer:GetAttribute("ClubNeonSpectatorTargetUserId")
	if not enabled then
		active = false
		restoreOwnCamera()
		return
	end
	if typeof(targetId) ~= "number" or targetId <= 0 or targetId % 1 ~= 0 then
		active = false
		restoreOwnCamera()
		return
	end
	active = true
	setControlsEnabled(false)
	local target = Players:GetPlayerByUserId(targetId)
	if target then
		if targetPlayer ~= target then watchTarget(target) end
	else
		disconnectTarget()
		if camera then camera.CameraSubject = nil end
	end
end

localPlayer:GetAttributeChangedSignal("ClubNeonSpectatorActive"):Connect(refresh)
localPlayer:GetAttributeChangedSignal("ClubNeonSpectatorTargetUserId"):Connect(refresh)
localPlayer.CharacterAdded:Connect(function()
	if not active then task.defer(restoreOwnCamera) else task.defer(refresh) end
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
	if active then disconnectTarget() end
	task.defer(refresh)
end)
Players.PlayerAdded:Connect(function(player)
	if active and player.UserId == localPlayer:GetAttribute("ClubNeonSpectatorTargetUserId") then
		task.defer(refresh)
	end
end)
Players.PlayerRemoving:Connect(function(player)
	if targetPlayer == player then
		disconnectTarget()
		if active and camera then camera.CameraSubject = nil end
	end
end)
refresh()
