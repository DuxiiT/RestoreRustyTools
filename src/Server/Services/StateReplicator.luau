-- Sends each player a client-safe view of their own profile, batched to at most one snapshot
-- per flush. Hidden traits and seeds never leave the server. Other services add fields through
-- contributors so this module does not depend on them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local PriceCalculator = require(Shared.Logic.PriceCalculator)

local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)

local StateReplicator = {}

local FlushIntervalSeconds = 0.1

local DirtyPlayers = {}
local Contributors = {}
local LastFlush = 0

-- Contributor(Player, Profile, Derived) returns the value stored at View[Key].
function StateReplicator.AddContributor(Key: string, Contributor)
	Contributors[Key] = Contributor
end

function StateReplicator.MarkDirty(Player: Player)
	DirtyPlayers[Player] = true
end

local function ListKeys(Set)
	local List = {}
	for Key in Set do
		table.insert(List, Key)
	end
	table.sort(List)
	return List
end

function StateReplicator.BuildItemView(Item, Stats)
	return {
		Uid = Item.Uid,
		TypeId = Item.TypeId,
		Condition = Item.Condition,
		State = Item.State,
		Favorite = Item.Favorite,
		Completed = Item.Completed,
		SlotId = Item.SlotId,
		Traits = table.clone(Item.RevealedTraits),
		HiddenTraitCount = #Item.Traits - #Item.RevealedTraits,
		Progress = if Item.Completed then 1 elseif Item.Restoration then Item.Restoration.Progress or 0 else 0,
		StageIndex = if Item.Restoration then Item.Restoration.StageIndex else 1,
		FullValue = PriceCalculator.FullValue(Item, Stats),
		ScrapValue = PriceCalculator.ScrapValue(Item, Stats),
		AcquiredAt = Item.AcquiredAt,
	}
end

local function BuildView(Player: Player, Profile)
	local Derived = PlayerDataService.GetDerived(Player)
	local Stats = Derived.Stats
	local CanAppraise = Derived.Features.Appraisal == true

	local Items = {}
	for Uid, Item in Profile.Items do
		local View = StateReplicator.BuildItemView(Item, Stats)
		if not CanAppraise then
			View.HiddenTraitCount = nil
		end
		Items[Uid] = View
	end

	local View = {
		Money = Profile.Money,
		Items = Items,
		ActiveItemUid = Profile.ActiveItemUid,
		SkillNodes = table.clone(Profile.SkillNodes),
		Stats = Stats,
		Tools = ListKeys(Derived.Tools),
		Pools = ListKeys(Derived.Pools),
		Features = ListKeys(Derived.Features),
		Collection = Profile.Collection,
		ClaimedRewards = Profile.ClaimedRewards,
		Tutorial = Profile.Tutorial,
		Pity = Profile.Pity,
		RollCooldowns = Profile.RollCooldowns,
		Workshop = Profile.Workshop,
		Settings = Profile.Settings,
		Daily = Profile.Daily,
		Weekly = Profile.Weekly,
		ServerTime = os.time(),
	}
	for Key, Contributor in Contributors do
		View[Key] = Contributor(Player, Profile, Derived)
	end
	return View
end

local function Flush()
	for Player in DirtyPlayers do
		DirtyPlayers[Player] = nil
		local Profile = PlayerDataService.Get(Player)
		if Profile and Player.Parent then
			NetworkService.Push(Player, "StateSnapshot", BuildView(Player, Profile))
		end
	end
end

function StateReplicator.Start()
	RunService.Heartbeat:Connect(function()
		local Now = os.clock()
		if Now - LastFlush >= FlushIntervalSeconds and next(DirtyPlayers) then
			LastFlush = Now
			Flush()
		end
	end)
	GameEvents.ProfileLoaded:Connect(StateReplicator.MarkDirty)
	Players.PlayerRemoving:Connect(function(Player)
		DirtyPlayers[Player] = nil
	end)
end

return StateReplicator
