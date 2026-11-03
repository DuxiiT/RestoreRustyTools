-- Server-resolved rolls. The outcome, hidden traits, charge and grant all happen inside one
-- non-yielding transaction; the client only ever presents what this returns.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SalvagePools = require(Shared.Config.SalvagePools)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local EffortEstimator = require(Shared.Logic.EffortEstimator)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local ContentRegistry = require(script.Parent.ContentRegistry)
local StationService = require(script.Parent.StationService)

local RollService = {}

local RandomSource = Random.new()

-- Options: Free, AllowIndirect, SkipProximity, Source.
function RollService.Roll(Player: Player, PoolId: string, Options)
	Options = Options or {}
	local Profile = PlayerDataService.Get(Player)
	local Pool = SalvagePools[PoolId]
	if Pool and not Options.SkipProximity and not StationService.IsNear(Player, StationService.Tags.SalvageDepot) then
		return Result.Fail("Visit the salvage depot to roll.", "TooFar")
	end

	local Derived = PlayerDataService.GetDerived(Player)
	local Response = ProfileTransactions.Roll(Profile, PoolId, {
		Derived = Derived,
		IsAvailable = ContentRegistry.IsAvailable,
		Random = RandomSource,
		Now = os.time(),
		UserId = Player.UserId,
		Free = Options.Free,
		AllowIndirect = Options.AllowIndirect,
		Source = Options.Source,
	})
	if not Response.Success then
		return Response
	end

	local Item = Response.Data.Item
	GameEvents.ItemRolled:Fire(Player, Item, PoolId)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({
		Item = StateReplicator.BuildItemView(Item, Derived.Stats),
		PoolId = PoolId,
		Cost = Response.Data.Cost,
		PityTriggered = Response.Data.PityTriggered,
		EstimatedSeconds = EffortEstimator.EstimateSeconds(ItemCatalog.Get(Item.TypeId), Derived.Tools, Derived.Stats),
	})
end

function RollService.Init()
	NetworkService.Handle("RollRequest", function(Player, PoolId)
		return RollService.Roll(Player, PoolId)
	end)
end

return RollService
