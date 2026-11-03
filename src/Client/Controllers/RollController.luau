-- Salvage depot: crate list with exact odds and costs, the dice presentation and the reveal.
-- The reveal only ever shows what the server returned, and skipping changes nothing but timing.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local SalvagePools = require(Shared.Config.SalvagePools)
local SkillTree = require(Shared.Config.SkillTree)
local RarityConfig = require(Shared.Config.RarityConfig)
local MaterialDefinitions = require(Shared.Config.MaterialDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local RollOdds = require(Shared.Logic.RollOdds)
local Schedule = require(Shared.Logic.Schedule)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)
local RestorationController = require(script.Parent.RestorationController)
local FeedbackController = require(script.Parent.FeedbackController)

local RollController = {}

local DiceSpinSeconds = 1.2

local Gui, PoolList, PoolTemplate, Reveal, AutoRollFrame
local Rolling = false
local SkipRequested = false
local LastRevealUid = nil

local function OrderedPools()
	local Pools = {}
	for _, Pool in SalvagePools do
		if Pool.Direct then
			table.insert(Pools, Pool)
		end
	end
	table.sort(Pools, function(A, B)
		return A.Order < B.Order
	end)
	return Pools
end

function RollController.DescribeOdds(Pool, Stats, PityCount: number): string
	local Odds = RollOdds.Compute(Pool, StateController.IsItemAvailable, Stats, PityCount)
	if #Odds.Tiers == 0 then
		return "No items available yet."
	end
	local Lines = {}
	for _, Tier in Odds.Tiers do
		table.insert(Lines, `{RarityConfig.Tiers[Tier.Rarity].Label} {Format.Percent(Tier.Chance)}`)
	end
	return table.concat(Lines, "  ·  ")
end

local function PoolStatus(Pool, State): (boolean, string)
	if Pool.UnlockNode and not StateController.HasPool(Pool.Id) then
		return false, `Locked: buy {SkillTree[Pool.UnlockNode].Name}`
	end
	local Now = StateController.ServerNow()
	if Pool.Featured and not Schedule.IsFeaturedPoolActive(Pool.Id, Now) then
		return false, "Not in rotation"
	end
	local ReadyAt = State.RollCooldowns[Pool.Id] or 0
	if ReadyAt > Now then
		return false, `Ready in {Format.Duration(ReadyAt - Now)}`
	end
	if StateController.StoredCount() >= State.Stats.InventoryCapacity then
		return false, "Storage full"
	end
	if State.Money < Pool.Cost then
		return false, `Need {Format.Money(Pool.Cost)}`
	end
	return true, "Ready"
end

local function RefreshPools()
	local State = StateController.Get()
	if not State or not PoolList or not PoolTemplate then
		return
	end
	UiUtil.ClearGenerated(PoolList)
	local Now = StateController.ServerNow()
	for _, Pool in OrderedPools() do
		if Pool.Featured and not Schedule.IsFeaturedPoolActive(Pool.Id, Now) then
			continue
		end
		local Row = UiUtil.CloneTemplate(PoolTemplate, PoolList)
		Row.Name = Pool.Id
		Row.LayoutOrder = Pool.Order
		local Pity = State.Pity[Pool.Id] or 0
		UiUtil.SetText(Row:FindFirstChild("NameLabel"), Pool.DisplayName)
		UiUtil.SetText(Row:FindFirstChild("DescriptionLabel"), Pool.Description)
		UiUtil.SetText(Row:FindFirstChild("CostLabel"), if Pool.Cost > 0 then Format.Money(Pool.Cost) else "Free")
		UiUtil.SetText(Row:FindFirstChild("OddsLabel"), RollController.DescribeOdds(Pool, State.Stats, Pity))
		local Threshold = RollOdds.GetPityThreshold(Pool, State.Stats)
		UiUtil.SetText(
			Row:FindFirstChild("PityLabel"),
			if Threshold then `Guaranteed {Pool.Pity.Rarity}+ within {math.max(1, Threshold - Pity)} rolls` else ""
		)
		local Ready, Status = PoolStatus(Pool, State)
		UiUtil.SetText(Row:FindFirstChild("StatusLabel"), Status)
		local Button = Row:FindFirstChild("RollButton")
		if Button and Button:IsA("GuiButton") then
			Button.Active = Ready
			Button.AutoButtonColor = Ready
			UiUtil.SetText(Button, if Pool.Cost > 0 then `Roll for {Format.Money(Pool.Cost)}` else "Roll free")
			UiUtil.Bind(Button, function()
				RollController.Roll(Pool.Id)
			end)
		end
	end
end

local function FindDice(): Instance?
	return CollectionService:GetTagged("SalvageDice")[1]
end

-- Spins the depot dice locally. The server outcome is already decided before this plays.
local function PlayDice()
	local Dice = FindDice()
	if not Dice or (not Dice:IsA("BasePart") and not Dice:IsA("Model")) then
		return
	end
	local Original = if Dice:IsA("Model") then Dice:GetPivot() else Dice.CFrame
	FeedbackController.PlaySound("DiceRoll")
	local Started = os.clock()
	while os.clock() - Started < DiceSpinSeconds and not SkipRequested do
		local Elapsed = os.clock() - Started
		local Spin = CFrame.Angles(Elapsed * 11, Elapsed * 7, Elapsed * 5)
		local Hop = CFrame.new(0, math.abs(math.sin(Elapsed * math.pi * 2)) * 1.5, 0)
		local Target = Original * Hop * Spin
		if Dice:IsA("Model") then
			Dice:PivotTo(Target)
		else
			Dice.CFrame = Target
		end
		RunService.RenderStepped:Wait()
	end
	if Dice:IsA("Model") then
		Dice:PivotTo(Original)
	else
		Dice.CFrame = Original
	end
end

local function ShowReveal(Data)
	local Item = Data.Item
	local Definition = ItemCatalog.Get(Item.TypeId)
	LastRevealUid = Item.Uid
	UiUtil.ShowItem(UiUtil.Find(Reveal, "Viewport"), Item.TypeId, false, nil)
	UiUtil.SetText(UiUtil.Find(Reveal, "NameLabel"), Definition.Name)
	UiUtil.ApplyRarity(UiUtil.Find(Reveal, "RarityLabel"), Definition.Rarity)
	UiUtil.SetText(UiUtil.Find(Reveal, "EffortLabel"), `About {Format.Duration(Data.EstimatedSeconds)} of work`)
	local Details = `{Definition.Category} · {MaterialDefinitions[Definition.Material].DisplayName} · Condition {Item.Condition}`
	if Item.HiddenTraitCount and Item.HiddenTraitCount > 0 then
		Details ..= ` · Hides {Item.HiddenTraitCount} detail(s)`
	end
	if Data.PityTriggered then
		Details ..= " · Pity guarantee!"
	end
	UiUtil.SetText(UiUtil.Find(Reveal, "DetailsLabel"), Details)
	UiUtil.SetVisible(Reveal, true)
	FeedbackController.PlaySound(`Reveal_{Definition.Rarity}`)
end

function RollController.Roll(PoolId: string)
	if Rolling then
		return
	end
	Rolling = true
	SkipRequested = false
	local Response = Remotes.Request("RollRequest", PoolId)
	if NotificationController.Report(Response) then
		if not StateController.Get().Settings.SkipRollAnimation then
			PlayDice()
		end
		ShowReveal(Response.Data)
	end
	Rolling = false
	RefreshPools()
end

-- Shows a reveal for an item granted elsewhere (daily delivery) using the same panel.
function RollController.PresentGrant(Data)
	PanelController.Open("Roll")
	ShowReveal(Data)
end

local function RefreshAutoRoll()
	local State = StateController.Get()
	if not AutoRollFrame or not State then
		return
	end
	local Unlocked = StateController.HasFeature("AutoRoll")
	UiUtil.SetVisible(AutoRollFrame, Unlocked)
	if not Unlocked then
		return
	end
	local Auto = State.AutoRoll or { Enabled = false, Log = {} }
	UiUtil.SetText(UiUtil.Find(AutoRollFrame, "ToggleButton"), if Auto.Enabled then "Stop auto-roll" else "Start auto-roll")
	local PoolId = Auto.PoolId or AutoRollFrame:GetAttribute("SelectedPool") or "HardwareCrate"
	local Pool = SalvagePools[PoolId]
	UiUtil.SetText(UiUtil.Find(AutoRollFrame, "PoolLabel"), `{Pool.DisplayName}: {Format.Money(Pool.Cost)} per roll`)
	UiUtil.SetText(
		UiUtil.Find(AutoRollFrame, "ScrapCommonsButton"),
		`Scrap plain Commons: {if AutoRollFrame:GetAttribute("ScrapCommons") then "On" else "Off"}`
	)
	UiUtil.SetText(
		UiUtil.Find(AutoRollFrame, "ScrapUncommonsButton"),
		`Scrap plain Uncommons: {if AutoRollFrame:GetAttribute("ScrapUncommons") then "On" else "Off"}`
	)
	local Lines = {}
	for _, Entry in Auto.Log do
		local Definition = ItemCatalog.Get(Entry.TypeId)
		local Name = if Definition then Definition.Name else Entry.TypeId
		table.insert(Lines, if Entry.Action == "Scrapped" then `Scrapped {Name} (+{Format.Money(Entry.Price)})` else `Kept {Name}`)
	end
	UiUtil.SetText(UiUtil.Find(AutoRollFrame, "LogLabel"), table.concat(Lines, "\n"))
end

local function BindAutoRoll()
	if not AutoRollFrame then
		return
	end
	AutoRollFrame:SetAttribute("SelectedPool", "HardwareCrate")
	local function Toggle(Attribute)
		AutoRollFrame:SetAttribute(Attribute, not AutoRollFrame:GetAttribute(Attribute))
		RefreshAutoRoll()
	end
	UiUtil.Bind(UiUtil.Find(AutoRollFrame, "ScrapCommonsButton"), function()
		Toggle("ScrapCommons")
	end)
	UiUtil.Bind(UiUtil.Find(AutoRollFrame, "ScrapUncommonsButton"), function()
		Toggle("ScrapUncommons")
	end)
	UiUtil.Bind(UiUtil.Find(AutoRollFrame, "NextPoolButton"), function()
		local Choices = {}
		for _, Pool in OrderedPools() do
			if
				Pool.Cost > 0
				and not Pool.CooldownSeconds
				and not Pool.Featured
				and (not Pool.UnlockNode or StateController.HasPool(Pool.Id))
			then
				table.insert(Choices, Pool.Id)
			end
		end
		local Index = table.find(Choices, AutoRollFrame:GetAttribute("SelectedPool")) or 0
		AutoRollFrame:SetAttribute("SelectedPool", Choices[(Index % #Choices) + 1])
		RefreshAutoRoll()
	end)
	UiUtil.Bind(UiUtil.Find(AutoRollFrame, "ToggleButton"), function()
		local State = StateController.Get()
		local Enabled = not (State.AutoRoll and State.AutoRoll.Enabled)
		local PoolId = AutoRollFrame:GetAttribute("SelectedPool")
		if
			Enabled
			and not UiUtil.Confirm(
				`Auto-roll {SalvagePools[PoolId].DisplayName} for {Format.Money(SalvagePools[PoolId].Cost)} each until you stop it, run out of money or fill your storage?`
			)
		then
			return
		end
		NotificationController.Report(
			Remotes.Request(
				"SetAutoRoll",
				Enabled,
				PoolId,
				AutoRollFrame:GetAttribute("ScrapCommons") == true,
				AutoRollFrame:GetAttribute("ScrapUncommons") == true
			)
		)
	end)
end

function RollController.Init()
	Gui = UiUtil.WaitForGui("RollGui")
	PanelController.Register("Roll", Gui)
	PoolList = UiUtil.Find(Gui, "Window/PoolList")
	PoolTemplate = UiUtil.Find(PoolList, "PoolTemplate")
	if PoolTemplate then
		PoolTemplate.Visible = false
	end
	Reveal = UiUtil.Find(Gui, "Reveal")
	UiUtil.SetVisible(Reveal, false)
	AutoRollFrame = UiUtil.Find(Gui, "Window/AutoRoll")

	UiUtil.Bind(UiUtil.Find(Gui, "Window/CloseButton"), function()
		PanelController.Close("Roll")
	end)
	UiUtil.Bind(UiUtil.Find(Reveal, "SkipButton"), function()
		SkipRequested = true
	end)
	UiUtil.Bind(UiUtil.Find(Reveal, "ContinueButton"), function()
		UiUtil.SetVisible(Reveal, false)
	end)
	UiUtil.Bind(UiUtil.Find(Reveal, "RestoreButton"), function()
		UiUtil.SetVisible(Reveal, false)
		PanelController.Close("Roll")
		if LastRevealUid then
			RestorationController.RequestStart(LastRevealUid)
		end
	end)
	BindAutoRoll()

	StateController.Changed:Connect(function()
		if PanelController.IsOpen("Roll") and not Rolling then
			RefreshPools()
			RefreshAutoRoll()
		end
	end)
	PanelController.Opened:Connect(function(Name)
		if Name == "Roll" then
			RefreshPools()
			RefreshAutoRoll()
		end
	end)
end

function RollController.Start()
	UiUtil.ConnectPrompts("SalvageDepotPrompt", function()
		PanelController.Open("Roll")
	end)
	-- Keep cooldown countdowns current while the depot is open.
	task.spawn(function()
		while true do
			task.wait(1)
			if PanelController.IsOpen("Roll") and not Rolling then
				RefreshPools()
			end
		end
	end)
end

return RollController
