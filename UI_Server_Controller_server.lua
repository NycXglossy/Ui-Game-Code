--!strict
-- UI_Server_Controller
-- Place as Script: ServerScriptService/UI_Server_Controller
-- Creates the authoritative remote contract and validates every client request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local CONFIG = {
    GroupId = 0, -- Set to the Roblox group ID for rank/group features.
    RankThresholds = { Owner = 255, CoOwner = 254, Admin = 200, GroupDJ = 100 },

    -- Extra staff without needing a group (treated as OWNER).
    StaffUserIds = {} :: {number},
    -- In Studio every player is treated as OWNER so you can test the DJ booth.
    -- Set to false to test the normal guest experience in Studio.
    StudioStaff = true,

    -- VIP: any ONE of these grants VIP. Staff are always VIP. Staff can also grant temporary VIP in the DJ booth.
    VipGamePassId = 0,   -- Set to your VIP game pass ID (0 = disabled).
    VipGroupRank = 0,    -- Group rank that counts as VIP (0 = disabled; needs GroupId).
    VipPriority = true,  -- VIP requests jump ahead of normal player requests (never ahead of the playing track).

    MaxRequestsPerPlayer = 2,
    VipMaxRequestsPerPlayer = 4,
    RequestCooldownSeconds = 8,
    VipCooldownSeconds = 3,
    MaxQueueSize = 40,         -- Max PLAYER requests waiting at once.

    AutoQueueTarget = 3,       -- Auto DJ keeps at least this many tracks visible in the queue.
    AutoAvoidRecent = 6,       -- Auto DJ will not repeat any of the last N tracks.

    SkipVoteRatio = 0.5,       -- Share of players needed to skip by vote.
    SkipVoteMin = 2,           -- Minimum votes (capped to the number of players in the server).

    MaxFavorites = 60,
    ResyncSeconds = 5,         -- Clients interpolate between resyncs, so we don't spam every second.

    DataStoreName = "SunsetStageClubProfiles_v1",
    SaveIntervalSeconds = 90,

    -- Optional audio. Map trackId -> "rbxassetid://123". Tracks without an entry play silently
    -- (the UI still shows progress and an animated visualizer).
    SoundIds = {} :: {[string]: string},
}

local TRACKS: {[string]: {[string]: {title: string, artist: string, duration: number, genre: string}}} = {
    hiphop = {
        ["hh-0"]={title="Palm Tree Freestyle",artist="Lil Coconut",duration=184,genre="Hip Hop / Rap"},
        ["hh-1"]={title="Tide Money",artist="MC Lagoon",duration=201,genre="Hip Hop / Rap"},
        ["hh-2"]={title="Boardwalk Bounce",artist="Kid Kahuna",duration=176,genre="Hip Hop / Rap"},
        ["hh-3"]={title="Sandcastle Kings",artist="Reef Gang",duration=213,genre="Hip Hop / Rap"},
        ["hh-4"]={title="Midnight Luau",artist="Big Pineapple",duration=195,genre="Hip Hop / Rap"},
        ["hh-5"]={title="Wave Check",artist="Yung Tsunami",duration=168,genre="Hip Hop / Rap"},
    },
    rnb = {
        ["rnb-0"]={title="Golden Hour Love",artist="Coral Rose",duration=224,genre="R&B / Soul"},
        ["rnb-1"]={title="Slow Tide",artist="Marina Soul",duration=241,genre="R&B / Soul"},
        ["rnb-2"]={title="Tiki Torch Serenade",artist="D'Angelo Bay",duration=232,genre="R&B / Soul"},
        ["rnb-3"]={title="Velvet Shoreline",artist="Honey Kai",duration=207,genre="R&B / Soul"},
        ["rnb-4"]={title="Lantern Light",artist="Nalu & The Keys",duration=219,genre="R&B / Soul"},
    },
    rock = {
        ["rk-0"]={title="Volcano Riff",artist="The Lava Kings",duration=238,genre="Rock"},
        ["rk-1"]={title="Surf's Up Anthem",artist="Riptide Rebels",duration=199,genre="Rock"},
        ["rk-2"]={title="Driftwood Highway",artist="Saltwater Saints",duration=262,genre="Rock"},
        ["rk-3"]={title="Thunder on the Bay",artist="Coral Crush",duration=221,genre="Rock"},
    },
    kpop = {
        ["kp-0"]={title="SUMMER GLITCH",artist="NEONWAVE",duration=192,genre="K-Pop"},
        ["kp-1"]={title="Pink Horizon",artist="STARR1SE",duration=205,genre="K-Pop"},
        ["kp-2"]={title="Island Signal",artist="LUMI-9",duration=187,genre="K-Pop"},
        ["kp-3"]={title="Heartbeat Lagoon",artist="KORAL",duration=199,genre="K-Pop"},
        ["kp-4"]={title="Firework Kiss",artist="AURA X",duration=181,genre="K-Pop"},
    },
    latin = {
        ["lt-0"]={title="Playa Caliente",artist="DJ Mango",duration=214,genre="Latin Music"},
        ["lt-1"]={title="Bailando en la Arena",artist="Sol y Mar",duration=228,genre="Latin Music"},
        ["lt-2"]={title="Noche Tropical",artist="La Ola",duration=203,genre="Latin Music"},
        ["lt-3"]={title="Fuego Lento",artist="Rey Coco",duration=197,genre="Latin Music"},
    },
    edm = {
        ["edm-0"]={title="Sunset Overdrive",artist="Aqualux",duration=246,genre="EDM"},
        ["edm-1"]={title="Neon Coastline",artist="VOLTA",duration=233,genre="EDM"},
        ["edm-2"]={title="Tidal Drop",artist="Prism Reef",duration=258,genre="EDM"},
        ["edm-3"]={title="Laser Lagoon",artist="Kairo",duration=219,genre="EDM"},
        ["edm-4"]={title="Afterglow Rave",artist="SKYE.EXE",duration=271,genre="EDM"},
        ["edm-5"]={title="Bassquake Beach",artist="Subduction",duration=205,genre="EDM"},
    },
    country = {
        ["ct-0"]={title="Beach Truck Blues",artist="Dusty Shores",duration=212,genre="Country"},
        ["ct-1"]={title="Sunburnt Sweetheart",artist="Cody Cove",duration=198,genre="Country"},
        ["ct-2"]={title="Barefoot Rodeo",artist="The Palm Ranch",duration=205,genre="Country"},
    },
    pop = {
        ["pop-0"]={title="Electric Paradise",artist="Mia Lumen",duration=189,genre="Pop"},
        ["pop-1"]={title="Coconut Crush",artist="Jade Rivers",duration=176,genre="Pop"},
        ["pop-2"]={title="Ocean Eyes Tonight",artist="Leo Starr",duration=201,genre="Pop"},
        ["pop-3"]={title="Glow Up Summer",artist="Nova Bay",duration=183,genre="Pop"},
        ["pop-4"]={title="Postcard Heart",artist="Kenna Blue",duration=194,genre="Pop"},
    },
    exclusive = {
        ["ex-0"]={title="Sunset Stage Anthem",artist="Club Resident",duration=262,genre="Club Exclusives"},
        ["ex-1"]={title="Tiki Torch Theory",artist="Club Resident ft. VOLTA",duration=238,genre="Club Exclusives"},
        ["ex-2"]={title="Low-Poly Paradise",artist="Pixel Palms",duration=224,genre="Club Exclusives"},
        ["ex-3"]={title="Mainstage Moonrise",artist="The Owners",duration=289,genre="Club Exclusives"},
    },
}

type Track = { id: string, genreId: string, title: string, artist: string, duration: number, genre: string }

-- Flat lookup so the "All Tracks" tab and favorites can reference any track by id.
local TRACK_BY_ID: {[string]: Track} = {}
local ALL_TRACK_IDS: {string} = {}
for genreId, list in pairs(TRACKS) do
    for id, t in pairs(list) do
        TRACK_BY_ID[id] = { id = id, genreId = genreId, title = t.title, artist = t.artist, duration = t.duration, genre = t.genre }
        table.insert(ALL_TRACK_IDS, id)
    end
end
table.sort(ALL_TRACK_IDS)

local TAGS: {[string]: boolean} = {
    vip = true, party = true, wave = true, tiki = true, sunset = true, bass = true, island = true,
}
local DAILY_REWARD_COUNT = 7
local store = DataStoreService:GetDataStore(CONFIG.DataStoreName)
local random = Random.new()

local function getOrCreate(parent: Instance, className: string, name: string): Instance
    local found = parent:FindFirstChild(name)
    if found and found.ClassName == className then return found end
    if found then found:Destroy() end
    local created = Instance.new(className)
    created.Name = name
    created.Parent = parent
    return created
end

local remotes = getOrCreate(ReplicatedStorage, "Folder", "ClubMusicRemotes") :: Folder
local actionRemote = getOrCreate(remotes, "RemoteEvent", "RequestAction") :: RemoteEvent
local stateRemote = getOrCreate(remotes, "RemoteEvent", "StateChanged") :: RemoteEvent
local noticeRemote = getOrCreate(remotes, "RemoteEvent", "Notice") :: RemoteEvent
local stateFunction = getOrCreate(remotes, "RemoteFunction", "GetState") :: RemoteFunction

local configFolder = getOrCreate(ReplicatedStorage, "Folder", "ClubMusicConfig") :: Folder
configFolder:SetAttribute("GroupId", CONFIG.GroupId)

type QueueEntry = {
    id: string,
    trackId: string,
    title: string,
    artist: string,
    duration: number,
    requestedBy: string,
    userId: number,
    genre: string,
    source: string, -- "player" | "auto"
    vip: boolean,
}
type Profile = {
    tickets: number,
    coins: number,
    loginStreak: number,
    lastClaimDay: number,
    claimedToday: boolean,
    equippedTag: string?,
    ownedTags: {[string]: boolean},
    glowsticks: number,
    skipTokens: number,
    neonTrail: boolean,
    favorites: {[string]: boolean},
}

local profiles: {[number]: Profile} = {}
local queue: {QueueEntry} = {}
local nowPlaying = {
    trackId = "",
    title = "",
    artist = "",
    genre = "",
    duration = 1,
    elapsed = 0,
    dj = "Automated Selector",
    source = "auto",
    requestedBy = "Auto DJ",
    vip = false,
    soundId = "",
}
local requestCounts: {[number]: number} = {}
local lastRequestAt: {[number]: number} = {}
local lastActionAt: {[number]: number} = {}
local queueCounter = 0

-- Session-only moderation / VIP / vote state
local rankCache: {[number]: {rank: string, level: number}} = {}
local vipPass: {[number]: boolean} = {}
local tempVip: {[number]: boolean} = {}
local blockedUsers: {[number]: boolean} = {}
local skipVotes: {[number]: boolean} = {}
local requestsLocked = false
local recentTracks: {string} = {}
local lastAutoGenre = ""

-- Ranks, permissions and VIP -------------------------------------------------

local function computeRank(player: Player): (string, number)
    for _, id in ipairs(CONFIG.StaffUserIds) do
        if id == player.UserId then return "OWNER", 4 end
    end
    if CONFIG.StudioStaff and RunService:IsStudio() then return "OWNER", 4 end
    if CONFIG.GroupId <= 0 then return "GUEST", 0 end

    local ok, rank = pcall(function() return player:GetRankInGroup(CONFIG.GroupId) end)
    if not ok or typeof(rank) ~= "number" then return "GUEST", 0 end
    local t = CONFIG.RankThresholds
    if rank >= t.Owner then return "OWNER", 4 end
    if rank >= t.CoOwner then return "CO-OWNER", 3 end
    if rank >= t.Admin then return "ADMIN", 2 end
    if rank >= t.GroupDJ then return "GROUP DJ", 1 end
    return "GUEST", 0
end

-- Yields (group lookups). Never call from the per-second loop.
local function refreshRank(player: Player)
    local rank, level = computeRank(player)
    rankCache[player.UserId] = { rank = rank, level = level }
end

local function getRank(player: Player): string
    local cached = rankCache[player.UserId]
    return if cached then cached.rank else "GUEST"
end

-- Permission level: 0 guest, 1 GROUP DJ, 2 ADMIN, 3 CO-OWNER, 4 OWNER
local function getLevel(player: Player): number
    local cached = rankCache[player.UserId]
    return if cached then cached.level else 0
end

local function isStaff(player: Player): boolean
    return getLevel(player) >= 1
end

local function isAdmin(player: Player): boolean
    return getLevel(player) >= 2
end

local function isVip(player: Player): boolean
    return getLevel(player) >= 1 or vipPass[player.UserId] == true or tempVip[player.UserId] == true
end

-- Owners can moderate anyone but themselves; everyone else only moderates strictly lower ranks.
local function canModerate(actor: Player, target: Player): boolean
    if actor == target then return false end
    local actorLevel = getLevel(actor)
    if actorLevel >= 4 then return true end
    return getLevel(target) < actorLevel
end

local function applyVipAttribute(player: Player)
    player:SetAttribute("IsVIP", isVip(player))
end

-- Yields (marketplace / group lookups).
local function refreshVip(player: Player)
    local pass = false
    if CONFIG.VipGamePassId > 0 then
        local ok, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, CONFIG.VipGamePassId)
        end)
        if ok and owns == true then pass = true end
    end
    if not pass and CONFIG.VipGroupRank > 0 and CONFIG.GroupId > 0 then
        local ok, rank = pcall(function() return player:GetRankInGroup(CONFIG.GroupId) end)
        if ok and typeof(rank) == "number" and rank >= CONFIG.VipGroupRank then pass = true end
    end
    vipPass[player.UserId] = pass
end

local function requestLimitFor(player: Player): number
    return if isVip(player) then CONFIG.VipMaxRequestsPerPlayer else CONFIG.MaxRequestsPerPlayer
end

local function cooldownFor(player: Player): number
    return if isVip(player) then CONFIG.VipCooldownSeconds else CONFIG.RequestCooldownSeconds
end

-- Profiles --------------------------------------------------------------------

local function defaultProfile(): Profile
    return {
        tickets = 0,
        coins = 0,
        loginStreak = 1,
        lastClaimDay = 0,
        claimedToday = false,
        equippedTag = nil,
        ownedTags = {vip=true, party=true, wave=true},
        glowsticks = 0,
        skipTokens = 0,
        neonTrail = false,
        favorites = {},
    }
end

local function loadProfile(player: Player)
    local profile = defaultProfile()
    local ok, data = pcall(function()
        return store:GetAsync(tostring(player.UserId))
    end)
    if ok and typeof(data) == "table" then
        profile.tickets = math.max(0, tonumber(data.tickets) or 0)
        profile.coins = math.max(0, tonumber(data.coins) or 0)
        profile.loginStreak = math.clamp(math.floor(tonumber(data.loginStreak) or 1), 1, 7)
        profile.lastClaimDay = math.max(0, math.floor(tonumber(data.lastClaimDay) or 0))
        profile.claimedToday = data.claimedToday == true
        profile.equippedTag = if typeof(data.equippedTag) == "string" then data.equippedTag else nil
        profile.glowsticks = math.max(0, math.floor(tonumber(data.glowsticks) or 0))
        profile.skipTokens = math.max(0, math.floor(tonumber(data.skipTokens) or 0))
        profile.neonTrail = data.neonTrail == true
        if typeof(data.ownedTags) == "table" then
            for id, owned in pairs(data.ownedTags) do
                if TAGS[id] == true and owned == true then profile.ownedTags[id] = true end
            end
        end
        if typeof(data.favorites) == "table" then
            local count = 0
            for id, flag in pairs(data.favorites) do
                if count >= CONFIG.MaxFavorites then break end
                if typeof(id) == "string" and flag == true and TRACK_BY_ID[id] then
                    profile.favorites[id] = true
                    count += 1
                end
            end
        end
    elseif not ok then
        warn("[ClubMusic] Profile load failed for " .. player.Name .. ": " .. tostring(data))
    end
    local today = math.floor(os.time() / 86400)
    if profile.lastClaimDay < today then
        if profile.lastClaimDay > 0 and today - profile.lastClaimDay == 1 then
            profile.loginStreak = (profile.loginStreak % 7) + 1
        elseif profile.lastClaimDay == 0 or today - profile.lastClaimDay > 1 then
            profile.loginStreak = 1
        end
        profile.claimedToday = false
    end

    profiles[player.UserId] = profile
    player:SetAttribute("Tickets", profile.tickets)
    player:SetAttribute("Coins", profile.coins)
    player:SetAttribute("Glowsticks", profile.glowsticks)
    player:SetAttribute("SkipTokens", profile.skipTokens)
    player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
    player:SetAttribute("LoginStreak", profile.loginStreak)
    player:SetAttribute("ClaimedToday", profile.claimedToday)
    player:SetAttribute("EquippedTag", profile.equippedTag or "")
end

local function saveProfile(player: Player)
    local profile = profiles[player.UserId]
    if not profile then return end
    local snapshot = {
        tickets = profile.tickets,
        coins = profile.coins,
        loginStreak = profile.loginStreak,
        lastClaimDay = profile.lastClaimDay,
        claimedToday = profile.claimedToday,
        equippedTag = profile.equippedTag,
        ownedTags = profile.ownedTags,
        glowsticks = profile.glowsticks,
        skipTokens = profile.skipTokens,
        neonTrail = profile.neonTrail,
        favorites = profile.favorites,
    }
    local ok, err = pcall(function()
        store:UpdateAsync(tostring(player.UserId), function()
            return snapshot
        end)
    end)
    if not ok then warn("[ClubMusic] Profile save failed for " .. player.Name .. ": " .. tostring(err)) end
end

-- Queue / Auto DJ ---------------------------------------------------------------

local function makeEntry(track: Track, source: string, player: Player?): QueueEntry
    queueCounter += 1
    return {
        id = (if player then tostring(player.UserId) else "auto") .. "-" .. tostring(queueCounter),
        trackId = track.id,
        title = track.title,
        artist = track.artist,
        duration = track.duration,
        requestedBy = if player then player.DisplayName else "Auto DJ",
        userId = if player then player.UserId else 0,
        genre = track.genre,
        source = source,
        vip = if player then isVip(player) else false,
    }
end

local function releaseSlot(entry: QueueEntry)
    if entry.source == "player" and entry.userId > 0 then
        local remaining = (requestCounts[entry.userId] or 0) - 1
        requestCounts[entry.userId] = if remaining > 0 then remaining else nil
    end
end

local function countPlayerEntries(): number
    local n = 0
    for _, entry in ipairs(queue) do
        if entry.source == "player" then n += 1 end
    end
    return n
end

local function findQueueIndex(id: string): number?
    for index, entry in ipairs(queue) do
        if entry.id == id then return index end
    end
    return nil
end

-- Queue order: [VIP requests][normal requests][auto tracks]
local function insertIndex(vip: boolean): number
    local lastVip, lastPlayer = 0, 0
    for index, entry in ipairs(queue) do
        if entry.source == "player" then
            lastPlayer = index
            if entry.vip then lastVip = index end
        end
    end
    if vip and CONFIG.VipPriority then return lastVip + 1 end
    return lastPlayer + 1
end

local function pickAutoTrack(): Track
    local queued: {[string]: boolean} = {}
    for _, entry in ipairs(queue) do queued[entry.trackId] = true end
    local recentSet: {[string]: boolean} = {}
    for _, id in ipairs(recentTracks) do recentSet[id] = true end

    local pool: {Track} = {}
    local preferred: {Track} = {}
    for _, id in ipairs(ALL_TRACK_IDS) do
        local track = TRACK_BY_ID[id]
        if not queued[id] and not recentSet[id] and id ~= nowPlaying.trackId then
            table.insert(pool, track)
            if track.genreId ~= lastAutoGenre then table.insert(preferred, track) end
        end
    end

    local source = if #preferred > 0 then preferred elseif #pool > 0 then pool else nil
    if source then
        local chosen = source[random:NextInteger(1, #source)]
        lastAutoGenre = chosen.genreId
        return chosen
    end
    return TRACK_BY_ID[ALL_TRACK_IDS[random:NextInteger(1, #ALL_TRACK_IDS)]]
end

local function topUpAuto()
    local guard = 0
    while #queue < CONFIG.AutoQueueTarget and guard < 10 do
        guard += 1
        table.insert(queue, makeEntry(pickAutoTrack(), "auto", nil))
    end
end

local function setNowPlaying(entry: QueueEntry)
    nowPlaying.trackId = entry.trackId
    nowPlaying.title = entry.title
    nowPlaying.artist = entry.artist
    nowPlaying.genre = entry.genre
    nowPlaying.duration = math.max(1, entry.duration)
    nowPlaying.elapsed = 0
    nowPlaying.dj = "Automated Selector"
    nowPlaying.source = entry.source
    nowPlaying.requestedBy = entry.requestedBy
    nowPlaying.vip = entry.vip
    nowPlaying.soundId = CONFIG.SoundIds[entry.trackId] or ""

    table.insert(recentTracks, entry.trackId)
    while #recentTracks > CONFIG.AutoAvoidRecent do
        table.remove(recentTracks, 1)
    end
    table.clear(skipVotes)
end

local function advance()
    local nextEntry = table.remove(queue, 1)
    if nextEntry then
        releaseSlot(nextEntry)
    else
        nextEntry = makeEntry(pickAutoTrack(), "auto", nil)
    end
    setNowPlaying(nextEntry :: QueueEntry)
    topUpAuto()
end

-- Boot: start with an auto-selected track and a visible auto queue.
setNowPlaying(makeEntry(TRACK_BY_ID["edm-0"], "auto", nil))
topUpAuto()

-- Skip voting ---------------------------------------------------------------------

local function skipStatus(player: Player?): (number, number, boolean)
    local list = Players:GetPlayers()
    local count = #list
    local votes = 0
    for _, p in ipairs(list) do
        if skipVotes[p.UserId] then votes += 1 end
    end
    local needed = math.min(count, math.max(CONFIG.SkipVoteMin, math.ceil(count * CONFIG.SkipVoteRatio)))
    needed = math.max(needed, 1)
    local voted = if player then skipVotes[player.UserId] == true else false
    return votes, needed, voted
end

local function checkSkipVotes(): boolean
    local votes, needed = skipStatus(nil)
    if votes > 0 and votes >= needed then
        advance()
        return true
    end
    return false
end

-- State publishing ------------------------------------------------------------------

local function snapshotFor(player: Player)
    local profile = profiles[player.UserId] or defaultProfile()
    local level = getLevel(player)
    local vip = isVip(player)

    local safeQueue = {}
    for _, item in ipairs(queue) do
        table.insert(safeQueue, {
            id = item.id, trackId = item.trackId, title = item.title, artist = item.artist,
            duration = item.duration, requestedBy = item.requestedBy, genre = item.genre,
            source = item.source, vip = item.vip,
        })
    end

    local favorites = {}
    for id in pairs(profile.favorites) do favorites[id] = true end

    local votes, needed, voted = skipStatus(player)

    local snapshot = {
        rank = getRank(player),
        perm = level,
        vip = vip,
        queue = safeQueue,
        nowPlaying = {
            trackId = nowPlaying.trackId, title = nowPlaying.title, artist = nowPlaying.artist,
            genre = nowPlaying.genre, duration = nowPlaying.duration, elapsed = nowPlaying.elapsed,
            dj = nowPlaying.dj, source = nowPlaying.source, requestedBy = nowPlaying.requestedBy,
            vip = nowPlaying.vip, soundId = nowPlaying.soundId,
        },
        favorites = favorites,
        skip = { votes = votes, needed = needed, voted = voted },
        requests = { used = requestCounts[player.UserId] or 0, limit = requestLimitFor(player) },
        locked = requestsLocked,
        blocked = blockedUsers[player.UserId] == true,
        vipPerks = {
            slots = CONFIG.VipMaxRequestsPerPlayer,
            cooldown = CONFIG.VipCooldownSeconds,
            baseSlots = CONFIG.MaxRequestsPerPlayer,
            baseCooldown = CONFIG.RequestCooldownSeconds,
            priority = CONFIG.VipPriority,
        },
        vipGamePassId = CONFIG.VipGamePassId,
        equippedTag = profile.equippedTag,
        ownedTags = profile.ownedTags,
        loginStreak = profile.loginStreak,
        claimedToday = profile.claimedToday,
        tickets = profile.tickets,
        coins = profile.coins,
        glowsticks = profile.glowsticks,
        skipTokens = profile.skipTokens,
        neonTrail = profile.neonTrail,
        groupId = CONFIG.GroupId,
        players = nil :: any,
    }

    -- Only staff receive the moderation roster.
    if level >= 1 then
        local roster = {}
        for _, other in ipairs(Players:GetPlayers()) do
            table.insert(roster, {
                userId = other.UserId,
                name = other.Name,
                displayName = other.DisplayName,
                rank = getRank(other),
                vip = isVip(other),
                tempVip = tempVip[other.UserId] == true,
                blocked = blockedUsers[other.UserId] == true,
                requests = requestCounts[other.UserId] or 0,
                canMod = canModerate(player, other),
            })
        end
        snapshot.players = roster
    end

    return snapshot
end

local function publishState(player: Player?)
    if player then
        stateRemote:FireClient(player, snapshotFor(player))
    else
        for _, target in ipairs(Players:GetPlayers()) do
            stateRemote:FireClient(target, snapshotFor(target))
        end
    end
end

local function notify(player: Player, text: string, kind: string?)
    noticeRemote:FireClient(player, { text = text, kind = kind or "info" })
end

local function broadcast(text: string, kind: string?)
    noticeRemote:FireAllClients({ text = text, kind = kind or "info" })
end

local function isValidString(value: any, maxLength: number): boolean
    return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

local function findTarget(actor: Player, userId: any): Player?
    if typeof(userId) ~= "number" or userId % 1 ~= 0 then return nil end
    local target = Players:GetPlayerByUserId(userId)
    if not target then return nil end
    if target == actor then return nil end
    if not canModerate(actor, target) then
        notify(actor, "You can't moderate someone with equal or higher rank.", "warn")
        return nil
    end
    return target
end

local function purgeUserEntries(userId: number): number
    local removed = 0
    for index = #queue, 1, -1 do
        local entry = queue[index]
        if entry.source == "player" and entry.userId == userId then
            releaseSlot(entry)
            table.remove(queue, index)
            removed += 1
        end
    end
    if removed > 0 then topUpAuto() end
    return removed
end

-- Actions -----------------------------------------------------------------------------

local function handleAction(player: Player, action: any, payload: any)
    if not isValidString(action, 32) or typeof(payload) ~= "table" then return end

    -- Light global throttle so a client can't hammer any action.
    local now = os.clock()
    if now - (lastActionAt[player.UserId] or 0) < 0.12 then return end
    lastActionAt[player.UserId] = now

    if action == "RequestTrack" then
        local trackId = payload.trackId
        if not isValidString(trackId, 24) then return end
        local track = TRACK_BY_ID[trackId]
        if not track then return end

        local level = getLevel(player)
        if blockedUsers[player.UserId] then
            notify(player, "Your requests are disabled by staff.", "warn")
            return
        end
        if requestsLocked and level < 1 then
            notify(player, "Requests are locked by staff right now.", "warn")
            return
        end
        if countPlayerEntries() >= CONFIG.MaxQueueSize then
            notify(player, "The request queue is full.", "warn")
            return
        end

        local cooldown = cooldownFor(player)
        local sinceLast = now - (lastRequestAt[player.UserId] or -1000)
        if sinceLast < cooldown then
            notify(player, string.format("Slow down - wait %ds to request again.", math.ceil(cooldown - sinceLast)), "warn")
            return
        end

        local count = requestCounts[player.UserId] or 0
        local limit = requestLimitFor(player)
        if count >= limit then
            notify(player, string.format("Request limit reached (%d/%d). Wait for your track to play.", count, limit), "warn")
            return
        end

        if nowPlaying.trackId == track.id then
            notify(player, "That track is playing right now.", "warn")
            return
        end
        for _, queued in ipairs(queue) do
            if queued.trackId == track.id then
                notify(player, "That track is already in the queue.", "warn")
                return
            end
        end

        local vip = isVip(player)
        local entry = makeEntry(track, "player", player)
        table.insert(queue, insertIndex(vip), entry)
        requestCounts[player.UserId] = count + 1
        lastRequestAt[player.UserId] = now
        notify(player, if vip and CONFIG.VipPriority then "Requested with VIP priority!" else "Track requested!", "ok")
        publishState(nil)
        return
    end

    if action == "ToggleFavorite" then
        local trackId = payload.trackId
        if not isValidString(trackId, 24) or not TRACK_BY_ID[trackId] then return end
        local profile = profiles[player.UserId]
        if not profile then return end
        if profile.favorites[trackId] then
            profile.favorites[trackId] = nil
        else
            local count = 0
            for _ in pairs(profile.favorites) do count += 1 end
            if count >= CONFIG.MaxFavorites then
                notify(player, "Favorites list is full.", "warn")
                return
            end
            profile.favorites[trackId] = true
        end
        publishState(player)
        return
    end

    if action == "VoteSkip" then
        if skipVotes[player.UserId] then
            notify(player, "You already voted to skip this track.", "warn")
            return
        end
        skipVotes[player.UserId] = true
        if checkSkipVotes() then
            broadcast("Track skipped by vote.", "ok")
        else
            local votes, needed = skipStatus(nil)
            notify(player, string.format("Skip vote counted (%d/%d).", votes, needed), "ok")
        end
        publishState(nil)
        return
    end

    -- Staff ----------------------------------------------------------------------------

    if action == "DJMoveUp" then
        if not isStaff(player) then return end
        local id = payload.queueId
        if not isValidString(id, 64) then return end
        local index = findQueueIndex(id)
        if index and index > 1 then
            queue[index], queue[index - 1] = queue[index - 1], queue[index]
            publishState(nil)
        end
        return
    end

    if action == "DJRemove" then
        if not isStaff(player) then return end
        local id = payload.queueId
        if not isValidString(id, 64) then return end
        local index = findQueueIndex(id)
        if index then
            releaseSlot(queue[index])
            table.remove(queue, index)
            topUpAuto()
            publishState(nil)
        end
        return
    end

    if action == "DJSkip" then
        if not isStaff(player) then return end
        advance()
        notify(player, "Track skipped.", "ok")
        publishState(nil)
        return
    end

    if action == "DJClearQueue" then
        if not isAdmin(player) then return end
        for _, entry in ipairs(queue) do releaseSlot(entry) end
        table.clear(queue)
        topUpAuto()
        notify(player, "Queue cleared.", "ok")
        publishState(nil)
        return
    end

    if action == "DJToggleLock" then
        if not isStaff(player) then return end
        requestsLocked = not requestsLocked
        broadcast(if requestsLocked then "Song requests are now LOCKED." else "Song requests are open again.", "info")
        publishState(nil)
        return
    end

    if action == "ModBlockUser" then
        if not isAdmin(player) then return end
        local target = findTarget(player, payload.userId)
        if not target or typeof(payload.blocked) ~= "boolean" then return end
        if payload.blocked then
            blockedUsers[target.UserId] = true
            purgeUserEntries(target.UserId)
            notify(target, "Staff disabled your song requests.", "warn")
            notify(player, target.DisplayName .. " can no longer request songs.", "ok")
        else
            blockedUsers[target.UserId] = nil
            notify(target, "Your song requests were re-enabled.", "ok")
            notify(player, target.DisplayName .. " can request songs again.", "ok")
        end
        publishState(nil)
        return
    end

    if action == "ModSetVip" then
        if not isAdmin(player) then return end
        local target = findTarget(player, payload.userId)
        if not target or typeof(payload.vip) ~= "boolean" then return end
        tempVip[target.UserId] = if payload.vip then true else nil
        applyVipAttribute(target)
        notify(target, if payload.vip then "You were given VIP by staff!" else "Your staff-granted VIP was removed.", "info")
        notify(player, (if payload.vip then "VIP granted to " else "VIP removed from ") .. target.DisplayName .. ".", "ok")
        publishState(nil)
        return
    end

    if action == "ModPurgeUser" then
        if not isAdmin(player) then return end
        local target = findTarget(player, payload.userId)
        if not target then return end
        local removed = purgeUserEntries(target.UserId)
        notify(player, string.format("Removed %d request(s) from %s.", removed, target.DisplayName), "ok")
        publishState(nil)
        return
    end

    -- Rewards / cosmetics -------------------------------------------------------------

    if action == "ClaimDailyReward" then
        local day = payload.day
        if typeof(day) ~= "number" or day % 1 ~= 0 or day < 1 or day > DAILY_REWARD_COUNT then return end
        local profile = profiles[player.UserId]
        if not profile or profile.claimedToday or day ~= profile.loginStreak then return end

        -- Grants map directly to the reward labels in the supplied data file.
        if day == 1 then profile.coins += 50
        elseif day == 2 then profile.glowsticks += 2
        elseif day == 3 then profile.tickets += 100
        elseif day == 4 then profile.skipTokens += 1
        elseif day == 5 then profile.coins += 250
        elseif day == 6 then profile.neonTrail = true
        elseif day == 7 then profile.ownedTags.island = true
        end
        profile.claimedToday = true
        profile.lastClaimDay = math.floor(os.time() / 86400)
        player:SetAttribute("Tickets", profile.tickets)
        player:SetAttribute("Coins", profile.coins)
        player:SetAttribute("Glowsticks", profile.glowsticks)
        player:SetAttribute("SkipTokens", profile.skipTokens)
        player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
        player:SetAttribute("ClaimedToday", true)
        task.spawn(saveProfile, player)
        publishState(player)
        return
    end

    if action == "EquipTitleTag" then
        local tagId = payload.tagId
        if not isValidString(tagId, 24) or TAGS[tagId] ~= true then return end
        local profile = profiles[player.UserId]
        if not profile or profile.ownedTags[tagId] ~= true then return end
        profile.equippedTag = tagId
        player:SetAttribute("EquippedTag", tagId)
        task.spawn(saveProfile, player)
        publishState(player)
        return
    end
end

stateFunction.OnServerInvoke = function(player: Player)
    return snapshotFor(player)
end

actionRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
    local ok, err = pcall(handleAction, player, action, payload)
    if not ok then warn("[ClubMusic] Action handler error: " .. tostring(err)) end
end)

-- Player lifecycle ----------------------------------------------------------------------

local function onJoin(player: Player)
    refreshRank(player)
    refreshVip(player)
    loadProfile(player)
    applyVipAttribute(player)
    player:SetAttribute("ClubRank", getRank(player))
    publishState(nil) -- also refreshes the staff roster for everyone with access
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(onJoin, player)
end)

Players.PlayerRemoving:Connect(function(player)
    saveProfile(player)
    local userId = player.UserId
    profiles[userId] = nil
    requestCounts[userId] = nil
    lastRequestAt[userId] = nil
    lastActionAt[userId] = nil
    rankCache[userId] = nil
    vipPass[userId] = nil
    tempVip[userId] = nil
    blockedUsers[userId] = nil
    skipVotes[userId] = nil
    -- The leaving player may still be counted by GetPlayers(); re-check next frame.
    task.defer(function()
        if checkSkipVotes() then broadcast("Track skipped by vote.", "ok") end
        publishState(nil)
    end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onJoin, player)
end

-- Purchasing the VIP pass mid-session unlocks VIP immediately.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
    if purchased and CONFIG.VipGamePassId > 0 and passId == CONFIG.VipGamePassId then
        vipPass[player.UserId] = true
        applyVipAttribute(player)
        notify(player, "VIP unlocked - enjoy priority requests!", "ok")
        publishState(nil)
    end
end)

task.spawn(function()
    while true do
        task.wait(CONFIG.SaveIntervalSeconds)
        for _, player in ipairs(Players:GetPlayers()) do
            saveProfile(player)
        end
    end
end)

-- Periodically re-check group rank / VIP so promotions apply without rejoining.
task.spawn(function()
    while true do
        task.wait(60)
        for _, player in ipairs(Players:GetPlayers()) do
            task.spawn(function()
                refreshRank(player)
                refreshVip(player)
                applyVipAttribute(player)
            end)
        end
    end
end)

-- The server publishes authoritative elapsed time and current state. Clients interpolate between
-- resyncs. Audio plays on each client when a SoundId is configured in CONFIG.SoundIds.
task.spawn(function()
    local ticks = 0
    while true do
        task.wait(1)
        nowPlaying.elapsed += 1
        ticks += 1
        if nowPlaying.elapsed >= nowPlaying.duration then
            advance()
            ticks = 0
            publishState(nil)
        elseif ticks >= CONFIG.ResyncSeconds then
            ticks = 0
            publishState(nil)
        end
    end
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        saveProfile(player)
    end
end)
