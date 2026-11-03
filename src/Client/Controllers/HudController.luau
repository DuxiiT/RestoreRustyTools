-- Always-visible essentials: money, storage, the active job and menu buttons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local StageDefinitions = require(Shared.Config.StageDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local RestorationController = require(script.Parent.RestorationController)

local HudController = {}

local Gui, MoneyLabel, CapacityLabel, JobPanel

local PanelButtons = {
	InventoryButton = "Inventory",
	SkillTreeButton = "SkillTree",
	CollectionButton = "Collection",
	CommissionsButton = "Commissions",
	WorkshopButton = "Workshop",
	SettingsButton = "Settings",
	RollButton = "Roll",
}

local function Refresh()
	local State = StateController.Get()
	if not State then
		UiUtil.SetText(MoneyLabel, "Loading...")
		return
	end
	UiUtil.SetText(MoneyLabel, Format.Money(State.Money))
	UiUtil.SetText(CapacityLabel, `Storage {StateController.StoredCount()}/{State.Stats.InventoryCapacity}`)

	local Active = State.ActiveJob
	UiUtil.SetVisible(JobPanel, Active ~= nil)
	if Active then
		local Item = State.Items[Active.ItemUid]
		local Definition = Item and ItemCatalog.Get(Item.TypeId)
		UiUtil.SetText(UiUtil.Find(JobPanel, "ItemNameLabel"), if Definition then Definition.Name else "")
		UiUtil.SetText(
			UiUtil.Find(JobPanel, "StageLabel"),
			`{StageDefinitions[Active.StageId].DisplayName} ({Active.StageIndex}/{Active.StageCount})`
		)
		UiUtil.SetProgress(UiUtil.Find(JobPanel, "ProgressBar"), Active.Progress)
	end
end

function HudController.Init()
	Gui = UiUtil.WaitForGui("HudGui")
	MoneyLabel = UiUtil.Find(Gui, "MoneyLabel")
	CapacityLabel = UiUtil.Find(Gui, "CapacityLabel")
	JobPanel = UiUtil.Find(Gui, "JobPanel")
	local Buttons = UiUtil.Find(Gui, "Buttons")
	for ButtonName, PanelName in PanelButtons do
		local Button = Buttons and Buttons:FindFirstChild(ButtonName)
		UiUtil.Bind(Button, function()
			PanelController.Toggle(PanelName)
		end)
	end
	UiUtil.Bind(UiUtil.Find(JobPanel, "OpenBenchButton"), RestorationController.EnterBench)

	StateController.Changed:Connect(Refresh)
	Refresh()
end

return HudController
