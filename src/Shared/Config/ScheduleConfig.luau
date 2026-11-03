-- All schedules derive from server os.time() in UTC, so every server agrees and rejoining
-- cannot reset a claim.
return {
	DaySeconds = 24 * 60 * 60,
	WeekSeconds = 7 * 24 * 60 * 60,
	-- Shifts week boundaries so weeks roll over on Monday 00:00 UTC (epoch started on a Thursday).
	WeekOffsetSeconds = 3 * 24 * 60 * 60,

	FeaturedRotationSeconds = 6 * 60 * 60,
	FeaturedThemes = {
		{ Theme = "Garage", Pool = "FeaturedGarage" },
		{ Theme = "Nautical", Pool = "FeaturedNautical" },
		{ Theme = "Medieval", Pool = "FeaturedMedieval" },
	},

	WeeklyChallengeCount = 3,
	WeeklyChallenges = {
		{ Id = "RestoreMany", Kind = "RestoreCount", Target = 15, Reward = 1200, Text = "Restore 15 items" },
		{ Id = "RestoreTools", Kind = "RestoreCategory", Category = "Tools", Target = 6, Reward = 900, Text = "Restore 6 Tools items" },
		{
			Id = "RestoreHardware",
			Kind = "RestoreCategory",
			Category = "Hardware",
			Target = 10,
			Reward = 700,
			Text = "Restore 10 Hardware items",
		},
		{
			Id = "RestoreHistorical",
			Kind = "RestoreCategory",
			Category = "Historical",
			Target = 3,
			Reward = 2500,
			Text = "Restore 3 Historical items",
		},
		{ Id = "RestoreRare", Kind = "RestoreRarity", Rarity = "Rare", Target = 3, Reward = 2000, Text = "Restore 3 Rare-or-better items" },
		{ Id = "EarnSales", Kind = "EarnMoney", Target = 5000, Reward = 1500, Text = "Earn $5,000 from sales" },
		{ Id = "OpenCrates", Kind = "RollCount", Target = 20, Reward = 800, Text = "Open 20 salvage crates" },
		{ Id = "FindDetails", Kind = "DiscoverVariant", Target = 2, Reward = 1800, Text = "Uncover 2 hidden details" },
	},
}
