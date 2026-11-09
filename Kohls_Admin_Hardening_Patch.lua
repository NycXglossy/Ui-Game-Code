--!strict
-- Kohl's Admin hardening patch
-- Run from Roblox Studio's Command Bar with the Kohl's Admin model/folder selected.
-- This patch intentionally does NOT merge Kohl's Admin permissions with ClubMusic.

local Selection = game:GetService("Selection")
local selected = Selection:Get()[1]
assert(selected, "Select the imported Kohl's Admin root model/folder first.")

local function replaceLiteral(source: string, old: string, new: string, label: string): string
	local first = string.find(source, old, 1, true)
	assert(first, "Patch stopped: expected source block not found (" .. label .. ").")
	local last = string.find(source, old, first + #old, true)
	assert(not last, "Patch stopped: source block is ambiguous (" .. label .. ").")
	return string.sub(source, 1, first - 1) .. new .. string.sub(source, first + #old)
end

local loader = selected:FindFirstChild("Loader", true)
assert(loader and loader:IsA("Script"), "Could not find Kohl's Admin Loader Script.")
local mainModule = loader:FindFirstChild("MainModule")
assert(mainModule and mainModule:IsA("ModuleScript"), "Bundled Loader.MainModule is missing; refusing external fallback.")

local loaderSource = loader.Source
local oldConfig = [=[local InsertService = game:GetService("InsertService")

local Package = script.Parent

local DEMO_PLACE = 2569622788
local MAIN_MODULE_ID = 1868400649
local MAIN_MODULE_NAME = "MainModule"

local AUTO_UPDATE = true
local LEGACY = false

local CONFIG = Package:FindFirstChild("Config")
if CONFIG then
	local autoUpdate = CONFIG:GetAttribute("AutoUpdate")
	if autoUpdate ~= nil then
		AUTO_UPDATE = autoUpdate
	end
	local legacy = CONFIG:GetAttribute("Legacy")
	if legacy ~= nil then
		LEGACY = legacy
	end
end]=]
local newConfig = [=[-- Security hardening: load only the reviewed, bundled MainModule.
-- Do not fetch executable code from Creator Store or an external asset at runtime.
local Package = script.Parent
local MAIN_MODULE_NAME = "MainModule"
local LEGACY = false

local CONFIG = Package:FindFirstChild("Config")
if CONFIG then
	local legacy = CONFIG:GetAttribute("Legacy")
	if legacy ~= nil then
		LEGACY = legacy
	end
end]=]
loaderSource = replaceLiteral(loaderSource, oldConfig, newConfig, "loader auto-update configuration")

local oldLoad = [=[	local localMainModule = script:FindFirstChild(MAIN_MODULE_NAME) or MAIN_MODULE_ID

	if typeof(localMainModule) == "Instance" then
		script:WaitForChild("Tools").Parent = localMainModule:FindFirstChild("Server") or localMainModule
	end

	local ok, result = pcall(require, if AUTO_UPDATE then MAIN_MODULE_ID else localMainModule)

	if not ok then
		if AUTO_UPDATE then
			local function loadModuleAsset(assetId: number)
				local asset = InsertService:LoadAsset(assetId)
				local module = asset:FindFirstChild("MainModule", true)
				if module then
					return assert(require(module), ":LoadAsset() module returned invalid values!")
				end
				error(`Failed to find the source for {assetId}.`)
			end

			warn("Kohl's Admin failed to auto-update from MainModule, trying to load from asset\nReason:\t" .. result)
			ok, result = pcall(loadModuleAsset, 172732271)
			if not ok then
				warn("Kohl's Admin failed to auto-update from asset, loading from local package\nReason:\t" .. result)
				result = require(localMainModule)
			end
		else
			warn("Kohl's Admin failed to load from local package\nReason:\t" .. result)
		end
	end

	if not LEGACY then
		result.initialize(CONFIG)
	end]=]
local newLoad = [=[	local localMainModule = script:FindFirstChild(MAIN_MODULE_NAME)
	if not localMainModule or not localMainModule:IsA("ModuleScript") then
		error("Kohl's Admin security check failed: bundled MainModule is missing. External asset loading is disabled.")
	end

	local tools = script:FindFirstChild("Tools")
	if tools then
		tools.Parent = localMainModule:FindFirstChild("Server") or localMainModule
	end

	local ok, result = pcall(require, localMainModule)
	if not ok then
		error("Kohl's Admin bundled MainModule failed to load: " .. tostring(result))
	end
	if type(result) ~= "table" or type(result.initialize) ~= "function" then
		error("Kohl's Admin bundled MainModule returned an invalid API; initialization aborted.")
	end

	if not LEGACY then
		result.initialize(CONFIG)
	end]=]
loaderSource = replaceLiteral(loaderSource, oldLoad, newLoad, "local-only module loading")
assert(not string.find(loaderSource, "InsertService", 1, true), "External asset loading reference remains in Loader.")
loader.Source = loaderSource

local serverSource = mainModule.Source
local oldRemote = [=[	elseif event == "KDelete" and arguments and f.getPower(plr) > 4 then
		arguments:Destroy()
	elseif event == "KPaste" and f.getPower(plr) > 4 then
		for _, v in arguments[1] do
			v:Clone().Parent = arguments[2]
			if arguments[3] then
				v:Destroy()
			end
		end]=]
local newRemote = [=[	elseif event == "KDelete" and f.getPower(plr) > 4 then
		-- Validate the client-supplied instance before invoking a destructive operation.
		if typeof(arguments) == "Instance" and arguments.Parent ~= nil then
			arguments:Destroy()
		end
	elseif event == "KPaste" and f.getPower(plr) > 4 then
		-- Reject malformed payloads and oversized batches before making any changes.
		if type(arguments) ~= "table"
			or type(arguments[1]) ~= "table"
			or typeof(arguments[2]) ~= "Instance"
			or (arguments[3] ~= nil and type(arguments[3]) ~= "boolean")
		then
			return
		end

		local sources = arguments[1]
		local destination = arguments[2]
		local moveSources = arguments[3] == true
		local count = #sources
		if count > 100 then
			return
		end

		-- Validate the entire batch first so malformed entries cannot cause partial moves.
		for index = 1, count do
			if typeof(sources[index]) ~= "Instance" or sources[index].Parent == nil then
				return
			end
		end

		for index = 1, count do
			local source = sources[index]
			local clone = source:Clone()
			clone.Parent = destination
			if moveSources then
				source:Destroy()
			end
		end]=]
serverSource = replaceLiteral(serverSource, oldRemote, newRemote, "privileged delete/paste validation")
mainModule.Source = serverSource

print("Kohl's Admin hardening patch applied:")
print("- External asset auto-update/fallback disabled; bundled MainModule is pinned.")
print("- Loader validates local module presence and initialize() API.")
print("- KDelete validates the supplied Instance.")
print("- KPaste validates payload types, all source Instances, and limits batches to 100.")
print("Review/disable the high-power script/localscript commands separately if dynamic code execution is not required.")
