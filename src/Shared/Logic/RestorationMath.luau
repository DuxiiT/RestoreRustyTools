-- Spatial coverage model shared by server (authoritative) and client (prediction).
-- Each stage layer is a set of cell parts covering the clean surface. Each cell holds a value
-- from 0 (clean) to 1 (fully covered). Tool contact points are expressed in the item's pivot
-- space, so rotating the item for inspection never changes the math.
local RestorationMath = {}

RestorationMath.ContactTolerance = 0.35
RestorationMath.MaxStrokeInterval = 0.2
RestorationMath.MaxPointsPerBatch = 12
RestorationMath.CleanCellValue = 0.06
RestorationMath.BaseCompletionThreshold = 0.94
RestorationMath.MinCompletionThreshold = 0.85
RestorationMath.NearCompletionProgress = 0.8
RestorationMath.RemainingCellScore = 0.6
-- Fraction of a sweeping stroke's ideal coverage a real player achieves; used only for calibration.
RestorationMath.SweepEfficiency = 0.6

local function CompareCells(A, B)
	if A.Part.Name ~= B.Part.Name then
		return A.Part.Name < B.Part.Name
	end
	local PositionA, PositionB = A.Local.Position, B.Local.Position
	if math.abs(PositionA.X - PositionB.X) > 1e-3 then
		return PositionA.X < PositionB.X
	end
	if math.abs(PositionA.Y - PositionB.Y) > 1e-3 then
		return PositionA.Y < PositionB.Y
	end
	return PositionA.Z < PositionB.Z
end

-- Returns cell parts and their geometry in a deterministic order, so server and client clones
-- of the same model agree on cell indices.
function RestorationMath.BuildGeometry(LayerFolder: Instance, Pivot: CFrame, SurfaceAttribute: string, DefaultSurface: string)
	local Entries = {}
	for _, Descendant in LayerFolder:GetDescendants() do
		if Descendant:IsA("BasePart") then
			table.insert(Entries, { Part = Descendant, Local = Pivot:ToObjectSpace(Descendant.CFrame) })
		end
	end
	table.sort(Entries, CompareCells)

	local Parts = table.create(#Entries)
	local Geometry = table.create(#Entries)
	for Index, Entry in Entries do
		local HalfSize = Entry.Part.Size / 2
		Parts[Index] = Entry.Part
		Geometry[Index] = {
			Inverse = Entry.Local:Inverse(),
			Center = Entry.Local.Position,
			HalfSize = HalfSize,
			BoundingRadius = HalfSize.Magnitude,
			Surface = Entry.Part:GetAttribute(SurfaceAttribute) or DefaultSurface,
		}
	end
	return Parts, Geometry
end

function RestorationMath.DistanceToCell(Point: Vector3, Cell): number
	local LocalPoint = Cell.Inverse * Point
	local HalfSize = Cell.HalfSize
	local Clamped = Vector3.new(
		math.clamp(LocalPoint.X, -HalfSize.X, HalfSize.X),
		math.clamp(LocalPoint.Y, -HalfSize.Y, HalfSize.Y),
		math.clamp(LocalPoint.Z, -HalfSize.Z, HalfSize.Z)
	)
	return (LocalPoint - Clamped).Magnitude
end

-- A cell is required for a stage when at least one base tool that works the stage can work its
-- surface; protected surfaces (for example paint under a metal-only tool) are not required.
function RestorationMath.ComputeWorkable(Geometry, StageId: string, ToolDefinitions)
	local Workable = table.create(#Geometry, false)
	for Index, Cell in Geometry do
		for _, Tool in ToolDefinitions do
			if Tool.Base and (Tool.StageMultipliers[StageId] or 0) > 0 and (Tool.Surfaces[Cell.Surface] or 0) > 0 then
				Workable[Index] = true
				break
			end
		end
	end
	return Workable
end

-- Deterministic initial coverage from the item's saved seed, so a job never needs its starting
-- state saved and resuming always reproduces the same corrosion pattern.
function RestorationMath.GenerateInitialValues(Seed: number, StageIndex: number, Count: number, Condition: number)
	local Generator = Random.new(Seed + StageIndex * 7919)
	local Minimum = 0.6 + 0.3 * (1 - math.clamp(Condition, 1, 100) / 100)
	local Values = table.create(Count)
	for Index = 1, Count do
		Values[Index] = Minimum + (1 - Minimum) * Generator:NextNumber()
	end
	return Values
end

-- Per-cell hardness so the stage takes about StageSeconds with the reference tool at base stats,
-- independent of how many cells the modeler created. Coverage is the average number of
-- required cells a reference-radius contact reaches.
function RestorationMath.CalibrateHardness(Geometry, Workable, InitialValues, StageSeconds: number, ReferenceRadius: number): number
	local Required = {}
	local InitialTotal = 0
	for Index, IsWorkable in Workable do
		if IsWorkable then
			table.insert(Required, Index)
			InitialTotal += InitialValues[Index]
		end
	end
	if #Required == 0 then
		return 1
	end

	local NeighborTotal = 0
	for _, IndexA in Required do
		local Center = Geometry[IndexA].Center
		for _, IndexB in Required do
			if RestorationMath.DistanceToCell(Center, Geometry[IndexB]) <= ReferenceRadius then
				NeighborTotal += 1
			end
		end
	end
	local Coverage = NeighborTotal / #Required
	local AverageInitial = InitialTotal / #Required
	local Hardness = StageSeconds * Coverage * RestorationMath.SweepEfficiency / (#Required * AverageInitial)
	return math.max(Hardness, 0.01)
end

function RestorationMath.ToolRadius(Tool, Stats): number
	return Tool.Radius * (Stats.ToolRadius or 1)
end

function RestorationMath.ToolWork(Tool, StageId: string, Stats, DeltaTime: number): number
	return DeltaTime * Tool.Power * (Tool.StageMultipliers[StageId] or 0) * (Stats[Tool.StrengthStat] or 1)
end

local function IsValidContact(Stage, Point: Vector3, Tool): boolean
	for _, Cell in Stage.Geometry do
		if
			(Tool.Surfaces[Cell.Surface] or 0) > 0
			and (Point - Cell.Center).Magnitude - Cell.BoundingRadius <= RestorationMath.ContactTolerance
			and RestorationMath.DistanceToCell(Point, Cell) <= RestorationMath.ContactTolerance
		then
			return true
		end
	end
	return false
end

local function ApplyContact(Stage, Point: Vector3, Radius: number, Work: number, Surfaces, Changed)
	for Index, Cell in Stage.Geometry do
		local Value = Stage.Values[Index]
		local SurfaceMultiplier = Surfaces[Cell.Surface] or 0
		if Value <= 0 or SurfaceMultiplier <= 0 then
			continue
		end
		if (Point - Cell.Center).Magnitude - Cell.BoundingRadius > Radius then
			continue
		end
		local Distance = RestorationMath.DistanceToCell(Point, Cell)
		if Distance <= Radius then
			local Falloff = 1 - (Distance / Radius) ^ 2
			Stage.Values[Index] = math.max(0, Value - Work * SurfaceMultiplier * Falloff / Stage.Hardness)
			Changed[Index] = true
		end
	end
end

-- Applies one batch of contact points. Total work is bounded by DeltaTime regardless of how
-- many points arrive, so flooding points cannot speed up cleaning. Points not touching a
-- workable cell (empty space) are discarded. Returns the number of accepted points.
function RestorationMath.ApplyBatch(Stage, StageId: string, Tool, Stats, Points, DeltaTime: number, Changed): number
	local ValidPoints = {}
	for Index = 1, math.min(#Points, RestorationMath.MaxPointsPerBatch) do
		local Point = Points[Index]
		if IsValidContact(Stage, Point, Tool) then
			table.insert(ValidPoints, Point)
		end
	end
	if #ValidPoints == 0 then
		return 0
	end
	local Radius = RestorationMath.ToolRadius(Tool, Stats)
	local WorkPerPoint = RestorationMath.ToolWork(Tool, StageId, Stats, math.clamp(DeltaTime, 0, RestorationMath.MaxStrokeInterval))
		/ #ValidPoints
	if WorkPerPoint <= 0 then
		return 0
	end
	for _, Point in ValidPoints do
		ApplyContact(Stage, Point, Radius, WorkPerPoint, Tool.Surfaces, Changed)
	end
	return #ValidPoints
end

-- Mean cleanliness of required cells relative to their starting coverage (0 to 1).
function RestorationMath.StageScore(Stage): number
	local Total, Count = 0, 0
	for Index, IsWorkable in Stage.Workable do
		if IsWorkable then
			local Initial = Stage.Initial[Index]
			local Span = math.max(Initial - RestorationMath.CleanCellValue, 1e-3)
			Total += 1 - math.clamp((Stage.Values[Index] - RestorationMath.CleanCellValue) / Span, 0, 1)
			Count += 1
		end
	end
	return if Count > 0 then Total / Count else 1
end

function RestorationMath.CompletionThreshold(Stats): number
	return math.max(RestorationMath.MinCompletionThreshold, RestorationMath.BaseCompletionThreshold - (Stats.CompletionLeniency or 0))
end

function RestorationMath.RemainingCells(Stage)
	local Remaining = {}
	for Index, IsWorkable in Stage.Workable do
		if IsWorkable then
			local Initial = Stage.Initial[Index]
			local Span = math.max(Initial - RestorationMath.CleanCellValue, 1e-3)
			local Score = 1 - math.clamp((Stage.Values[Index] - RestorationMath.CleanCellValue) / Span, 0, 1)
			if Score < RestorationMath.RemainingCellScore then
				table.insert(Remaining, Index)
			end
		end
	end
	return Remaining
end

return RestorationMath
