local Config = script.Parent.Parent.Config
local StageDefinitions = require(Config.StageDefinitions)
local ToolDefinitions = require(Config.ToolDefinitions)

local EffortEstimator = {}

function EffortEstimator.StageSeconds(Definition, StageId: string): number
	local TotalWeight = 0
	for _, Id in Definition.Stages do
		TotalWeight += StageDefinitions[Id].EffortWeight
	end
	return Definition.TargetSeconds * StageDefinitions[StageId].EffortWeight / TotalWeight
end

local function ToolRate(Tool, StageId: string, Stats): number
	return Tool.Power * (Tool.StageMultipliers[StageId] or 0) * (Stats[Tool.StrengthStat] or 1)
end

function EffortEstimator.BestTool(StageId: string, OwnedTools, Stats)
	local BestId, BestRate = nil, 0
	for ToolId in OwnedTools do
		local Tool = ToolDefinitions[ToolId]
		if Tool then
			local Rate = ToolRate(Tool, StageId, Stats)
			if Rate > BestRate then
				BestId, BestRate = ToolId, Rate
			end
		end
	end
	return BestId, BestRate
end

-- Approximate seconds to finish, scaled by the player's best owned tool per stage.
function EffortEstimator.EstimateSeconds(Definition, OwnedTools, Stats): number
	local Total = 0
	for _, StageId in Definition.Stages do
		local Reference = ToolDefinitions[StageDefinitions[StageId].ReferenceTool]
		local ReferenceRate = Reference.Power * Reference.StageMultipliers[StageId]
		local _, BestRate = EffortEstimator.BestTool(StageId, OwnedTools, Stats)
		local Seconds = EffortEstimator.StageSeconds(Definition, StageId)
		Total += if BestRate > 0 then Seconds * ReferenceRate / BestRate else Seconds * 10
	end
	return math.ceil(Total)
end

return EffortEstimator
