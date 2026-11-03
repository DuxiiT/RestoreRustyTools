-- Item location changes that are not sales or rolls: favorites, finishing choices and settings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Result = require(Shared.Util.Result)

local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local WorkshopService = require(script.Parent.WorkshopService)
local SalesService = require(script.Parent.SalesService)
local DisplayService = require(script.Parent.DisplayService)

local InventoryService = {}

function InventoryService.SetFavorite(Player: Player, Uid: string, Favorite: boolean)
	local Profile = PlayerDataService.Get(Player)
	local Item = Profile.Items[Uid]
	if not Item then
		return Result.Fail("That item is no longer in your inventory.")
	end
	Item.Favorite = Favorite
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ItemUid = Uid, Favorite = Favorite })
end

-- The three choices offered when a restoration finishes. Each moves the same item record.
function InventoryService.ResolveResult(Player: Player, Uid: string, Action: string)
	local Profile = PlayerDataService.Get(Player)
	local Item = Profile.Items[Uid]
	if not Item or not Item.Completed then
		return Result.Fail("That finished item is no longer available.")
	end
	if Action == "Sell" then
		return SalesService.Sell(Player, Uid, "Full")
	elseif Action == "Display" then
		return DisplayService.Place(Player, Uid, nil)
	end
	if Item.State == "Tray" then
		Item.State = "Storage"
		WorkshopService.RefreshTray(Player, Profile)
		StateReplicator.MarkDirty(Player)
	end
	return Result.Ok({ ItemUid = Uid, State = Item.State })
end

local SettingTypes = {
	SoundEffects = "boolean",
	ReducedEffects = "boolean",
	SkipRollAnimation = "boolean",
	ToolVolume = "number",
}

function InventoryService.UpdateSetting(Player: Player, Key: string, Value)
	if typeof(Value) ~= SettingTypes[Key] then
		return Result.Fail("That setting value isn't valid.")
	end
	PlayerDataService.Get(Player).Settings[Key] = Value
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ Key = Key, Value = Value })
end

function InventoryService.Init()
	NetworkService.Handle("SetFavorite", InventoryService.SetFavorite)
	NetworkService.Handle("ResolveResult", InventoryService.ResolveResult)
	NetworkService.Handle("UpdateSetting", InventoryService.UpdateSetting)
end

return InventoryService
