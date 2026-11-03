-- Permanent discovery records. Entries are written on roll and restoration and never removed
-- by selling. Each reward has a ClaimedRewards key so it can only be paid once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollectionSets = require(Shared.Config.CollectionSets)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)

local CollectionIndexService = {}

local function GetEntry(Profile, TypeId: string)
	local Entry = Profile.Collection[TypeId]
	if not Entry then
		Entry = { Discovered = true, DiscoveredAt = os.time(), Restored = false, RestoredCount = 0, Variants = {} }
		Profile.Collection[TypeId] = Entry
	end
	return Entry
end

local function OnItemRolled(Player: Player, Item)
	local Profile = PlayerDataService.Get(Player)
	if Profile then
		GetEntry(Profile, Item.TypeId)
	end
end

local function OnItemCompleted(Player: Player, Item)
	local Profile = PlayerDataService.Get(Player)
	if not Profile then
		return
	end
	local Entry = GetEntry(Profile, Item.TypeId)
	Entry.Restored = true
	Entry.RestoredCount += 1
	for _, VariantId in Item.RevealedTraits do
		Entry.Variants[VariantId] = true
	end

	local RewardKey = `Discovery_{Item.TypeId}`
	if not Profile.ClaimedRewards[RewardKey] then
		Profile.ClaimedRewards[RewardKey] = true
		local Bonus = math.floor(ItemCatalog.Get(Item.TypeId).BaseValue * EconomyConfig.DiscoveryBonusFraction + 0.5)
		ProfileTransactions.Earn(Profile, Bonus)
		NetworkService.Notify(Player, `New collection entry: {ItemCatalog.Get(Item.TypeId).Name}! +{Format.Money(Bonus)}`, "Discovery")
	end
	StateReplicator.MarkDirty(Player)
end

function CollectionIndexService.IsSetComplete(Profile, SetId: string): boolean
	for _, TypeId in CollectionSets[SetId].Items do
		local Entry = Profile.Collection[TypeId]
		if not Entry or not Entry.Restored then
			return false
		end
	end
	return true
end

function CollectionIndexService.ClaimSetReward(Player: Player, SetId: string)
	local Set = CollectionSets[SetId]
	if not Set then
		return Result.Fail("That collection doesn't exist.")
	end
	local Profile = PlayerDataService.Get(Player)
	local RewardKey = `Set_{SetId}`
	if Profile.ClaimedRewards[RewardKey] then
		return Result.Fail("You already claimed this collection reward.", "Claimed")
	end
	if not CollectionIndexService.IsSetComplete(Profile, SetId) then
		return Result.Fail("Restore every item in this collection first.", "Incomplete")
	end
	Profile.ClaimedRewards[RewardKey] = true
	ProfileTransactions.Earn(Profile, Set.Reward)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ SetId = SetId, Reward = Set.Reward })
end

function CollectionIndexService.Init()
	GameEvents.ItemRolled:Connect(OnItemRolled)
	GameEvents.ItemCompleted:Connect(OnItemCompleted)
	NetworkService.Handle("ClaimSetReward", CollectionIndexService.ClaimSetReward)
end

return CollectionIndexService
