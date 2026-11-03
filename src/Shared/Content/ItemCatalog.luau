-- Resolves raw item definitions into complete, frozen definitions with defaults applied.
-- Adding an item only requires a new entry in one of the Config/Items modules.
local Config = script.Parent.Parent.Config
local RarityConfig = require(Config.RarityConfig)
local StageDefinitions = require(Config.StageDefinitions)
local VariantDefinitions = require(Config.VariantDefinitions)
local MaterialDefinitions = require(Config.MaterialDefinitions)
local ContentConfig = require(Config.ContentConfig)

local ItemCatalog = {}

local CategoryModules = {
	Config.Items.StarterItems,
	Config.Items.HardwareAndTools,
	Config.Items.HouseholdAndGarden,
	Config.Items.MechanicalAndSporting,
	Config.Items.HistoricalWeapons,
	Config.Items.NauticalAndCollectibles,
	Config.Items.LargeProjectsAndRelics,
}

local Definitions = {}
local OrderedIds = {}

function ItemCatalog.SuggestBaseValue(Rarity: string, TargetSeconds: number): number
	local Tier = RarityConfig.Tiers[Rarity]
	return math.floor(Tier.FlatValue + Tier.ValuePerSecond * TargetSeconds + 0.5)
end

local function ValidateDefinition(Raw, Phase)
	local Problems = {}
	if typeof(Raw.Id) ~= "string" or not string.match(Raw.Id, "^[%w_]+$") then
		table.insert(Problems, "invalid Id")
	end
	if Definitions[Raw.Id] then
		table.insert(Problems, "duplicate Id")
	end
	if not RarityConfig.Tiers[Raw.Rarity] then
		table.insert(Problems, `unknown rarity {tostring(Raw.Rarity)}`)
	end
	if not MaterialDefinitions[Raw.Material] then
		table.insert(Problems, `unknown material {tostring(Raw.Material)}`)
	end
	if typeof(Raw.TargetSeconds) ~= "number" or Raw.TargetSeconds <= 0 then
		table.insert(Problems, "TargetSeconds must be positive")
	end
	if typeof(Raw.Stages) ~= "table" or #Raw.Stages == 0 then
		table.insert(Problems, "needs at least one stage")
	else
		local Seen = {}
		for _, StageId in Raw.Stages do
			if not StageDefinitions[StageId] then
				table.insert(Problems, `unknown stage {tostring(StageId)}`)
			elseif Seen[StageId] then
				table.insert(Problems, `stage {StageId} listed twice`)
			end
			Seen[StageId] = true
		end
	end
	for _, VariantId in Raw.Variants or {} do
		if not VariantDefinitions[VariantId] then
			table.insert(Problems, `unknown variant {tostring(VariantId)}`)
		end
	end
	local Mount = Raw.Mount or "Bench"
	if not ContentConfig.MountTargetExtent[Mount] then
		table.insert(Problems, `unknown mount {tostring(Mount)}`)
	end
	if #Problems > 0 then
		error(`Item definition {tostring(Raw.Id)} (phase {Phase}): {table.concat(Problems, ", ")}`)
	end
end

local function Resolve(Raw, Phase)
	ValidateDefinition(Raw, Phase)
	return table.freeze({
		Id = Raw.Id,
		Name = Raw.Name,
		Category = Raw.Category,
		Rarity = Raw.Rarity,
		Material = Raw.Material,
		Mount = Raw.Mount or "Bench",
		ModelName = Raw.ModelName or Raw.Id,
		TargetSeconds = Raw.TargetSeconds,
		Stages = table.freeze(table.clone(Raw.Stages)),
		Variants = table.freeze(table.clone(Raw.Variants or {})),
		BaseValue = Raw.BaseValue or ItemCatalog.SuggestBaseValue(Raw.Rarity, Raw.TargetSeconds),
		Description = Raw.Description or "",
		Phase = Phase,
	})
end

local EnabledPhases = {}
for _, Phase in ContentConfig.EnabledPhases do
	EnabledPhases[Phase] = true
end

for _, Module in CategoryModules do
	local Group = require(Module)
	if EnabledPhases[Group.Phase] then
		for _, Raw in Group.Items do
			local Definition = Resolve(Raw, Group.Phase)
			Definitions[Definition.Id] = Definition
			table.insert(OrderedIds, Definition.Id)
		end
	end
end

table.freeze(Definitions)
table.freeze(OrderedIds)

function ItemCatalog.Get(ItemId: string)
	return Definitions[ItemId]
end

function ItemCatalog.Exists(ItemId: string): boolean
	return Definitions[ItemId] ~= nil
end

function ItemCatalog.GetAll()
	return Definitions
end

function ItemCatalog.GetOrderedIds()
	return OrderedIds
end

return ItemCatalog
