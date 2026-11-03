-- Derives effective stats and unlocks from owned skill-node ranks. Nothing derived is stored,
-- so an effect can never be applied twice and reconfigured nodes apply to existing saves.
local Config = script.Parent.Parent.Config
local SkillTree = require(Config.SkillTree)
local ToolDefinitions = require(Config.ToolDefinitions)
local EconomyConfig = require(Config.EconomyConfig)

local StatCalculator = {}

StatCalculator.BaseStats = table.freeze({
	CleaningStrength = 1,
	ToolRadius = 1,
	PolishEfficiency = 1,
	TreatmentPotency = 1,
	DetailPrecision = 1,
	RarityLuck = 0,
	VariantChance = 1,
	SaleValue = 1,
	InventorySlots = 0,
	DisplaySlots = 0,
	PityReduction = 0,
	CompletionLeniency = 0,
	CommissionBonus = 0,
})

function StatCalculator.Compute(OwnedNodes)
	local Stats = table.clone(StatCalculator.BaseStats)
	local CategoryBonus = {}
	local Tools = {}
	local Pools = {}
	local Features = {}

	for ToolId, Tool in ToolDefinitions do
		if Tool.Base then
			Tools[ToolId] = true
		end
	end

	for NodeId, Rank in OwnedNodes do
		local Node = SkillTree[NodeId]
		if not Node or typeof(Rank) ~= "number" or Rank <= 0 then
			continue
		end
		local EffectiveRank = math.min(Rank, Node.MaxRank)
		for _, Effect in Node.Effects do
			if Effect.Type == "Stat" then
				Stats[Effect.Stat] += Effect.PerRank * EffectiveRank
			elseif Effect.Type == "CategoryBonus" then
				CategoryBonus[Effect.Category] = (CategoryBonus[Effect.Category] or 0) + Effect.PerRank * EffectiveRank
			elseif Effect.Type == "UnlockTool" then
				Tools[Effect.Tool] = true
			elseif Effect.Type == "UnlockPool" then
				Pools[Effect.Pool] = true
			elseif Effect.Type == "UnlockFeature" then
				Features[Effect.Feature] = true
			end
		end
	end

	Stats.CategoryBonus = CategoryBonus
	Stats.InventoryCapacity = EconomyConfig.BaseInventoryCapacity + Stats.InventorySlots
	Stats.DisplayCapacity = EconomyConfig.BaseDisplaySlots + Stats.DisplaySlots

	return {
		Stats = Stats,
		Tools = Tools,
		Pools = Pools,
		Features = Features,
	}
end

return StatCalculator
