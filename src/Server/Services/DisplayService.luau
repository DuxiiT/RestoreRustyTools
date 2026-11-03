-- Display shelves and workshop cosmetics. Displays and cosmetics are visual only and never
-- add an active restoration slot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WorkshopConfig = require(Shared.Config.WorkshopConfig)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local WorkshopService = require(script.Parent.WorkshopService)

local DisplayService = {}

function DisplayService.CountDisplays(Profile): number
	local Count = 0
	for _ in Profile.Workshop.Displays do
		Count += 1
	end
	return Count
end

-- Slots usable right now, in order: limited by both physical anchors and DisplayCapacity.
local function AllowedSlots(Player: Player, Stats)
	local SlotIds = WorkshopService.GetDisplaySlotIds(Player)
	local Allowed = {}
	for Index = 1, math.min(#SlotIds, Stats.DisplayCapacity) do
		table.insert(Allowed, SlotIds[Index])
	end
	return Allowed
end

function DisplayService.Place(Player: Player, Uid: string, SlotId: string?)
	local Profile = PlayerDataService.Get(Player)
	local Derived = PlayerDataService.GetDerived(Player)
	local Item = Profile.Items[Uid]
	if not Item then
		return Result.Fail("That item is no longer in your inventory.")
	end
	if not Item.Completed then
		return Result.Fail("Only restored items can go on display.")
	end
	if Item.State ~= "Storage" and Item.State ~= "Tray" then
		return Result.Fail("That item can't be displayed right now.")
	end
	if not WorkshopService.IsNearOwnWorkshop(Player) then
		return Result.Fail("Head back to your workshop to arrange displays.", "TooFar")
	end
	if DisplayService.CountDisplays(Profile) >= Derived.Stats.DisplayCapacity then
		return Result.Fail("Your display slots are full. Unlock more with Display Cabinets.", "DisplaysFull")
	end

	local Allowed = AllowedSlots(Player, Derived.Stats)
	if SlotId then
		if not table.find(Allowed, SlotId) then
			return Result.Fail("That display slot isn't available.")
		end
		if Profile.Workshop.Displays[SlotId] then
			return Result.Fail("That display slot is already used.")
		end
	else
		for _, Candidate in Allowed do
			if not Profile.Workshop.Displays[Candidate] then
				SlotId = Candidate
				break
			end
		end
		if not SlotId then
			return Result.Fail("No free display slot is available.", "DisplaysFull")
		end
	end

	Item.State = "Display"
	Item.SlotId = SlotId
	Profile.Workshop.Displays[SlotId] = Uid
	WorkshopService.RefreshDisplays(Player, Profile)
	WorkshopService.RefreshTray(Player, Profile)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ItemUid = Uid, SlotId = SlotId })
end

function DisplayService.Remove(Player: Player, SlotId: string)
	local Profile = PlayerDataService.Get(Player)
	local Derived = PlayerDataService.GetDerived(Player)
	local Uid = Profile.Workshop.Displays[SlotId]
	local Item = Uid and Profile.Items[Uid]
	if not Item then
		return Result.Fail("That display slot is empty.")
	end
	if not ProfileTransactions.HasSpace(Profile, Derived.Stats) then
		return Result.Fail("Make room in storage before taking this off display.", "StorageFull")
	end
	Item.State = "Storage"
	Item.SlotId = nil
	Profile.Workshop.Displays[SlotId] = nil
	WorkshopService.RefreshDisplays(Player, Profile)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ItemUid = Uid })
end

local function FindOption(Category: string, OptionId: string)
	local CategoryConfig = WorkshopConfig.Customization[Category]
	if not CategoryConfig then
		return nil
	end
	for _, Option in CategoryConfig.Options do
		if Option.Id == OptionId then
			return Option
		end
	end
	return nil
end

local function OwnsCosmetic(Profile, Category: string, Option): boolean
	return Option.Default == true or Profile.Workshop.OwnedCosmetics[`{Category}.{Option.Id}`] == true
end

function DisplayService.ApplyCosmetic(Player: Player, Category: string, OptionId: string)
	local Profile = PlayerDataService.Get(Player)
	local Option = FindOption(Category, OptionId)
	if not Option then
		return Result.Fail("That decoration doesn't exist.")
	end
	if not OwnsCosmetic(Profile, Category, Option) then
		return Result.Fail("Buy this decoration first.")
	end
	Profile.Workshop.Customization[Category] = OptionId
	WorkshopService.RefreshCustomization(Player, Profile)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ Category = Category, OptionId = OptionId })
end

function DisplayService.BuyCosmetic(Player: Player, Category: string, OptionId: string)
	local Profile = PlayerDataService.Get(Player)
	local Option = FindOption(Category, OptionId)
	if not Option then
		return Result.Fail("That decoration doesn't exist.")
	end
	if OwnsCosmetic(Profile, Category, Option) then
		return Result.Fail("You already own this decoration.")
	end
	if not ProfileTransactions.Spend(Profile, Option.Price) then
		return Result.Fail(`You need {Format.Money(Option.Price)} for {Option.Name}.`, "InsufficientFunds")
	end
	Profile.Workshop.OwnedCosmetics[`{Category}.{OptionId}`] = true
	return DisplayService.ApplyCosmetic(Player, Category, OptionId)
end

function DisplayService.Init()
	NetworkService.Handle("PlaceDisplay", DisplayService.Place)
	NetworkService.Handle("RemoveDisplay", DisplayService.Remove)
	NetworkService.Handle("BuyCosmetic", DisplayService.BuyCosmetic)
	NetworkService.Handle("ApplyCosmetic", DisplayService.ApplyCosmetic)
end

return DisplayService
