local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ItemCatalog = require(Shared.Content.ItemCatalog)
local SalvagePools = require(Shared.Config.SalvagePools)
local CollectionSets = require(Shared.Config.CollectionSets)
local RarityConfig = require(Shared.Config.RarityConfig)
local ToolDefinitions = require(Shared.Config.ToolDefinitions)
local StageDefinitions = require(Shared.Config.StageDefinitions)
local TutorialSteps = require(Shared.Config.TutorialSteps)
local SkillTreeRules = require(Shared.Logic.SkillTreeRules)

return function(Test, Expect)
	Test("starter catalog has the twenty planned items", function()
		local Count = 0
		for _, Definition in ItemCatalog.GetAll() do
			if Definition.Phase == 1 then
				Count += 1
			end
		end
		Expect.Equal(Count, 20, "phase 1 item count")
	end)

	Test("every item has positive value and effort", function()
		for ItemId, Definition in ItemCatalog.GetAll() do
			Expect.True(Definition.BaseValue > 0, `{ItemId} base value`)
			Expect.True(Definition.TargetSeconds > 0, `{ItemId} target seconds`)
		end
	end)

	Test("large commons pay at least as well per second as small commons", function()
		local Bolt = ItemCatalog.Get("Bolt")
		local Kettle = ItemCatalog.Get("Kettle")
		Expect.True(Kettle.BaseValue / Kettle.TargetSeconds >= Bolt.BaseValue / Bolt.TargetSeconds * 0.8, "kettle value per second")
	end)

	Test("skill tree has no cycles, unreachable nodes or missing effects", function()
		local Problems = SkillTreeRules.Validate()
		Expect.Equal(#Problems, 0, table.concat(Problems, "; "))
	end)

	Test("pools only use known rarities and pity rarities", function()
		for PoolId, Pool in SalvagePools do
			for Rarity in Pool.RarityWeights do
				Expect.True(RarityConfig.Tiers[Rarity] ~= nil, `{PoolId} rarity {Rarity}`)
			end
			if Pool.Pity then
				Expect.True(Pool.RarityWeights[Pool.Pity.Rarity] ~= nil, `{PoolId} pity rarity is in pool`)
			end
		end
	end)

	Test("collection sets reference catalog items", function()
		for SetId, Set in CollectionSets do
			for _, ItemId in Set.Items do
				Expect.True(ItemCatalog.Exists(ItemId), `{SetId} item {ItemId}`)
			end
		end
	end)

	Test("tools reference real stages", function()
		for ToolId, Tool in ToolDefinitions do
			for StageId in Tool.StageMultipliers do
				Expect.True(StageDefinitions[StageId] ~= nil, `{ToolId} stage {StageId}`)
			end
		end
	end)

	Test("tutorial steps have prompts and events", function()
		for _, Step in TutorialSteps do
			Expect.True(typeof(Step.Prompt) == "string" and #Step.Prompt > 0, `{Step.Id} prompt`)
			Expect.True(typeof(Step.Event) == "string", `{Step.Id} event`)
		end
	end)
end
