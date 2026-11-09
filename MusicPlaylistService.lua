--!strict
-- MusicPlaylistService
-- Place as ModuleScript: ServerStorage/MusicPlaylistService
-- Persistent staff-managed playlists. Does not own playback or queue state.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local MusicPlaylistService = {}
local store = DataStoreService:GetDataStore("ClubMusic_Playlists_v1")
local KEY = "playlists"
local MAX_PLAYLISTS = 30
local MAX_TRACKS = 100
local MAX_NAME = 32

type Playlist = {id: string, name: string, trackIds: {string}, createdAt: number, updatedAt: number}
local playlists: {Playlist} = {}
local ready = false
local persistent = false
local busy = false

local function cleanName(value: any): string?
 if typeof(value) ~= "string" then return nil end
 local name = string.gsub(value, "^%s*(.-)%s*$", "%1")
 if #name < 2 or #name > MAX_NAME then return nil end
 if string.find(name, "[%c]") then return nil end
 return name
end

local function clonePlaylist(p: Playlist): Playlist
 return {id=p.id, name=p.name, trackIds=table.clone(p.trackIds), createdAt=p.createdAt, updatedAt=p.updatedAt}
end

local function sanitize(raw: any): {Playlist}
 local result: {Playlist} = {}
 if typeof(raw) ~= "table" or typeof(raw.playlists) ~= "table" then return result end
 local ids: {[string]: boolean} = {}
 local names: {[string]: boolean} = {}
 for _, item in ipairs(raw.playlists) do
  if #result >= MAX_PLAYLISTS then break end
  if typeof(item) == "table" and typeof(item.id) == "string" and #item.id <= 64
   and string.match(item.id, "^[%w%-_]+$") and not ids[item.id] then
   local name = cleanName(item.name)
   local folded = if name then string.lower(name) else ""
   if name and not names[folded] and typeof(item.trackIds) == "table" then
    local tracks: {string} = {}
    local seen: {[string]: boolean} = {}
    for _, trackId in ipairs(item.trackIds) do
     if #tracks >= MAX_TRACKS then break end
     if typeof(trackId) == "string" and #trackId <= 24
      and string.match(trackId, "^[%w%-_]+$") and not seen[trackId] then
      table.insert(tracks, trackId); seen[trackId] = true
     end
    end
    table.insert(result, {id=item.id, name=name, trackIds=tracks,
     createdAt=math.max(0, tonumber(item.createdAt) or 0),
     updatedAt=math.max(0, tonumber(item.updatedAt) or 0)})
    ids[item.id] = true; names[folded] = true
   end
  end
 end
 return result
end

local function pack(list: {Playlist})
 local data = {schemaVersion=1, playlists={}}
 for _, p in ipairs(list) do table.insert(data.playlists, clonePlaylist(p)) end
 return data
end

function MusicPlaylistService:Initialize(studioUseDataStore: boolean?, budgetCallback: (() -> boolean)?): boolean
 if ready then return true end
 persistent = not RunService:IsStudio() or studioUseDataStore == true
 if not persistent then ready = true; return true end
 if budgetCallback and not budgetCallback() then return false end
 local ok, data = pcall(function() return store:GetAsync(KEY) end)
 if not ok then warn("[ClubMusic Playlists] Initial load failed: " .. tostring(data)); return false end
 playlists = sanitize(data); ready = true
 return true
end

function MusicPlaylistService:IsReady(): boolean return ready end

function MusicPlaylistService:GetAll(): {Playlist}
 local result = {}
 for _, p in ipairs(playlists) do table.insert(result, clonePlaylist(p)) end
 table.sort(result, function(a,b)
  local aa,bb=string.lower(a.name),string.lower(b.name)
  return if aa == bb then a.id < b.id else aa < bb
 end)
 return result
end

function MusicPlaylistService:Refresh(budgetCallback: (() -> boolean)?): boolean
 if not ready then return false end
 if not persistent then return true end
 if busy then return false end
 -- Serialize refresh reads with mutations so a stale GetAsync cannot replace a
 -- newer in-memory playlist list after a successful UpdateAsync.
 busy = true
 if budgetCallback and not budgetCallback() then
  busy = false
  return false
 end
 local ok, data = pcall(function() return store:GetAsync(KEY) end)
 if not ok then
  busy = false
  warn("[ClubMusic Playlists] Refresh failed: " .. tostring(data))
  return false
 end
 playlists = sanitize(data)
 busy = false
 return true
end

local function applyMutation(self, mutate: ({Playlist}) -> (boolean, string)): (boolean, string)
 if not ready then return false, "Playlist storage is unavailable." end
 if busy then return false, "Playlist storage is busy. Try again shortly." end
 if not persistent then
  local candidate = {}
  for _, p in ipairs(playlists) do table.insert(candidate, clonePlaylist(p)) end
  local ok, message = mutate(candidate)
  if ok then playlists = candidate end
  return ok, message
 end
 busy = true
 local accepted, response = false, "Playlist save failed."
 local ok, result = pcall(function()
  return store:UpdateAsync(KEY, function(old)
   local candidate = sanitize(old)
   local changed, message = mutate(candidate)
   accepted, response = changed, message
   if not changed then return old end
   return pack(candidate)
  end)
 end)
 busy = false
 if not ok then warn("[ClubMusic Playlists] Mutation failed: " .. tostring(result)); return false, "Playlist save failed; no change was applied." end
 if not accepted then return false, response end
 playlists = sanitize(result)
 return true, response
end

function MusicPlaylistService:Create(name: any): (boolean, string, string?)
 local clean = cleanName(name)
 if not clean then return false, "Playlist names must be 2–32 characters.", nil end
 local id = HttpService:GenerateGUID(false)
 local now = os.time()
 local ok, message = applyMutation(self, function(list)
  if #list >= MAX_PLAYLISTS then return false, "The playlist limit (30) has been reached." end
  for _, p in ipairs(list) do if string.lower(p.name) == string.lower(clean) then return false, "A playlist with that name already exists." end end
  table.insert(list, {id=id, name=clean, trackIds={}, createdAt=now, updatedAt=now})
  return true, "Playlist created."
 end)
 return ok, message, if ok then id else nil
end

function MusicPlaylistService:Delete(id: any): (boolean, string)
 if typeof(id) ~= "string" or #id > 64 then return false, "Invalid playlist." end
 return applyMutation(self, function(list)
  for i,p in ipairs(list) do if p.id == id then table.remove(list,i); return true,"Playlist deleted." end end
  return false, "Playlist not found."
 end)
end

function MusicPlaylistService:AddTrack(id: any, trackId: any): (boolean, string)
 if typeof(id) ~= "string" or #id > 64 or typeof(trackId) ~= "string" or #trackId > 24
  or not string.match(trackId, "^[%w%-_]+$") then return false, "Invalid playlist or track." end
 return applyMutation(self, function(list)
  for _,p in ipairs(list) do if p.id == id then
   if table.find(p.trackIds, trackId) then return false,"That track is already in this playlist." end
   if #p.trackIds >= MAX_TRACKS then return false,"This playlist is full (100 tracks)." end
   table.insert(p.trackIds,trackId); p.updatedAt=os.time(); return true,"Track added to playlist."
  end end
  return false,"Playlist not found."
 end)
end

function MusicPlaylistService:RemoveTrack(id: any, trackId: any): (boolean, string)
 if typeof(id) ~= "string" or #id > 64 or typeof(trackId) ~= "string" or #trackId > 24 then return false,"Invalid playlist or track." end
 return applyMutation(self, function(list)
  for _,p in ipairs(list) do if p.id == id then
   local index = table.find(p.trackIds,trackId)
   if not index then return false,"Track not found in playlist." end
   table.remove(p.trackIds,index); p.updatedAt=os.time(); return true,"Track removed from playlist."
  end end
  return false,"Playlist not found."
 end)
end

function MusicPlaylistService:MoveTrack(id: any, trackId: any, position: any): (boolean, string)
 if typeof(id) ~= "string" or #id > 64 or typeof(trackId) ~= "string" or #trackId > 24
  or typeof(position) ~= "number" or position ~= position or position % 1 ~= 0 then return false,"Invalid playlist order." end
 return applyMutation(self, function(list)
  for _,p in ipairs(list) do if p.id == id then
   local old = table.find(p.trackIds,trackId)
   if not old then return false,"Track not found in playlist." end
   local target = math.clamp(position,1,#p.trackIds)
   table.remove(p.trackIds,old); table.insert(p.trackIds,target,trackId)
   p.updatedAt=os.time(); return true,"Playlist order updated."
  end end
  return false,"Playlist not found."
 end)
end

return MusicPlaylistService
