-- Builds a temporary grid of cell parts (test fixture only, never parented to the world).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ToolDefinitions = require(Shared.Config.ToolDefinitions)
local RestorationMath = require(Shared.Logic.RestorationMath)
local CoverageCodec = require(Shared.Logic.CoverageCodec)
local StatCalculator = require(Shared.Logic.StatCalculator)

local BaseStats = StatCalculator.Compute({ FirstWorkshop = 1 }).Stats
local GridSize = 8
local CellSize = 0.5

local function BuildStage(TargetSeconds: number)
	local Folder = Instance.new("Folder")
	for X = 1, GridSize do
		for Z = 1, GridSize do
			local Part = Instance.new("Part")
			Part.Name = string.format("Cell_%02d_%02d", X, Z)
			Part.Size = Vector3.new(CellSize, 0.05, CellSize)
			Part.CFrame = CFrame.new((X - 0.5) * CellSize, 0, (Z - 0.5) * CellSize)
			Part.Parent = Folder
		end
	end
	local _, Geometry = RestorationMath.BuildGeometry(Folder, CFrame.new(), "Surface", "Metal")
	Folder:Destroy()
	local Initial = RestorationMath.GenerateInitialValues(42, 1, #Geometry, 50)
	local Workable = RestorationMath.ComputeWorkable(Geometry, "Brush", ToolDefinitions)
	local Stage = {
		Geometry = Geometry,
		Initial = Initial,
		Values = table.clone(Initial),
		Workable = Workable,
	}
	Stage.Hardness = RestorationMath.CalibrateHardness(Geometry, Workable, Initial, TargetSeconds, ToolDefinitions.WireBrush.Radius)
	return Stage
end

local function TotalCoverage(Stage)
	local Total = 0
	for _, Value in Stage.Values do
		Total += Value
	end
	return Total
end

return function(Test, Expect)
	local Brush = ToolDefinitions.WireBrush

	Test("brushing one corner leaves the far corner untouched", function()
		local Stage = BuildStage(20)
		local FarIndex = #Stage.Values
		local FarBefore = Stage.Values[FarIndex]
		for _ = 1, 30 do
			RestorationMath.ApplyBatch(Stage, "Brush", Brush, BaseStats, { Vector3.new(0.2, 0, 0.2) }, 0.1, {})
		end
		Expect.True(Stage.Values[1] < Stage.Initial[1] * 0.5, "corner cleaned")
		Expect.Equal(Stage.Values[FarIndex], FarBefore, "far cell")
	end)

	Test("brushing empty space removes nothing", function()
		local Stage = BuildStage(20)
		local Before = TotalCoverage(Stage)
		local Accepted = RestorationMath.ApplyBatch(
			Stage,
			"Brush",
			Brush,
			BaseStats,
			{ Vector3.new(50, 10, 50), Vector3.new(0, 5, 0) },
			0.2,
			{}
		)
		Expect.Equal(Accepted, 0, "accepted points")
		Expect.Equal(TotalCoverage(Stage), Before, "coverage")
	end)

	Test("flooding points does not increase total work", function()
		local Single, Flooded = BuildStage(20), BuildStage(20)
		local Point = Vector3.new(2, 0, 2)
		RestorationMath.ApplyBatch(Single, "Brush", Brush, BaseStats, { Point }, 0.1, {})
		local Many = table.create(12, Point)
		RestorationMath.ApplyBatch(Flooded, "Brush", Brush, BaseStats, Many, 0.1, {})
		Expect.Near(TotalCoverage(Flooded), TotalCoverage(Single), 1e-6, "total coverage")
	end)

	Test("delta time is capped so a stalled client cannot dump work", function()
		local Capped, Huge = BuildStage(20), BuildStage(20)
		local Point = Vector3.new(2, 0, 2)
		RestorationMath.ApplyBatch(Capped, "Brush", Brush, BaseStats, { Point }, RestorationMath.MaxStrokeInterval, {})
		RestorationMath.ApplyBatch(Huge, "Brush", Brush, BaseStats, { Point }, 1000, {})
		Expect.Near(TotalCoverage(Huge), TotalCoverage(Capped), 1e-6, "coverage")
	end)

	Test("tools that cannot work a stage do nothing", function()
		local Stage = BuildStage(20)
		local Before = TotalCoverage(Stage)
		RestorationMath.ApplyBatch(Stage, "Brush", ToolDefinitions.PolishCloth, BaseStats, { Vector3.new(2, 0, 2) }, 0.2, {})
		Expect.Equal(TotalCoverage(Stage), Before, "coverage")
	end)

	Test("a sweeping player finishes near the target time", function()
		local Target = 20
		local Stage = BuildStage(Target)
		local Threshold = RestorationMath.CompletionThreshold(BaseStats)
		local Elapsed, Step = 0, 0.08
		local Row, Column = 0, 0
		while RestorationMath.StageScore(Stage) < Threshold and Elapsed < Target * 6 do
			-- Serpentine sweep over the grid at roughly a brush width per stroke.
			local Point = Vector3.new(Column * 0.3 + 0.1, 0, Row * 0.6 + 0.2)
			RestorationMath.ApplyBatch(Stage, "Brush", Brush, BaseStats, { Point }, Step, {})
			Elapsed += Step
			Column += 1
			if Column * 0.3 > GridSize * CellSize then
				Column = 0
				Row = (Row + 1) % math.ceil(GridSize * CellSize / 0.6)
			end
		end
		Expect.True(Elapsed > Target * 0.3 and Elapsed < Target * 4, `finished in {Elapsed}s for target {Target}s`)
	end)

	Test("coverage survives encode and decode", function()
		local Values = { 0, 0.25, 0.5, 0.75, 1 }
		local Decoded = CoverageCodec.Decode(CoverageCodec.Encode(Values), #Values)
		for Index, Value in Values do
			Expect.Near(Decoded[Index], Value, 0.5 / CoverageCodec.Levels + 1e-9, `value {Index}`)
		end
		Expect.Equal(CoverageCodec.Decode("AB", 3), nil, "length mismatch")
		Expect.Equal(CoverageCodec.Decode("A!", 2), nil, "invalid character")
	end)

	Test("initial coverage is deterministic for a seed", function()
		local First = RestorationMath.GenerateInitialValues(77, 2, 10, 40)
		local Second = RestorationMath.GenerateInitialValues(77, 2, 10, 40)
		for Index = 1, 10 do
			Expect.Equal(First[Index], Second[Index], `cell {Index}`)
		end
	end)
end
