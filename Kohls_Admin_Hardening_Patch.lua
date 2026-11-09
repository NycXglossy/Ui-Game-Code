--!strict
-- Kohl's Admin hardening patch
-- Run from Roblox Studio's Command Bar with the Kohl's Admin root selected.
-- Apply to a BACKUP copy first. This patch does not merge Kohl's Admin permissions
-- with ClubMusic and does not remove the optional high-power script commands.

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
local mainModule = loader:FindFirstChild("MainModule") or loader:FindFirstChild("MainModuleLegacy")
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
local newConfig = [=[local Package = script.Parent

-- Security hardening: runtime code is loaded only from this bundled package.
local LEGACY = false
local MAIN_MODULE_NAME = "MainModule"

local CONFIG = Package:FindFirstChild("Config")
if CONFIG then
	local legacy = CONFIG:GetAttribute("Legacy")
	if legacy ~= nil then
		LEGACY = legacy
	end
end]=]
loaderSource = replaceLiteral(loaderSource, oldConfig, newConfig, "loader configuration")
loaderSource = replaceLiteral(
	loaderSource,
	"local legacyConfig = CONFIG:FindFirstChild(\"Legacy\")",
	"local legacyConfig = CONFIG and CONFIG:FindFirstChild(\"Legacy\")",
	"optional legacy configuration"
)
loaderSource = replaceLiteral(
	loaderSource,
	"\tif LEGACY then\n\t\t_G.KAU = true",
	"\tif LEGACY then\n\t\tassert(legacyConfig, \"Legacy mode requested but Config.Legacy is missing.\")\n\t\t_G.KAU = true",
	"legacy configuration validation"
)

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
assert(not string.find(loaderSource, "MAIN_MODULE_ID", 1, true), "External MainModule asset ID remains in Loader.")
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
		-- Validate the client-supplied Instance before destructive operations.
		if typeof(arguments) == "Instance"
			and arguments.Parent ~= nil
			and arguments:IsDescendantOf(game)
		then
			arguments:Destroy()
		end
	elseif event == "KPaste" and f.getPower(plr) > 4 then
		-- Validate the full payload before making any changes.
		if type(arguments) ~= "table"
			or type(arguments[1]) ~= "table"
			or typeof(arguments[2]) ~= "Instance"
			or not arguments[2]:IsDescendantOf(game)
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

		for index = 1, count do
			if typeof(sources[index]) ~= "Instance"
				or sources[index].Parent == nil
				or not sources[index]:IsDescendantOf(game)
			then
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
print("- External auto-update and Creator Store fallback removed from Loader.")
print("- Loader requires only the bundled MainModule and validates initialize().")
print("- Legacy configuration is checked before use.")
print("- KDelete and KPaste validate live Instances and payload shape.")
print("- KPaste batches are limited to 100 Instances.")
print("NOTE: Dynamic script/localscript execution remains a separate high-impact feature; review or disable it if not required.")
print("NOTE: This patch does not replace a complete audit or add general RemoteEvent rate limiting.")
