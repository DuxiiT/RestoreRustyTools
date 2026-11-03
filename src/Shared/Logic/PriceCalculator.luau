-- Sale prices. Only revealed traits count, so the displayed value never leaks hidden features
-- and a finished item (where every trait is revealed) pays its full value.
local Config = script.Parent.Parent.Config
local EconomyConfig = require(Config.EconomyConfig)
local VariantDefinitions = require(Config.VariantDefinitions)
local ItemCatalog = require(script.Parent.Parent.Content.ItemCatalog)

local PriceCalculator = {}

function PriceCalculator.ConditionMultiplier(Condition: number): number
	local Fraction = math.clamp((Condition - 1) / 99, 0, 1)
	return EconomyConfig.ConditionValueMin + (EconomyConfig.ConditionValueMax - EconomyConfig.ConditionValueMin) * Fraction
end

function PriceCalculator.TraitMultiplier(RevealedTraits): number
	local Multiplier = 1
	for _, VariantId in RevealedTraits or {} do
		local Variant = VariantDefinitions[VariantId]
		if Variant then
			Multiplier *= Variant.ValueMultiplier
		end
	end
	return Multiplier
end

-- FullValue is the price of the item once finished; scrap is the explicit unfinished rule.
function PriceCalculator.FullValue(Item, Stats): number
	local Definition = ItemCatalog.Get(Item.TypeId)
	if not Definition then
		return 0
	end
	local CategoryBonus = Stats.CategoryBonus and Stats.CategoryBonus[Definition.Category] or 0
	local Value = Definition.BaseValue
		* PriceCalculator.ConditionMultiplier(Item.Condition)
		* PriceCalculator.TraitMultiplier(Item.RevealedTraits)
		* (Stats.SaleValue + CategoryBonus)
	return math.max(1, math.floor(Value + 0.5))
end

function PriceCalculator.ScrapValue(Item, Stats): number
	return math.max(1, math.floor(PriceCalculator.FullValue(Item, Stats) * EconomyConfig.ScrapValueFraction + 0.5))
end

function PriceCalculator.SalePrice(Item, Stats, Mode: string): number
	if Mode == "Scrap" then
		return PriceCalculator.ScrapValue(Item, Stats)
	end
	return PriceCalculator.FullValue(Item, Stats)
end

return PriceCalculator
