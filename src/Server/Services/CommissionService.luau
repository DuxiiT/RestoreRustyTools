-- Customer commissions: clear requests with known rewards, drawn only from items the player can
-- actually roll. One offer is a timed order with a generous deadline and a bonus; letting it
-- expire only replaces the offer and never touches owned items.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CommissionConfig = require(Shared.Config.CommissionConfig)
local SalvagePools = require(Shared.Config.SalvagePools)
local RarityConfig = require(Shared.Config.RarityConfig)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local RollOdds = require(Shared.Logic.RollOdds)
local PriceCalculator = require(Shared.Logic.PriceCalculator)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local ContentRegistry = require(script.Parent.ContentRegistry)
local WorkshopService = require(script.Parent.WorkshopService)

local CommissionService = {}

local ExpiryCheckSeconds = 60
local RandomSource = Random.new()

local function RequestableItems(Derived)
	local MaxRank = RarityConfig.GetRank(CommissionConfig.MaxRequestRarity)
	local Seen, Items = {}, {}
	for PoolId, Pool in SalvagePools do
		local Unlocked = not Pool.UnlockNode or Derived.Pools[PoolId]
		if Pool.Direct and not Pool.Featured and Unlocked then
			for Rarity, ItemIds in RollOdds.GetPoolItems(Pool, ContentRegistry.IsAvailable) do
				if RarityConfig.GetRank(Rarity) <= MaxRank then
					for _, ItemId in ItemIds do
						if not Seen[ItemId] then
							Seen[ItemId] = true
							table.insert(Items, ItemId)
						end
					end
				end
			end
		end
	end
	table.sort(Items)
	return Items
end

local function GenerateOffer(Profile, Derived, Timed: boolean)
	local Candidates = RequestableItems(Derived)
	if #Candidates == 0 then
		return nil
	end
	local Taken = {}
	for _, Offer in Profile.Commissions.Offers do
		Taken[Offer.TypeId or Offer.Category] = true
	end

	local Multiplier = (if Timed then CommissionConfig.TimedRewardMultiplier else CommissionConfig.RewardMultiplier)
		* (1 + Derived.Stats.CommissionBonus)
	Profile.Commissions.Serial += 1
	local Offer = { Id = `C{Profile.Commissions.Serial}`, Timed = Timed }
	if Timed then
		Offer.ExpiresAt = os.time() + CommissionConfig.TimedDurationSeconds
	end

	if RandomSource:NextNumber() < CommissionConfig.CategoryRequestChance then
		local ValuesByCategory = {}
		for _, ItemId in Candidates do
			local Definition = ItemCatalog.Get(ItemId)
			ValuesByCategory[Definition.Category] = ValuesByCategory[Definition.Category] or {}
			table.insert(ValuesByCategory[Definition.Category], Definition.BaseValue)
		end
		local Categories = {}
		for Category in ValuesByCategory do
			if not Taken[Category] then
				table.insert(Categories, Category)
			end
		end
		if #Categories > 0 then
			table.sort(Categories)
			local Category = Categories[RandomSource:NextInteger(1, #Categories)]
			local Lowest = math.min(table.unpack(ValuesByCategory[Category]))
			Offer.Kind = "Category"
			Offer.Category = Category
			Offer.Reward = math.floor(Lowest * Multiplier * CommissionConfig.CategoryRewardMultiplier + 0.5)
			return Offer
		end
	end

	local Available = {}
	for _, ItemId in Candidates do
		if not Taken[ItemId] then
			table.insert(Available, ItemId)
		end
	end
	if #Available == 0 then
		return nil
	end
	local TypeId = Available[RandomSource:NextInteger(1, #Available)]
	Offer.Kind = "Item"
	Offer.TypeId = TypeId
	Offer.Reward = math.floor(ItemCatalog.Get(TypeId).BaseValue * Multiplier + 0.5)
	return Offer
end

-- Removes expired timed orders and tops offers back up. Returns true when anything changed.
local function RefreshOffers(Player: Player, Profile): boolean
	local Derived = PlayerDataService.GetDerived(Player)
	if not Derived.Features.Commissions then
		return false
	end
	local Offers = Profile.Commissions.Offers
	local Now = os.time()
	local Changed = false
	for Index = #Offers, 1, -1 do
		if Offers[Index].ExpiresAt and Offers[Index].ExpiresAt <= Now then
			table.remove(Offers, Index)
			Changed = true
		end
	end
	local function CountOffers(Timed)
		local Count = 0
		for _, Offer in Offers do
			if Offer.Timed == Timed then
				Count += 1
			end
		end
		return Count
	end
	for _, Spec in { { Timed = false, Target = CommissionConfig.OfferCount }, { Timed = true, Target = CommissionConfig.TimedOfferCount } } do
		while CountOffers(Spec.Timed) < Spec.Target do
			local Offer = GenerateOffer(Profile, Derived, Spec.Timed)
			if not Offer then
				break
			end
			table.insert(Offers, Offer)
			Changed = true
		end
	end
	return Changed
end

local function FindOffer(Profile, CommissionId: string)
	for Index, Offer in Profile.Commissions.Offers do
		if Offer.Id == CommissionId then
			return Offer, Index
		end
	end
	return nil, nil
end

function CommissionService.Submit(Player: Player, CommissionId: string, Uid: string)
	local Profile = PlayerDataService.Get(Player)
	local Derived = PlayerDataService.GetDerived(Player)
	if not Derived.Features.Commissions then
		return Result.Fail("Unlock the Commission Board on the skill board first.", "Locked")
	end
	local Offer, Index = FindOffer(Profile, CommissionId)
	if not Offer or (Offer.ExpiresAt and Offer.ExpiresAt <= os.time()) then
		return Result.Fail("That commission is no longer open.")
	end
	local Item = Profile.Items[Uid]
	if not Item then
		return Result.Fail("That item is no longer in your inventory.")
	end
	if not Item.Completed then
		return Result.Fail("Commissions need a fully restored item.")
	end
	if Item.Favorite then
		return Result.Fail("Unfavorite this item before handing it over.", "Favorite")
	end
	if Item.State ~= "Storage" and Item.State ~= "Tray" then
		return Result.Fail("Take this item off display first.")
	end
	local Definition = ItemCatalog.Get(Item.TypeId)
	local Matches = if Offer.Kind == "Item" then Item.TypeId == Offer.TypeId else Definition.Category == Offer.Category
	if not Matches then
		return Result.Fail("That item doesn't match this request.")
	end

	-- A commission never pays less than selling the same item normally would.
	local Reward = math.max(Offer.Reward, PriceCalculator.FullValue(Item, Derived.Stats))
	Profile.Items[Uid] = nil
	table.remove(Profile.Commissions.Offers, Index)
	ProfileTransactions.Earn(Profile, Reward)
	Profile.Stats.MoneyEarned += Reward
	RefreshOffers(Player, Profile)
	WorkshopService.RefreshTray(Player, Profile)
	StateReplicator.MarkDirty(Player)
	NetworkService.Notify(Player, `Commission complete! +{Format.Money(Reward)}`, "Sale")
	return Result.Ok({ CommissionId = CommissionId, Reward = Reward })
end

function CommissionService.Decline(Player: Player, CommissionId: string)
	local Profile = PlayerDataService.Get(Player)
	local Now = os.time()
	if Now < Profile.Commissions.DeclineReadyAt then
		return Result.Fail(`You can decline another request in {Format.Duration(Profile.Commissions.DeclineReadyAt - Now)}.`, "Cooldown")
	end
	local _, Index = FindOffer(Profile, CommissionId)
	if not Index then
		return Result.Fail("That commission is no longer open.")
	end
	table.remove(Profile.Commissions.Offers, Index)
	Profile.Commissions.DeclineReadyAt = Now + CommissionConfig.DeclineCooldownSeconds
	RefreshOffers(Player, Profile)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({})
end

local function ExpiryLoop()
	while true do
		task.wait(ExpiryCheckSeconds)
		for _, Player in PlayerDataService.GetLoadedPlayers() do
			local Profile = PlayerDataService.Get(Player)
			if Profile and RefreshOffers(Player, Profile) then
				StateReplicator.MarkDirty(Player)
			end
		end
	end
end

function CommissionService.Init()
	NetworkService.Handle("SubmitCommission", CommissionService.Submit)
	NetworkService.Handle("DeclineCommission", CommissionService.Decline)
	GameEvents.ProfileLoaded:Connect(RefreshOffers)
	GameEvents.NodePurchased:Connect(function(Player)
		local Profile = PlayerDataService.Get(Player)
		if Profile and RefreshOffers(Player, Profile) then
			StateReplicator.MarkDirty(Player)
		end
	end)
	StateReplicator.AddContributor("Commissions", function(_Player, Profile)
		return Profile.Commissions
	end)
end

function CommissionService.Start()
	task.spawn(ExpiryLoop)
end

return CommissionService
