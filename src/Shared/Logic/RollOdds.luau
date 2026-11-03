-- Builds the exact odds table the server rolls from. The client uses the same function with
-- the replicated availability list, so displayed odds always match real odds.
local Config = script.Parent.Parent.Config
local RarityConfig = require(Config.RarityConfig)
local ItemCatalog = require(script.Parent.Parent.Content.ItemCatalog)

local RollOdds = {}

function RollOdds.GetPoolItems(Pool, IsAvailable)
	local CategorySet = {}
	for _, Category in Pool.Categories or {} do
		CategorySet[Category] = true
	end
	local ExplicitSet = {}
	for _, ItemId in Pool.Items or {} do
		ExplicitSet[ItemId] = true
	end

	local ItemsByRarity = {}
	for _, ItemId in ItemCatalog.GetOrderedIds() do
		local Definition = ItemCatalog.Get(ItemId)
		local InPool = ExplicitSet[ItemId] or CategorySet[Definition.Category]
		if InPool and Pool.RarityWeights[Definition.Rarity] and IsAvailable(ItemId) then
			ItemsByRarity[Definition.Rarity] = ItemsByRarity[Definition.Rarity] or {}
			table.insert(ItemsByRarity[Definition.Rarity], ItemId)
		end
	end
	return ItemsByRarity
end

function RollOdds.GetPityThreshold(Pool, Stats): number?
	if not Pool.Pity then
		return nil
	end
	return math.max(1, Pool.Pity.Threshold - (Stats.PityReduction or 0))
end

-- Returns { Tiers = { { Rarity, Weight, Chance, Items } }, PityActive, PityThreshold }.
-- Luck multiplies the weight of every tier above Common by (1 + RarityLuck).
-- When pity is active only tiers at or above the pity rarity remain.
function RollOdds.Compute(Pool, IsAvailable, Stats, PityCount: number?)
	local ItemsByRarity = RollOdds.GetPoolItems(Pool, IsAvailable)
	local PityThreshold = RollOdds.GetPityThreshold(Pool, Stats)
	local PityRank = if Pool.Pity then RarityConfig.GetRank(Pool.Pity.Rarity) else 0

	local PityPossible = false
	if PityThreshold then
		for Rarity in ItemsByRarity do
			if RarityConfig.GetRank(Rarity) >= PityRank then
				PityPossible = true
				break
			end
		end
	end
	local PityActive = PityPossible and (PityCount or 0) + 1 >= PityThreshold

	local Tiers = {}
	local TotalWeight = 0
	for _, Rarity in RarityConfig.Order do
		local Items = ItemsByRarity[Rarity]
		local BaseWeight = Pool.RarityWeights[Rarity]
		if Items and BaseWeight and BaseWeight > 0 then
			local Rank = RarityConfig.GetRank(Rarity)
			if not PityActive or Rank >= PityRank then
				local Weight = if Rank > 1 then BaseWeight * (1 + (Stats.RarityLuck or 0)) else BaseWeight
				table.insert(Tiers, { Rarity = Rarity, Weight = Weight, Items = Items })
				TotalWeight += Weight
			end
		end
	end

	for _, Tier in Tiers do
		Tier.Chance = Tier.Weight / TotalWeight
	end

	return {
		Tiers = Tiers,
		PityActive = PityActive,
		PityThreshold = PityThreshold,
		PityRarity = if Pool.Pity then Pool.Pity.Rarity else nil,
	}
end

-- RandomSource is a Roblox Random object. Returns ItemId, Rarity or nil when the pool is empty.
function RollOdds.Pick(Odds, RandomSource)
	if #Odds.Tiers == 0 then
		return nil, nil
	end
	local Roll = RandomSource:NextNumber()
	local Cumulative = 0
	local Chosen = Odds.Tiers[#Odds.Tiers]
	for _, Tier in Odds.Tiers do
		Cumulative += Tier.Chance
		if Roll < Cumulative then
			Chosen = Tier
			break
		end
	end
	local ItemId = Chosen.Items[RandomSource:NextInteger(1, #Chosen.Items)]
	return ItemId, Chosen.Rarity
end

-- Pity counts rolls since the last result at or above the pity rarity.
function RollOdds.NextPityCount(Pool, Rarity: string, PityCount: number): number
	if not Pool.Pity then
		return 0
	end
	if RarityConfig.GetRank(Rarity) >= RarityConfig.GetRank(Pool.Pity.Rarity) then
		return 0
	end
	return PityCount + 1
end

return RollOdds
