--!strict
-- ToolShop.server.lua
-- Install as a Script in ServerScriptService. Creates persistent Coins and a
-- server-owned Tool Shop query endpoint. The catalog intentionally starts empty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")

local STARTING_COINS = 0 -- Change deliberately when choosing the launch economy.
local AUTOSAVE_SECONDS = 60
local COIN_STORE = DataStoreService:GetDataStore("ClubNeon_v1_ToolShopCoins")

local folder = ReplicatedStorage:FindFirstChild("UtilityBarRemotes")
if folder and not folder:IsA("Folder") then folder:Destroy(); folder = nil end
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "UtilityBarRemotes"
	folder.Parent = ReplicatedStorage
end
local remote = folder:FindFirstChild("ToolShop")
if remote and not remote:IsA("RemoteFunction") then remote:Destroy(); remote = nil end
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "ToolShop"
	remote.Parent = folder
end
local shopRemote = remote :: RemoteFunction

local function reportShopSignal(player: Player, signal: string)
	local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
	local report = api and api:IsA("Folder") and api:FindFirstChild("ReportSignal")
	if report and report:IsA("BindableFunction") then
		local ok, accepted = pcall(function() return report:Invoke(player.UserId, signal) end)
		if ok and accepted == true then return end
	end
	local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function() replay:Invoke("Record", signal, player.UserId, 0, "Warning", "ToolShopRemote", {}) end)
	end
end

local loaded: {[number]: boolean} = {}
local saving: {[number]: boolean} = {}
local lastShopRequestAt: {[number]: number} = {}
local SHOP_QUERY_COOLDOWN = 0.5

local function getCoinsValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then return coins end
	return nil
end

local function savePlayer(player: Player)
	if not loaded[player.UserId] or saving[player.UserId] then return end
	local coins = getCoinsValue(player)
	if not coins then return end
	saving[player.UserId] = true
	local amount = math.max(0, math.floor(coins.Value))
	local ok, err = pcall(function()
		COIN_STORE:SetAsync("u_" .. player.UserId, amount)
	end)
	if not ok then warn("[Tool Shop] Coin save failed for " .. player.Name .. ": " .. tostring(err)) end
	saving[player.UserId] = nil
end

local function setupPlayer(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local coins = stats:FindFirstChild("Coins")
	if coins and not coins:IsA("IntValue") then
		warn("[Tool Shop] Existing leaderstats.Coins is not an IntValue; leaving it untouched.")
		return
	end
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Value = STARTING_COINS
		coins.Parent = stats
	end
	local coinValue = coins :: IntValue
	local ok, stored = pcall(function()
		return COIN_STORE:GetAsync("u_" .. player.UserId)
	end)
	if ok then
		if typeof(stored) == "number" then
			coinValue.Value = math.max(0, math.floor(stored))
		end
		loaded[player.UserId] = true
	else
		warn("[Tool Shop] Coin load failed for " .. player.Name .. "; purchases remain unavailable until data loads.")
		loaded[player.UserId] = false
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(setupPlayer, player) end
Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	loaded[player.UserId] = nil
	saving[player.UserId] = nil
	lastShopRequestAt[player.UserId] = nil
end)

shopRemote.OnServerInvoke = function(player: Player, operation: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return {ok = false, message = "A connected player is required."}
	end
	local now = os.clock()
	local previous = lastShopRequestAt[player.UserId] or 0
	if now - previous < SHOP_QUERY_COOLDOWN then
		return {ok = false, message = "Please wait before refreshing the shop."}
	end
	lastShopRequestAt[player.UserId] = now
	if operation ~= "GetShop" then
		reportShopSignal(player, "toolshop_operation_unsupported")
		return {ok = false, message = "Unsupported shop request."}
	end
	local coins = getCoinsValue(player)
	return {
		ok = loaded[player.UserId] == true,
		coins = if coins then coins.Value else 0,
		items = {}, -- Add approved Tool assets and prices in a later shop-stock phase.
	}
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do task.spawn(savePlayer, player) end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayer(player)
	end
	task.wait(2)
end)

print("[Tool Shop] Coins persistence and empty placeholder catalog are ready.")
