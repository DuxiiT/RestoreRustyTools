-- Upgrade purchases and the safe reset. Only purchased ranks and recorded spend are stored;
-- effects are always derived, so they apply immediately and never stack twice.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SkillTree = require(Shared.Config.SkillTree)
local Format = require(Shared.Util.Format)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local StationService = require(script.Parent.StationService)
local WorkshopService = require(script.Parent.WorkshopService)
local DisplayService = require(script.Parent.DisplayService)

local SkillTreeService = {}

local function CanReachBoard(Player: Player): boolean
	return WorkshopService.IsNearOwnWorkshop(Player) or StationService.IsNear(Player, StationService.Tags.SkillBoard)
end

function SkillTreeService.Purchase(Player: Player, NodeId: string)
	if not CanReachBoard(Player) then
		return Result.Fail("Use the skill board in your workshop or the courtyard.", "TooFar")
	end
	local Profile = PlayerDataService.Get(Player)
	local Response = ProfileTransactions.PurchaseNode(Profile, NodeId)
	if not Response.Success then
		return Response
	end
	GameEvents.NodePurchased:Fire(Player, NodeId, Response.Data.Rank)
	StateReplicator.MarkDirty(Player)
	NetworkService.Notify(Player, `{SkillTree[NodeId].Name} upgraded!`, "Upgrade")
	return Response
end

function SkillTreeService.PreviewReset(Player: Player)
	local Profile = PlayerDataService.Get(Player)
	return Result.Ok(ProfileTransactions.PreviewReset(Profile, DisplayService.CountDisplays(Profile)))
end

function SkillTreeService.Reset(Player: Player, Confirmed: boolean)
	if not Confirmed then
		return Result.Fail("Review and confirm the reset first.", "NeedsConfirmation")
	end
	if not CanReachBoard(Player) then
		return Result.Fail("Use the skill board in your workshop or the courtyard.", "TooFar")
	end
	local Profile = PlayerDataService.Get(Player)
	local Response = ProfileTransactions.ApplyReset(Profile, DisplayService.CountDisplays(Profile))
	if not Response.Success then
		return Response
	end
	GameEvents.SkillTreeReset:Fire(Player)
	StateReplicator.MarkDirty(Player)
	NetworkService.Notify(Player, `Skill tree reset. Refunded {Format.Money(Response.Data.Net)}.`, "Upgrade")
	return Response
end

function SkillTreeService.Init()
	NetworkService.Handle("PurchaseNode", SkillTreeService.Purchase)
	NetworkService.Handle("PreviewSkillReset", SkillTreeService.PreviewReset)
	NetworkService.Handle("ResetSkillTree", SkillTreeService.Reset)
end

return SkillTreeService
