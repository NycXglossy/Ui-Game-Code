--!strict
-- Club Neon controller bootstrap helpers.
-- Dependency-injected: the main controller retains startup and state ownership.
return function(serverStorage: ServerStorage)
	local helpers = {}

	helpers.getOrCreate = function(parent: Instance, className: string, name: string): Instance
		local found = parent:FindFirstChild(name)
		if found and found.ClassName == className then return found end
		if found then found:Destroy() end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = parent
		return created
	end

	helpers.findAudioModule = function(moduleName: string): ModuleScript?
		if typeof(moduleName) ~= "string" or #moduleName < 1 or #moduleName > 100 then return nil end
		local modulesFolder = serverStorage:FindFirstChild("ClubMusicAudioModules")
		local candidate = if modulesFolder and modulesFolder:IsA("Folder") then modulesFolder:FindFirstChild(moduleName) else nil
		if candidate and candidate:IsA("ModuleScript") then return candidate end
		candidate = serverStorage:FindFirstChild(moduleName)
		if candidate and candidate:IsA("ModuleScript") then return candidate end
		return nil
	end

	helpers.findServerStorageModule = function(moduleName: string): Instance?
		if typeof(moduleName) ~= "string" or #moduleName < 1 or #moduleName > 100 then return nil end
		local direct = serverStorage:FindFirstChild(moduleName)
		if direct then return direct end
		local packageFolder = serverStorage:FindFirstChild("ClubMusic_ServerStorage_Modules")
		if packageFolder and packageFolder:IsA("Folder") then
			local bundled = packageFolder:FindFirstChild(moduleName)
			if bundled then return bundled end
		end
		local waited = serverStorage:WaitForChild(moduleName, 20)
		if waited then return waited end
		if packageFolder and packageFolder:IsA("Folder") then return packageFolder:WaitForChild(moduleName, 2) end
		return nil
	end

	return helpers
end
