--!strict
-- Isolated Creator Hub audio inspection and AudioProbe lifecycle.
return function(context: {[string]: any})
	local musicValidation = context.musicValidation
	local SoundService = context.SoundService
	local ContentProvider = context.ContentProvider
	local CONFIG = context.CONFIG
	local decrementInspectionSlot = context.decrementInspectionSlot

local function inspectAudioAsset(assetId: number): (boolean, string, string, number, boolean)
	-- Cache metadata only. Every request still creates and preloads an AudioProbe
	-- below, so a metadata cache hit never bypasses experience permission/playability checks.
	local infoOk, infoOrError = musicValidation:GetAudioAssetInfo(assetId)
	if not infoOk then
		return false, tostring(infoOrError), "", 0, false
	end
	local info = infoOrError :: any
	if info.AssetTypeId ~= Enum.AssetType.Audio.Value then
		return false, "That asset is not an audio file.", "", 0, false
	end

	local audioProbe = Instance.new("AudioPlayer")
	audioProbe.Name = "AudioProbe"
	audioProbe.AutoLoad = true
	audioProbe.Asset = "rbxassetid://" .. tostring(assetId)
	audioProbe.Parent = SoundService
	local loadedOk = false
	local finished = false
	local timedOut = false
	task.spawn(function()
		loadedOk = pcall(function() ContentProvider:PreloadAsync({ audioProbe }) end)
		finished = true
		if timedOut then
			-- A timed-out PreloadAsync cannot be cancelled. Keep the global slot
			-- occupied until the underlying work really ends, then clean it up.
			pcall(function() audioProbe:Destroy() end)
			decrementInspectionSlot()
		end
	end)
	local waited = 0
	while not finished and waited < CONFIG.AudioLoadTimeoutSeconds do
		task.wait(0.2)
		waited += 0.2
	end
	if not finished then
		timedOut = true
		return false, "Audio inspection timed out. The server will release its inspection slot when loading finishes.", "", 0, true
	end

	local isReady = audioProbe.IsReady
	local length = audioProbe.TimeLength
	pcall(function() audioProbe:Destroy() end)
	if not loadedOk or not isReady or length <= 0 then
		return false, "Audio could not be loaded (it may be private or not allowed in this experience).", "", 0, false
	end
	local normalized = musicValidation:NormalizeAudioMetadata(assetId, info, math.ceil(length))
	if typeof(normalized) ~= "table" then
		return false, "Audio metadata could not be normalized.", "", 0, false
	end
	return true, normalized.title, normalized.artist, normalized.duration, false
end
	return inspectAudioAsset
end
