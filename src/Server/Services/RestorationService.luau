-- Server-authoritative restoration. Clients only send tool contact points; the server checks
-- ownership, the active job, the equipped tool, distance to the bench and that each point
-- touches the item, then applies time-bounded work to the coverage cells. Completion is
-- derived from coverage and marked exactly once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ContentConfig = require(Shared.Config.ContentConfig)
local StageDefinitions = require(Shared.Config.StageDefinitions)
local ToolDefinitions = require(Shared.Config.ToolDefinitions)
local VariantDefinitions = require(Shared.Config.VariantDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local RestorationMath = require(Shared.Logic.RestorationMath)
local CoverageCodec = require(Shared.Logic.CoverageCodec)
local CellVisuals = require(Shared.Logic.CellVisuals)
local EffortEstimator = require(Shared.Logic.EffortEstimator)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)
local NetworkService = require(script.Parent.NetworkService)
local StateReplicator = require(script.Parent.StateReplicator)
local ContentRegistry = require(script.Parent.ContentRegistry)
local WorkshopService = require(script.Parent.WorkshopService)

local RestorationService = {}

local VisualFlushInterval = 0.2
local MaxRemainingCellsSent = 48
local DefaultTool = "WireBrush"

local Jobs = {}
local EquippedTools = {}
local LastVisualFlush = 0

local function BuildStage(Job, StageIndex: number)
	local StageId = Job.Definition.Stages[StageIndex]
	local Layer = Job.Model:FindFirstChild(StageDefinitions[StageId].LayerName)
	local Parts, Geometry =
		RestorationMath.BuildGeometry(Layer, Job.Pivot, ContentConfig.CellSurfaceAttribute, ContentConfig.DefaultSurface)
	local Initial = RestorationMath.GenerateInitialValues(Job.Item.Seed, StageIndex, #Geometry, Job.Item.Condition)
	for _, Part in Parts do
		CellVisuals.Prepare(Part)
	end
	return {
		Id = StageId,
		Index = StageIndex,
		Parts = Parts,
		Geometry = Geometry,
		Initial = Initial,
		Values = table.clone(Initial),
		Workable = RestorationMath.ComputeWorkable(Geometry, StageId, ToolDefinitions),
		Hardness = nil,
	}
end

-- Hardness calibration is O(cells^2), so it runs only when a stage becomes active.
local function ActivateStage(Job, StageIndex: number)
	Job.StageIndex = StageIndex
	local Stage = Job.Stages[StageIndex]
	if not Stage.Hardness then
		local Reference = ToolDefinitions[StageDefinitions[Stage.Id].ReferenceTool]
		local StageSeconds = EffortEstimator.StageSeconds(Job.Definition, Stage.Id)
		Stage.Hardness = RestorationMath.CalibrateHardness(Stage.Geometry, Stage.Workable, Stage.Initial, StageSeconds, Reference.Radius)
	end
end

local function ApplyAllVisuals(Job)
	for Index, Stage in Job.Stages do
		for CellIndex, Part in Stage.Parts do
			CellVisuals.Apply(Part, if Index < Job.StageIndex then 0 else Stage.Values[CellIndex])
		end
	end
end

local function RemainingForClient(Job, Stats)
	local NearAt = RestorationMath.NearCompletionProgress - (Stats.CompletionLeniency or 0) * 5
	if Job.StageProgress < NearAt then
		return nil
	end
	local Remaining = RestorationMath.RemainingCells(Job.Stages[Job.StageIndex])
	if #Remaining > MaxRemainingCellsSent then
		return nil
	end
	return Remaining
end

local function BuildUpdate(Job, Kind: string, Stats)
	local Stage = Job.Stages[Job.StageIndex]
	return {
		Kind = Kind,
		ItemUid = Job.Item.Uid,
		TypeId = Job.Item.TypeId,
		StageIndex = Job.StageIndex,
		StageId = Stage.Id,
		StageCount = #Job.Stages,
		Hardness = Stage.Hardness,
		Values = CoverageCodec.Encode(Stage.Values),
		Seq = Job.LastSeq,
		Progress = Job.Progress,
		StageProgress = Job.StageProgress,
		Revealed = table.clone(Job.Item.RevealedTraits),
		Remaining = RemainingForClient(Job, Stats),
	}
end

local function PushUpdate(Job, Kind: string)
	local Derived = PlayerDataService.GetDerived(Job.Player)
	if Derived then
		NetworkService.Push(Job.Player, "JobUpdate", BuildUpdate(Job, Kind, Derived.Stats))
	end
end

local function SnapshotJob(Job)
	local Stage = Job.Stages[Job.StageIndex]
	Job.Item.Restoration = {
		StageIndex = Job.StageIndex,
		Values = CoverageCodec.Encode(Stage.Values),
		Progress = Job.Progress,
	}
end

local function RevealTrait(Job, VariantId: string)
	local Item = Job.Item
	table.insert(Item.RevealedTraits, VariantId)
	Job.Profile.Stats.VariantsFound += 1
	local Folder = Job.Hidden[VariantId]
	local Container = Job.Model:FindFirstChild(ContentConfig.VariantsFolderName)
	if Folder and Container then
		Folder.Parent = Container
	end
	Job.Hidden[VariantId] = nil
	NetworkService.Notify(Job.Player, `Hidden detail uncovered: {VariantDefinitions[VariantId].Name}!`, "Discovery")
	GameEvents.TraitRevealed:Fire(Job.Player, Item, VariantId)
	StateReplicator.MarkDirty(Job.Player)
end

local function RevealDueTraits(Job, RevealEverything: boolean)
	for _, VariantId in Job.Item.Traits do
		if
			not table.find(Job.Item.RevealedTraits, VariantId)
			and (RevealEverything or Job.Progress >= VariantDefinitions[VariantId].RevealAt)
		then
			RevealTrait(Job, VariantId)
		end
	end
end

local function CompleteJob(Job)
	if Job.Completed then
		return
	end
	Job.Completed = true
	local Player, Profile, Item = Job.Player, Job.Profile, Job.Item

	Job.Progress = 1
	RevealDueTraits(Job, true)
	Item.Completed = true
	Item.CompletedAt = os.time()
	Item.Restoration = nil
	Item.State = "Tray"
	Profile.ActiveItemUid = nil
	Profile.Stats.ItemsRestored += 1
	Jobs[Player] = nil

	WorkshopService.ClearActiveItem(Player)
	WorkshopService.RefreshTray(Player, Profile)
	GameEvents.ItemCompleted:Fire(Player, Item)

	local Derived = PlayerDataService.GetDerived(Player)
	NetworkService.Push(Player, "JobUpdate", {
		Kind = "Completed",
		ItemUid = Item.Uid,
		TypeId = Item.TypeId,
		Item = StateReplicator.BuildItemView(Item, Derived.Stats),
	})
	StateReplicator.MarkDirty(Player)
end

local function AdvanceStage(Job)
	local Stage = Job.Stages[Job.StageIndex]
	for Index in Stage.Values do
		Stage.Values[Index] = 0
		CellVisuals.Apply(Stage.Parts[Index], 0)
	end
	Job.DirtyCells = {}
	if Job.StageIndex >= #Job.Stages then
		CompleteJob(Job)
		return
	end
	ActivateStage(Job, Job.StageIndex + 1)
	Job.StageProgress = 0
	Job.Progress = (Job.StageIndex - 1) / #Job.Stages
	PushUpdate(Job, "Stage")
end

local function EvaluateProgress(Job, Stats): boolean
	local Stage = Job.Stages[Job.StageIndex]
	local Score = RestorationMath.StageScore(Stage)
	local Threshold = RestorationMath.CompletionThreshold(Stats)
	Job.StageProgress = math.min(1, Score / Threshold)
	Job.Progress = ((Job.StageIndex - 1) + Job.StageProgress) / #Job.Stages
	Job.Item.Restoration.Progress = Job.Progress
	RevealDueTraits(Job, false)
	if Score >= Threshold then
		AdvanceStage(Job)
		return true
	end
	return false
end

-- Builds the live job for an item already marked as on the bench. Returns true on success.
local function BeginJob(Player: Player, Profile, Item): boolean
	local Model = WorkshopService.PlaceActiveItem(Player, Item)
	if not Model then
		return false
	end
	local Definition = ItemCatalog.Get(Item.TypeId)
	local Pivot = Model:GetPivot()
	local _, BoxSize = Model:GetBoundingBox()

	local Job = {
		Player = Player,
		Profile = Profile,
		Item = Item,
		Definition = Definition,
		Model = Model,
		Pivot = Pivot,
		MaxPointDistance = BoxSize.Magnitude + 1,
		Stages = {},
		StageIndex = 1,
		StageProgress = 0,
		Progress = 0,
		LastSeq = 0,
		LastStrokeAt = 0,
		DirtyCells = {},
		Completed = false,
	}
	Job.Hidden = WorkshopService.SplitVariants(Model, Item)
	for Index in Definition.Stages do
		Job.Stages[Index] = BuildStage(Job, Index)
	end

	local Saved = Item.Restoration or {}
	local StageIndex = math.clamp(Saved.StageIndex or 1, 1, #Definition.Stages)
	local Stage = Job.Stages[StageIndex]
	local SavedValues = Saved.Values and CoverageCodec.Decode(Saved.Values, #Stage.Geometry)
	if SavedValues then
		-- Never let a saved value exceed the generated starting value for its cell.
		for Index, Value in SavedValues do
			Stage.Values[Index] = math.min(Value, Stage.Initial[Index])
		end
	elseif Saved.Values then
		warn(`[RestorationService] Saved coverage for {Item.Uid} no longer matches its model; restarting that stage.`)
	end
	ActivateStage(Job, StageIndex)
	Item.Restoration = { StageIndex = StageIndex, Progress = 0 }
	Jobs[Player] = Job

	local Derived = PlayerDataService.GetDerived(Player)
	EvaluateProgress(Job, Derived.Stats)
	if Jobs[Player] ~= Job then
		-- The saved state was already complete under current settings and finished immediately.
		return true
	end
	ApplyAllVisuals(Job)
	PushUpdate(Job, "Start")
	return true
end

function RestorationService.GetJob(Player: Player)
	return Jobs[Player]
end

function RestorationService.StartJob(Player: Player, Uid: string)
	local Profile = PlayerDataService.Get(Player)
	local Item = Profile.Items[Uid]
	if not Item then
		return Result.Fail("That item is no longer in your inventory.")
	end
	if Profile.ActiveItemUid or Jobs[Player] then
		return Result.Fail("Finish or shelve the item on your bench first. You can work on one item at a time.", "BenchBusy")
	end
	if Item.State ~= "Storage" then
		return Result.Fail("Only items in storage can go on the bench.")
	end
	if Item.Completed then
		return Result.Fail("This item is already restored.")
	end
	if not ContentRegistry.IsAvailable(Item.TypeId) then
		return Result.Fail("This item's model isn't available yet.")
	end
	if not WorkshopService.GetPlot(Player) then
		return Result.Fail("Your workshop isn't ready yet.")
	end
	if not WorkshopService.IsNearOwnWorkshop(Player) then
		return Result.Fail("Head back to your workshop to use your bench.", "TooFar")
	end

	Item.State = "Bench"
	Profile.ActiveItemUid = Uid
	if not BeginJob(Player, Profile, Item) then
		Item.State = "Storage"
		Profile.ActiveItemUid = nil
		return Result.Fail("Your bench couldn't hold this item. Please try again.")
	end
	GameEvents.JobStarted:Fire(Player, Item)
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ItemUid = Uid })
end

function RestorationService.ShelveJob(Player: Player)
	local Job = Jobs[Player]
	if not Job then
		return Result.Fail("There's nothing on your bench.")
	end
	SnapshotJob(Job)
	Job.Item.State = "Storage"
	Job.Profile.ActiveItemUid = nil
	Jobs[Player] = nil
	WorkshopService.ClearActiveItem(Player)
	NetworkService.Push(Player, "JobUpdate", { Kind = "Ended", ItemUid = Job.Item.Uid })
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ItemUid = Job.Item.Uid, Progress = Job.Progress })
end

function RestorationService.EquipTool(Player: Player, ToolId: string)
	local Derived = PlayerDataService.GetDerived(Player)
	if not ToolDefinitions[ToolId] or not Derived.Tools[ToolId] then
		return Result.Fail("You haven't unlocked that tool.")
	end
	EquippedTools[Player] = ToolId
	StateReplicator.MarkDirty(Player)
	return Result.Ok({ ToolId = ToolId })
end

function RestorationService.GetEquippedTool(Player: Player): string
	return EquippedTools[Player] or DefaultTool
end

local function OnStrokes(Player: Player, Seq: number, ToolId: string, Points)
	local Job = Jobs[Player]
	if not Job or Job.Completed or Seq <= Job.LastSeq then
		return
	end
	Job.LastSeq = Seq

	local Derived = PlayerDataService.GetDerived(Player)
	local Tool = ToolDefinitions[ToolId]
	local Stage = Job.Stages[Job.StageIndex]
	if not Tool or RestorationService.GetEquippedTool(Player) ~= ToolId or not Derived.Tools[ToolId] then
		return
	end
	if (Tool.StageMultipliers[Stage.Id] or 0) <= 0 or not WorkshopService.IsNearBench(Player, Job.Definition.Mount) then
		PushUpdate(Job, "Ack")
		return
	end

	local Now = os.clock()
	local DeltaTime = math.min(Now - Job.LastStrokeAt, RestorationMath.MaxStrokeInterval)
	Job.LastStrokeAt = Now

	local InRange = {}
	for _, Point in Points do
		if Point.Magnitude <= Job.MaxPointDistance then
			table.insert(InRange, Point)
		end
	end
	local Changed = {}
	if RestorationMath.ApplyBatch(Stage, Stage.Id, Tool, Derived.Stats, InRange, DeltaTime, Changed) > 0 then
		for Index in Changed do
			Job.DirtyCells[Index] = true
		end
		if EvaluateProgress(Job, Derived.Stats) then
			return
		end
	end
	PushUpdate(Job, "Ack")
end

local function FlushVisuals()
	for _, Job in Jobs do
		if next(Job.DirtyCells) then
			local Stage = Job.Stages[Job.StageIndex]
			for Index in Job.DirtyCells do
				CellVisuals.Apply(Stage.Parts[Index], CoverageCodec.Quantize(Stage.Values[Index]))
			end
			Job.DirtyCells = {}
		end
	end
end

local function ResumeSavedJob(Player: Player, _Plot, Profile)
	local Uid = Profile.ActiveItemUid
	local Item = Uid and Profile.Items[Uid]
	if not Item then
		return
	end
	if ContentRegistry.IsAvailable(Item.TypeId) and BeginJob(Player, Profile, Item) then
		return
	end
	-- Model missing on this server: keep the item and its progress safely in storage.
	Item.State = "Storage"
	Profile.ActiveItemUid = nil
	NetworkService.Notify(Player, "Your bench item was moved to storage with its progress kept.", "Info")
	StateReplicator.MarkDirty(Player)
end

function RestorationService.Init()
	NetworkService.Handle("StartJob", RestorationService.StartJob)
	NetworkService.Handle("ShelveJob", RestorationService.ShelveJob)
	NetworkService.Handle("EquipTool", RestorationService.EquipTool)
	NetworkService.Handle("SubmitStrokes", OnStrokes)

	PlayerDataService.AddSaveHook(function(Player)
		local Job = Jobs[Player]
		if Job and not Job.Completed then
			SnapshotJob(Job)
		end
	end)

	WorkshopService.Assigned:Connect(ResumeSavedJob)
	GameEvents.ProfileReleasing:Connect(function(Player)
		Jobs[Player] = nil
		EquippedTools[Player] = nil
	end)
	GameEvents.SkillTreeReset:Connect(function(Player)
		local Derived = PlayerDataService.GetDerived(Player)
		if Derived and not Derived.Tools[RestorationService.GetEquippedTool(Player)] then
			EquippedTools[Player] = DefaultTool
		end
	end)

	StateReplicator.AddContributor("EquippedTool", function(Player)
		return RestorationService.GetEquippedTool(Player)
	end)
	StateReplicator.AddContributor("ActiveJob", function(Player)
		local Job = Jobs[Player]
		if not Job then
			return nil
		end
		return {
			ItemUid = Job.Item.Uid,
			StageIndex = Job.StageIndex,
			StageId = Job.Stages[Job.StageIndex].Id,
			StageCount = #Job.Stages,
			Progress = Job.Progress,
		}
	end)
end

function RestorationService.Start()
	RunService.Heartbeat:Connect(function()
		local Now = os.clock()
		if Now - LastVisualFlush >= VisualFlushInterval then
			LastVisualFlush = Now
			FlushVisuals()
		end
	end)
end

return RestorationService
