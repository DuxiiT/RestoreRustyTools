-- Creates owned item instances. Hidden traits, condition and the corrosion seed are decided
-- here exactly once and saved with the item; nothing later rerolls them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ItemCatalog = require(Shared.Content.ItemCatalog)
local VariantDefinitions = require(Shared.Config.VariantDefinitions)
local EconomyConfig = require(Shared.Config.EconomyConfig)

local ItemFactory = {}

function ItemFactory.RollTraits(Definition, RandomSource, Stats)
	local Traits = {}
	for _, VariantId in Definition.Variants do
		if #Traits >= EconomyConfig.MaxVariantsPerItem then
			break
		end
		local Chance = VariantDefinitions[VariantId].Chance * (Stats.VariantChance or 1)
		if RandomSource:NextNumber() < Chance then
			table.insert(Traits, VariantId)
		end
	end
	return Traits
end

local function NextUid(Profile, UserId: number): string
	local Uid
	repeat
		Uid = `{UserId}-{Profile.NextItemSerial}`
		Profile.NextItemSerial += 1
	until Profile.Items[Uid] == nil
	return Uid
end

-- Options: Condition, Traits, Source. Caller is responsible for capacity checks.
function ItemFactory.Create(Profile, UserId: number, TypeId: string, RandomSource, Stats, Options)
	local Definition = ItemCatalog.Get(TypeId)
	assert(Definition, `Unknown item type {TypeId}`)
	Options = Options or {}
	-- Averaging two rolls favors middling condition over extremes.
	local RolledCondition = (RandomSource:NextInteger(1, 100) + RandomSource:NextInteger(1, 100)) // 2

	local Item = {
		Uid = NextUid(Profile, UserId),
		TypeId = TypeId,
		OwnerUserId = UserId,
		Condition = Options.Condition or RolledCondition,
		Seed = RandomSource:NextInteger(1, 2 ^ 30),
		Traits = Options.Traits or ItemFactory.RollTraits(Definition, RandomSource, Stats),
		RevealedTraits = {},
		State = "Storage",
		Favorite = false,
		Completed = false,
		AcquiredAt = os.time(),
		Source = Options.Source or "Roll",
	}
	Profile.Items[Item.Uid] = Item
	return Item
end

return ItemFactory
