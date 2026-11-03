-- Shared rules so the planning board explains exactly what the server enforces.
local Config = script.Parent.Parent.Config
local SkillTree = require(Config.SkillTree)
local ToolDefinitions = require(Config.ToolDefinitions)
local SalvagePools = require(Config.SalvagePools)
local StageDefinitions = require(Config.StageDefinitions)
local StatCalculator = require(script.Parent.StatCalculator)
local Format = require(script.Parent.Parent.Util.Format)

local SkillTreeRules = {}

local StatLabels = {
	CleaningStrength = "Cleaning strength",
	ToolRadius = "Tool width",
	PolishEfficiency = "Polishing speed",
	TreatmentPotency = "Treatment speed",
	DetailPrecision = "Detail speed",
	RarityLuck = "Uncommon-and-better crate weights",
	VariantChance = "Hidden feature chance",
	SaleValue = "Sale value",
	InventorySlots = "Storage slots",
	DisplaySlots = "Display slots",
	PityReduction = "Pity threshold",
	CompletionLeniency = "Finish tolerance",
	CommissionBonus = "Commission rewards",
}

local CountStats = { InventorySlots = true, DisplaySlots = true }

function SkillTreeRules.GetRank(OwnedNodes, NodeId: string): number
	return OwnedNodes[NodeId] or 0
end

function SkillTreeRules.MissingPrerequisites(OwnedNodes, NodeId: string)
	local Missing = {}
	for _, RequiredId in SkillTree[NodeId].Requires do
		if SkillTreeRules.GetRank(OwnedNodes, RequiredId) < 1 then
			table.insert(Missing, RequiredId)
		end
	end
	return Missing
end

-- Returns "Owned" (max rank), "Available", or "Locked".
function SkillTreeRules.GetState(OwnedNodes, NodeId: string): string
	local Node = SkillTree[NodeId]
	if SkillTreeRules.GetRank(OwnedNodes, NodeId) >= Node.MaxRank then
		return "Owned"
	end
	if #SkillTreeRules.MissingPrerequisites(OwnedNodes, NodeId) > 0 then
		return "Locked"
	end
	return "Available"
end

function SkillTreeRules.NextPrice(OwnedNodes, NodeId: string): number?
	local Node = SkillTree[NodeId]
	return Node.Prices[SkillTreeRules.GetRank(OwnedNodes, NodeId) + 1]
end

function SkillTreeRules.DescribeEffect(Effect, Rank: number): string
	if Effect.Type == "Stat" then
		local Amount = Effect.PerRank * Rank
		local Label = StatLabels[Effect.Stat] or Effect.Stat
		if Effect.Stat == "PityReduction" then
			return `{Label} -{Amount} rolls`
		elseif Effect.Stat == "CompletionLeniency" then
			return `{Label} +{Format.Percent(Amount, 0)}`
		elseif CountStats[Effect.Stat] then
			return `{Label} +{Amount}`
		end
		return `{Label} +{Format.Percent(Amount, 0)}`
	elseif Effect.Type == "CategoryBonus" then
		return `{Effect.Category} sale value +{Format.Percent(Effect.PerRank * Rank, 0)}`
	elseif Effect.Type == "UnlockTool" then
		return `Unlocks {ToolDefinitions[Effect.Tool].DisplayName}`
	elseif Effect.Type == "UnlockPool" then
		return `Unlocks {SalvagePools[Effect.Pool].DisplayName}`
	elseif Effect.Type == "UnlockFeature" then
		return `Unlocks {Effect.Feature}`
	end
	return "Unknown effect"
end

function SkillTreeRules.DescribeRank(NodeId: string, Rank: number): string
	if Rank <= 0 then
		return "None"
	end
	local Lines = {}
	for _, Effect in SkillTree[NodeId].Effects do
		table.insert(Lines, SkillTreeRules.DescribeEffect(Effect, Rank))
	end
	return if #Lines > 0 then table.concat(Lines, "\n") else SkillTree[NodeId].Description
end

-- Structural validation run at server start and by tests. Returns a list of problems.
function SkillTreeRules.Validate()
	local Problems = {}
	local RootId

	for NodeId, Node in SkillTree do
		if Node.AutoOwned then
			if RootId then
				table.insert(Problems, "more than one AutoOwned root node")
			end
			RootId = NodeId
		end
		if #Node.Prices == 0 then
			table.insert(Problems, `{NodeId} has no ranks`)
		end
		for _, RequiredId in Node.Requires do
			if not SkillTree[RequiredId] then
				table.insert(Problems, `{NodeId} requires unknown node {RequiredId}`)
			end
		end
		for _, Effect in Node.Effects do
			if Effect.Type == "Stat" and StatCalculator.BaseStats[Effect.Stat] == nil then
				table.insert(Problems, `{NodeId} modifies unknown stat {Effect.Stat}`)
			elseif Effect.Type == "UnlockTool" and not ToolDefinitions[Effect.Tool] then
				table.insert(Problems, `{NodeId} unlocks unknown tool {Effect.Tool}`)
			elseif Effect.Type == "UnlockPool" and not SalvagePools[Effect.Pool] then
				table.insert(Problems, `{NodeId} unlocks unknown pool {Effect.Pool}`)
			end
		end
		if #Node.Effects == 0 and not Node.AutoOwned then
			table.insert(Problems, `{NodeId} has no effect`)
		end
	end

	if not RootId then
		table.insert(Problems, "no AutoOwned root node")
		return Problems
	end

	-- Cycle detection by depth-first search over prerequisite edges.
	local VisitState = {}
	local function Visit(NodeId)
		if VisitState[NodeId] == "Done" then
			return
		end
		if VisitState[NodeId] == "Active" then
			table.insert(Problems, `prerequisite cycle through {NodeId}`)
			return
		end
		VisitState[NodeId] = "Active"
		for _, RequiredId in SkillTree[NodeId].Requires do
			if SkillTree[RequiredId] then
				Visit(RequiredId)
			end
		end
		VisitState[NodeId] = "Done"
	end
	for NodeId in SkillTree do
		Visit(NodeId)
	end

	-- Reachability: repeatedly unlock any node whose prerequisites are all unlocked.
	local Reachable = { [RootId] = true }
	local Changed = true
	while Changed do
		Changed = false
		for NodeId, Node in SkillTree do
			if not Reachable[NodeId] then
				local AllMet = true
				for _, RequiredId in Node.Requires do
					if not Reachable[RequiredId] then
						AllMet = false
						break
					end
				end
				if AllMet then
					Reachable[NodeId] = true
					Changed = true
				end
			end
		end
	end
	for NodeId in SkillTree do
		if not Reachable[NodeId] then
			table.insert(Problems, `{NodeId} is unreachable from {RootId}`)
		end
	end

	local Positions = {}
	for NodeId, Node in SkillTree do
		local Key = `{Node.Position.X},{Node.Position.Y}`
		if Positions[Key] then
			table.insert(Problems, `{NodeId} shares a board position with {Positions[Key]}`)
		end
		Positions[Key] = NodeId
	end

	-- Every stage must stay workable with base tools alone so no reset can strand a job.
	for StageId in StageDefinitions do
		local HasBaseTool = false
		for _, Tool in ToolDefinitions do
			if Tool.Base and (Tool.StageMultipliers[StageId] or 0) > 0 then
				HasBaseTool = true
				break
			end
		end
		if not HasBaseTool then
			table.insert(Problems, `stage {StageId} has no base tool fallback`)
		end
	end

	return Problems
end

return SkillTreeRules
