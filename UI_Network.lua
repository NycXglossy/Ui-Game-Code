--!strict
-- UI_Network
-- Place as ModuleScript: ReplicatedStorage/UI_Network
-- Client-only transport facade. The server creates and owns all remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = {}
Network.__index = Network

local FOLDER_NAME = "ClubMusicRemotes"
local ACTION_EVENT = "RequestAction"
local STATE_EVENT = "StateChanged"
local STATE_FUNCTION = "GetState"
local NOTICE_EVENT = "Notice"

export type Notice = {
    text: string,
    kind: string,
}

export type State = {
    rank: string,
    perm: number,
    vip: boolean,
    queue: {any},
    nowPlaying: {[string]: any},
    favorites: {[string]: boolean},
    skip: {votes: number, needed: number, voted: boolean},
    requests: {used: number, limit: number},
    locked: boolean,
    blocked: boolean,
    vipPerks: {[string]: any},
    vipGamePassId: number,
    players: {any}?,
    equippedTag: string?,
    ownedTags: {[string]: boolean}?,
    loginStreak: number,
    claimedToday: boolean,
    tickets: number,
    coins: number,
    groupId: number,
}

local folder: Folder? = nil
local actionRemote: RemoteEvent? = nil
local stateRemote: RemoteEvent? = nil
local noticeRemote: RemoteEvent? = nil
local stateFunction: RemoteFunction? = nil
local stateChanged = Instance.new("BindableEvent")
local noticeReceived = Instance.new("BindableEvent")
local latestState: State? = nil
local stateConnected = false
local noticeConnected = false
local lastFailAt = 0

local function resolve(): boolean
    if folder and folder.Parent and actionRemote and stateRemote and stateFunction then
        return true
    end

    -- Do not block every call for 20+ seconds when the server remotes are missing.
    if lastFailAt > 0 and os.clock() - lastFailAt < 10 then
        return false
    end

    local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, 20)
    if not found or not found:IsA("Folder") then
        lastFailAt = os.clock()
        warn("[ClubMusic] Server remotes were not found. UI will remain in offline/read-only mode.")
        return false
    end

    folder = found
    local action = found:WaitForChild(ACTION_EVENT, 10)
    local state = found:WaitForChild(STATE_EVENT, 10)
    local getState = found:WaitForChild(STATE_FUNCTION, 10)
    local notice = found:WaitForChild(NOTICE_EVENT, 5) -- optional: older servers do not have it

    if not action or not action:IsA("RemoteEvent")
        or not state or not state:IsA("RemoteEvent")
        or not getState or not getState:IsA("RemoteFunction") then
        lastFailAt = os.clock()
        warn("[ClubMusic] Remote contract is incomplete.")
        return false
    end

    actionRemote = action
    stateRemote = state
    stateFunction = getState

    if not stateConnected then
        stateConnected = true
        state.OnClientEvent:Connect(function(nextState: State)
            latestState = nextState
            stateChanged:Fire(nextState)
        end)
    end

    if notice and notice:IsA("RemoteEvent") then
        noticeRemote = notice
        if not noticeConnected then
            noticeConnected = true
            notice.OnClientEvent:Connect(function(payload: Notice)
                if typeof(payload) == "table" and typeof(payload.text) == "string" then
                    noticeReceived:Fire(payload)
                end
            end)
        end
    end

    return true
end

-- Fetches the authoritative state from the server and broadcasts it to listeners.
function Network.Refresh(): State?
    if not resolve() then
        return nil
    end

    local ok, result = pcall(function()
        return (stateFunction :: RemoteFunction):InvokeServer()
    end)
    if ok and typeof(result) == "table" then
        latestState = result :: State
        stateChanged:Fire(latestState)
        return latestState
    end

    return nil
end

function Network.Init(): boolean
    if Network.Refresh() then
        return true
    end

    warn("[ClubMusic] Could not fetch initial server state.")
    return false
end

function Network.GetState(): State?
    return latestState
end

function Network.OnStateChanged(callback: (State) -> ()): RBXScriptConnection
    return stateChanged.Event:Connect(callback)
end

function Network.OnNotice(callback: (Notice) -> ()): RBXScriptConnection
    return noticeReceived.Event:Connect(callback)
end

function Network.Send(actionName: string, payload: {[string]: any}?): boolean
    if not resolve() then
        return false
    end
    (actionRemote :: RemoteEvent):FireServer(actionName, payload or {})
    return true
end

-- Listener requests ---------------------------------------------------------

function Network.RequestTrack(genreId: string, trackId: string): boolean
    return Network.Send("RequestTrack", { genreId = genreId, trackId = trackId })
end

function Network.ToggleFavorite(trackId: string): boolean
    return Network.Send("ToggleFavorite", { trackId = trackId })
end

function Network.VoteSkip(): boolean
    return Network.Send("VoteSkip", {})
end

-- DJ / staff ----------------------------------------------------------------

function Network.DJMoveUp(queueId: string): boolean
    return Network.Send("DJMoveUp", { queueId = queueId })
end

function Network.DJRemove(queueId: string): boolean
    return Network.Send("DJRemove", { queueId = queueId })
end

function Network.DJSkip(): boolean
    return Network.Send("DJSkip", {})
end

function Network.DJClearQueue(): boolean
    return Network.Send("DJClearQueue", {})
end

function Network.DJToggleLock(): boolean
    return Network.Send("DJToggleLock", {})
end

function Network.ModBlockUser(userId: number, blocked: boolean): boolean
    return Network.Send("ModBlockUser", { userId = userId, blocked = blocked })
end

function Network.ModSetVip(userId: number, vip: boolean): boolean
    return Network.Send("ModSetVip", { userId = userId, vip = vip })
end

function Network.ModPurgeUser(userId: number): boolean
    return Network.Send("ModPurgeUser", { userId = userId })
end

-- Rewards / cosmetics -------------------------------------------------------

function Network.ClaimDailyReward(day: number): boolean
    return Network.Send("ClaimDailyReward", { day = day })
end

function Network.EquipTitleTag(tagId: string): boolean
    return Network.Send("EquipTitleTag", { tagId = tagId })
end

function Network.Destroy()
    stateChanged:Destroy()
    noticeReceived:Destroy()
end

return Network
