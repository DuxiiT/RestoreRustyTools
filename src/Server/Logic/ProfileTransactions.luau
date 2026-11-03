-- Economy transactions on a profile table. Each function validates everything first and only
-- then mutates, without yielding, so a transaction is atomic and a repeated request finds the
-- state already changed (item gone, rank owned) instead of granting twice.
-- Kept free of Players and remotes so tests can run them on plain tables.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local SalvagePools = require(Shared.Config.SalvagePools)
local SkillTree = require(Shared.Config.SkillTree)
local RollOdds = require(Shared.Logic.RollOdds)
local PriceCalculator = require(Shared.Logic.PriceCalculator)
local SkillTreeRules = require(Shared.Logic.SkillTreeRules)
local StatCalculator = require(Shared.Logic.StatCalculator)
local Schedule = require(Shared.Logic.Schedule)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)
local ItemFactory = require(script.Parent.ItemFactory)

local ProfileTransactions = {}

local CapacityStates = { Storage = true, Bench = true, Tray = true }

function ProfileTransactions.StoredCount(Profile): number
	local Count = 0
	for _, Item in Profile.Items do
		if CapacityStates[Item.State] then
			Count += 1
		end
	end
	return Count
end

function ProfileTransactions.HasSpace(Profile, Stats, Count: number?): boolean
	return ProfileTransactions.StoredCount(Profile) + (Count or 1) <= Stats.InventoryCapacity
end

function ProfileTransactions.Earn(Profile, Amount: number)
	Profile.Money = math.min(EconomyConfig.MaxMoney, Profile.Money + math.max(0, math.floor(Amount)))
end

function ProfileTransactions.Spend(Profile, Amount: number): boolean
	if Amount < 0 or Profile.Money < Amount then
		return false
	end
	Profile.Money -= Amount
	return true
end

-- Context: { Derived, IsAvailable, Random, Now, UserId, Free, AllowIndirect, Source }
function ProfileTransactions.Roll(Profile, PoolId: string, Context)
	local Pool = SalvagePools[PoolId]
	if not Pool or (not Pool.Direct and not Context.AllowIndirect) then
		return Result.Fail("That crate doesn't exist.")
	end
	if Pool.UnlockNode and not Context.Derived.Pools[PoolId] then
		return Result.Fail(`Unlock {SkillTree[Pool.UnlockNode].Name} on the skill board first.`, "Locked")
	end
	if Pool.Featured and not Schedule.IsFeaturedPoolActive(PoolId, Context.Now) then
		return Result.Fail("That featured delivery isn't in rotation right now.", "NotFeatured")
	end
	if not Context.Free then
		local ReadyAt = Profile.RollCooldowns[PoolId] or 0
		if Context.Now < ReadyAt then
			return Result.Fail(`{Pool.DisplayName} is ready in {Format.Duration(ReadyAt - Context.Now)}.`, "Cooldown")
		end
	end
	local Stats = Context.Derived.Stats
	if not ProfileTransactions.HasSpace(Profile, Stats) then
		return Result.Fail("Your storage is full. Sell, display or scrap an item first.", "StorageFull")
	end
	local Cost = if Context.Free then 0 else Pool.Cost
	if Profile.Money < Cost then
		return Result.Fail(`You need {Format.Money(Cost)} for this crate. The Scrap Bin is always free.`, "InsufficientFunds")
	end

	local Odds = RollOdds.Compute(Pool, Context.IsAvailable, Stats, Profile.Pity[PoolId] or 0)
	local ItemId, Rarity = RollOdds.Pick(Odds, Context.Random)
	if not ItemId then
		return Result.Fail("Nothing is available in this crate yet.", "Empty")
	end

	ProfileTransactions.Spend(Profile, Cost)
	if not Context.Free and Pool.CooldownSeconds then
		Profile.RollCooldowns[PoolId] = Context.Now + Pool.CooldownSeconds
	end
	if Pool.Pity then
		Profile.Pity[PoolId] = RollOdds.NextPityCount(Pool, Rarity, Profile.Pity[PoolId] or 0)
	end
	local Item = ItemFactory.Create(Profile, Context.UserId, ItemId, Context.Random, Stats, { Source = Context.Source or PoolId })
	Profile.Stats.TotalRolls += 1

	return Result.Ok({ Item = Item, PoolId = PoolId, Cost = Cost, PityTriggered = Odds.PityActive })
end

function ProfileTransactions.SellItem(Profile, Uid: string, Mode: string, Stats)
	local Item = Profile.Items[Uid]
	if not Item then
		return Result.Fail("That item is no longer in your inventory.", "Missing")
	end
	if Item.Favorite then
		return Result.Fail("Unfavorite this item before selling it.", "Favorite")
	end
	if Item.State == "Bench" then
		return Result.Fail("Shelve the item on your bench before selling it.", "OnBench")
	end
	if Item.State == "Display" then
		return Result.Fail("Take this item off display before selling it.", "OnDisplay")
	end
	if Mode ~= "Scrap" and not Item.Completed then
		return Result.Fail("This item isn't restored yet. You can scrap it for parts instead.", "Unfinished")
	end

	local Price = PriceCalculator.SalePrice(Item, Stats, Mode)
	Profile.Items[Uid] = nil
	ProfileTransactions.Earn(Profile, Price)
	Profile.Stats.ItemsSold += 1
	Profile.Stats.MoneyEarned += Price
	return Result.Ok({ Item = Item, Price = Price, Mode = Mode })
end

function ProfileTransactions.PurchaseNode(Profile, NodeId: string)
	local Node = SkillTree[NodeId]
	if not Node then
		return Result.Fail("That upgrade doesn't exist.")
	end
	local Rank = SkillTreeRules.GetRank(Profile.SkillNodes, NodeId)
	if Rank >= Node.MaxRank then
		return Result.Fail(`{Node.Name} is already at its maximum rank.`, "MaxRank")
	end
	local Missing = SkillTreeRules.MissingPrerequisites(Profile.SkillNodes, NodeId)
	if #Missing > 0 then
		local Names = {}
		for _, MissingId in Missing do
			table.insert(Names, SkillTree[MissingId].Name)
		end
		return Result.Fail(`Requires {table.concat(Names, " and ")}.`, "Locked")
	end
	local Price = Node.Prices[Rank + 1]
	if not ProfileTransactions.Spend(Profile, Price) then
		return Result.Fail(`You need {Format.Money(Price)} for {Node.Name}.`, "InsufficientFunds")
	end
	Profile.SkillNodes[NodeId] = Rank + 1
	Profile.SkillSpend[NodeId] = (Profile.SkillSpend[NodeId] or 0) + Price
	return Result.Ok({ NodeId = NodeId, Rank = Rank + 1, Price = Price })
end

local function RootNodes()
	local Nodes = {}
	for NodeId, Node in SkillTree do
		if Node.AutoOwned then
			Nodes[NodeId] = 1
		end
	end
	return Nodes
end

local function MissingKeys(Before, After)
	local Lost = {}
	for Key in Before do
		if not After[Key] then
			table.insert(Lost, Key)
		end
	end
	table.sort(Lost)
	return Lost
end

-- Refunds exactly what was recorded as spent, minus a fee, so a reset can never create money.
function ProfileTransactions.PreviewReset(Profile, DisplayCount: number)
	local Refund = 0
	local AffectedNodes = {}
	for NodeId, Spent in Profile.SkillSpend do
		Refund += Spent
		if (Profile.SkillNodes[NodeId] or 0) > 0 then
			table.insert(AffectedNodes, NodeId)
		end
	end
	table.sort(AffectedNodes)
	local Fee = math.min(Refund, math.max(EconomyConfig.SkillResetMinimumFee, math.floor(Refund * EconomyConfig.SkillResetFeeFraction)))

	local Current = StatCalculator.Compute(Profile.SkillNodes)
	local AfterReset = StatCalculator.Compute(RootNodes())
	local Warnings = {}
	local Stored = ProfileTransactions.StoredCount(Profile)
	if Stored > AfterReset.Stats.InventoryCapacity then
		table.insert(
			Warnings,
			`You keep all {Stored} stored items, but can't roll until you are under {AfterReset.Stats.InventoryCapacity}.`
		)
	end
	if DisplayCount > AfterReset.Stats.DisplayCapacity then
		table.insert(
			Warnings,
			`Your {DisplayCount} displayed items stay, but you can't add more until under {AfterReset.Stats.DisplayCapacity}.`
		)
	end
	if Current.Features.AutoRoll then
		table.insert(Warnings, "Auto-roll stops.")
	end

	return {
		CanReset = Refund > 0,
		Refund = Refund,
		Fee = Fee,
		Net = Refund - Fee,
		AffectedNodes = AffectedNodes,
		LostTools = MissingKeys(Current.Tools, AfterReset.Tools),
		LostPools = MissingKeys(Current.Pools, AfterReset.Pools),
		LostFeatures = MissingKeys(Current.Features, AfterReset.Features),
		Warnings = Warnings,
	}
end

function ProfileTransactions.ApplyReset(Profile, DisplayCount: number)
	local Preview = ProfileTransactions.PreviewReset(Profile, DisplayCount)
	if not Preview.CanReset then
		return Result.Fail("You haven't bought any upgrades to reset.")
	end
	Profile.SkillNodes = RootNodes()
	Profile.SkillSpend = {}
	ProfileTransactions.Earn(Profile, Preview.Net)
	return Result.Ok(Preview)
end

return ProfileTransactions
