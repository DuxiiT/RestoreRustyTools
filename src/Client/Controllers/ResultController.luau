-- Finished-restoration screen: before and after, discovered details, value, and the choice to
-- sell, store or display. Closing leaves the item safely on the finished tray.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RarityConfig = require(Shared.Config.RarityConfig)
local VariantDefinitions = require(Shared.Config.VariantDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)
local RestorationController = require(script.Parent.RestorationController)
local FeedbackController = require(script.Parent.FeedbackController)

local ResultController = {}

local Gui, Window
local CurrentUid = nil

local function Resolve(Action: string)
	if not CurrentUid then
		return
	end
	local Response = Remotes.Request("ResolveResult", CurrentUid, Action)
	if NotificationController.Report(Response) then
		if Action == "Sell" then
			NotificationController.Show(`Sold for {Format.Money(Response.Data.Price)}`, "Sale")
			FeedbackController.PlaySound("Sale")
		end
		CurrentUid = nil
		PanelController.Close("Result")
	end
end

function ResultController.Show(Item)
	local Definition = ItemCatalog.Get(Item.TypeId)
	CurrentUid = Item.Uid
	UiUtil.ShowItem(UiUtil.Find(Window, "BeforeViewport"), Item.TypeId, false, nil)
	UiUtil.ShowItem(UiUtil.Find(Window, "AfterViewport"), Item.TypeId, true, Item.Traits)
	UiUtil.SetText(UiUtil.Find(Window, "NameLabel"), Definition.Name)
	UiUtil.ApplyRarity(UiUtil.Find(Window, "RarityLabel"), Definition.Rarity)

	local Details = { `Condition {Item.Condition}` }
	for _, VariantId in Item.Traits do
		local Variant = VariantDefinitions[VariantId]
		table.insert(Details, `{Variant.Name}: {Variant.Description}`)
	end
	UiUtil.SetText(UiUtil.Find(Window, "DetailsLabel"), table.concat(Details, "\n"))
	UiUtil.SetText(UiUtil.Find(Window, "ValueLabel"), `Sells for {Format.Money(Item.FullValue)}`)
	UiUtil.SetText(
		UiUtil.Find(Window, "SellButton"),
		if Item.Favorite then "Favorite (protected)" else `Sell {Format.Money(Item.FullValue)}`
	)
	PanelController.Open("Result")

	-- Bigger celebrations are kept for rare finds and hidden details.
	local Important = #Item.Traits > 0 or RarityConfig.GetRank(Definition.Rarity) >= RarityConfig.GetRank("Epic")
	FeedbackController.PlaySound(if Important then "Celebrate_Big" else "Celebrate_Small")
end

function ResultController.Init()
	Gui = UiUtil.WaitForGui("ResultGui")
	PanelController.Register("Result", Gui)
	Window = UiUtil.Find(Gui, "Window")
	UiUtil.Bind(UiUtil.Find(Window, "SellButton"), function()
		Resolve("Sell")
	end)
	UiUtil.Bind(UiUtil.Find(Window, "StoreButton"), function()
		Resolve("Store")
	end)
	UiUtil.Bind(UiUtil.Find(Window, "DisplayButton"), function()
		Resolve("Display")
	end)
	UiUtil.Bind(UiUtil.Find(Window, "CloseButton"), function()
		PanelController.Close("Result")
	end)
	RestorationController.Completed:Connect(ResultController.Show)
end

return ResultController
