--!strict
-- Server-owned catalog mutation actions. All mutable controller state is injected.
return function(ctx: {[string]: any}, player: Player, action: string, payload: any, now: number, userId: number)
	local ControllerFunctions = ctx.ControllerFunctions
	local CONFIG = ctx.CONFIG
	local catalogStorageReady = ctx.catalogStorageReady
	local MusicCatalogService = ctx.MusicCatalogService
	local TRACK_BY_ID = ctx.TRACK_BY_ID
	local ALL_TRACK_IDS = ctx.ALL_TRACK_IDS
	local MarketplaceService = ctx.MarketplaceService
	local Enum = ctx.Enum
	local pendingArtwork = ctx.pendingArtwork
	local Players = ctx.Players
	local pendingAudio = ctx.pendingAudio
	local lastAudioInspection = ctx.lastAudioInspection
	local globalAudioBucket = ctx.globalAudioBucket
	local nowPlaying = ctx.nowPlaying
	local queue = ctx.queue
	local activePlaylistId = ctx.getActivePlaylistId()
	local activePlaylistTracks = ctx.activePlaylistTracks
	local activePlaylistCursor = ctx.activePlaylistCursor
	local publishState = ctx.publishState
	local notify = ctx.notify
	local function getArtworkInspectionCount() return ctx.getArtworkInspectionCount() end
	local function setArtworkInspectionCount(value: number) ctx.setArtworkInspectionCount(value) end
	local function getAudioInspectionCount() return ctx.getAudioInspectionCount() end
	local function setAudioInspectionCount(value: number) ctx.setAudioInspectionCount(value) end
	if action == "CatalogAddAudio" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can add catalog tracks.", "warn"); return end
		if not catalogStorageReady or not MusicCatalogService:IsStorageReady() then
			notify(player, "Persistent catalog storage is unavailable. No changes were made.", "warn"); return
		end
		local assetId = payload.assetId
		local genreId = payload.genreId
		local artworkAssetId = payload.artworkAssetId
		if not ControllerFunctions.isValidAudioAssetId(assetId) then
			notify(player, "Enter a valid audio asset ID.", "warn"); return
		end
		if typeof(genreId) ~= "string" or #genreId > 24 then
			notify(player, "Choose a valid catalog genre.", "warn"); return
		end
		if artworkAssetId ~= nil and not ControllerFunctions.isValidAudioAssetId(artworkAssetId) then
			notify(player, "Artwork must be a valid Roblox image asset ID.", "warn"); return
		end
		if artworkAssetId ~= nil then
			-- Metadata lookups yield. Bound concurrent artwork inspections separately
			-- from audio preloads, and allow only one pending artwork lookup per caller.
			if pendingArtwork[userId] then
				notify(player, "An artwork inspection is already running.", "warn"); return
			end
			if ctx.getArtworkInspectionCount() >= 4 then
				notify(player, "Artwork inspection is busy. Try again shortly.", "warn"); return
			end
			pendingArtwork[userId] = true
			ctx.setArtworkInspectionCount(ctx.getArtworkInspectionCount() + 1)
			local artworkInfoOk, artworkInfo = pcall(function()
				return MarketplaceService:GetProductInfo(artworkAssetId, Enum.InfoType.Asset)
			end)
			pendingArtwork[userId] = nil
			ctx.setArtworkInspectionCount(math.max(0, ctx.getArtworkInspectionCount() - 1))
			local imageType = Enum.AssetType.Image.Value
			local decalType = Enum.AssetType.Decal.Value
			local deletedName = artworkInfoOk and typeof(artworkInfo) == "table"
				and typeof(artworkInfo.Name) == "string"
				and string.lower(string.gsub(artworkInfo.Name, "%s+", " ")) == "[ content deleted ]"
			if not artworkInfoOk or typeof(artworkInfo) ~= "table"
				or (artworkInfo.AssetTypeId ~= imageType and artworkInfo.AssetTypeId ~= decalType)
				or deletedName then
				notify(player, "That artwork is unavailable or is not an accessible Roblox image/decal asset.", "warn"); return
			end
			-- Recheck the caller after the yielding marketplace lookup. A role or
			-- session change while inspection was in flight must not authorize a write.
			if player.Parent ~= Players or not ControllerFunctions.isStaff(player) then return end
		end
		if CONFIG.RestrictAudioToAllowlist and not table.find(CONFIG.AllowedAudioAssetIds, assetId) then
			notify(player, "That audio asset is not on the approved list.", "warn"); return
		end
		if pendingAudio[userId] then notify(player, "An audio inspection is already running.", "warn"); return end
		local audioNow = os.clock()
		local previousAudio = lastAudioInspection[userId] or 0
		if previousAudio > 0 and audioNow - previousAudio < CONFIG.AudioInspectionCooldownSeconds then
			notify(player, "Please wait before inspecting another audio asset.", "warn"); return
		end
		if ctx.getAudioInspectionCount() >= math.max(1, CONFIG.MaxConcurrentAudioInspections)
			or not ControllerFunctions.consumeToken(globalAudioBucket, audioNow, 1) then
			notify(player, "Audio inspection is busy. Try again shortly.", "warn"); return
		end
		pendingAudio[userId] = true
		lastAudioInspection[userId] = audioNow
		ctx.setAudioInspectionCount(ctx.getAudioInspectionCount() + 1)
		local inspectOk, valid, title, artist, duration, inspectionOwnsSlot = pcall(ControllerFunctions.inspectAudioAsset, assetId)
		if inspectionOwnsSlot ~= true then ctx.setAudioInspectionCount(math.max(0, ctx.getAudioInspectionCount() - 1)) end
		pendingAudio[userId] = nil
		if not inspectOk or not valid then
			notify(player, if inspectOk then tostring(title) else "Audio inspection failed.", "warn"); return
		end
		if duration > CONFIG.AudioMaxSeconds then
			notify(player, string.format("Audio exceeds the %d-minute catalog limit.", math.floor(CONFIG.AudioMaxSeconds / 60)), "warn"); return
		end
		if player.Parent ~= Players or not ControllerFunctions.isStaff(player) then return end
		local budgetReady = ControllerFunctions.waitForDataStoreBudget(5)
		if not budgetReady then notify(player, "Shared DataStore budget is unavailable; catalog was not changed.", "warn"); return end
		-- DataStore budget waits yield; do not let a departed or demoted caller
		-- commit a catalog change using an earlier authorization check.
		if not ControllerFunctions.isLiveRemotePlayer(player) or not ControllerFunctions.isStaff(player) then return end
		local trackId = "custom-" .. tostring(assetId)
		local saved, message = MusicCatalogService:AddCustomTrack(assetId, title, artist, duration, genreId, artworkAssetId)
		if not saved then
			notify(player, message, "warn")
			return
		end

		local track = MusicCatalogService:GetTrackById(trackId)
		if track then
			TRACK_BY_ID[trackId] = track
			if not table.find(ALL_TRACK_IDS, trackId) then table.insert(ALL_TRACK_IDS, trackId) end
			table.sort(ALL_TRACK_IDS)
		end
		local publishOk, published = ControllerFunctions.globalInvoke("PublishCatalogChange")
		if not publishOk or published ~= true then
			warn("[ClubMusic] Catalog add saved locally; cross-server invalidation publish failed.")
		end
		notify(player, message, "ok")
		publishState(nil)
		return
	end

	if action == "CatalogRemoveTrack" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can remove catalog tracks.", "warn"); return end
		local trackId = payload.trackId
		if not ControllerFunctions.isValidString(trackId, 32) or not string.match(trackId, "^custom%-%d+$") then
			notify(player, "Only a valid staff-added catalog track ID can be removed.", "warn"); return
		end
		local track = TRACK_BY_ID[trackId]
		if not track or track.assetId == nil then
			notify(player, "Only staff-added catalog tracks can be removed here.", "warn"); return
		end
		if not catalogStorageReady or not ControllerFunctions.waitForDataStoreBudget(5) then
			notify(player, "Catalog storage is unavailable; track was not removed.", "warn"); return
		end
		-- The storage-budget wait can yield while the caller leaves or loses staff access.
		if not ControllerFunctions.isLiveRemotePlayer(player) or not ControllerFunctions.isStaff(player) then return end
		if nowPlaying.trackId == trackId then
			notify(player, "That track is currently playing. Remove it after playback ends.", "warn"); return
		end
		for _, queued in ipairs(queue) do
			if queued.trackId == trackId then
				notify(player, "That track is queued. Remove it from the queue first.", "warn"); return
			end
		end
		local removed, message = MusicCatalogService:RemoveCustomTrack(trackId)
		if not removed then
			notify(player, tostring(message or "Catalog track could not be removed."), "warn")
			return
		end
		TRACK_BY_ID[trackId] = nil
		for index, id in ipairs(ALL_TRACK_IDS) do
			if id == trackId then table.remove(ALL_TRACK_IDS, index); break end
		end
		if activePlaylistId then
			for index = #activePlaylistTracks, 1, -1 do
				if activePlaylistTracks[index].id == trackId then table.remove(activePlaylistTracks, index) end
			end
			ctx.setActivePlaylistCursor(math.clamp(ctx.getActivePlaylistCursor(), 1, math.max(1, #activePlaylistTracks)))
			ControllerFunctions.clearAutomaticQueue()
			ControllerFunctions.topUpAuto()
		end
		local publishOk, published = ControllerFunctions.globalInvoke("PublishCatalogChange")
		if not publishOk or published ~= true then
			warn("[ClubMusic] Catalog removal saved locally; cross-server invalidation publish failed.")
		end
		notify(player, tostring(message or "Track removed from the catalog."), "ok")
		publishState(nil)
		return
	end

end
