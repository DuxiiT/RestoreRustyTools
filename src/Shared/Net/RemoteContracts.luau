-- Single source of truth for every remote. Kind:
--   Request  client -> server RemoteFunction returning a Result
--   Stream   client -> server RemoteEvent (high frequency, no response)
--   Push     server -> client RemoteEvent
-- Rate is a per-player token bucket: Count requests per Window seconds.
local Validators = require(script.Parent.Validators)
local SettingKeys = { "SoundEffects", "ReducedEffects", "SkipRollAnimation", "ToolVolume" }

local V = Validators

return {
	RollRequest = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 4, Window = 2 } },
	StartJob = { Kind = "Request", Args = { V.ItemUid() }, Rate = { Count = 4, Window = 2 } },
	ShelveJob = { Kind = "Request", Args = {}, Rate = { Count = 3, Window = 2 } },
	EquipTool = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 8, Window = 2 } },
	ResolveResult = { Kind = "Request", Args = { V.ItemUid(), V.OneOf({ "Sell", "Store", "Display" }) }, Rate = { Count = 4, Window = 2 } },
	SellItem = { Kind = "Request", Args = { V.ItemUid(), V.OneOf({ "Full", "Scrap" }) }, Rate = { Count = 6, Window = 2 } },
	BulkSell = { Kind = "Request", Args = {}, Rate = { Count = 1, Window = 3 } },
	SetFavorite = { Kind = "Request", Args = { V.ItemUid(), V.Boolean() }, Rate = { Count = 10, Window = 2 } },
	PurchaseNode = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 4, Window = 2 } },
	PreviewSkillReset = { Kind = "Request", Args = {}, Rate = { Count = 3, Window = 2 } },
	ResetSkillTree = { Kind = "Request", Args = { V.Boolean() }, Rate = { Count = 1, Window = 5 } },
	SkipTutorial = { Kind = "Request", Args = {}, Rate = { Count = 2, Window = 5 } },
	ClaimSetReward = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 3, Window = 2 } },
	SellSet = { Kind = "Request", Args = { V.Identifier(), V.Boolean() }, Rate = { Count = 2, Window = 3 } },
	SubmitCommission = { Kind = "Request", Args = { V.Identifier(), V.ItemUid() }, Rate = { Count = 3, Window = 2 } },
	DeclineCommission = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 2, Window = 2 } },
	ClaimDaily = { Kind = "Request", Args = {}, Rate = { Count = 2, Window = 3 } },
	ClaimChallenge = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 3, Window = 2 } },
	PlaceDisplay = { Kind = "Request", Args = { V.ItemUid(), V.Optional(V.Identifier()) }, Rate = { Count = 4, Window = 2 } },
	RemoveDisplay = { Kind = "Request", Args = { V.Identifier() }, Rate = { Count = 4, Window = 2 } },
	BuyCosmetic = { Kind = "Request", Args = { V.Identifier(), V.Identifier() }, Rate = { Count = 3, Window = 2 } },
	ApplyCosmetic = { Kind = "Request", Args = { V.Identifier(), V.Identifier() }, Rate = { Count = 4, Window = 2 } },
	SetAutoRoll = {
		Kind = "Request",
		Args = { V.Boolean(), V.Optional(V.Identifier()), V.Boolean(), V.Boolean() },
		Rate = { Count = 3, Window = 2 },
	},
	UpdateSetting = {
		Kind = "Request",
		Args = { V.OneOf(SettingKeys), V.AnyOf(V.Boolean(), V.Number(0, 1)) },
		Rate = { Count = 10, Window = 2 },
	},

	-- Clients send contact batches about every 0.08s; the bucket allows bursts after hitches.
	SubmitStrokes = {
		Kind = "Stream",
		Args = { V.Integer(0, 2 ^ 31), V.Identifier(), V.Vector3Array(12, 64) },
		Rate = { Count = 30, Window = 1 },
	},

	StateSnapshot = { Kind = "Push" },
	JobUpdate = { Kind = "Push" },
	Notify = { Kind = "Push" },
}
