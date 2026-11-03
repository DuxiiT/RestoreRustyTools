-- Display slots, cosmetics, and inspecting any player's displayed items. Inspection reads only
-- the public attributes the server puts on display models.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WorkshopConfig = require(Shared.Config.WorkshopConfig)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)

local WorkshopController = {}

local Gui, Window, InspectPanel

local function OwnDisplaySlots()
	for _, Plot in CollectionService:GetTagged("WorkshopPlot") do
		if Plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			local Folder = Plot:FindFirstChild("DisplaySlots")
			local SlotIds = {}
			for _, Slot in (Folder and Folder:GetChildren() or {}) do
				if Slot:IsA("BasePart") then
					table.insert(SlotIds, Slot.Name)
				end
			end
			table.sort(SlotIds)
			return SlotIds
		end
	end
	return {}
end

local function RefreshDisplays(State)
	local List = UiUtil.Find(Window, "DisplayList")
	local Template = UiUtil.Find(List, "SlotTemplate")
	if not List or not Template then
		return
	end
	Template.Visible = false
	UiUtil.ClearGenerated(List)
	for Index, SlotId in OwnDisplaySlots() do
		local Row = UiUtil.CloneTemplate(Template, List)
		Row.LayoutOrder = Index
		local Uid = State.Workshop.Displays[SlotId]
		local Item = Uid and State.Items[Uid]
		local Unlocked = Index <= State.Stats.DisplayCapacity
		UiUtil.SetText(Row:FindFirstChild("SlotLabel"), `Slot {Index}`)
		UiUtil.SetText(
			Row:FindFirstChild("ItemLabel"),
			if Item
				then ItemCatalog.Get(Item.TypeId).Name
				elseif Unlocked then "Empty: display a restored item from your inventory"
				else "Locked: buy Display Cabinets"
		)
		local RemoveButton = Row:FindFirstChild("RemoveButton")
		UiUtil.SetVisible(RemoveButton, Item ~= nil)
		UiUtil.Bind(RemoveButton, function()
			NotificationController.Report(Remotes.Request("RemoveDisplay", SlotId))
		end)
	end
end

local function RefreshCosmetics(State)
	local List = UiUtil.Find(Window, "CosmeticList")
	local Template = UiUtil.Find(List, "CosmeticTemplate")
	if not List or not Template then
		return
	end
	Template.Visible = false
	UiUtil.ClearGenerated(List)
	local Order = 0
	for Category, CategoryConfig in WorkshopConfig.Customization do
		for _, Option in CategoryConfig.Options do
			Order += 1
			local Owned = Option.Default or State.Workshop.OwnedCosmetics[`{Category}.{Option.Id}`] == true
			local Applied = (State.Workshop.Customization[Category] or (Option.Default and Option.Id)) == Option.Id
			local Row = UiUtil.CloneTemplate(Template, List)
			Row.LayoutOrder = Order
			UiUtil.SetText(Row:FindFirstChild("NameLabel"), `{CategoryConfig.DisplayName}: {Option.Name}`)
			UiUtil.SetText(
				Row:FindFirstChild("PriceLabel"),
				if Owned then (if Applied then "In use" else "Owned") else Format.Money(Option.Price)
			)
			local BuyButton = Row:FindFirstChild("BuyButton")
			local ApplyButton = Row:FindFirstChild("ApplyButton")
			UiUtil.SetVisible(BuyButton, not Owned)
			UiUtil.SetVisible(ApplyButton, Owned and not Applied)
			UiUtil.Bind(BuyButton, function()
				if UiUtil.Confirm(`Buy {Option.Name} for {Format.Money(Option.Price)}?`) then
					NotificationController.Report(Remotes.Request("BuyCosmetic", Category, Option.Id))
				end
			end)
			UiUtil.Bind(ApplyButton, function()
				NotificationController.Report(Remotes.Request("ApplyCosmetic", Category, Option.Id))
			end)
		end
	end
end

local function Refresh()
	local State = StateController.Get()
	if State and Window then
		RefreshDisplays(State)
		RefreshCosmetics(State)
	end
end

local function ShowInspect(Model: Instance)
	if not InspectPanel then
		return
	end
	UiUtil.SetText(UiUtil.Find(InspectPanel, "NameLabel"), Model:GetAttribute("ItemName") or "")
	UiUtil.SetText(UiUtil.Find(InspectPanel, "RarityLabel"), Model:GetAttribute("Rarity") or "")
	local Traits = Model:GetAttribute("Traits")
	UiUtil.SetText(UiUtil.Find(InspectPanel, "TraitsLabel"), if Traits and Traits ~= "" then Traits else "No special details")
	UiUtil.SetText(UiUtil.Find(InspectPanel, "OwnerLabel"), `Restored by {Model:GetAttribute("OwnerName") or "someone"}`)
	UiUtil.SetVisible(InspectPanel, true)
end

function WorkshopController.Init()
	Gui = UiUtil.WaitForGui("WorkshopGui")
	PanelController.Register("Workshop", Gui)
	Window = UiUtil.Find(Gui, "Window")
	UiUtil.Bind(UiUtil.Find(Window, "CloseButton"), function()
		PanelController.Close("Workshop")
	end)

	local InspectGui = UiUtil.WaitForGui("InspectGui")
	InspectPanel = UiUtil.Find(InspectGui, "InspectPanel")
	UiUtil.SetVisible(InspectPanel, false)
	UiUtil.Bind(UiUtil.Find(InspectPanel, "CloseButton"), function()
		UiUtil.SetVisible(InspectPanel, false)
	end)

	PanelController.Opened:Connect(function(Name)
		if Name == "Workshop" then
			Refresh()
		end
	end)
	StateController.Changed:Connect(function()
		if PanelController.IsOpen("Workshop") then
			Refresh()
		end
	end)
end

function WorkshopController.Start()
	ProximityPromptService.PromptTriggered:Connect(function(Prompt, PlayerWhoTriggered)
		if PlayerWhoTriggered ~= Players.LocalPlayer or Prompt.Name ~= "InspectPrompt" then
			return
		end
		local Model = Prompt:FindFirstAncestorWhichIsA("Model")
		while Model and Model:GetAttribute("ItemName") == nil do
			Model = Model:FindFirstAncestorWhichIsA("Model")
		end
		if Model then
			ShowInspect(Model)
		end
	end)
end

return WorkshopController
