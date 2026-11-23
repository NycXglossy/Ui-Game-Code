--!strict
-- ReplicatedStorage/ClubNeon_UI_Renderer_StateHelpers.lua
-- Small stateful helpers for local playback interpolation and snapshot comparison.

local StateHelpers = {}

function StateHelpers.new(deps: {[string]: any})
	local getState = deps.getState
	local formatTime = deps.formatTime
	local colors = deps.colors
	local clock = deps.clock or os.clock
	local mathLib = deps.math or math
	local typeofFn = deps.typeof or typeof
	local elapsedBase = 0
	local baseClock = clock()

	local function playbackIsPaused(): boolean
		local nowPlaying = getState().nowPlaying
		return typeofFn(nowPlaying) == "table" and nowPlaying.paused == true
	end

	local function syncElapsed()
		local nowPlaying = getState().nowPlaying
		if typeofFn(nowPlaying) == "table" then
			elapsedBase = tonumber(nowPlaying.elapsed) or 0
			baseClock = clock()
		end
	end

	local function interpolatedElapsed(duration: number): number
		local elapsed = elapsedBase
		if not playbackIsPaused() then
			elapsed += mathLib.max(0, clock() - baseClock)
		end
		return mathLib.clamp(elapsed, 0, duration)
	end

	local function updateProgress(refs: any)
		if not refs or not refs.fill.Parent then return end
		local elapsed = interpolatedElapsed(refs.duration)
		refs.fill.Size = UDim2.new(mathLib.clamp(elapsed / refs.duration, 0, 1), 0, 1, 0)
		refs.fill.BackgroundColor3 = if playbackIsPaused() then colors.Orange else colors.Gold
		refs.timeLabel.Text = formatTime(elapsed) .. " / " .. formatTime(refs.duration)
	end

	local function mobileRenderStateChanged(previous: any, nextState: any): boolean
		local function equivalent(a: any, b: any, path: string, depth: number): boolean
			if a == b then return true end
			if typeofFn(a) ~= typeofFn(b) then return false end
			if typeofFn(a) ~= "table" then return false end
			if depth >= 10 then return false end
			for key, value in pairs(a) do
				local childPath = if path == "" then tostring(key) else path .. "." .. tostring(key)
				if childPath ~= "nowPlaying.elapsed" then
					if b[key] == nil and value ~= nil then return false end
					if not equivalent(value, b[key], childPath, depth + 1) then return false end
				end
			end
			for key, value in pairs(b) do
				local childPath = if path == "" then tostring(key) else path .. "." .. tostring(key)
				if childPath ~= "nowPlaying.elapsed" and a[key] == nil and value ~= nil then
					return false
				end
			end
			return true
		end
		return not equivalent(previous, nextState, "", 0)
	end

	return {
		syncElapsed = syncElapsed,
		playbackIsPaused = playbackIsPaused,
		interpolatedElapsed = interpolatedElapsed,
		updateProgress = updateProgress,
		mobileRenderStateChanged = mobileRenderStateChanged,
	}
end

return StateHelpers
