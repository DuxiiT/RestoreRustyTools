-- Provisional first-session numbers. Tune here; no system hardcodes these values.
return {
	StartingMoney = 25,
	StarterItemId = "Bolt",
	StarterItemCondition = 60,
	MaxMoney = 1e12,

	BaseInventoryCapacity = 12,
	BaseDisplaySlots = 3,

	-- Selling an unfinished item (or scrapping any item) pays this fraction of its value.
	ScrapValueFraction = 0.25,
	ConditionValueMin = 0.85,
	ConditionValueMax = 1.15,
	MaxVariantsPerItem = 2,

	-- First restoration of each item type pays this fraction of its base value once.
	DiscoveryBonusFraction = 0.5,

	SkillResetFeeFraction = 0.1,
	SkillResetMinimumFee = 50,

	DailyDeliveryMoney = 50,
	DailyDeliveryPool = "DailyDelivery",

	AutoRollIntervalSeconds = 3,
	AutoRollLogLength = 20,

	-- Interaction ranges in studs. Generous so touch players are never fighting distance checks.
	StationRange = 40,
	BenchRange = 30,
}
