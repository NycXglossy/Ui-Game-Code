--!strict
-- ReplicatedStorage/ClubNeon_UI_Renderer_Typography.lua
-- Applies responsive text sizing to the mounted menu and tracks dynamic descendants.

local Typography = {}

function Typography.new(deps: {[string]: any})
	local panel: Frame = deps.panel
	local connections: {any} = deps.connections
	local getDevice: () -> string = deps.getDevice
	local boldFont = deps.boldFont
	local regularFont = deps.regularFont
	local cameraProvider = deps.cameraProvider
	local targets: {TextLabel | TextButton | TextBox} = {}
	local initialized = false
	local dirty = true
	local lastDevice: string? = nil
	local lastViewportWidth: number? = nil

	local function isTarget(item: Instance): boolean
		return item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")
	end

	local function apply()
		local device = getDevice()
		local scaleByDevice = {Desktop=1.04, Tablet=0.98, Mobile=0.92, Console=1.02, VR=0.96}
		local camera = cameraProvider()
		local viewportWidth = if camera then camera.ViewportSize.X else 1280
		local textScale = (scaleByDevice[device] or 1) * (if viewportWidth < 560 then 0.9 elseif viewportWidth < 760 then 0.95 else 1)
		if not dirty and lastDevice == device and lastViewportWidth == viewportWidth then
			return
		end
		lastDevice = device
		lastViewportWidth = viewportWidth
		if not initialized then
			initialized = true
			for _, descendant in ipairs(panel:GetDescendants()) do
				if isTarget(descendant) then
					table.insert(targets, descendant :: any)
				end
			end
			table.insert(connections, panel.DescendantAdded:Connect(function(descendant)
				if isTarget(descendant) then
					table.insert(targets, descendant :: any)
					dirty = true
				end
			end))
			table.insert(connections, panel.DescendantRemoving:Connect(function(descendant)
				if isTarget(descendant) then
					local index = table.find(targets, descendant)
					if index then table.remove(targets, index) end
				end
			end))
		end
		for _, item in ipairs(targets) do
			if item.Parent ~= nil then
				local baseSize = item:GetAttribute("ClubBaseTextSize")
				if typeof(baseSize) ~= "number" then
					baseSize = item.TextSize
					item:SetAttribute("ClubBaseTextSize", baseSize)
				end
				local minSize = if device == "Mobile" or viewportWidth < 560 then 8 else 9
				local maxSize = if device == "Mobile" then 25 elseif viewportWidth < 560 then 24 else 28
				item.TextSize = math.clamp(math.floor(baseSize * textScale + 0.5), minSize, maxSize)
				if item:IsA("TextLabel") then
					item.Font = if baseSize >= 13 then boldFont else regularFont
					item.TextScaled = false
					local height = item.Size.Y.Offset
					if height >= 26 and #item.Text > 34 then
						item.TextWrapped = true
					end
				elseif item:IsA("TextButton") then
					item.TextScaled = false
					item.Font = boldFont
				elseif item:IsA("TextBox") then
					item.TextScaled = false
					item.Font = regularFont
				end
			end
		end
		dirty = false
	end

	return {
		apply = apply,
		isTarget = isTarget,
	}
end

return Typography
