-- Tiki Tide Studio Runtime Audit
-- Paste into Roblox Studio > View > Command Bar while NOT playing.
-- Read-only: does not modify instances, scripts, attributes, tags, or data.
-- Use this to identify the source of high instance counts, duplicate Theme objects,
-- duplicate script names, and leftover Hello world scripts before changing anything.

local roots = game:GetChildren()
local classCounts = {}
local serviceRows = {}
local themeRows = {}
local helloRows = {}
local duplicateNameRows = {}
local nameIndex = {}

local function safeFullName(instance)
	local ok, value = pcall(function() return instance:GetFullName() end)
	return if ok then value else instance.Name
end

local function safeSource(instance)
	local ok, value = pcall(function() return instance.Source end)
	return if ok and type(value) == "string" then value else nil
end

for _, root in ipairs(roots) do
	local descendants = root:GetDescendants()
	local counts = {}
	local baseParts = 0
	local scripts = 0
	local models = 0
	local guiObjects = 0
	local meshParts = 0
	local unions = 0

	for _, instance in ipairs(descendants) do
		local className = instance.ClassName
		counts[className] = (counts[className] or 0) + 1
		classCounts[className] = (classCounts[className] or 0) + 1

		if instance:IsA("BasePart") then baseParts += 1 end
		if instance:IsA("LuaSourceContainer") then scripts += 1 end
		if instance:IsA("Model") then models += 1 end
		if instance:IsA("GuiObject") then guiObjects += 1 end
		if className == "MeshPart" then meshParts += 1 end
		if className == "UnionOperation" then unions += 1 end

		if string.lower(instance.Name) == "theme" then
			table.insert(themeRows, safeFullName(instance) .. " [" .. className .. "]")
		end

		if instance:IsA("LuaSourceContainer") then
			local source = safeSource(instance)
			if source and string.find(string.lower(source), "hello world!", 1, true) then
				table.insert(helloRows, safeFullName(instance) .. " [" .. className .. "]")
			end
		end

		local key = className .. "|" .. instance.Name
		nameIndex[key] = nameIndex[key] or {}
		table.insert(nameIndex[key], safeFullName(instance))
	end

	table.insert(serviceRows, {
		name = root.Name,
		className = root.ClassName,
		count = #descendants,
		baseParts = baseParts,
		meshParts = meshParts,
		unions = unions,
		models = models,
		guiObjects = guiObjects,
		scripts = scripts,
	})
end

for key, paths in pairs(nameIndex) do
	if #paths > 1 then
		table.insert(duplicateNameRows, key .. " (" .. #paths .. " copies): " .. table.concat(paths, " || "))
	end
end

table.sort(serviceRows, function(a, b) return a.count > b.count end)
table.sort(themeRows)
table.sort(helloRows)
table.sort(duplicateNameRows)

print("========== TIKI TIDE READ-ONLY STUDIO AUDIT ==========")
print("Total DataModel descendants: " .. #game:GetDescendants())
print("Top-level service count: " .. #roots)
print("-- Descendants by service (largest first) --")
for index, row in ipairs(serviceRows) do
	print(string.format(
		"%02d. %s (%s): %d descendants | BaseParts=%d MeshParts=%d Unions=%d Models=%d GuiObjects=%d Scripts=%d",
		index, row.name, row.className, row.count, row.baseParts, row.meshParts,
		row.unions, row.models, row.guiObjects, row.scripts
	))
end

print("-- Global class totals (largest first) --")
local classRows = {}
for className, count in pairs(classCounts) do
	table.insert(classRows, {name = className, count = count})
end
table.sort(classRows, function(a, b) return a.count > b.count end)
for index = 1, math.min(25, #classRows) do
	local row = classRows[index]
	print(string.format("%02d. %s = %d", index, row.name, row.count))
end

print("-- Objects named Theme --")
if #themeRows == 0 then print("No objects named exactly Theme were found.") end
for _, row in ipairs(themeRows) do print(row) end

print("-- Scripts containing 'Hello world!' --")
if #helloRows == 0 then print("No script source containing 'Hello world!' was readable/found.") end
for _, row in ipairs(helloRows) do print(row) end

print("-- Duplicate instance names (same class + name) --")
for index = 1, math.min(100, #duplicateNameRows) do print(duplicateNameRows[index]) end
if #duplicateNameRows > 100 then print("Additional duplicate-name groups omitted: " .. (#duplicateNameRows - 100)) end

print("========== END READ-ONLY AUDIT ==========")
