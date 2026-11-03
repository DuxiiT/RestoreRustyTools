-- Gameplay events that cross system boundaries (tutorial, collection, challenges, commissions)
-- so those systems listen instead of being called from every service.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

return {
	ProfileLoaded = Signal.New(), -- (Player, Profile)
	ProfileReleasing = Signal.New(), -- (Player, Profile)
	ItemRolled = Signal.New(), -- (Player, Item, PoolId)
	JobStarted = Signal.New(), -- (Player, Item)
	TraitRevealed = Signal.New(), -- (Player, Item, VariantId)
	ItemCompleted = Signal.New(), -- (Player, Item)
	ItemSold = Signal.New(), -- (Player, Item, Price)
	NodePurchased = Signal.New(), -- (Player, NodeId, Rank)
	SkillTreeReset = Signal.New(), -- (Player)
}
