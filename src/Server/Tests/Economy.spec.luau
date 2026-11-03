local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local SalvagePools = require(Shared.Config.SalvagePools)
local StatCalculator = require(Shared.Logic.StatCalculator)
local PriceCalculator = require(Shared.Logic.PriceCalculator)

local Server = script.Parent.Parent
local ProfileSchema = require(Server.Logic.ProfileSchema)
local ProfileTransactions = require(Server.Logic.ProfileTransactions)
local ItemFactory = require(Server.Logic.ItemFactory)

local UserId = 1001

local function NewProfile()
	return ProfileSchema.CreateDefault()
end

local function RollContext(Profile, Overrides)
	local Context = {
		Derived = StatCalculator.Compute(Profile.SkillNodes),
		IsAvailable = function()
			return true
		end,
		Random = Random.new(99),
		Now = 1_000_000,
		UserId = UserId,
	}
	for Key, Value in Overrides or {} do
		Context[Key] = Value
	end
	return Context
end

local function CountItems(Profile)
	local Count = 0
	for _ in Profile.Items do
		Count += 1
	end
	return Count
end

local function AddFinishedItem(Profile, TypeId)
	local Stats = StatCalculator.Compute(Profile.SkillNodes).Stats
	local Item = ItemFactory.Create(Profile, UserId, TypeId, Random.new(1), Stats, { Traits = {}, Condition = 50 })
	Item.Completed = true
	return Item
end

return function(Test, Expect)
	Test("insufficient funds charges nothing and grants nothing", function()
		local Profile = NewProfile()
		Profile.Money = SalvagePools.HardwareCrate.Cost - 1
		local Response = ProfileTransactions.Roll(Profile, "HardwareCrate", RollContext(Profile))
		Expect.Equal(Response.Success, false, "roll success")
		Expect.Equal(Response.Code, "InsufficientFunds", "code")
		Expect.Equal(Profile.Money, SalvagePools.HardwareCrate.Cost - 1, "money")
		Expect.Equal(CountItems(Profile), 0, "items")
	end)

	Test("full storage blocks rolling without charging", function()
		local Profile = NewProfile()
		Profile.Money = 1000
		local Capacity = StatCalculator.Compute(Profile.SkillNodes).Stats.InventoryCapacity
		for _ = 1, Capacity do
			AddFinishedItem(Profile, "Bolt")
		end
		local Response = ProfileTransactions.Roll(Profile, "HardwareCrate", RollContext(Profile))
		Expect.Equal(Response.Code, "StorageFull", "code")
		Expect.Equal(Profile.Money, 1000, "money")
		Expect.Equal(CountItems(Profile), Capacity, "items")
	end)

	Test("successful roll charges once and grants exactly one item", function()
		local Profile = NewProfile()
		Profile.Money = 100
		local Response = ProfileTransactions.Roll(Profile, "HardwareCrate", RollContext(Profile))
		Expect.True(Response.Success, "roll success")
		Expect.Equal(Profile.Money, 100 - SalvagePools.HardwareCrate.Cost, "money")
		Expect.Equal(CountItems(Profile), 1, "items")
	end)

	Test("free bin cooldown prevents back-to-back free rolls", function()
		local Profile = NewProfile()
		local Context = RollContext(Profile)
		Expect.True(ProfileTransactions.Roll(Profile, "ScrapBin", Context).Success, "first roll")
		local Second = ProfileTransactions.Roll(Profile, "ScrapBin", Context)
		Expect.Equal(Second.Code, "Cooldown", "second roll code")
		Expect.Equal(CountItems(Profile), 1, "items")
	end)

	Test("zero money player can still roll the free bin", function()
		local Profile = NewProfile()
		Profile.Money = 0
		Expect.True(ProfileTransactions.Roll(Profile, "ScrapBin", RollContext(Profile)).Success, "free roll")
	end)

	Test("locked and indirect pools cannot be rolled", function()
		local Profile = NewProfile()
		Profile.Money = 100000
		Expect.Equal(ProfileTransactions.Roll(Profile, "CollectorCrate", RollContext(Profile)).Code, "Locked", "locked pool")
		Expect.Equal(ProfileTransactions.Roll(Profile, "DailyDelivery", RollContext(Profile)).Success, false, "indirect pool")
		Expect.Equal(ProfileTransactions.Roll(Profile, "NotAPool", RollContext(Profile)).Success, false, "unknown pool")
	end)

	Test("an item sells once and pays once", function()
		local Profile = NewProfile()
		local Item = AddFinishedItem(Profile, "Bolt")
		local Stats = StatCalculator.Compute(Profile.SkillNodes).Stats
		local Expected = PriceCalculator.FullValue(Item, Stats)
		local Before = Profile.Money
		Expect.True(ProfileTransactions.SellItem(Profile, Item.Uid, "Full", Stats).Success, "first sale")
		Expect.Equal(ProfileTransactions.SellItem(Profile, Item.Uid, "Full", Stats).Code, "Missing", "second sale")
		Expect.Equal(Profile.Money, Before + Expected, "money")
	end)

	Test("favorites, bench items and unfinished items are protected", function()
		local Profile = NewProfile()
		local Stats = StatCalculator.Compute(Profile.SkillNodes).Stats
		local Favorite = AddFinishedItem(Profile, "Bolt")
		Favorite.Favorite = true
		Expect.Equal(ProfileTransactions.SellItem(Profile, Favorite.Uid, "Scrap", Stats).Code, "Favorite", "favorite")

		local OnBench = AddFinishedItem(Profile, "Nut")
		OnBench.State = "Bench"
		Expect.Equal(ProfileTransactions.SellItem(Profile, OnBench.Uid, "Scrap", Stats).Code, "OnBench", "bench")

		local Unfinished = AddFinishedItem(Profile, "Washer")
		Unfinished.Completed = false
		Expect.Equal(ProfileTransactions.SellItem(Profile, Unfinished.Uid, "Full", Stats).Code, "Unfinished", "unfinished full")
		local Scrap = ProfileTransactions.SellItem(Profile, Unfinished.Uid, "Scrap", Stats)
		Expect.True(Scrap.Success, "unfinished scrap allowed")
	end)

	Test("node purchase checks prerequisites, funds and max rank", function()
		local Profile = NewProfile()
		Profile.Money = 100000
		Expect.Equal(ProfileTransactions.PurchaseNode(Profile, "WideBrushHead").Code, "Locked", "missing prerequisite")
		Expect.True(ProfileTransactions.PurchaseNode(Profile, "StifferBristles").Success, "rank 1")
		Expect.True(ProfileTransactions.PurchaseNode(Profile, "StifferBristles").Success, "rank 2")
		Expect.True(ProfileTransactions.PurchaseNode(Profile, "StifferBristles").Success, "rank 3")
		Expect.Equal(ProfileTransactions.PurchaseNode(Profile, "StifferBristles").Code, "MaxRank", "max rank")
		Profile.Money = 0
		Expect.Equal(ProfileTransactions.PurchaseNode(Profile, "WideBrushHead").Code, "InsufficientFunds", "funds")
	end)

	Test("effects derive from ranks and never double apply", function()
		local Derived = StatCalculator.Compute({ FirstWorkshop = 1, StifferBristles = 2 })
		Expect.Near(Derived.Stats.CleaningStrength, 1.3, 1e-9, "cleaning strength")
		local Overranked = StatCalculator.Compute({ FirstWorkshop = 1, StifferBristles = 99 })
		Expect.Near(Overranked.Stats.CleaningStrength, 1.45, 1e-9, "rank clamped to max")
	end)

	Test("skill reset refunds at most what was spent and cannot repeat", function()
		local Profile = NewProfile()
		Profile.Money = 1000
		ProfileTransactions.PurchaseNode(Profile, "StifferBristles")
		ProfileTransactions.PurchaseNode(Profile, "Haggling")
		local Spent = 1000 - Profile.Money
		local MoneyBefore = Profile.Money
		local Response = ProfileTransactions.ApplyReset(Profile, 0)
		Expect.True(Response.Success, "reset")
		Expect.True(Profile.Money - MoneyBefore <= Spent, "refund within spend")
		Expect.Equal(Profile.SkillNodes.StifferBristles, nil, "node cleared")
		Expect.Equal(Profile.SkillNodes.FirstWorkshop, 1, "root kept")
		Expect.Equal(ProfileTransactions.ApplyReset(Profile, 0).Success, false, "second reset")
	end)
end
