-- Collection index. Historical discovery (kept forever) is shown separately from what the
-- player physically owns, and missing entries are never shown as complete.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollectionSets = require(Shared.Config.CollectionSets)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)

local CollectionController = {}

local Gui, SetList, SetTemplate

local function OwnedFinishedCount(State, TypeId: string): number
	local Count = 0
	for _, Item in State.Items do
		if Item.TypeId == TypeId and Item.Completed then
			Count += 1
		end
	end
	return Count
end

local function EntryStatus(State, TypeId: string): (string, string)
	local Definition = ItemCatalog.Get(TypeId)
	local Entry = State.Collection[TypeId]
	local Name = if Definition and Entry then Definition.Name else "???"
	if not Definition or not StateController.IsItemAvailable(TypeId) then
		return Name, "Not available yet"
	elseif Entry and Entry.Restored then
		local Owned = OwnedFinishedCount(State, TypeId)
		return Name, `Restored ×{Entry.RestoredCount}` .. (if Owned > 0 then ` · {Owned} owned` else "")
	elseif Entry then
		return Name, "Discovered"
	end
	return Name, "Missing"
end

-- Mirrors the server's choice: the cheapest finished, non-favorite copy of each set item.
local function SetSaleTotal(State, Set): number?
	local Total = 0
	for _, TypeId in Set.Items do
		local Best
		for _, Item in State.Items do
			if Item.TypeId == TypeId and Item.Completed and not Item.Favorite and (Item.State == "Storage" or Item.State == "Tray") then
				if not Best or Item.FullValue < Best.FullValue then
					Best = Item
				end
			end
		end
		if not Best then
			return nil
		end
		Total += math.floor(Best.FullValue * (1 + Set.SetSaleBonus) + 0.5)
	end
	return Total
end

local function Refresh()
	local State = StateController.Get()
	if not State or not SetList or not SetTemplate then
		return
	end
	UiUtil.ClearGenerated(SetList)
	for SetId, Set in CollectionSets do
		local Row = UiUtil.CloneTemplate(SetTemplate, SetList)
		Row.Name = SetId
		Row.LayoutOrder = Set.Order
		local Restored = 0
		for _, TypeId in Set.Items do
			local Entry = State.Collection[TypeId]
			if Entry and Entry.Restored then
				Restored += 1
			end
		end
		local Complete = Restored == #Set.Items
		local Claimed = State.ClaimedRewards[`Set_{SetId}`] == true
		UiUtil.SetText(Row:FindFirstChild("NameLabel"), Set.Name)
		UiUtil.SetText(Row:FindFirstChild("ProgressLabel"), `{Restored}/{#Set.Items} restored`)
		UiUtil.SetText(Row:FindFirstChild("RewardLabel"), if Claimed then "Reward claimed" else `Reward {Format.Money(Set.Reward)}`)

		local ClaimButton = Row:FindFirstChild("ClaimButton")
		UiUtil.SetVisible(ClaimButton, Complete and not Claimed)
		UiUtil.Bind(ClaimButton, function()
			local Response = Remotes.Request("ClaimSetReward", SetId)
			if NotificationController.Report(Response) then
				NotificationController.Show(`{Set.Name} complete! +{Format.Money(Response.Data.Reward)}`, "Discovery")
			end
		end)

		local SellSetButton = Row:FindFirstChild("SellSetButton")
		local SaleTotal = SetSaleTotal(State, Set)
		UiUtil.SetVisible(SellSetButton, StateController.HasFeature("SetSales") and SaleTotal ~= nil)
		UiUtil.Bind(SellSetButton, function()
			local Total = SetSaleTotal(StateController.Get(), Set)
			if
				Total
				and UiUtil.Confirm(
					`Sell one finished copy of every {Set.Name} item for {Format.Money(Total)}? Favorites are never included. Your collection record stays.`
				)
			then
				NotificationController.Report(Remotes.Request("SellSet", SetId, true))
			end
		end)

		local Entries = Row:FindFirstChild("Entries")
		local EntryTemplate = Entries and Entries:FindFirstChild("EntryTemplate")
		if EntryTemplate then
			EntryTemplate.Visible = false
			for Index, TypeId in Set.Items do
				local EntryRow = UiUtil.CloneTemplate(EntryTemplate, Entries)
				EntryRow.LayoutOrder = Index
				local Name, Status = EntryStatus(State, TypeId)
				UiUtil.SetText(EntryRow:FindFirstChild("NameLabel"), Name)
				UiUtil.SetText(EntryRow:FindFirstChild("StatusLabel"), Status)
				local Entry = State.Collection[TypeId]
				if Entry then
					UiUtil.ShowItem(EntryRow:FindFirstChild("Viewport"), TypeId, Entry.Restored, nil)
				end
			end
		end
	end
end

function CollectionController.Init()
	Gui = UiUtil.WaitForGui("CollectionGui")
	PanelController.Register("Collection", Gui)
	SetList = UiUtil.Find(Gui, "Window/SetList")
	SetTemplate = UiUtil.Find(SetList, "SetTemplate")
	if SetTemplate then
		SetTemplate.Visible = false
	end
	UiUtil.Bind(UiUtil.Find(Gui, "Window/CloseButton"), function()
		PanelController.Close("Collection")
	end)
	PanelController.Opened:Connect(function(Name)
		if Name == "Collection" then
			Refresh()
		end
	end)
	StateController.Changed:Connect(function()
		if PanelController.IsOpen("Collection") then
			Refresh()
		end
	end)
end

function CollectionController.Start()
	UiUtil.ConnectPrompts("GalleryPrompt", function()
		PanelController.Open("Collection")
	end)
end

return CollectionController
