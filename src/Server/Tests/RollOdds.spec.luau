local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local SalvagePools = require(Shared.Config.SalvagePools)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local RollOdds = require(Shared.Logic.RollOdds)
local StatCalculator = require(Shared.Logic.StatCalculator)

local BaseStats = StatCalculator.Compute({ FirstWorkshop = 1 }).Stats

local function AllAvailable()
	return true
end

return function(Test, Expect)
	Test("simulated rolls match configured odds", function()
		local Pool = SalvagePools.HardwareCrate
		local Odds = RollOdds.Compute(Pool, AllAvailable, BaseStats, 0)
		local Counts = {}
		local Trials = 100000
		local Generator = Random.new(12345)
		for _ = 1, Trials do
			local _, Rarity = RollOdds.Pick(Odds, Generator)
			Counts[Rarity] = (Counts[Rarity] or 0) + 1
		end
		for _, Tier in Odds.Tiers do
			local Expected = Tier.Chance
			local Observed = (Counts[Tier.Rarity] or 0) / Trials
			local Sigma = math.sqrt(Expected * (1 - Expected) / Trials)
			Expect.Near(Observed, Expected, 5 * Sigma + 1e-4, `{Tier.Rarity} frequency`)
		end
	end)

	Test("never returns unavailable content", function()
		local Allowed = { Bolt = true, Nut = true }
		local IsAvailable = function(ItemId)
			return Allowed[ItemId] == true
		end
		local Odds = RollOdds.Compute(SalvagePools.HardwareCrate, IsAvailable, BaseStats, 0)
		local Generator = Random.new(7)
		for _ = 1, 2000 do
			local ItemId = RollOdds.Pick(Odds, Generator)
			Expect.True(Allowed[ItemId], `rolled {tostring(ItemId)}`)
		end
	end)

	Test("empty pool yields nothing", function()
		local Odds = RollOdds.Compute(SalvagePools.HardwareCrate, function()
			return false
		end, BaseStats, 0)
		Expect.Equal(RollOdds.Pick(Odds, Random.new(1)), nil, "empty pick")
	end)

	Test("chances sum to one", function()
		for PoolId, Pool in SalvagePools do
			local Odds = RollOdds.Compute(Pool, AllAvailable, BaseStats, 0)
			if #Odds.Tiers > 0 then
				local Total = 0
				for _, Tier in Odds.Tiers do
					Total += Tier.Chance
				end
				Expect.Near(Total, 1, 1e-9, `{PoolId} total chance`)
			end
		end
	end)

	Test("luck raises the share of uncommon-and-better", function()
		local Pool = SalvagePools.HardwareCrate
		local Lucky = table.clone(BaseStats)
		Lucky.RarityLuck = 0.5
		local Base = RollOdds.Compute(Pool, AllAvailable, BaseStats, 0)
		local Boosted = RollOdds.Compute(Pool, AllAvailable, Lucky, 0)
		Expect.True(Boosted.Tiers[1].Chance < Base.Tiers[1].Chance, "common share drops")
	end)

	Test("pity guarantees the pity rarity and resets", function()
		local Pool = SalvagePools.HardwareCrate
		local Threshold = RollOdds.GetPityThreshold(Pool, BaseStats)
		local Odds = RollOdds.Compute(Pool, AllAvailable, BaseStats, Threshold - 1)
		Expect.True(Odds.PityActive, "pity active")
		local Generator = Random.new(3)
		for _ = 1, 500 do
			local ItemId = RollOdds.Pick(Odds, Generator)
			local Rarity = ItemCatalog.Get(ItemId).Rarity
			Expect.True(Rarity ~= "Common" and Rarity ~= "Uncommon", `pity rolled {Rarity}`)
		end
		Expect.Equal(RollOdds.NextPityCount(Pool, "Rare", Threshold - 1), 0, "pity reset")
		Expect.Equal(RollOdds.NextPityCount(Pool, "Common", 3), 4, "pity increment")
	end)
end
