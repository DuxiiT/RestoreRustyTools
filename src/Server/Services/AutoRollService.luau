-- Optional auto-roll. Each roll goes through the normal RollService transaction, so cost,
-- capacity and funds are checked every time and it stops on the first failure.
-- Scrap filters are opt-in, only touch Common/Uncommon items with no hidden features at all,
-- and every action is logged for the player to review.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local SalvagePools = require(Shared.Config.SalvagePools)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local RollService = require(script.Parent.RollService)
local SalesService = require(script.Parent.SalesService)

local AutoRollService = {}

local Sessions = {}

local function GetSession(Player: Player)
	local Session = Sessions[Player]
	if not Session then
		Session = { Enabled = false, Token = 0, Log = {} }
		Sessions[Player] = Session
	end
	return Session
end

local function AddLog(Session, Entry)
	table.insert(Session.Log, 1, Entry)
	if #Session.Log > EconomyConfig.AutoRollLogLength then
		table.remove(Session.Log)
	end
end

local function Stop(Player: Player, Reason: string?)
	local Session = Sessions[Player]
	if not Session or not Session.Enabled then
		return
	end
	Session.Enabled = false
	Session.Token += 1
	if Reason then
		NetworkService.Notify(Player, `Auto-roll stopped: {Reason}`, "Warning")
	end
	StateReplicator.MarkDirty(Player)
end

local function ShouldScrap(Session, Item): boolean
	if Item.Favorite or #Item.Traits > 0 then
		return false
	end
	local Rarity = ItemCatalog.Get(Item.TypeId).Rarity
	return (Rarity == "Common" and Session.ScrapCommons) or (Rarity == "Uncommon" and Session.ScrapUncommons)
end

local function RunLoop(Player: Player, Session, Token: number)
	while Session.Enabled and Session.Token == Token and PlayerDataService.IsLoaded(Player) do
		local Response = RollService.Roll(Player, Session.PoolId, { SkipProximity = true, Source = "AutoRoll" })
		if not Response.Success then
			Stop(Player, Response.Message)
			return
		end
		local Profile = PlayerDataService.Get(Player)
		local Item = Profile and Profile.Items[Response.Data.Item.Uid]
		if Item and ShouldScrap(Session, Item) then
			local Sale = SalesService.Sell(Player, Item.Uid, "Scrap", { SkipProximity = true })
			local Price = if Sale.Success then Sale.Data.Price else 0
			AddLog(Session, { TypeId = Item.TypeId, Action = if Sale.Success then "Scrapped" else "Kept", Price = Price })
		elseif Item then
			AddLog(Session, { TypeId = Item.TypeId, Action = "Kept", Price = 0 })
		end
		StateReplicator.MarkDirty(Player)
		task.wait(EconomyConfig.AutoRollIntervalSeconds)
	end
end

function AutoRollService.Configure(Player: Player, Enabled: boolean, PoolId: string?, ScrapCommons: boolean, ScrapUncommons: boolean)
	if not Enabled then
		Stop(Player, nil)
		return Result.Ok({ Enabled = false })
	end
	local Derived = PlayerDataService.GetDerived(Player)
	if not Derived.Features.AutoRoll then
		return Result.Fail("Unlock Auto Roller on the skill board first.", "Locked")
	end
	local Pool = PoolId and SalvagePools[PoolId]
	if not Pool or not Pool.Direct or Pool.CooldownSeconds or Pool.Cost <= 0 then
		return Result.Fail("Choose a paid crate for auto-roll.")
	end
	if Pool.UnlockNode and not Derived.Pools[PoolId] then
		return Result.Fail("That crate is locked.", "Locked")
	end

	local Session = GetSession(Player)
	Session.Enabled = true
	Session.Token += 1
	Session.PoolId = PoolId
	Session.ScrapCommons = ScrapCommons
	Session.ScrapUncommons = ScrapUncommons
	task.spawn(RunLoop, Player, Session, Session.Token)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ Enabled = true, PoolId = PoolId, Cost = Pool.Cost })
end

function AutoRollService.Init()
	NetworkService.Handle("SetAutoRoll", AutoRollService.Configure)
	GameEvents.ProfileReleasing:Connect(function(Player)
		Stop(Player, nil)
		Sessions[Player] = nil
	end)
	GameEvents.SkillTreeReset:Connect(function(Player)
		local Derived = PlayerDataService.GetDerived(Player)
		if Derived and not Derived.Features.AutoRoll then
			Stop(Player, "Auto Roller is no longer unlocked.")
		end
	end)
	StateReplicator.AddContributor("AutoRoll", function(Player)
		local Session = Sessions[Player]
		if not Session then
			return { Enabled = false, Log = {} }
		end
		return {
			Enabled = Session.Enabled,
			PoolId = Session.PoolId,
			ScrapCommons = Session.ScrapCommons,
			ScrapUncommons = Session.ScrapUncommons,
			Log = Session.Log,
		}
	end)
end

return AutoRollService
