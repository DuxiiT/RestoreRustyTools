-- Saved profile layout, versioned migrations and integrity repair.
-- Only string keys and arrays are used so the data is always DataStore-safe.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local TableUtil = require(Shared.Util.TableUtil)

local ProfileSchema = {}

ProfileSchema.CurrentVersion = 1

ProfileSchema.ItemStates = table.freeze({
	Storage = "Storage",
	Bench = "Bench",
	Tray = "Tray",
	Display = "Display",
})

function ProfileSchema.CreateDefault()
	return {
		SchemaVersion = ProfileSchema.CurrentVersion,
		Money = EconomyConfig.StartingMoney,
		Items = {},
		NextItemSerial = 1,
		SkillNodes = { FirstWorkshop = 1 },
		SkillSpend = {},
		Collection = {},
		ClaimedRewards = {},
		Tutorial = { Step = 1, Completed = false, Skipped = false },
		Workshop = { Displays = {}, Customization = {}, OwnedCosmetics = {} },
		Pity = {},
		RollCooldowns = {},
		Commissions = { Offers = {}, Serial = 0, DeclineReadyAt = 0 },
		Daily = { LastClaimDay = -1 },
		Weekly = { WeekIndex = -1, Progress = {}, Claimed = {} },
		Settings = { SoundEffects = true, ReducedEffects = false, SkipRollAnimation = false, ToolVolume = 1 },
		Stats = { TotalRolls = 0, ItemsRestored = 0, ItemsSold = 0, MoneyEarned = 0, VariantsFound = 0 },
		StarterGranted = false,
		CreatedAt = os.time(),
	}
end

-- Migrations[N] upgrades a version N profile to N + 1 in place. Never remove an entry.
local Migrations = {}

-- Enforces "every owned item exists in exactly one location" after loading.
local function RepairItemLocations(Data)
	local States = ProfileSchema.ItemStates
	for Uid, Item in Data.Items do
		if typeof(Item) ~= "table" then
			Data.Items[Uid] = nil
			continue
		end
		Item.Uid = Uid
		Item.Traits = Item.Traits or {}
		Item.RevealedTraits = Item.RevealedTraits or {}
		Item.Favorite = Item.Favorite == true
		Item.Completed = Item.Completed == true
		if not States[Item.State] then
			Item.State = States.Storage
		end
	end

	local Active = Data.ActiveItemUid and Data.Items[Data.ActiveItemUid]
	if not Active or Active.State ~= States.Bench or Active.Completed then
		Data.ActiveItemUid = nil
	end
	for Uid, Item in Data.Items do
		if Item.State == States.Bench and Uid ~= Data.ActiveItemUid then
			Item.State = States.Storage
		end
	end

	local Displays = Data.Workshop.Displays
	for SlotId, Uid in Displays do
		local Item = Data.Items[Uid]
		if not Item or Item.State ~= States.Display or Item.SlotId ~= SlotId then
			Displays[SlotId] = nil
		end
	end
	for Uid, Item in Data.Items do
		if Item.State == States.Display and Displays[Item.SlotId] ~= Uid then
			Item.State = States.Storage
			Item.SlotId = nil
		elseif Item.State ~= States.Display then
			Item.SlotId = nil
		end
	end
end

-- Returns the upgraded profile, or nil and a reason if it must not be used.
function ProfileSchema.Prepare(Data)
	if typeof(Data) ~= "table" then
		return nil, "Saved data is not a table"
	end
	local Version = Data.SchemaVersion or 1
	if Version > ProfileSchema.CurrentVersion then
		-- Saved by a newer server build; loading it here could downgrade and overwrite it.
		return nil, `Saved data version {Version} is newer than this server ({ProfileSchema.CurrentVersion})`
	end
	while Version < ProfileSchema.CurrentVersion do
		Migrations[Version](Data)
		Version += 1
		Data.SchemaVersion = Version
	end
	TableUtil.FillMissing(Data, ProfileSchema.CreateDefault())
	RepairItemLocations(Data)
	return Data
end

return ProfileSchema
