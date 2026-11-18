--!strict
-- Server-only Kohl's Admin integration for Tiki Tide SecurityCore.
-- Install as ServerScriptService > Kohl's Admin > Addons > RegularCommandsSecurityServer.
-- Does not modify Kohl's Admin core or the existing ClubMusic add-on.
--
-- This adapter uses the installed Kohl's Process.addCommandFilter enforcement point.
-- It authorizes before command-request splitting, then wraps only the matched server
-- handlers so approved movement changes are registered and sensitive actions are audited after execution.

return function(_K: any)
	if _K.IsServer ~= true then return end
	if not (_K.Process and type(_K.Process.addCommandFilter) == "function") then
		warn("[Tiki Tide Security][Kohl's] Process.addCommandFilter is unavailable; regular command security was not installed.")
		return
	end

	local Players = game:GetService("Players")
	local ServerStorage = game:GetService("ServerStorage")
	local AUTHORITY_NAME = "TikiTideMovementAuthority"

	local sanityModule = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local sanityModuleScript = sanityModule and sanityModule:IsA("Folder") and sanityModule:FindFirstChild("SanityValidation")
	local SanityValidation: any = nil
	if sanityModuleScript and sanityModuleScript:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, sanityModuleScript)
		if requireOk and typeof(exported) == "table"
			and type(exported.IsFiniteNumber) == "function"
			and type(exported.IsLivePlayer) == "function"
			and type(exported.ValidatePlayerTargets) == "function" then
			SanityValidation = exported
		end
	end
	if not SanityValidation then
		warn("[Tiki Tide Security][Kohl's] Shared SanityValidation is unavailable; privileged regular commands were not installed.")
		return
	end

	local POLICY: {[string]: {permission: string, property: string, valueArg: number?, targetArg: number?, targetArg2: number?, detailArg: number?, global: boolean?, targetSelf: boolean?, authority: boolean?, auditKind: string?, limitProperty: string?, budget: string?, authorityTTL: number?}} = {
		-- Verified movement/environment commands in the supplied Kohl's Admin export.
		gravity = {permission = "GlobalConfig", property = "WorldGravity", valueArg = 1, global = true, authority = true, budget = "World"},
		starterspeed = {permission = "GlobalConfig", property = "StarterWalkSpeed", valueArg = 1, global = true, authority = true, budget = "World"},
		speed = {permission = "GlobalModeration", property = "WalkSpeed", valueArg = 2, targetArg = 1, authority = true},
		jumppower = {permission = "GlobalModeration", property = "JumpPower", valueArg = 2, targetArg = 1, authority = true},
		jump = {permission = "GlobalModeration", property = "JumpImpulse", targetArg = 1, authority = true},
		size = {permission = "GlobalModeration", property = "BodyScale", valueArg = 2, targetArg = 1, authority = true},
		fly = {permission = "GlobalModeration", property = "Flight", valueArg = 2, targetArg = 1, authority = true, limitProperty = "FlightSpeed"},
		unfly = {permission = "GlobalModeration", property = "Flight", targetArg = 1, authority = true},
		freeze = {permission = "GlobalModeration", property = "Frozen", targetArg = 1, authority = true},
		thaw = {permission = "GlobalModeration", property = "Frozen", targetArg = 1, authority = true},
		bring = {permission = "GlobalModeration", property = "Teleport", targetArg = 1, authority = true},
		fling = {permission = "GlobalModeration", property = "Fling", valueArg = 2, targetArg = 1, authority = true, limitProperty = "FlingStrength", authorityTTL = 5},
		tp = {permission = "GlobalModeration", property = "Teleport", targetArg = 1, authority = true},
		to = {permission = "GlobalModeration", property = "Teleport", targetSelf = true, authority = true},
		place = {permission = "GlobalConfig", property = "TeleportPlace", targetArg = 1, auditKind = "AdminAction", budget = "World"},

		-- Native moderation enforcement commands retain Kohl's own role/target checks.
		ban = {permission = "GlobalModeration", property = "Ban", targetArg = 1, auditKind = "Moderation"},
		unban = {permission = "GlobalModeration", property = "Unban", targetArg = 1, auditKind = "Moderation"},
		kick = {permission = "GlobalModeration", property = "Kick", targetArg = 1, auditKind = "Moderation"},
		mute = {permission = "GlobalModeration", property = "Mute", targetArg = 1, auditKind = "Moderation"},
		unmute = {permission = "GlobalModeration", property = "Unmute", targetArg = 1, auditKind = "Moderation"},
		punish = {permission = "GlobalModeration", property = "Punish", targetArg = 1, auditKind = "Moderation"},
		unpunish = {permission = "GlobalModeration", property = "Unpunish", targetArg = 1, auditKind = "Moderation"},
		kill = {permission = "GlobalModeration", property = "Kill", targetArg = 1, auditKind = "Moderation"},
		hurt = {permission = "GlobalModeration", property = "Hurt", targetArg = 1, auditKind = "Moderation"},
		health = {permission = "GlobalModeration", property = "Health", targetArg = 1, auditKind = "Moderation"},
		stun = {permission = "GlobalModeration", property = "Stun", targetArg = 1, auditKind = "Moderation"},
		unstun = {permission = "GlobalModeration", property = "Unstun", targetArg = 1, auditKind = "Moderation"},
		blind = {permission = "GlobalModeration", property = "Blind", targetArg = 1, auditKind = "Moderation"},
		unblind = {permission = "GlobalModeration", property = "Unblind", targetArg = 1, auditKind = "Moderation"},

		-- Additional destructive/player-state moderation commands from the supplied export.
		toolban = {permission = "GlobalModeration", property = "ToolBan", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		untoolban = {permission = "GlobalModeration", property = "ToolUnban", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		removetools = {permission = "GlobalModeration", property = "ToolRemove", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		heal = {permission = "GlobalModeration", property = "Heal", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		immortal = {permission = "GlobalModeration", property = "Immortal", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		invisible = {permission = "GlobalModeration", property = "Invisible", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		visible = {permission = "GlobalModeration", property = "Visible", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		resetstats = {permission = "GlobalModeration", property = "ResetStats", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		collide = {permission = "GlobalModeration", property = "CharacterCollision", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		notrip = {permission = "GlobalModeration", property = "PreventTrip", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		join = {permission = "GlobalModeration", property = "JoinPlayerServer", auditKind = "AdminAction", budget = "Moderation"},
		sword = {permission = "GlobalConfig", property = "AssetSwordGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		
		-- Fun commands that directly alter target characters or client experience.
		creeper = {permission = "GlobalModeration", property = "CreeperTransform", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		dog = {permission = "GlobalModeration", property = "DogTransform", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		char = {permission = "GlobalModeration", property = "CharacterAppearance", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		clone = {permission = "GlobalModeration", property = "CharacterClone", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		jumpscare = {permission = "GlobalModeration", property = "ClientJumpscare", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		glitch = {permission = "GlobalModeration", property = "ClientGlitch", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		seizure = {permission = "GlobalModeration", property = "CharacterSeizure", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		spin = {permission = "GlobalModeration", property = "CharacterSpin", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		skydive = {permission = "GlobalModeration", property = "CharacterSkydive", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		trip = {permission = "GlobalModeration", property = "CharacterTrip", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		rocket = {permission = "GlobalModeration", property = "CharacterRocket", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		slim = {permission = "GlobalModeration", property = "CharacterSlim", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		noobify = {permission = "GlobalModeration", property = "CharacterNoobify", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		slippery = {permission = "GlobalModeration", property = "CharacterSlippery", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},

		-- Persistent roles/permissions are owner/co-owner operations.
		role = {permission = "GlobalConfig", property = "RoleAssign", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		temprole = {permission = "GlobalConfig", property = "TemporaryRoleAssign", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		unrole = {permission = "GlobalConfig", property = "RoleRemove", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		removemember = {permission = "GlobalConfig", property = "MemberPermissionsRemove", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},

		-- Asset/tool grants can introduce executable or persistent content.
		give = {permission = "GlobalConfig", property = "ToolGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		startergive = {permission = "GlobalConfig", property = "PersistentToolGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		starterremove = {permission = "GlobalConfig", property = "PersistentToolRemove", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		copytools = {permission = "GlobalConfig", property = "ToolCopy", targetArg = 1, targetArg2 = 2, auditKind = "AdminAction", budget = "Asset"},
		gear = {permission = "GlobalConfig", property = "AssetGearGrant", valueArg = 2, targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		btools = {permission = "GlobalConfig", property = "BuildingToolsGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		insert = {permission = "GlobalConfig", property = "AssetInsert", valueArg = 1, auditKind = "AdminAction", budget = "Asset"},

		-- Cross-server announcements and local broadcasts are separately permissioned.
		announce = {permission = "GlobalAnnouncement", property = "PersistentAnnouncement", global = true, auditKind = "AdminAction", budget = "Broadcast"},
		unannounce = {permission = "GlobalAnnouncement", property = "PersistentAnnouncementClear", global = true, auditKind = "AdminAction", budget = "Broadcast"},
		hint = {permission = "GlobalAnnouncement", property = "BroadcastHint", auditKind = "AdminAction", budget = "Broadcast"},
		message = {permission = "GlobalAnnouncement", property = "BroadcastMessage", auditKind = "AdminAction", budget = "Broadcast"},
		fullmessage = {permission = "GlobalAnnouncement", property = "FullScreenBroadcast", auditKind = "AdminAction", budget = "Broadcast"},
		privatehint = {permission = "GlobalModeration", property = "PrivateHint", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},
		notify = {permission = "GlobalModeration", property = "TargetedNotification", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},
		privatemessage = {permission = "GlobalModeration", property = "PrivateMessage", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},

		-- Player-targeted polling and server-wide countdown overlays.
		vote = {permission = "GlobalAnnouncement", property = "PlayerVote", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},
		poll = {permission = "GlobalAnnouncement", property = "PlayerPoll", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},
		countdown = {permission = "GlobalAnnouncement", property = "Countdown", auditKind = "AdminAction", budget = "Broadcast"},
		tts = {permission = "GlobalAnnouncement", property = "TextToSpeechBroadcast", auditKind = "AdminAction", budget = "Broadcast"},

		-- Respawn/refresh and destructive world actions are sensitive too.
		respawn = {permission = "GlobalModeration", property = "Respawn", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		refresh = {permission = "GlobalModeration", property = "Refresh", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		removelimbs = {permission = "GlobalModeration", property = "RemoveLimbs", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		forcefield = {permission = "GlobalModeration", property = "ForceField", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		incognito = {permission = "GlobalModeration", property = "Incognito", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		team = {permission = "GlobalModeration", property = "TeamChange", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		teamrespawn = {permission = "GlobalModeration", property = "TeamRespawn", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		substitute = {permission = "GlobalModeration", property = "TeamSubstitute", targetArg = 1, targetArg2 = 2, auditKind = "Moderation", budget = "Moderation"},
		randomizeteams = {permission = "GlobalModeration", property = "TeamRandomize", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		change = {permission = "GlobalConfig", property = "LeaderstatChange", valueArg = 3, detailArg = 2, targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		clean = {permission = "GlobalConfig", property = "AdminCleanup", auditKind = "AdminAction", budget = "World"},
		clearterrain = {permission = "GlobalConfig", property = "ClearTerrain", global = true, auditKind = "AdminAction", budget = "World"},
		time = {permission = "GlobalConfig", property = "LightingTime", auditKind = "AdminAction", budget = "World"},
		brightness = {permission = "GlobalConfig", property = "LightingBrightness", valueArg = 1, limitProperty = "LightingBrightness", auditKind = "AdminAction", budget = "World"},
		colorshift = {permission = "GlobalConfig", property = "LightingColorShift", auditKind = "AdminAction", budget = "World"},
		latitude = {permission = "GlobalConfig", property = "LightingLatitude", auditKind = "AdminAction", budget = "World"},
		diffusescale = {permission = "GlobalConfig", property = "LightingDiffuseScale", auditKind = "AdminAction", budget = "World"},
		exposure = {permission = "GlobalConfig", property = "LightingExposure", auditKind = "AdminAction", budget = "World"},
		disco = {permission = "GlobalConfig", property = "DiscoLighting", auditKind = "AdminAction", budget = "World"},
		specularscale = {permission = "GlobalConfig", property = "LightingSpecularScale", valueArg = 1, auditKind = "AdminAction", budget = "World"},

		-- Additional player-control commands verified against the supplied command handlers.
		setgravity = {permission = "GlobalModeration", property = "PlayerGravity", valueArg = 2, targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		noclip = {permission = "GlobalModeration", property = "NoClip", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		clip = {permission = "GlobalModeration", property = "NoClipClear", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		jail = {permission = "GlobalModeration", property = "Jail", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unjail = {permission = "GlobalModeration", property = "Unjail", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		lock = {permission = "GlobalModeration", property = "CharacterLock", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unlock = {permission = "GlobalModeration", property = "CharacterUnlock", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		cameraoffset = {permission = "GlobalModeration", property = "CameraOffset", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		fov = {permission = "GlobalModeration", property = "FieldOfView", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		vehiclespeed = {permission = "GlobalModeration", property = "VehicleSpeed", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		vehicletorque = {permission = "GlobalModeration", property = "VehicleTorque", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		slopeangle = {permission = "GlobalModeration", property = "MaxSlopeAngle", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		starterjumppower = {permission = "GlobalConfig", property = "StarterJumpPower", valueArg = 1, auditKind = "AdminAction", budget = "World"},
		starterslopeangle = {permission = "GlobalConfig", property = "StarterSlopeAngle", valueArg = 1, auditKind = "AdminAction", budget = "World"},

		-- Targeted disruptive Fun commands are still native Kohl's handlers, but require SecurityCore moderation authority.
		explode = {permission = "GlobalModeration", property = "Explode", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		nuke = {permission = "GlobalModeration", property = "Nuke", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		smite = {permission = "GlobalModeration", property = "Smite", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		poison = {permission = "GlobalModeration", property = "Poison", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		infect = {permission = "GlobalModeration", property = "Infect", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		confuse = {permission = "GlobalModeration", property = "Confuse", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},

		-- Environment and Terrain mutations are owner/co-owner operations.
		fix = {permission = "GlobalConfig", property = "EnvironmentReset", auditKind = "AdminAction", budget = "World"},
		ambient = {permission = "GlobalConfig", property = "LightingAmbient", auditKind = "AdminAction", budget = "World"},
		outdoorambient = {permission = "GlobalConfig", property = "LightingOutdoorAmbient", auditKind = "AdminAction", budget = "World"},
		atmosphere = {permission = "GlobalConfig", property = "LightingAtmosphere", auditKind = "AdminAction", budget = "World"},
		fogcolor = {permission = "GlobalConfig", property = "LightingFogColor", auditKind = "AdminAction", budget = "World"},
		fogstart = {permission = "GlobalConfig", property = "LightingFogStart", auditKind = "AdminAction", budget = "World"},
		fogend = {permission = "GlobalConfig", property = "LightingFogEnd", auditKind = "AdminAction", budget = "World"},
		shadows = {permission = "GlobalConfig", property = "LightingShadows", auditKind = "AdminAction", budget = "World"},
		skybox = {permission = "GlobalConfig", property = "LightingSkybox", auditKind = "AdminAction", budget = "World"},
		airdensity = {permission = "GlobalConfig", property = "WorldAirDensity", auditKind = "AdminAction", budget = "World"},
		winddir = {permission = "GlobalConfig", property = "WorldWindDirection", auditKind = "AdminAction", budget = "World"},
		windspeed = {permission = "GlobalConfig", property = "WorldWindSpeed", auditKind = "AdminAction", budget = "World"},
		watercolor = {permission = "GlobalConfig", property = "TerrainWaterColor", auditKind = "AdminAction", budget = "World"},
		waterreflectance = {permission = "GlobalConfig", property = "TerrainWaterReflectance", auditKind = "AdminAction", budget = "World"},
		watertransparency = {permission = "GlobalConfig", property = "TerrainWaterTransparency", auditKind = "AdminAction", budget = "World"},
		watersize = {permission = "GlobalConfig", property = "TerrainWaterSize", auditKind = "AdminAction", budget = "World"},
		waterspeed = {permission = "GlobalConfig", property = "TerrainWaterSpeed", auditKind = "AdminAction", budget = "World"},

		-- Reserved-server records, badge awards, and team definitions are privileged operations.
		reserve = {permission = "GlobalConfig", property = "ReservedServerCreate", auditKind = "AdminAction", budget = "Privilege"},
		unreserve = {permission = "GlobalConfig", property = "ReservedServerRemove", auditKind = "AdminAction", budget = "Privilege"},
		badge = {permission = "GlobalConfig", property = "BadgeAward", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		createteam = {permission = "GlobalConfig", property = "TeamCreate", auditKind = "AdminAction", budget = "Privilege"},
		editteam = {permission = "GlobalConfig", property = "TeamEdit", auditKind = "AdminAction", budget = "Privilege"},
		removeteam = {permission = "GlobalConfig", property = "TeamRemove", auditKind = "AdminAction", budget = "Privilege"},
		clearteams = {permission = "GlobalConfig", property = "TeamsClear", auditKind = "AdminAction", budget = "Privilege"},

		-- Server-wide disruptive commands require the highest Tiki Tide permission.
		serverlock = {permission = "GlobalConfig", property = "ServerLock", global = true, auditKind = "AdminAction", budget = "World"},
		unserverlock = {permission = "GlobalConfig", property = "ServerUnlock", global = true, auditKind = "AdminAction", budget = "World"},
		shutdown = {permission = "GlobalConfig", property = "Shutdown", global = true, auditKind = "AdminAction", budget = "World"},

		-- Remaining player-facing Kohl's commands verified against the supplied package.
		name = {permission = "GlobalModeration", property = "DisplayNameChange", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		title = {permission = "GlobalModeration", property = "PlayerTitleChange", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		hidename = {permission = "GlobalModeration", property = "HidePlayerName", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		showname = {permission = "GlobalModeration", property = "ShowPlayerName", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		setcoregui = {permission = "GlobalModeration", property = "ClientCoreGuiControl", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unforcefield = {permission = "GlobalModeration", property = "ForceFieldRemove", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		sit = {permission = "GlobalModeration", property = "PlayerSit", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unsit = {permission = "GlobalModeration", property = "PlayerUnsit", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		r6 = {permission = "GlobalModeration", property = "CharacterRigChange", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		removearms = {permission = "GlobalModeration", property = "CharacterArmsRemove", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		removelegs = {permission = "GlobalModeration", property = "CharacterLegsRemove", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		buy = {permission = "GlobalModeration", property = "PlayerPurchasePrompt", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},
		promptgroup = {permission = "GlobalModeration", property = "PlayerGroupJoinPrompt", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},
		uncreeper = {permission = "GlobalModeration", property = "CreeperTransformRevert", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		undog = {permission = "GlobalModeration", property = "DogTransformRevert", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unchar = {permission = "GlobalModeration", property = "CharacterAppearanceRestore", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unseizure = {permission = "GlobalModeration", property = "CharacterSeizureClear", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unspin = {permission = "GlobalModeration", property = "CharacterSpinStop", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},

		-- VIP commands that mutate another player retain Kohl's native VIP role checks,
		-- and additionally require SecurityCore moderation authority.
		normal = {permission = "GlobalModeration", property = "VIPNormal", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		fire = {permission = "GlobalModeration", property = "VIPFire", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unfire = {permission = "GlobalModeration", property = "VIPUnfire", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		smoke = {permission = "GlobalModeration", property = "VIPSmoke", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unsmoke = {permission = "GlobalModeration", property = "VIPUnsmoke", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		sparkles = {permission = "GlobalModeration", property = "VIPSparkles", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unsparkles = {permission = "GlobalModeration", property = "VIPUnsparkles", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		light = {permission = "GlobalModeration", property = "VIPLight", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unlight = {permission = "GlobalModeration", property = "VIPUnlight", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		highlight = {permission = "GlobalModeration", property = "VIPHighlight", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		particle = {permission = "GlobalModeration", property = "VIPParticle", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unparticle = {permission = "GlobalModeration", property = "VIPUnparticle", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		trail = {permission = "GlobalModeration", property = "VIPTrail", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		untrail = {permission = "GlobalModeration", property = "VIPUntrail", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		shine = {permission = "GlobalModeration", property = "VIPShine", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		bundle = {permission = "GlobalModeration", property = "VIPBundle", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		headless = {permission = "GlobalModeration", property = "VIPHeadless", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		korblox = {permission = "GlobalModeration", property = "VIPKorblox", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		werewolf = {permission = "GlobalModeration", property = "VIPWerewolf", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		vampire = {permission = "GlobalModeration", property = "VIPVampire", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		cape = {permission = "GlobalModeration", property = "VIPCape", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		uncape = {permission = "GlobalModeration", property = "VIPUncape", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		hat = {permission = "GlobalModeration", property = "VIPHat", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		removehats = {permission = "GlobalModeration", property = "VIPRemovehats", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		head = {permission = "GlobalModeration", property = "VIPHead", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		headsize = {permission = "GlobalModeration", property = "VIPHeadsize", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		face = {permission = "GlobalModeration", property = "VIPFace", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		shirt = {permission = "GlobalModeration", property = "VIPShirt", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		pants = {permission = "GlobalModeration", property = "VIPPants", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		tshirt = {permission = "GlobalModeration", property = "VIPTshirt", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		bodycolor = {permission = "GlobalModeration", property = "VIPBodycolor", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		crm = {permission = "GlobalModeration", property = "VIPCrm", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		goldify = {permission = "GlobalModeration", property = "VIPGoldify", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		shiny = {permission = "GlobalModeration", property = "VIPShiny", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		silverify = {permission = "GlobalModeration", property = "VIPSilverify", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		ungoldify = {permission = "GlobalModeration", property = "VIPUngoldify", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		swagify = {permission = "GlobalModeration", property = "VIPSwagify", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unswagify = {permission = "GlobalModeration", property = "VIPUnswagify", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		-- Client-side and targeted player controls that can affect privacy or playability.
		antilag = {permission = "GlobalModeration", property = "ClientAntiLag", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		fps = {permission = "GlobalModeration", property = "ClientFPSLimit", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		link = {permission = "GlobalModeration", property = "PlayerLink", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		unlink = {permission = "GlobalModeration", property = "PlayerUnlink", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		watch = {permission = "GlobalModeration", property = "PlayerWatch", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		spectate = {permission = "GlobalModeration", property = "PlayerSpectate", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		xray = {permission = "GlobalModeration", property = "ClientXray", auditKind = "Moderation", budget = "Moderation"},
		viewtools = {permission = "GlobalModeration", property = "PlayerToolInspection", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		clearlogs = {permission = "GlobalConfig", property = "AdminLogClear", global = true, auditKind = "AdminAction", budget = "Privilege"},
		hidelogs = {permission = "GlobalModeration", property = "AdminLogVisibility", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		customcommand = {permission = "GlobalAnnouncement", property = "AddonBroadcast", auditKind = "AdminAction", budget = "Broadcast"},
	}

	local BLOCKED_COMMANDS: {[string]: string} = {
		-- Native Kohl's ban commands bypass Phase 32 case evidence, review, and reversal.
		-- Use ;cmtempban, ;cmpermban, ;cmpermban-alts, and ;cmunban instead.
		ban = "Use the Tiki Tide Phase 32 moderation commands so bans and reversals are recorded.",
		unban = "Use ;cmunban so the reversal is authorized and retained in moderation history.",
		tempban = "Use ;cmtempban so the suspension is recorded and authorized.",
		permban = "Use ;cmpermban so the permanent ban is recorded and authorized.",
		serverban = "Use the Tiki Tide Phase 32 moderation commands for persistent bans.",
		globalban = "Use the Tiki Tide Phase 32 moderation commands for persistent bans.",
		-- Disable client-crashing/repeated-kill commands and arbitrary script/global execution.
		crash = "This command is disabled by Tiki Tide security.",
		loopkill = "This command is disabled by Tiki Tide security.",
		loopfling = "Repeated fling commands are disabled by Tiki Tide security.",
		script = "Arbitrary server script execution is disabled by Tiki Tide security.",
		localscript = "Arbitrary client script execution is disabled by Tiki Tide security.",
		global = "Native global command strings are disabled; use dedicated Tiki Tide global controls.",
		control = "Character takeover is disabled by Tiki Tide security because it transfers another player character and network ownership.",

		-- Kohl's legacy Sound commands conflict with the game's AudioPlayer-only backend.
		play = "Kohl's legacy Sound playback is disabled; use the Tiki Tide music controls.",
		pause = "Kohl's legacy Sound playback is disabled; use the Tiki Tide music controls.",
		resume = "Kohl's legacy Sound playback is disabled; use the Tiki Tide music controls.",
		stop = "Kohl's legacy Sound playback is disabled; use the Tiki Tide music controls.",
		pitch = "Kohl's legacy Sound playback is disabled; use the Tiki Tide music controls.",
		volume = "Kohl's legacy Sound playback is disabled; use the Tiki Tide music controls.",
	}

	-- Kohl's passes the invoked alias through command.alias. Resolve aliases before
	-- both blocking and policy lookup so alternate spellings cannot skip SecurityCore.
	local COMMAND_ALIASES: {[string]: string} = {
		s = "script",
		loadstring = "script",
		ls = "localscript",
		h = "hint",
		phint = "privatehint",
		ph = "privatehint",
		m = "message",
		msg = "message",
		fm = "fullmessage",
		fmsg = "fullmessage",
		n = "notify",
		pm = "privatemessage",
		pmsg = "privatemessage",
		stopmusic = "stop",
	}

	local function canonicalCommandName(value: any): string
		local name = string.lower(tostring(value or ""))
		return COMMAND_ALIASES[name] or name
	end

	local VALUE_LIMITS: {[string]: {min: number, max: number}} = {
		WorldGravity = {min = 0, max = 500},
		StarterWalkSpeed = {min = 0, max = 100},
		WalkSpeed = {min = 0, max = 100},
		JumpPower = {min = 0, max = 250},
		BodyScale = {min = 0.1, max = 10},
		FlightSpeed = {min = 0, max = 256},
		FlingStrength = {min = 0.1, max = 5},
		LightingBrightness = {min = 0, max = 10},
		LightingSpecularScale = {min = 0, max = 1},
	}

	local function finiteNumber(value: any): boolean
		return SanityValidation.IsFiniteNumber(value)
	end

	local function validatePreparedTargets(command: any, policy: any): (boolean, string?)
		if policy.targetSelf then
			if not SanityValidation.IsLivePlayer(command.fromPlayer) then
				return false, "A live player actor is required for this command."
			end
		end
		local prepared = command.preparedArgs
		for _, index in ipairs({policy.targetArg, policy.targetArg2}) do
			if index then
				if typeof(prepared) ~= "table" then return false, "Command target arguments are unavailable." end
				local valid, _, reason = SanityValidation.ValidatePlayerTargets(prepared[index], 8)
				if not valid then return false, reason or "Command target failed server validation." end
			end
		end
		return true
	end

	local function actorUserId(command: any): number?
		local player = command.fromPlayer
		if typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
			return player.UserId
		end
		return nil
	end

	-- Use the same SecurityCore authorization singleton as ClubMusic Global.
	-- Check is synchronous and reads only the module's short-lived server cache;
	-- an expired/missing cache denies the command while refresh happens asynchronously.
	local authorizationService: any = nil
	do
		local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
		local module = if core and core:IsA("Folder") then core:FindFirstChild("Authorization") else nil
		if module and module:IsA("ModuleScript") then
			local requireOk, exported = pcall(require, module)
			if requireOk and typeof(exported) == "table" and type(exported.GetShared) == "function" then
				local sharedOk, instance = pcall(exported.GetShared)
				if sharedOk and typeof(instance) == "table" and type(instance.Check) == "function" then
					authorizationService = instance
				else
					warn("[Tiki Tide Security][Kohl's] SecurityCore Authorization could not initialize; privileged commands are fail-closed.")
				end
			else
				warn("[Tiki Tide Security][Kohl's] SecurityCore Authorization module failed to load; privileged commands are fail-closed.")
			end
		else
			warn("[Tiki Tide Security][Kohl's] SecurityCore Authorization module is missing; privileged commands are fail-closed.")
		end
	end

	local function authorize(userId: number, permission: string): boolean
		if not authorizationService then return false end
		local ok, allowed = pcall(authorizationService.Check, authorizationService, userId, permission)
		return ok and allowed == true
	end

	-- Small per-server buckets are split by risk class so routine moderation
	-- cannot consume the budget reserved for privilege/world-changing operations.
	-- This is synchronous, bounded by active players, and creates no MemoryStore entries.
	local BUDGETS: {[string]: {capacity: number, refillPerSecond: number}} = {
		Moderation = {capacity = 5, refillPerSecond = 0.5},
		Privilege = {capacity = 2, refillPerSecond = 1 / 30},
		Asset = {capacity = 2, refillPerSecond = 1 / 10},
		Broadcast = {capacity = 2, refillPerSecond = 1 / 15},
		World = {capacity = 2, refillPerSecond = 1 / 30},
		General = {capacity = 5, refillPerSecond = 0.5},
	}
	local buckets: {[number]: {[string]: {tokens: number, updatedAt: number}}} = {}
	local function consumeBudget(userId: number, budgetName: string?): boolean
		local config = BUDGETS[budgetName or "General"] or BUDGETS.General
		local userBuckets = buckets[userId]
		if not userBuckets then
			userBuckets = {}
			buckets[userId] = userBuckets
		end
		local now = os.clock()
		local entry = userBuckets[budgetName or "General"]
		if not entry then
			entry = {tokens = config.capacity, updatedAt = now}
			userBuckets[budgetName or "General"] = entry
		end
		entry.tokens = math.min(config.capacity, entry.tokens + math.max(0, now - entry.updatedAt) * config.refillPerSecond)
		entry.updatedAt = now
		if entry.tokens < 1 then return false end
		entry.tokens -= 1
		return true
	end

	-- Bound security-signal reporting so repeated denied commands cannot spawn
	-- an unbounded number of report tasks or grow a per-player table indefinitely.
	local reportCooldowns: {[string]: number} = {}
	local function reportSecuritySignal(actorId: number, signal: string, detail: string)
		local key = tostring(actorId) .. ":" .. signal
		local now = os.clock()
		local last = reportCooldowns[key]
		if last and now - last < 15 then return end
		local count = 0
		local oldestKey, oldestAt = nil, math.huge
		for existingKey, timestamp in pairs(reportCooldowns) do
			count += 1
			if timestamp < oldestAt then oldestKey, oldestAt = existingKey, timestamp end
		end
		if count >= 256 and oldestKey then reportCooldowns[oldestKey] = nil end
		reportCooldowns[key] = now
		task.spawn(function()
			local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
			local report = api and api:IsA("Folder") and api:FindFirstChild("ReportSignal")
			if report and report:IsA("BindableFunction") then
				pcall(function() report:Invoke(actorId, signal, string.sub(detail, 1, 120)) end)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player.UserId] = nil
		local prefix = tostring(player.UserId) .. ":"
		for key in pairs(reportCooldowns) do
			if string.sub(key, 1, #prefix) == prefix then reportCooldowns[key] = nil end
		end
	end)

	-- Compatibility adapter: keep the existing ServerStorage BindableFunction API
	-- while the ledger itself lives in the private SecurityCore module.
	local authorityModuleScript = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local movementAuthorityModule = authorityModuleScript and authorityModuleScript:IsA("Folder")
		and authorityModuleScript:FindFirstChild("MovementAuthority")
	local movementAuthority: any = nil
	if movementAuthorityModule and movementAuthorityModule:IsA("ModuleScript") then
		local requireOk, result = pcall(require, movementAuthorityModule)
		if requireOk and typeof(result) == "table" and type(result.Invoke) == "function" then
			movementAuthority = result
		else
			warn("[Tiki Tide Security][Kohl's] MovementAuthority module failed to load; movement authorization is fail-closed.")
		end
	else
		warn("[Tiki Tide Security][Kohl's] SecurityCore MovementAuthority module is missing; install the updated security module bundle.")
	end

	local authority = ServerStorage:FindFirstChild(AUTHORITY_NAME)
	if authority and not authority:IsA("BindableFunction") then
		warn("[Tiki Tide Security][Kohl's] TikiTideMovementAuthority exists with the wrong class; movement adapter unavailable.")
		authority = nil
	end
	if not authority then
		authority = Instance.new("BindableFunction")
		authority.Name = AUTHORITY_NAME
		authority.Parent = ServerStorage
	end
	(authority :: BindableFunction).OnInvoke = function(operation: any, actorId: any, targetId: any, property: any, value: any, origin: any, ttl: any)
		if not movementAuthority then
			return false, "SecurityCore MovementAuthority is unavailable."
		end
		return movementAuthority.Invoke(operation, actorId, targetId, property, value, origin, ttl)
	end

	local auditUnavailableWarned = false
	local function logAction(command: any, policy: any, value: any, targetCount: number, targetSummary: string)
		local id = actorUserId(command)
		local valueText = if value == nil then "default" elseif typeof(value) == "boolean" then tostring(value) else tostring(value)
		local commandName = tostring(command.alias or command.definition.name)
		local message = string.format(
			"Kohl's administrative command invoked: command=%s property=%s targets=%d targetIds=%s value=%s",
			commandName, policy.property, targetCount, string.sub(targetSummary, 1, 96), string.sub(valueText, 1, 24)
		)
		if type(_K.log) == "function" then
			local ok, err = pcall(_K.log, message, "COMMAND", id)
			if not ok then warn("[Tiki Tide Security][Kohl's] Kohl's log failed: " .. tostring(err)) end
		end
		-- Sensitive command invocations enter the existing unified SecurityCore Audit.
		local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
		local audit = api and api:IsA("Folder") and api:FindFirstChild("RecordGlobalAuditEvent")
		if audit and audit:IsA("BindableFunction") then
			task.spawn(function()
				local ok = pcall(function()
					return audit:Invoke(policy.auditKind or "AdminAction", id or 0,
						string.sub(targetSummary, 1, 160), "kohls:" .. policy.property)
				end)
				if not ok then warn("[Tiki Tide Security][Kohl's] Unified SecurityCore audit invocation failed for command=" .. commandName) end
			end)
		elseif not auditUnavailableWarned then
			auditUnavailableWarned = true
			warn("[Tiki Tide Security][Kohl's] Unified SecurityCore audit API unavailable; Kohl's command log remains the fallback.")
		end
	end

	local wrappedDefinitions = setmetatable({}, {__mode = "k"})
	local authorityRegistrationWarned = false
	local function wrapHandler(command: any)
		local definition = command.definition
		if wrappedDefinitions[definition] then return end
		local original = definition.run
		if type(original) ~= "function" then return end
		wrappedDefinitions[definition] = true
		definition.run = function(context: any, ...)
			local args = table.pack(...)
			local result = table.pack(original(context, table.unpack(args, 1, args.n)))
			local aliasName = canonicalCommandName(context.alias or definition.name)
			local activePolicy = POLICY[aliasName] or POLICY[canonicalCommandName(definition.name)]
			if not activePolicy then return table.unpack(result, 1, result.n) end

			local targets: {Player} = {}
			local targetRefs: {string} = {}
			local targetCount = if activePolicy.targetSelf then 1 else 0
			local function addTargetRef(target: any)
				if #targetRefs >= 8 then return end
				if typeof(target) == "Instance" and target:IsA("Player") then
					table.insert(targetRefs, tostring(target.UserId))
				elseif typeof(target) == "number" and finiteNumber(target) then
					table.insert(targetRefs, tostring(math.floor(target)))
				elseif typeof(target) == "string" and #target <= 24 then
					table.insert(targetRefs, target)
				end
			end
			if activePolicy.targetSelf then addTargetRef(context.fromPlayer and context.fromPlayer.UserId) end
			for _, targetIndex in ipairs({activePolicy.targetArg, activePolicy.targetArg2}) do
				if targetIndex then
					local rawTargets = args[targetIndex]
					if typeof(rawTargets) == "Instance" and rawTargets:IsA("Player") then
						table.insert(targets, rawTargets)
						targetCount += 1
						addTargetRef(rawTargets)
					elseif typeof(rawTargets) == "table" then
						targetCount += #rawTargets
						for _, target in ipairs(rawTargets) do
							if typeof(target) == "Instance" and target:IsA("Player") then table.insert(targets, target) end
							addTargetRef(target)
						end
					end
				end
			end
			local targetSummary = if #targetRefs > 0 then table.concat(targetRefs, ",")
				else if activePolicy.global then "server-wide" else "none"
			if targetCount > #targetRefs then targetSummary ..= string.format(",+%d", targetCount - #targetRefs) end

			local value = if activePolicy.valueArg then args[activePolicy.valueArg] else nil
			if activePolicy.detailArg then
				value = tostring(args[activePolicy.detailArg]) .. "=" .. tostring(value)
			end
			if activePolicy.property == "JumpImpulse" then value = true end
			if activePolicy.property == "Fling" and value == nil then value = 1 end
			if activePolicy.property == "BodyScale" and (value == nil or context.undo) then value = 1 end
			if activePolicy.property == "Flight" then value = aliasName ~= "unfly" and not context.undo end
			if activePolicy.property == "Frozen" then value = aliasName ~= "thaw" and aliasName ~= "unfreeze" and not context.undo end
			if value == nil then value = "DEFAULT" end

			local actorId = actorUserId(context)
			if actorId then
				if activePolicy.authority == true then
					local function registerAuthority(targetId: number, propertyValue: any)
						local invokeOk, registered = pcall(function()
							return (authority :: BindableFunction):Invoke("Register", actorId, targetId, activePolicy.property, propertyValue, "KohlsAdmin", activePolicy.authorityTTL or 120)
						end)
						if (not invokeOk or registered ~= true) and not authorityRegistrationWarned then
							authorityRegistrationWarned = true
							warn("[Tiki Tide Security][Kohl's] MovementAuthority registration failed; command audit remains active.")
						end
					end
					if activePolicy.targetSelf then
						registerAuthority(actorId, "DEFAULT")
					elseif activePolicy.global then
						local globalValue = value
						if globalValue == "DEFAULT" and activePolicy.property == "WorldGravity" and context.env then globalValue = context.env.gravity end
						registerAuthority(0, globalValue)
					else
						for _, target in ipairs(targets) do registerAuthority(target.UserId, value) end
					end
				end
				logAction(context, activePolicy, value, targetCount, targetSummary)
			end
			return table.unpack(result, 1, result.n)
		end
	end

	local function getNumericArgument(command: any, index: number?): any
		if not index then return nil end
		local prepared = command.preparedArgs
		return typeof(prepared) == "table" and prepared[index] or nil
	end

	local filter = function(command: any): (boolean, string?)
		if typeof(command) ~= "table" or typeof(command.definition) ~= "table" then return true end
		local commandName = canonicalCommandName(command.alias or command.definition.name or "")
		local definitionName = canonicalCommandName(command.definition.name or "")
		local blockedReason = BLOCKED_COMMANDS[commandName] or BLOCKED_COMMANDS[definitionName]
		if blockedReason then
			local actorId = actorUserId(command)
			if actorId then reportSecuritySignal(actorId, "kohls_dangerous_command_blocked", commandName) end
			return false, blockedReason
		end
		local policy = POLICY[commandName] or POLICY[definitionName]
		if not policy then return true end

		local actorId = actorUserId(command)
		if not actorId then return false, "This administrative command requires a live server player." end
		if not authorize(actorId, policy.permission) then
			reportSecuritySignal(actorId, "kohls_regular_command_denied", commandName)
			return false, if policy.permission == "GlobalConfig"
				then "Tiki Tide owner/co-owner authorization is required for this server-wide command."
				elseif policy.permission == "GlobalAnnouncement"
				then "Tiki Tide announcement authorization is required for this broadcast command."
				else "Tiki Tide administrator authorization is required for this moderation or player-control command."
		end
		local targetsValid, targetError = validatePreparedTargets(command, policy)
		if not targetsValid then
			reportSecuritySignal(actorId, "kohls_invalid_command_target", commandName)
			return false, targetError or "Command target failed server validation."
		end
		if not consumeBudget(actorId, policy.budget) then
			return false, "Regular administrative commands are being rate-limited. Wait a moment and retry."
		end

		local value = getNumericArgument(command, policy.valueArg)
		local limitProperty = policy.limitProperty or policy.property
		local limits = VALUE_LIMITS[limitProperty]
		if value ~= nil and limits and (not finiteNumber(value) or value < limits.min or value > limits.max) then
			return false, string.format("The requested %s value is outside the permitted range.", limitProperty)
		end
		if policy.property == "JumpImpulse" then
			value = true
		elseif policy.property == "Fling" and value == nil then
			value = 1
		elseif policy.property == "Flight" or policy.property == "Frozen" then
			value = commandName == "fly" or commandName == "freeze"
		elseif value ~= nil and policy.authority == true and not finiteNumber(value) then
			return false, string.format("The requested %s value is invalid.", policy.property)
		end

		wrapHandler(command)
		return true
	end

	local ok, removeFilter = pcall(_K.Process.addCommandFilter, filter)
	if not ok or type(removeFilter) ~= "function" then
		warn("[Tiki Tide Security][Kohl's] Failed to register regular-command security filter: " .. tostring(removeFilter))
		return
	end

	print("[Tiki Tide Security][Kohl's] Regular command security filter ready. Movement authorization ledger is server-local.")
end
