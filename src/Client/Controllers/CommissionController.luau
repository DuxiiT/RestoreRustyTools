-- Commissions, the daily delivery, weekly challenges and the featured delivery rotation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SalvagePools = require(Shared.Config.SalvagePools)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Schedule = require(Shared.Logic.Schedule)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)
local RollController = require(script.Parent.RollController)

local CommissionController = {}

local Gui, Window

-- The same rule the player would pick by hand: the cheapest finished, non-favorite match.
local function FindMatchingItem(State, Offer)
	local Best
	for _, Item in State.Items do
		local Definition = ItemCatalog.Get(Item.TypeId)
		local Matches = Definition and (if Offer.Kind == "Item" then Item.TypeId == Offer.TypeId else Definition.Category == Offer.Category)
		if Matches and Item.Completed and not Item.Favorite and (Item.State == "Storage" or Item.State == "Tray") then
			if not Best or Item.FullValue < Best.FullValue then
				Best = Item
			end
		end
	end
	return Best
end

local function OfferTitle(Offer): string
	if Offer.Kind == "Item" then
		return `Restored {ItemCatalog.Get(Offer.TypeId).Name}`
	end
	return `Any restored {Offer.Category} item`
end

local function RefreshOffers(State)
	local List = UiUtil.Find(Window, "OfferList")
	local Template = UiUtil.Find(List, "OfferTemplate")
	if not List or not Template then
		return
	end
	Template.Visible = false
	UiUtil.ClearGenerated(List)
	local Unlocked = StateController.HasFeature("Commissions")
	UiUtil.SetVisible(UiUtil.Find(Window, "LockedLabel"), not Unlocked)
	if not Unlocked or not State.Commissions then
		return
	end
	local Now = StateController.ServerNow()
	for Index, Offer in State.Commissions.Offers do
		local Row = UiUtil.CloneTemplate(Template, List)
		Row.LayoutOrder = Index
		UiUtil.SetText(Row:FindFirstChild("TitleLabel"), OfferTitle(Offer))
		UiUtil.SetText(Row:FindFirstChild("RewardLabel"), `Reward {Format.Money(Offer.Reward)}`)
		UiUtil.SetText(
			Row:FindFirstChild("DeadlineLabel"),
			if Offer.ExpiresAt then `Timed bonus · {Format.Duration(Offer.ExpiresAt - Now)} left (optional)` else "No deadline"
		)
		local Match = FindMatchingItem(State, Offer)
		local SubmitButton = Row:FindFirstChild("SubmitButton")
		UiUtil.SetText(SubmitButton, if Match then "Hand over" else "No finished match yet")
		UiUtil.Bind(SubmitButton, function()
			local Current = FindMatchingItem(StateController.Get(), Offer)
			if not Current then
				NotificationController.Show("Restore a matching item first.", "Info")
				return
			end
			local Name = ItemCatalog.Get(Current.TypeId).Name
			if UiUtil.Confirm(`Hand over your {Name} for {Format.Money(math.max(Offer.Reward, Current.FullValue))}?`) then
				NotificationController.Report(Remotes.Request("SubmitCommission", Offer.Id, Current.Uid))
			end
		end)
		UiUtil.Bind(Row:FindFirstChild("DeclineButton"), function()
			NotificationController.Report(Remotes.Request("DeclineCommission", Offer.Id))
		end)
	end
end

local function RefreshDaily(State)
	local Daily = UiUtil.Find(Window, "Daily")
	if not Daily then
		return
	end
	local Now = StateController.ServerNow()
	local Claimed = State.Daily.LastClaimDay == Schedule.DayIndex(Now)
	UiUtil.SetText(
		UiUtil.Find(Daily, "StatusLabel"),
		if Claimed
			then `Next delivery in {Format.Duration(Schedule.NextDayAt(Now) - Now)}`
			else "Your daily delivery is waiting at the truck."
	)
	UiUtil.SetVisible(UiUtil.Find(Daily, "ClaimButton"), not Claimed)
end

local function RefreshWeekly(State)
	local Weekly = UiUtil.Find(Window, "Weekly")
	local Template = UiUtil.Find(Weekly, "ChallengeTemplate")
	if not Weekly or not Template or not State.Schedule then
		return
	end
	Template.Visible = false
	UiUtil.ClearGenerated(Weekly)
	local CurrentWeek = State.Weekly.WeekIndex == Schedule.WeekIndex(StateController.ServerNow())
	for Index, Challenge in State.Schedule.WeeklyChallenges do
		local Progress = if CurrentWeek then State.Weekly.Progress[Challenge.Id] or 0 else 0
		local Claimed = CurrentWeek and State.Weekly.Claimed[Challenge.Id] == true
		local Row = UiUtil.CloneTemplate(Template, Weekly)
		Row.LayoutOrder = Index
		UiUtil.SetText(Row:FindFirstChild("DescriptionLabel"), Challenge.Text)
		UiUtil.SetText(Row:FindFirstChild("ProgressLabel"), `{math.min(Progress, Challenge.Target)}/{Challenge.Target}`)
		UiUtil.SetText(Row:FindFirstChild("RewardLabel"), if Claimed then "Claimed" else Format.Money(Challenge.Reward))
		local ClaimButton = Row:FindFirstChild("ClaimButton")
		UiUtil.SetVisible(ClaimButton, not Claimed and Progress >= Challenge.Target)
		UiUtil.Bind(ClaimButton, function()
			NotificationController.Report(Remotes.Request("ClaimChallenge", Challenge.Id))
		end)
	end
	local Now = StateController.ServerNow()
	UiUtil.SetText(
		UiUtil.Find(Window, "WeekLabel"),
		`New challenges in {Format.Duration(State.Schedule.WeekEndsAt - Now)}. Missing a week costs nothing.`
	)
end

local function Refresh()
	local State = StateController.Get()
	if not State or not Window then
		return
	end
	RefreshOffers(State)
	RefreshDaily(State)
	RefreshWeekly(State)
	if State.Schedule then
		local Pool = SalvagePools[State.Schedule.FeaturedPool]
		local Now = StateController.ServerNow()
		UiUtil.SetText(
			UiUtil.Find(Window, "FeaturedLabel"),
			`{Pool.DisplayName} at the depot for {Format.Duration(State.Schedule.FeaturedEndsAt - Now)}`
		)
	end
end

local function ClaimDaily()
	local Response = Remotes.Request("ClaimDaily")
	if NotificationController.Report(Response) then
		NotificationController.Show(`Daily delivery: +{Format.Money(Response.Data.Money)}`, "Sale")
		RollController.PresentGrant(Response.Data)
	end
end

function CommissionController.Init()
	Gui = UiUtil.WaitForGui("CommissionGui")
	PanelController.Register("Commissions", Gui)
	Window = UiUtil.Find(Gui, "Window")
	UiUtil.Bind(UiUtil.Find(Window, "CloseButton"), function()
		PanelController.Close("Commissions")
	end)
	UiUtil.Bind(UiUtil.Find(Window, "Daily/ClaimButton"), ClaimDaily)
	PanelController.Opened:Connect(function(Name)
		if Name == "Commissions" then
			Refresh()
		end
	end)
	StateController.Changed:Connect(function()
		if PanelController.IsOpen("Commissions") then
			Refresh()
		end
	end)
end

function CommissionController.Start()
	UiUtil.ConnectPrompts("CommissionPrompt", function()
		PanelController.Open("Commissions")
	end)
	UiUtil.ConnectPrompts("DeliveryPrompt", ClaimDaily)
end

return CommissionController
