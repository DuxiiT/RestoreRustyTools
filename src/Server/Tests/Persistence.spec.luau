local Server = script.Parent.Parent
local ProfileSchema = require(Server.Logic.ProfileSchema)
local RateLimiter = require(Server.Logic.RateLimiter)

return function(Test, Expect)
	Test("prepare fills missing fields without overwriting progress", function()
		local Saved = { SchemaVersion = 1, Money = 4321, Items = {}, SkillNodes = { FirstWorkshop = 1, Haggling = 2 } }
		local Profile = ProfileSchema.Prepare(Saved)
		Expect.Equal(Profile.Money, 4321, "money kept")
		Expect.Equal(Profile.SkillNodes.Haggling, 2, "nodes kept")
		Expect.True(typeof(Profile.Settings) == "table", "settings filled")
		Expect.True(typeof(Profile.Workshop.Displays) == "table", "nested defaults filled")
	end)

	Test("data from a newer schema is refused rather than downgraded", function()
		local Profile, Reason = ProfileSchema.Prepare({ SchemaVersion = ProfileSchema.CurrentVersion + 1 })
		Expect.Equal(Profile, nil, "profile")
		Expect.True(typeof(Reason) == "string", "reason")
	end)

	Test("corrupt data is refused", function()
		Expect.Equal(ProfileSchema.Prepare("garbage"), nil, "string data")
	end)

	Test("each item ends up in exactly one valid location", function()
		local Saved = ProfileSchema.CreateDefault()
		Saved.Items["1-1"] = { Uid = "1-1", TypeId = "Bolt", State = "Bench", Traits = {}, RevealedTraits = {} }
		Saved.Items["1-2"] = { Uid = "1-2", TypeId = "Nut", State = "Bench", Traits = {}, RevealedTraits = {} }
		Saved.Items["1-3"] = { Uid = "1-3", TypeId = "Key", State = "Display", SlotId = "Slot1", Completed = true }
		Saved.Items["1-4"] = { Uid = "1-4", TypeId = "Gear", State = "Nowhere" }
		Saved.ActiveItemUid = "1-1"
		local Profile = ProfileSchema.Prepare(Saved)
		Expect.Equal(Profile.Items["1-1"].State, "Bench", "active bench item")
		Expect.Equal(Profile.Items["1-2"].State, "Storage", "second bench item moved")
		Expect.Equal(Profile.Items["1-3"].State, "Storage", "display without slot record")
		Expect.Equal(Profile.Items["1-4"].State, "Storage", "unknown state")
	end)

	Test("rate limiter allows bursts up to the limit and refills", function()
		local Now = 0
		local Limiter = RateLimiter.New(function()
			return Now
		end)
		local Rate = { Count = 3, Window = 3 }
		Expect.True(Limiter:Allow("P", "R", Rate), "1")
		Expect.True(Limiter:Allow("P", "R", Rate), "2")
		Expect.True(Limiter:Allow("P", "R", Rate), "3")
		Expect.Equal(Limiter:Allow("P", "R", Rate), false, "4 blocked")
		Now = 1
		Expect.True(Limiter:Allow("P", "R", Rate), "refilled one")
		Expect.Equal(Limiter:Allow("P", "R", Rate), false, "then blocked")
	end)
end
