-- Inventory: inspect items, pick the next job, favorite, sell, scrap and display.
-- Rows are cached per item so previews are only rebuilt when an item changes appearance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RarityConfig = require(Shared.Config.RarityConfig)
local VariantDefinitions = require(Shared.Config.VariantDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)
local RestorationController = require(script.Parent.RestorationController)
local FeedbackController = require(script.Parent.FeedbackController)

local InventoryController = {}

local StateOrder = { Bench = 1, Tray = 2, Storage = 3, Display = 4 }
local StateLabels = { Bench = "On bench", Tray = "Finished tray", Storage = "Storage", Display = "On display" }

local Gui, List, Template
local Rows = {}

local function SortKey(Item)
	local Definition = ItemCatalog.Get(Item.TypeId)
	return StateOrder[Item.State] or 9, -RarityConfig.GetRank(Definition.Rarity), Item.AcquiredAt or 0
end

local function Describe(Item): string
	local Parts = { StateLabels[Item.State] or Item.State }
	if Item.Completed then
		table.insert(Parts, "Restored")
	elseif Item.Progress > 0 then
		table.insert(Parts, `{Format.Percent(Item.Progress, 0)} restored`)
	end
	if Item.Favorite then
		table.insert(Parts, "Favorite")
	end
	for _, VariantId in Item.Traits do
		table.insert(Parts, VariantDefinitions[VariantId].Name)
	end
	if Item.HiddenTraitCount and Item.HiddenTraitCount > 0 then
		table.insert(Parts, `Hides {Item.HiddenTraitCount} detail(s)`)
	end
	return table.concat(Parts, " · ")
end

local function Act(Name: string, ...)
	local Response = Remotes.Request(Name, ...)
	if NotificationController.Report(Response) and Name == "SellItem" then
		NotificationController.Show(`Sold for {Format.Money(Response.Data.Price)}`, "Sale")
		FeedbackController.PlaySound("Sale")
	end
	return Response
end

local function ScrapItem(Item)
	local Definition = ItemCatalog.Get(Item.TypeId)
	local Message = if Item.Completed
		then `Scrap {Definition.Name} for {Format.Money(Item.ScrapValue)}? Selling it restored pays {Format.Money(Item.FullValue)}.`
		else `Scrap the unfinished {Definition.Name} for {Format.Money(Item.ScrapValue)}? Restored it would sell for about {Format.Money(
			Item.FullValue
		)}.`
	if UiUtil.Confirm(Message) then
		Act("SellItem", Item.Uid, "Scrap")
	end
end

local function BindRow(Row, Uid: string)
	local function Current()
		return StateController.Get().Items[Uid]
	end
	UiUtil.Bind(Row:FindFirstChild("FavoriteButton"), function()
		local Item = Current()
		if Item then
			Act("SetFavorite", Uid, not Item.Favorite)
		end
	end)
	UiUtil.Bind(Row:FindFirstChild("PrimaryButton"), function()
		local Item = Current()
		if not Item then
			return
		elseif Item.State == "Bench" then
			RestorationController.EnterBench()
		elseif Item.State == "Storage" and not Item.Completed then
			RestorationController.RequestStart(Uid)
		end
	end)
	UiUtil.Bind(Row:FindFirstChild("SellButton"), function()
		Act("SellItem", Uid, "Full")
	end)
	UiUtil.Bind(Row:FindFirstChild("ScrapButton"), function()
		local Item = Current()
		if Item then
			ScrapItem(Item)
		end
	end)
	UiUtil.Bind(Row:FindFirstChild("DisplayButton"), function()
		Act("PlaceDisplay", Uid, nil)
	end)
end

local function UpdateRow(Entry, Item)
	local Row = Entry.Row
	local Definition = ItemCatalog.Get(Item.TypeId)
	local AppearanceKey = `{tostring(Item.Completed)}:{table.concat(Item.Traits, ",")}`
	if Entry.AppearanceKey ~= AppearanceKey then
		Entry.AppearanceKey = AppearanceKey
		UiUtil.ShowItem(Row:FindFirstChild("Viewport"), Item.TypeId, Item.Completed, Item.Traits)
	end
	UiUtil.SetText(Row:FindFirstChild("NameLabel"), Definition.Name)
	UiUtil.ApplyRarity(Row:FindFirstChild("RarityLabel"), Definition.Rarity)
	UiUtil.SetText(Row:FindFirstChild("StatusLabel"), Describe(Item))
	UiUtil.SetText(
		Row:FindFirstChild("ValueLabel"),
		if Item.Completed
			then `Worth {Format.Money(Item.FullValue)}`
			else `Scrap {Format.Money(Item.ScrapValue)} · Restored ~{Format.Money(Item.FullValue)}`
	)
	UiUtil.SetText(Row:FindFirstChild("FavoriteButton"), if Item.Favorite then "★" else "☆")

	local Primary = Row:FindFirstChild("PrimaryButton")
	UiUtil.SetVisible(Primary, Item.State == "Bench" or (Item.State == "Storage" and not Item.Completed))
	UiUtil.SetText(Primary, if Item.State == "Bench" then "Open bench" elseif Item.Progress > 0 then "Resume" else "Restore")
	local Sellable = (Item.State == "Storage" or Item.State == "Tray") and not Item.Favorite
	UiUtil.SetVisible(Row:FindFirstChild("SellButton"), Sellable and Item.Completed)
	UiUtil.SetVisible(Row:FindFirstChild("ScrapButton"), Sellable)
	UiUtil.SetVisible(Row:FindFirstChild("DisplayButton"), Item.Completed and (Item.State == "Storage" or Item.State == "Tray"))
end

local function Refresh()
	local State = StateController.Get()
	if not State or not List or not Template then
		return
	end
	for Uid, Entry in Rows do
		if not State.Items[Uid] then
			Entry.Row:Destroy()
			Rows[Uid] = nil
		end
	end
	local Ordered = {}
	for _, Item in State.Items do
		-- Items from a content phase disabled on this server stay saved but are not listed.
		if ItemCatalog.Get(Item.TypeId) then
			table.insert(Ordered, Item)
		end
	end
	table.sort(Ordered, function(A, B)
		local A1, A2, A3 = SortKey(A)
		local B1, B2, B3 = SortKey(B)
		if A1 ~= B1 then
			return A1 < B1
		elseif A2 ~= B2 then
			return A2 < B2
		end
		return A3 > B3
	end)
	for Index, Item in Ordered do
		local Entry = Rows[Item.Uid]
		if not Entry then
			local Row = UiUtil.CloneTemplate(Template, List)
			Row.Name = Item.Uid
			BindRow(Row, Item.Uid)
			Entry = { Row = Row }
			Rows[Item.Uid] = Entry
		end
		Entry.Row.LayoutOrder = Index
		UpdateRow(Entry, Item)
	end

	UiUtil.SetText(UiUtil.Find(Gui, "Window/CapacityLabel"), `Storage {StateController.StoredCount()}/{State.Stats.InventoryCapacity}`)
	UiUtil.SetVisible(UiUtil.Find(Gui, "Window/ShelveButton"), State.ActiveJob ~= nil)
	UiUtil.SetVisible(UiUtil.Find(Gui, "Window/BulkSellButton"), StateController.HasFeature("BulkSell"))
end

function InventoryController.Init()
	Gui = UiUtil.WaitForGui("InventoryGui")
	PanelController.Register("Inventory", Gui)
	List = UiUtil.Find(Gui, "Window/List")
	Template = UiUtil.Find(List, "ItemTemplate")
	if Template then
		Template.Visible = false
	end
	UiUtil.Bind(UiUtil.Find(Gui, "Window/CloseButton"), function()
		PanelController.Close("Inventory")
	end)
	UiUtil.Bind(UiUtil.Find(Gui, "Window/ShelveButton"), function()
		Act("ShelveJob")
	end)
	UiUtil.Bind(UiUtil.Find(Gui, "Window/BulkSellButton"), function()
		if UiUtil.Confirm("Sell every finished item that isn't a favorite or on display?") then
			local Response = Remotes.Request("BulkSell")
			if NotificationController.Report(Response) then
				NotificationController.Show(`Sold {Response.Data.Count} items for {Format.Money(Response.Data.Total)}`, "Sale")
				FeedbackController.PlaySound("Sale")
			end
		end
	end)

	StateController.Changed:Connect(function()
		if PanelController.IsOpen("Inventory") then
			Refresh()
		end
	end)
	PanelController.Opened:Connect(function(Name)
		if Name == "Inventory" then
			Refresh()
		end
	end)
end

function InventoryController.Start()
	local function OpenInventory()
		PanelController.Open("Inventory")
	end
	UiUtil.ConnectPrompts("BuyerPrompt", OpenInventory)
	UiUtil.ConnectPrompts("WorkshopSellCounter", OpenInventory)
	UiUtil.ConnectPrompts("WorkshopStorage", OpenInventory)
end

return InventoryController
