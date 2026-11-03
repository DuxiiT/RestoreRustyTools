-- ValuePerSecond and FlatValue feed the suggested base value of items that do not
-- set BaseValue explicitly, so long jobs are paid for regardless of rarity.
local RarityConfig = {}

RarityConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

RarityConfig.Tiers = {
	Common = { Rank = 1, Label = "Common", Color = Color3.fromRGB(176, 176, 176), ValuePerSecond = 0.9, FlatValue = 3 },
	Uncommon = { Rank = 2, Label = "Uncommon", Color = Color3.fromRGB(98, 190, 98), ValuePerSecond = 1.3, FlatValue = 10 },
	Rare = { Rank = 3, Label = "Rare", Color = Color3.fromRGB(72, 142, 232), ValuePerSecond = 2.0, FlatValue = 40 },
	Epic = { Rank = 4, Label = "Epic", Color = Color3.fromRGB(166, 92, 222), ValuePerSecond = 3.0, FlatValue = 120 },
	Legendary = { Rank = 5, Label = "Legendary", Color = Color3.fromRGB(242, 172, 42), ValuePerSecond = 4.5, FlatValue = 400 },
	Mythic = { Rank = 6, Label = "Mythic", Color = Color3.fromRGB(232, 62, 92), ValuePerSecond = 6.5, FlatValue = 1200 },
}

function RarityConfig.GetRank(Rarity: string): number
	local Tier = RarityConfig.Tiers[Rarity]
	return if Tier then Tier.Rank else 0
end

return RarityConfig
