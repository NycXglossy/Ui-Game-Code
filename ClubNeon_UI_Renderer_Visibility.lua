--!strict
-- ReplicatedStorage/ClubNeon_UI_Renderer_Visibility.lua
-- Coordinates the compact HUD and launcher with independent local UI panels.

local Visibility = {}

function Visibility.new(deps: {[string]: any})
	local playerGui: PlayerGui = deps.playerGui
	local hud: GuiObject = deps.hud
	local toggleButton: GuiObject = deps.toggleButton
	local connections: {any} = deps.connections
	local getExpanded: () -> boolean = deps.getExpanded
	local compactHudCandidates: {GuiObject} = {}

	local function isCompactClubHud(instance: Instance): boolean
		if not instance:IsA("GuiObject") then return false end
		local normalizedName = string.lower(string.gsub(instance.Name, "[^%w]", ""))
		return normalizedName == "topbarhud"
			or normalizedName == "clubmusictopbarhud"
			or normalizedName == "compactclubhud"
			or normalizedName == "clubmusiccompacthud"
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant ~= hud and isCompactClubHud(descendant) then
			table.insert(compactHudCandidates, descendant :: GuiObject)
		end
	end

	local function hideDuplicateCompactHuds()
		for index = #compactHudCandidates, 1, -1 do
			local candidate = compactHudCandidates[index]
			if candidate.Parent == nil then
				table.remove(compactHudCandidates, index)
			elseif candidate ~= hud then
				candidate.Visible = false
			end
		end
	end

	local function syncLauncherVisibility()
		local eliteSettingsOpen = playerGui:GetAttribute("ClubNeonSettingsOpen") == true
		local inventoryOpen = playerGui:GetAttribute("UtilityInventoryOpen") == true
		toggleButton.Visible = not getExpanded() and not eliteSettingsOpen and not inventoryOpen
	end

	local function setCompactHudVisibility(visible: boolean)
		playerGui:SetAttribute("ClubMusicMenuExpanded", getExpanded())
		local eliteSettingsOpen = playerGui:GetAttribute("ClubNeonSettingsOpen") == true
		local inventoryOpen = playerGui:GetAttribute("UtilityInventoryOpen") == true
		hideDuplicateCompactHuds()
		hud.Visible = visible and not getExpanded() and not eliteSettingsOpen and not inventoryOpen
		syncLauncherVisibility()
	end

	local function syncExternalPanelHudVisibility()
		local expanded = getExpanded()
		local inventoryOpen = playerGui:GetAttribute("UtilityInventoryOpen") == true
		local eliteSettingsOpen = playerGui:GetAttribute("ClubNeonSettingsOpen") == true
		if inventoryOpen or eliteSettingsOpen or expanded then
			hideDuplicateCompactHuds()
		end
		hud.Visible = not expanded and not eliteSettingsOpen and not inventoryOpen
		syncLauncherVisibility()
	end

	table.insert(connections, playerGui:GetAttributeChangedSignal("ClubNeonSettingsOpen"):Connect(syncExternalPanelHudVisibility))
	table.insert(connections, playerGui:GetAttributeChangedSignal("UtilityInventoryOpen"):Connect(syncExternalPanelHudVisibility))
	syncExternalPanelHudVisibility()
	table.insert(connections, playerGui.DescendantAdded:Connect(function(descendant)
		if descendant ~= hud and isCompactClubHud(descendant) then
			table.insert(compactHudCandidates, descendant :: GuiObject)
			if getExpanded() or playerGui:GetAttribute("UtilityInventoryOpen") == true
				or playerGui:GetAttribute("ClubNeonSettingsOpen") == true then
				(descendant :: GuiObject).Visible = false
			end
		end
	end))
	table.insert(connections, playerGui.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("GuiObject") then
			local index = table.find(compactHudCandidates, descendant)
			if index then table.remove(compactHudCandidates, index) end
		end
	end))

	return {
		hideDuplicateCompactHuds = hideDuplicateCompactHuds,
		syncLauncherVisibility = syncLauncherVisibility,
		setCompactHudVisibility = setCompactHudVisibility,
		syncExternalPanelHudVisibility = syncExternalPanelHudVisibility,
	}
end

return Visibility
