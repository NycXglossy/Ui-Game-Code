--!strict
-- Shared server-authority sanity checks.
-- This module validates data; callers still own permission and game-state decisions.
local Players = game:GetService("Players")

local SanityValidation = {}

local DEFAULT_WORLD_LIMIT = 100000
local DEFAULT_MAX_DEPTH = 6
local DEFAULT_MAX_ENTRIES = 512
local DEFAULT_MAX_STRING = 2048

function SanityValidation.IsFiniteNumber(value: any, minimum: number?, maximum: number?): boolean
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if minimum ~= nil and value < minimum then return false end
	if maximum ~= nil and value > maximum then return false end
	return true
end

function SanityValidation.IsInteger(value: any, minimum: number?, maximum: number?): boolean
	return SanityValidation.IsFiniteNumber(value, minimum, maximum) and value % 1 == 0
end

function SanityValidation.IsBoundedString(value: any, minimumLength: number?, maximumLength: number?): boolean
	if typeof(value) ~= "string" then return false end
	local length = #value
	return length >= (minimumLength or 0) and length <= (maximumLength or DEFAULT_MAX_STRING)
end

function SanityValidation.IsLivePlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
		and value.Parent == Players and Players:GetPlayerByUserId(value.UserId) == value
end

function SanityValidation.IsVector3(value: any, worldLimit: number?): boolean
	if typeof(value) ~= "Vector3" then return false end
	local limit = worldLimit or DEFAULT_WORLD_LIMIT
	return SanityValidation.IsFiniteNumber(value.X, -limit, limit)
		and SanityValidation.IsFiniteNumber(value.Y, -limit, limit)
		and SanityValidation.IsFiniteNumber(value.Z, -limit, limit)
end

function SanityValidation.IsCFrame(value: any, worldLimit: number?): boolean
	if typeof(value) ~= "CFrame" then return false end
	local limit = worldLimit or DEFAULT_WORLD_LIMIT
	local components = {value:GetComponents()}
	for index = 1, 3 do
		if not SanityValidation.IsFiniteNumber(components[index], -limit, limit) then return false end
	end
	for index = 4, 12 do
		if not SanityValidation.IsFiniteNumber(components[index], -1.001, 1.001) then return false end
	end
	return true
end

-- Validates a plain data tree before a server service consumes it. Instances,
-- userdata, functions, threads, cyclic tables, non-finite numbers and exotic
-- keys are rejected unless a caller validates those values separately.
function SanityValidation.ValidateDataTree(value: any, options: any?): (boolean, string?)
	local config = if typeof(options) == "table" then options else {}
	local maxDepth = if SanityValidation.IsInteger(config.maxDepth, 1, 12) then config.maxDepth else DEFAULT_MAX_DEPTH
	local maxEntries = if SanityValidation.IsInteger(config.maxEntries, 1, 4096) then config.maxEntries else DEFAULT_MAX_ENTRIES
	local maxString = if SanityValidation.IsInteger(config.maxStringLength, 0, 16384) then config.maxStringLength else DEFAULT_MAX_STRING
	local entries = 0
	local visiting: {[any]: boolean} = {}

	local function visit(node: any, depth: number): (boolean, string?)
		local kind = typeof(node)
		if kind == "nil" or kind == "boolean" then return true end
		if kind == "number" then
			return SanityValidation.IsFiniteNumber(node), if SanityValidation.IsFiniteNumber(node) then nil else "Non-finite numeric value."
		end
		if kind == "string" then
			return #node <= maxString, if #node <= maxString then nil else "String exceeds size limit."
		end
		if kind ~= "table" then return false, "Unsupported value type: " .. kind end
		if depth >= maxDepth then return false, "Payload nesting exceeds depth limit." end
		if visiting[node] then return false, "Cyclic payload table." end
		visiting[node] = true
		for key, child in pairs(node) do
			entries += 1
			if entries > maxEntries then visiting[node] = nil; return false, "Payload exceeds entry limit." end
			local keyType = typeof(key)
			if keyType == "string" then
				if #key > 100 then visiting[node] = nil; return false, "Payload key exceeds size limit." end
			elseif keyType == "number" then
				if not SanityValidation.IsFiniteNumber(key) then visiting[node] = nil; return false, "Invalid numeric payload key." end
			else
				visiting[node] = nil
				return false, "Unsupported payload key type."
			end
			local ok, reason = visit(child, depth + 1)
			if not ok then visiting[node] = nil; return false, reason end
		end
		visiting[node] = nil
		return true
	end

	return visit(value, 0)
end

-- Accepts one Player or a dense array of Players. Rejects stale references,
-- duplicate targets, sparse/mixed arrays and target lists above the cap.
function SanityValidation.ValidatePlayerTargets(value: any, maximumTargets: number?): (boolean, {Player}?, string?)
	local limit = if SanityValidation.IsInteger(maximumTargets, 1, 32) then maximumTargets else 8
	local targets: {Player} = {}
	local seen: {[number]: boolean} = {}

	if SanityValidation.IsLivePlayer(value) then
		table.insert(targets, value)
	else
		if typeof(value) ~= "table" then return false, nil, "A live player target is required." end
		local count = 0
		for key in pairs(value) do
			if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return false, nil, "Target list must be a dense numeric array."
			end
			count += 1
			if count > limit then return false, nil, "Target list exceeds its limit." end
		end
		for index = 1, count do
			local target = value[index]
			if not SanityValidation.IsLivePlayer(target) then return false, nil, "Target list contains an inactive player." end
			table.insert(targets, target)
		end
		if #targets ~= count then return false, nil, "Target list contains missing entries." end
	end

	if #targets == 0 or #targets > limit then return false, nil, "Target count is outside permitted limits." end
	for _, target in ipairs(targets) do
		if seen[target.UserId] then return false, nil, "Duplicate player target." end
		seen[target.UserId] = true
	end
	return true, targets
end

return SanityValidation
