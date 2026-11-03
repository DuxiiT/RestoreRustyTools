-- Daily deliveries, weekly challenges and the featured delivery rotation, all keyed to server
-- UTC time. Claim state is saved, so rejoining or switching servers cannot claim twice, and
-- missing a day costs nothing beyond that day's package.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Schedule = require(Shared.Logic.Schedule)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local StationService = require(script.Parent.StationService)
local RollService = require(script.Parent.RollService)

local ScheduleService = {}

local function EnsureCurrentWeek(Profile)
	local WeekIndex = Schedule.WeekIndex(os.time())
	if Profile.Weekly.WeekIndex ~= WeekIndex then
		Profile.Weekly = { WeekIndex = WeekIndex, Progress = {}, Claimed = {} }
	end
	return Schedule.WeeklyChallenges(WeekIndex)
end

local function AddProgress(Player: Player, Matches)
	local Profile = PlayerDataService.Get(Player)
	if not Profile then
		return
	end
	local Changed = false
	for _, Challenge in EnsureCurrentWeek(Profile) do
		local Amount = Matches(Challenge)
		if Amount and Amount > 0 and not Profile.Weekly.Claimed[Challenge.Id] then
			Profile.Weekly.Progress[Challenge.Id] = math.min(Challenge.Target, (Profile.Weekly.Progress[Challenge.Id] or 0) + Amount)
			Changed = true
		end
	end
	if Changed then
		StateReplicator.MarkDirty(Player)
	end
end

function ScheduleService.ClaimDaily(Player: Player)
	local Profile = PlayerDataService.Get(Player)
	local Now = os.time()
	local Today = Schedule.DayIndex(Now)
	if Profile.Daily.LastClaimDay == Today then
		return Result.Fail(`Your next delivery arrives in {Format.Duration(Schedule.NextDayAt(Now) - Now)}.`, "Claimed")
	end
	if not StationService.IsNear(Player, StationService.Tags.DeliveryTruck) then
		return Result.Fail("Pick up your delivery at the truck entrance.", "TooFar")
	end
	-- The roll checks storage first; if it fails nothing is marked claimed.
	local Roll = RollService.Roll(Player, EconomyConfig.DailyDeliveryPool, {
		Free = true,
		AllowIndirect = true,
		SkipProximity = true,
		Source = "Daily",
	})
	if not Roll.Success then
		return Roll
	end
	Profile.Daily.LastClaimDay = Today
	ProfileTransactions.Earn(Profile, EconomyConfig.DailyDeliveryMoney)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ Item = Roll.Data.Item, Money = EconomyConfig.DailyDeliveryMoney, EstimatedSeconds = Roll.Data.EstimatedSeconds })
end

function ScheduleService.ClaimChallenge(Player: Player, ChallengeId: string)
	local Profile = PlayerDataService.Get(Player)
	local Challenge
	for _, Candidate in EnsureCurrentWeek(Profile) do
		if Candidate.Id == ChallengeId then
			Challenge = Candidate
			break
		end
	end
	if not Challenge then
		return Result.Fail("That challenge isn't active this week.")
	end
	if Profile.Weekly.Claimed[ChallengeId] then
		return Result.Fail("You already claimed this challenge.", "Claimed")
	end
	if (Profile.Weekly.Progress[ChallengeId] or 0) < Challenge.Target then
		return Result.Fail(`{Challenge.Text} to claim this reward.`, "Incomplete")
	end
	Profile.Weekly.Claimed[ChallengeId] = true
	ProfileTransactions.Earn(Profile, Challenge.Reward)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ChallengeId = ChallengeId, Reward = Challenge.Reward })
end

local function OnItemCompleted(Player: Player, Item)
	local Definition = ItemCatalog.Get(Item.TypeId)
	AddProgress(Player, function(Challenge)
		if Challenge.Kind == "RestoreCount" then
			return 1
		elseif Challenge.Kind == "RestoreCategory" and Challenge.Category == Definition.Category then
			return 1
		elseif Challenge.Kind == "RestoreRarity" and RarityConfig.GetRank(Definition.Rarity) >= RarityConfig.GetRank(Challenge.Rarity) then
			return 1
		end
		return nil
	end)
end

function ScheduleService.Init()
	NetworkService.Handle("ClaimDaily", ScheduleService.ClaimDaily)
	NetworkService.Handle("ClaimChallenge", ScheduleService.ClaimChallenge)

	GameEvents.ItemCompleted:Connect(OnItemCompleted)
	GameEvents.ItemSold:Connect(function(Player, _Item, Price)
		AddProgress(Player, function(Challenge)
			return if Challenge.Kind == "EarnMoney" then Price else nil
		end)
	end)
	GameEvents.ItemRolled:Connect(function(Player)
		AddProgress(Player, function(Challenge)
			return if Challenge.Kind == "RollCount" then 1 else nil
		end)
	end)
	GameEvents.TraitRevealed:Connect(function(Player)
		AddProgress(Player, function(Challenge)
			return if Challenge.Kind == "DiscoverVariant" then 1 else nil
		end)
	end)
	GameEvents.ProfileLoaded:Connect(function(_Player, Profile)
		EnsureCurrentWeek(Profile)
	end)

	StateReplicator.AddContributor("Schedule", function()
		local Now = os.time()
		local Featured, FeaturedEndsAt = Schedule.ActiveFeatured(Now)
		return {
			FeaturedPool = Featured.Pool,
			FeaturedTheme = Featured.Theme,
			FeaturedEndsAt = FeaturedEndsAt,
			NextDailyAt = Schedule.NextDayAt(Now),
			WeekEndsAt = Schedule.NextWeekAt(Now),
			WeeklyChallenges = Schedule.WeeklyChallenges(Schedule.WeekIndex(Now)),
		}
	end)
end

return ScheduleService
