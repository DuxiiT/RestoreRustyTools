-- Commissions only request items from pools the player has unlocked, capped at MaxRequestRarity,
-- so they never wait on a tier they cannot roll.
return {
	OfferCount = 3,
	TimedOfferCount = 1,
	RewardMultiplier = 1.5,
	CategoryRewardMultiplier = 1.25,
	TimedRewardMultiplier = 2.2,
	TimedDurationSeconds = 24 * 60 * 60,
	DeclineCooldownSeconds = 120,
	MaxRequestRarity = "Rare",
	CategoryRequestChance = 0.35,
}
