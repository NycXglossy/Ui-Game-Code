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
local mainModule = loader:FindFirstChild("MainModule")
assert(mainModule and mainModule:IsA("ModuleScript"), "Bundled Loader.MainModule is missing; refusing external fallback.")
local legacyModule = loader:FindFirstChild("MainModuleLegacy")
assert(legacyModule and legacyModule:IsA("ModuleScript"), "Bundled Loader.MainModuleLegacy is missing; cannot harden the optional legacy path.")

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
local serverSource = legacyModule.Source

-- Rate-limit the shared admin RemoteEvent by player and operation. Preserve
-- the existing command dispatcher cooldown and use tighter limits for costly actions.
local oldHandler = [=[function ServerEvent(plr: Player, event, arguments, uID)
	if type(arguments) == "function" or type(event) ~= "string" then
		return
	end
	uID, event = event:match("(%d*)(.+)")]=]
local newHandler = [=[local remoteEventCooldowns = {
	KuID = 1,
	KCClr = 0.1,
	KRefresh = 1,
	KCmdBar = 0.5,
	KDelete = 0.1,
	KPaste = 1,
	KUpdate = 0.5,
	KVote = 0.05,
	KHat = 2,
	KTrail = 2,
	KShine = 2,
	KBulkPurchase = 5,
	KVIPCheck = 5,
	KPing = 0.5,
	KCam = 0.5,
}
-- Sensitive operations have a central minimum-power policy in addition to
-- their handler-level checks. Power 5 is Kohl's Admin Owner and power 6 is Creator.
local remoteEventMinimumPower = {
	KDelete = 5,
	KPaste = 5,
	KUpdate = 5,
}
local remoteEventLast = {}
local function allowRemoteEvent(player: Player, eventName: string): boolean
	local requiredPower = remoteEventMinimumPower[eventName]
	if requiredPower and f.getPower(player) < requiredPower then
		return false
	end
	local now = os.clock()
	local playerEvents = remoteEventLast[player]
	if not playerEvents then
		playerEvents = {}
		remoteEventLast[player] = playerEvents
	end
	local last = playerEvents[eventName]
	if last and now - last < (remoteEventCooldowns[eventName] or 0.05) then
		return false
	end
	playerEvents[eventName] = now
	return true
end
services.Players.PlayerRemoving:Connect(function(player)
	remoteEventLast[player] = nil
end)

function ServerEvent(plr: Player, event, arguments, uID)
	if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
		return
	end
	if type(arguments) == "function" or type(event) ~= "string" then
		return
	end
	uID, event = event:match("(%d*)(.+)")
	if type(event) ~= "string" then
		return
	end
	if event == "KuID" then
		if uID ~= "" or not allowRemoteEvent(plr, event) then
			return
		end
	else
		if uID ~= f.uID or not remoteEventCooldowns[event] or not allowRemoteEvent(plr, event) then
			return
		end
	end]=]
serverSource = replaceLiteral(serverSource, oldHandler, newHandler, "RemoteEvent rate limiting and event allowlist")

-- Remove the legacy native loadstring command entirely; power checks are not a sandbox.
serverSource = replaceLiteral(
	serverSource,
	[=[f.addCommand(
			{ "s", "script" },
			{ "Creates a script.", "game.Players:Destroy()" },
			5,
			{ "string" },
			function(pl, args)
				if pcall(loadstring("a=0")) == false then
					f.Error("LoadString must be enabled to use the script command!", pl)
				else
					local success, err = pcall(loadstring(args[1]))
					if success == false then
						f.Error("SCRIPT ERROR\t" .. err, pl)
					end
				end
			end
		)]=],
	"",
	"remove legacy arbitrary-code script command"
)

-- Validate the client-supplied camera payload before reading LookVector.
serverSource = replaceLiteral(
	serverSource,
	"if plr == pl and a == f.uID .. \"KCam\" then",
	"local function isSafeCameraCFrame(value)\n\tif typeof(value) ~= \"CFrame\" then return false end\n\tlocal components = { value:GetComponents() }\n\tfor _, component in ipairs(components) do\n\t\tif component ~= component or component == math.huge or component == -math.huge then return false end\n\tend\n\tlocal position = value.Position\n\treturn math.abs(position.X) <= 100000 and math.abs(position.Y) <= 100000 and math.abs(position.Z) <= 100000\nend\nif plr == pl and a == f.uID .. \"KCam\" and isSafeCameraCFrame(b) then",
	"KCam finite and bounded CFrame validation"
)

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
		-- Only allow world-edit deletion of live Workspace objects.
		if typeof(arguments) == "Instance"
			and arguments ~= workspace
			and arguments.Parent ~= nil
			and arguments:IsDescendantOf(workspace)
			and not arguments:IsA("Script")
			and not arguments:IsA("LocalScript")
			and not arguments:IsA("ModuleScript")
		then
			arguments:Destroy()
		end
	elseif event == "KPaste" and f.getPower(plr) > 4 then
		-- Validate a dense, bounded list and a Workspace destination before cloning.
		if type(arguments) ~= "table"
			or type(arguments[1]) ~= "table"
			or typeof(arguments[2]) ~= "Instance"
			or arguments[2] == workspace
			or not arguments[2]:IsDescendantOf(workspace)
			or (arguments[3] ~= nil and type(arguments[3]) ~= "boolean")
		then
			return
		end

		local sources = arguments[1]
		local destination = arguments[2]
		local moveSources = arguments[3] == true
		local count = 0
		local totalDescendants = 0
		for key, source in pairs(sources) do
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
				return
			end
			count += 1
			if count > 25
				or typeof(source) ~= "Instance"
				or source.Parent == nil
				or not source:IsDescendantOf(workspace)
				or source == workspace
				or destination == source
				or destination:IsDescendantOf(source)
			then
				return
			end
			totalDescendants += #source:GetDescendants() + 1
			if totalDescendants > 500 then
				return
			end
		end
		if count == 0 then
			return
		end
		for index = 1, count do
			if sources[index] == nil then
				return
			end
		end

		-- Prepare every clone first. A clone failure must not partially mutate the world.
		local clones = {}
		for index = 1, count do
			local ok, clone = pcall(function()
				return sources[index]:Clone()
			end)
			if not ok or typeof(clone) ~= "Instance" then
				for _, prepared in ipairs(clones) do
					prepared:Destroy()
				end
				return
			end
			table.insert(clones, clone)
		end

		for _, clone in ipairs(clones) do
			clone.Parent = destination
		end
		if moveSources then
			for index = 1, count do
				sources[index]:Destroy()
			end
		end]=]
serverSource = replaceLiteral(serverSource, oldRemote, newRemote, "privileged delete/paste validation")
-- Remove the v3 Creator script/localscript command registrations.
local creatorModule = mainModule:FindFirstChild("Creator", true)
assert(creatorModule and creatorModule:IsA("ModuleScript"), "MainModule.Shared.DefaultCommands.Creator is missing.")
local creatorSource = creatorModule.Source
creatorSource = replaceLiteral(creatorSource, "return {", "local creatorCommands = {", "Creator command table")
creatorSource ..= [=[

for index = #creatorCommands, 1, -1 do
	local commandName = creatorCommands[index].name
	if commandName == "script" or commandName == "localscript" then
		table.remove(creatorCommands, index)
	end
end
return creatorCommands
]=]
assert(not string.find(creatorSource, 'name = "script"', 1, true), "Creator script command remains registered.")
assert(not string.find(creatorSource, 'name = "localscript"', 1, true), "Creator localscript command remains registered.")

-- Disable the underlying FiOne/loadstring runner as defense in depth.
local loadScriptModule = mainModule:FindFirstChild("LoadScript", true)
assert(loadScriptModule and loadScriptModule:IsA("ModuleScript"), "MainModule.Server.LoadScript is missing.")
local loadScriptSource = loadScriptModule.Source
assert(string.find(loadScriptSource, "script.Loadstring", 1, true), "Unexpected LoadScript implementation; refusing to overwrite.")
loadScriptSource = [=[--!strict
-- Security hardening: runtime source execution is disabled.
return function(...)
	error("Kohl's Admin script/localscript execution is disabled by the security patch.", 2)
end
]=]

-- Bound command-bar payload size before handing text to the command parser.
serverSource = replaceLiteral(
	serverSource,
	'elseif event == "KCmdBar" and type(arguments) == "string" then',
	'elseif event == "KCmdBar" and type(arguments) == "string" and #arguments <= 512 then',
	"command bar payload length limit"
)

-- Source assignment is deferred until every source transformation has passed.

-- Commit all modified source only after every replacement assertion succeeded.
-- If any Source write fails, restore every earlier write in reverse order.
local writes = {
	{ instance = legacyModule, source = serverSource },
	{ instance = creatorModule, source = creatorSource },
	{ instance = loadScriptModule, source = loadScriptSource },
	{ instance = loader, source = loaderSource },
}
local originals = {}
for index, write in ipairs(writes) do
	originals[index] = write.instance.Source
	local ok, writeError = pcall(function()
		write.instance.Source = write.source
	end)
	if not ok then
		for rollbackIndex = index - 1, 1, -1 do
			pcall(function()
				writes[rollbackIndex].instance.Source = originals[rollbackIndex]
			end)
		end
		error("Kohl's Admin patch write failed; earlier source writes were rolled back: " .. tostring(writeError))
	end
end

print("Kohl's Admin hardening patch applied:")
print("- External auto-update and Creator Store fallback removed from Loader.")
print("- Loader requires only the bundled MainModule and validates initialize().")
print("- Legacy configuration is checked before use.")
print("- KDelete and KPaste validate live Instances and payload shape.")
print("- KPaste batches are limited to 25 Workspace Instances and 500 total descendants.")
print("- Delete/paste targets are restricted to Workspace world-edit objects.")
print("- Paste clones are staged before parenting to prevent partial clone batches.")
print("- All four source writes are deferred and rolled back on failure.")
print("- Delete/paste cooldowns are reduced to 10/sec and 1/sec per player respectively.")
print("- KCam validates finite CFrame components and bounds position coordinates.")
print("- Creator script/localscript commands are removed; FiOne/loadstring execution is disabled.")
print("- Shared admin RemoteEvent operations are allowlisted and rate-limited per player.")
print("- Legacy native loadstring script command is removed.")
print("- KCam validates the client CFrame payload.")
print("- Command-bar payloads are limited to 512 characters.")
print("NOTE: Review custom add-ons separately; bundled arbitrary-code execution paths are disabled.")
