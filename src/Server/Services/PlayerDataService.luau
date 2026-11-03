-- Profile lifecycle: load with session lock, migrate, autosave, release on leave and shutdown.
-- A failed load kicks the player instead of creating defaults, so existing progress is never
-- overwritten. Profiles are only reachable after a successful load.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local StatCalculator = require(Shared.Logic.StatCalculator)
local TableUtil = require(Shared.Util.TableUtil)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileSchema = require(Server.Logic.ProfileSchema)
local ItemFactory = require(Server.Logic.ItemFactory)
local DataStoreGateway = require(script.Parent.DataStoreGateway)

local PlayerDataService = {}

local AutosaveIntervalSeconds = 120
local ShutdownTimeoutSeconds = 25
local ReleaseSaveAttempts = 3

local Profiles = {}
local SaveHooks = {}
local SavingPlayers = {}
local PendingSaves = 0
local RandomSource = Random.new()

function PlayerDataService.Get(Player: Player)
	return Profiles[Player]
end

function PlayerDataService.IsLoaded(Player: Player): boolean
	return Profiles[Player] ~= nil
end

function PlayerDataService.GetLoadedPlayers()
	local Loaded = {}
	for Player in Profiles do
		table.insert(Loaded, Player)
	end
	return Loaded
end

-- Effective stats and unlocks derived from skill nodes; see StatCalculator.
function PlayerDataService.GetDerived(Player: Player)
	local Profile = Profiles[Player]
	return if Profile then StatCalculator.Compute(Profile.SkillNodes) else nil
end

-- Hooks run before every save so live state (such as an active restoration) is captured.
function PlayerDataService.AddSaveHook(Hook)
	table.insert(SaveHooks, Hook)
end

local function RunSaveHooks(Player: Player, Profile)
	for _, Hook in SaveHooks do
		local Success, ErrorMessage = pcall(Hook, Player, Profile)
		if not Success then
			warn(`[PlayerDataService] Save hook failed for {Player.Name}: {ErrorMessage}`)
		end
	end
end

local function WriteProfile(UserId: number, Profile, Release: boolean): boolean
	while SavingPlayers[UserId] do
		task.wait(0.1)
	end
	SavingPlayers[UserId] = true
	PendingSaves += 1
	local Attempts = if Release then ReleaseSaveAttempts else 1
	local Saved, Reason = false, nil
	for Attempt = 1, Attempts do
		Saved, Reason = DataStoreGateway.Save(UserId, TableUtil.DeepCopy(Profile), Release)
		if Saved or Reason == "LockLost" then
			break
		end
		if Attempt < Attempts then
			task.wait(Attempt)
		end
	end
	PendingSaves -= 1
	SavingPlayers[UserId] = nil
	if not Saved then
		warn(`[PlayerDataService] Save for {UserId} failed: {tostring(Reason)}`)
	end
	return Saved
end

local function GrantStarter(Player: Player, Profile)
	if Profile.StarterGranted then
		return
	end
	local Derived = StatCalculator.Compute(Profile.SkillNodes)
	ItemFactory.Create(Profile, Player.UserId, EconomyConfig.StarterItemId, RandomSource, Derived.Stats, {
		Condition = EconomyConfig.StarterItemCondition,
		Traits = {},
		Source = "Starter",
	})
	Profile.StarterGranted = true
end

local function OnPlayerAdded(Player: Player)
	local UserId = Player.UserId
	local Success, StoredData = DataStoreGateway.LoadAndLock(UserId)

	if not Player:IsDescendantOf(Players) then
		if Success then
			DataStoreGateway.Save(UserId, StoredData, true)
		end
		return
	end
	if not Success then
		Player:Kick("We couldn't load your save safely, so nothing was changed. Please rejoin in a moment.")
		return
	end

	local Profile, Problem
	if StoredData == nil then
		Profile = ProfileSchema.CreateDefault()
	else
		Profile, Problem = ProfileSchema.Prepare(StoredData)
	end
	if not Profile then
		warn(`[PlayerDataService] Refusing to load {UserId}: {Problem}`)
		DataStoreGateway.Save(UserId, StoredData, true)
		Player:Kick("Your save needs a newer server. Please rejoin; nothing was changed.")
		return
	end

	GrantStarter(Player, Profile)
	Profiles[Player] = Profile
	Player:SetAttribute("DataLoaded", true)
	GameEvents.ProfileLoaded:Fire(Player, Profile)
end

local function OnPlayerRemoving(Player: Player)
	local Profile = Profiles[Player]
	if not Profile then
		return
	end
	RunSaveHooks(Player, Profile)
	GameEvents.ProfileReleasing:Fire(Player, Profile)
	Profiles[Player] = nil
	WriteProfile(Player.UserId, Profile, true)
end

local function OnShutdown()
	for Player, Profile in Profiles do
		RunSaveHooks(Player, Profile)
		Profiles[Player] = nil
		task.spawn(WriteProfile, Player.UserId, Profile, true)
	end
	local Deadline = os.clock() + ShutdownTimeoutSeconds
	while PendingSaves > 0 and os.clock() < Deadline do
		task.wait(0.2)
	end
end

local function AutosaveLoop()
	while true do
		task.wait(AutosaveIntervalSeconds)
		-- Snapshot the list because the loop yields and players may join or leave meanwhile.
		for _, Player in PlayerDataService.GetLoadedPlayers() do
			local Profile = Profiles[Player]
			if Profile then
				RunSaveHooks(Player, Profile)
				task.spawn(WriteProfile, Player.UserId, Profile, false)
				task.wait(0.25)
			end
		end
	end
end

function PlayerDataService.Init()
	DataStoreGateway.Init()
end

function PlayerDataService.Start()
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	for _, Player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, Player)
	end
	game:BindToClose(OnShutdown)
	task.spawn(AutosaveLoop)
	if RunService:IsStudio() and DataStoreGateway.IsUsingMemory() then
		warn("[PlayerDataService] Progress will not persist between Studio sessions.")
	end
end

return PlayerDataService
