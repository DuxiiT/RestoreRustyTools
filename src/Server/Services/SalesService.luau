-- Selling at the buyer or the player's own workshop counter. Prices are computed on the server
-- and the item is consumed in the same transaction that pays for it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollectionSets = require(Shared.Config.CollectionSets)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local PriceCalculator = require(Shared.Logic.PriceCalculator)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local StationService = require(script.Parent.StationService)
local WorkshopService = require(script.Parent.WorkshopService)

local SalesService = {}

local SellableStates = { Storage = true, Tray = true }

local function CanReachBuyer(Player: Player): boolean
	return WorkshopService.IsNearOwnWorkshop(Player) or StationService.IsNear(Player, StationService.Tags.Buyer)
end

local function AfterSale(Player: Player, Profile, Item, Price: number)
	GameEvents.ItemSold:Fire(Player, Item, Price)
	WorkshopService.RefreshTray(Player, Profile)
	StateReplicator.MarkDirty(Player)
end

-- Mode "Full" requires a finished item; "Scrap" sells anything for the scrap fraction.
-- Options: SkipProximity (used by auto-roll filters).
function SalesService.Sell(Player: Player, Uid: string, Mode: string, Options)
	if not (Options and Options.SkipProximity) and not CanReachBuyer(Player) then
		return Result.Fail("Sell at the buyer or your workshop counter.", "TooFar")
	end
	local Profile = PlayerDataService.Get(Player)
	local Derived = PlayerDataService.GetDerived(Player)
	local Response = ProfileTransactions.SellItem(Profile, Uid, Mode, Derived.Stats)
	if not Response.Success then
		return Response
	end
	AfterSale(Player, Profile, Response.Data.Item, Response.Data.Price)
	return Result.Ok({ ItemUid = Uid, Price = Response.Data.Price, Mode = Mode })
end

function SalesService.BulkSell(Player: Player)
	local Derived = PlayerDataService.GetDerived(Player)
	if not Derived.Features.BulkSell then
		return Result.Fail("Unlock Bulk Sale on the skill board first.", "Locked")
	end
	if not CanReachBuyer(Player) then
		return Result.Fail("Sell at the buyer or your workshop counter.", "TooFar")
	end
	local Profile = PlayerDataService.Get(Player)
	local Uids = {}
	for Uid, Item in Profile.Items do
		if Item.Completed and not Item.Favorite and SellableStates[Item.State] then
			table.insert(Uids, Uid)
		end
	end
	if #Uids == 0 then
		return Result.Fail("You have no finished, non-favorite items to sell.")
	end
	local Total = 0
	for _, Uid in Uids do
		local Response = ProfileTransactions.SellItem(Profile, Uid, "Full", Derived.Stats)
		if Response.Success then
			Total += Response.Data.Price
			GameEvents.ItemSold:Fire(Player, Response.Data.Item, Response.Data.Price)
		end
	end
	WorkshopService.RefreshTray(Player, Profile)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ Count = #Uids, Total = Total })
end

-- The cheapest finished, non-favorite owned copy of each set item, or nil plus missing names.
function SalesService.FindSetItems(Profile, SetId: string, Stats)
	local Set = CollectionSets[SetId]
	local Chosen, Missing = {}, {}
	for _, TypeId in Set.Items do
		local Best, BestValue
		for _, Item in Profile.Items do
			if Item.TypeId == TypeId and Item.Completed and not Item.Favorite and SellableStates[Item.State] then
				local Value = PriceCalculator.FullValue(Item, Stats)
				if not Best or Value < BestValue then
					Best, BestValue = Item, Value
				end
			end
		end
		if Best then
			table.insert(Chosen, Best)
		else
			local Definition = ItemCatalog.Get(TypeId)
			table.insert(Missing, if Definition then Definition.Name else TypeId)
		end
	end
	return if #Missing == 0 then Chosen else nil, Missing
end

function SalesService.SellSet(Player: Player, SetId: string, Confirmed: boolean)
	local Set = CollectionSets[SetId]
	local Derived = PlayerDataService.GetDerived(Player)
	if not Set then
		return Result.Fail("That collection doesn't exist.")
	end
	if not Derived.Features.SetSales then
		return Result.Fail("Unlock Collection Buyers on the skill board first.", "Locked")
	end
	if not Confirmed then
		return Result.Fail("Confirm the set sale first.", "NeedsConfirmation")
	end
	if not CanReachBuyer(Player) then
		return Result.Fail("Sell at the buyer or your workshop counter.", "TooFar")
	end
	local Profile = PlayerDataService.Get(Player)
	local Items, Missing = SalesService.FindSetItems(Profile, SetId, Derived.Stats)
	if not Items then
		return Result.Fail(`You still need a finished, non-favorite: {table.concat(Missing, ", ")}.`, "Incomplete")
	end

	local Total = 0
	for _, Item in Items do
		local Price = math.floor(PriceCalculator.FullValue(Item, Derived.Stats) * (1 + Set.SetSaleBonus) + 0.5)
		Profile.Items[Item.Uid] = nil
		ProfileTransactions.Earn(Profile, Price)
		Profile.Stats.ItemsSold += 1
		Profile.Stats.MoneyEarned += Price
		Total += Price
		GameEvents.ItemSold:Fire(Player, Item, Price)
	end
	WorkshopService.RefreshTray(Player, Profile)
	StateReplicator.MarkDirty(Player)
	NetworkService.Notify(Player, `Sold the {Set.Name} set for {Format.Money(Total)}!`, "Sale")
	return Result.Ok({ SetId = SetId, Total = Total })
end

function SalesService.Init()
	NetworkService.Handle("SellItem", function(Player, Uid, Mode)
		return SalesService.Sell(Player, Uid, Mode)
	end)
	NetworkService.Handle("BulkSell", SalesService.BulkSell)
	NetworkService.Handle("SellSet", SalesService.SellSet)
end

return SalesService
