-- Hands-on restoration. The player works on a local copy of the bench item (so it can be
-- rotated freely without affecting what visitors see). Tool contacts are raycast against that
-- copy, converted to item pivot space and sent in small batches. The same shared math predicts
-- the result immediately; server acknowledgements are authoritative and reconcile it.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local ContentConfig = require(Shared.Config.ContentConfig)
local StageDefinitions = require(Shared.Config.StageDefinitions)
local ToolDefinitions = require(Shared.Config.ToolDefinitions)
local MaterialDefinitions = require(Shared.Config.MaterialDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local RestorationMath = require(Shared.Logic.RestorationMath)
local CoverageCodec = require(Shared.Logic.CoverageCodec)
local CellVisuals = require(Shared.Logic.CellVisuals)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local BenchCameraController = require(script.Parent.BenchCameraController)
local NotificationController = require(script.Parent.NotificationController)
local PanelController = require(script.Parent.PanelController)

local RestorationController = {}

RestorationController.JobChanged = Signal.New() -- (Job or nil)
RestorationController.Completed = Signal.New() -- (ItemView)

local SendIntervalSeconds = 0.08
local MinPointSpacing = 0.05
local VisualEpsilon = 0.004
local LocalPlayer = Players.LocalPlayer

local Job = nil
local PendingAutoEnter = false
local NextSeq = 1
local InBench = false
local Brushing = false
local PointerPosition = Vector2.zero
local BatchPoints = {}
local LastSendAt = 0
local LastPoint = nil
local ToolVisual, ContactEffect, ToolSound
local RemainingMarkers = {}
local ServerModelConnection
local PrepareFeedback -- assigned below; EnterBench needs it before its definition

local BenchGui, ToolBar, ToolTemplate, StageLabel, ProgressBar, HintLabel

local function Assets()
	return ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
end

local function FindAsset(FolderName: string, Name: string)
	local Root = Assets()
	local Folder = Root and Root:FindFirstChild(FolderName)
	return Folder and Folder:FindFirstChild(Name)
end

local function GetOwnPlot()
	for _, Plot in CollectionService:GetTagged("WorkshopPlot") do
		if Plot:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			return Plot
		end
	end
	return nil
end

local function WaitForServerModel(ItemUid: string): Model?
	local Deadline = os.clock() + 10
	while os.clock() < Deadline do
		local Plot = GetOwnPlot()
		local Runtime = Plot and Plot:FindFirstChild("Runtime")
		local Model = Runtime and Runtime:FindFirstChild("ActiveItem")
		if Model and Model:GetAttribute("ItemUid") == ItemUid then
			return Model
		end
		task.wait(0.1)
	end
	return nil
end

local function HideLocally(Instance: Instance)
	if Instance:IsA("BasePart") then
		Instance.LocalTransparencyModifier = 1
	end
end

local function ApplyStageVisuals(Stage, Values)
	for Index, Part in Stage.Parts do
		local Value = Values[Index]
		if math.abs((Stage.Shown[Index] or -1) - Value) > VisualEpsilon then
			Stage.Shown[Index] = Value
			CellVisuals.Apply(Part, Value)
		end
	end
end

local function CurrentStage()
	return Job and Job.Stages[Job.StageIndex]
end

local function ClearRemainingMarkers()
	for _, Marker in RemainingMarkers do
		Marker:Destroy()
	end
	RemainingMarkers = {}
end

local function ShowRemainingMarkers(Remaining)
	ClearRemainingMarkers()
	local Template = FindAsset("Effects", "RemainingMarker")
	local Stage = CurrentStage()
	if not Remaining or not Template or not Stage then
		return
	end
	for _, Index in Remaining do
		local Part = Stage.Parts[Index]
		if Part then
			local Marker = Template:Clone()
			if Marker:IsA("SelectionBox") or Marker:IsA("Highlight") or Marker:IsA("BillboardGui") then
				Marker.Adornee = Part
			end
			Marker.Parent = Part
			table.insert(RemainingMarkers, Marker)
		end
	end
end

local function BestToolsFor(StageId: string)
	local Names = {}
	for ToolId, Tool in ToolDefinitions do
		if (Tool.StageMultipliers[StageId] or 0) >= 1 then
			table.insert(Names, Tool.DisplayName .. (if StateController.OwnsTool(ToolId) then "" else " (locked)"))
		end
	end
	table.sort(Names)
	return table.concat(Names, ", ")
end

local function UpdateHud()
	if not Job then
		return
	end
	local StageDefinition = StageDefinitions[Job.StageId]
	UiUtil.SetText(StageLabel, `Stage {Job.StageIndex}/{Job.StageCount}: {StageDefinition.DisplayName}`)
	UiUtil.SetProgress(ProgressBar, Job.Progress)
	local State = StateController.Get()
	local Tool = State and ToolDefinitions[State.EquippedTool]
	if Tool and (Tool.StageMultipliers[Job.StageId] or 0) <= 0 then
		UiUtil.SetText(HintLabel, `The {Tool.DisplayName} can't do this. Try: {BestToolsFor(Job.StageId)}`)
	else
		UiUtil.SetText(HintLabel, StageDefinition.Description)
	end
end

local function BuildLocalStages(LocalModel: Model)
	local Pivot = LocalModel:GetPivot()
	local Stages = {}
	for Index, StageId in Job.Definition.Stages do
		local Layer = LocalModel:FindFirstChild(StageDefinitions[StageId].LayerName)
		local Parts, Geometry =
			RestorationMath.BuildGeometry(Layer, Pivot, ContentConfig.CellSurfaceAttribute, ContentConfig.DefaultSurface)
		Stages[Index] = { Id = StageId, Parts = Parts, Geometry = Geometry, Shown = {} }
	end
	return Stages
end

local function SetStage(Update)
	for Index = 1, Update.StageIndex - 1 do
		local Previous = Job.Stages[Index]
		ApplyStageVisuals(Previous, table.create(#Previous.Parts, 0))
	end
	Job.StageIndex = Update.StageIndex
	Job.StageId = Update.StageId
	local Stage = CurrentStage()
	Stage.Hardness = Update.Hardness
	Stage.Values = CoverageCodec.Decode(Update.Values, #Stage.Geometry) or table.create(#Stage.Geometry, 1)
	Job.Pending = {}
	ApplyStageVisuals(Stage, Stage.Values)
end

local function DestroyLocalModel()
	ClearRemainingMarkers()
	if ServerModelConnection then
		ServerModelConnection:Disconnect()
		ServerModelConnection = nil
	end
	if Job and Job.LocalModel then
		Job.LocalModel:Destroy()
	end
	if Job and Job.ServerModel and Job.ServerModel.Parent then
		for _, Descendant in Job.ServerModel:GetDescendants() do
			if Descendant:IsA("BasePart") then
				Descendant.LocalTransparencyModifier = 0
			end
		end
	end
end

-- Copies a newly revealed variant from the server model into the local copy, keeping its
-- position relative to the item pivot even if the local copy has been rotated.
local function MirrorRevealedVariant(Child: Instance)
	if not Job or not Job.LocalModel then
		return
	end
	local LocalVariants = Job.LocalModel:FindFirstChild(ContentConfig.VariantsFolderName)
	if not LocalVariants or LocalVariants:FindFirstChild(Child.Name) then
		return
	end
	local Copy = Child:Clone()
	local ServerPivot = Job.ServerModel:GetPivot()
	local LocalPivot = Job.LocalModel:GetPivot()
	for _, Descendant in Copy:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.LocalTransparencyModifier = 0
			Descendant.CFrame = LocalPivot * ServerPivot:ToObjectSpace(Descendant.CFrame)
		end
	end
	if Copy:IsA("BasePart") then
		Copy.CFrame = LocalPivot * ServerPivot:ToObjectSpace(Copy.CFrame)
	end
	Copy.Parent = LocalVariants
end

local function StartJob(Update)
	DestroyLocalModel()
	local ServerModel = WaitForServerModel(Update.ItemUid)
	if not ServerModel then
		NotificationController.Show("Your bench item didn't load. Reopen the bench to try again.", "Warning")
		return
	end
	Job = {
		ItemUid = Update.ItemUid,
		TypeId = Update.TypeId,
		Definition = ItemCatalog.Get(Update.TypeId),
		StageCount = Update.StageCount,
		Progress = Update.Progress or 0,
		ServerModel = ServerModel,
		Pending = {},
	}
	local LocalModel = ServerModel:Clone()
	LocalModel.Name = "LocalBenchItem"
	LocalModel.Parent = workspace
	Job.LocalModel = LocalModel
	Job.Stages = BuildLocalStages(LocalModel)

	for _, Descendant in ServerModel:GetDescendants() do
		HideLocally(Descendant)
	end
	ServerModelConnection = ServerModel.DescendantAdded:Connect(function(Descendant)
		HideLocally(Descendant)
		local Parent = Descendant.Parent
		if Parent and Parent.Name == ContentConfig.VariantsFolderName and Parent.Parent == ServerModel then
			task.defer(MirrorRevealedVariant, Descendant)
		end
	end)

	SetStage(Update)
	ShowRemainingMarkers(Update.Remaining)
	UpdateHud()
	RestorationController.JobChanged:Fire(Job)
end

local function Reconcile(Update)
	local Stage = CurrentStage()
	if not Stage or Update.StageIndex ~= Job.StageIndex then
		return
	end
	local ServerValues = CoverageCodec.Decode(Update.Values, #Stage.Geometry)
	if not ServerValues then
		return
	end
	local StillPending = {}
	for _, Batch in Job.Pending do
		if Batch.Seq > Update.Seq then
			table.insert(StillPending, Batch)
		end
	end
	Job.Pending = StillPending
	Stage.Values = ServerValues
	local State = StateController.Get()
	for _, Batch in StillPending do
		RestorationMath.ApplyBatch(Stage, Stage.Id, ToolDefinitions[Batch.ToolId], State.Stats, Batch.Points, Batch.DeltaTime, {})
	end
	ApplyStageVisuals(Stage, Stage.Values)
	Job.Progress = Update.Progress
	ShowRemainingMarkers(Update.Remaining)
	UpdateHud()
end

function RestorationController.ExitBench()
	if not InBench then
		return
	end
	InBench = false
	Brushing = false
	BenchCameraController.Exit()
	UiUtil.SetVisible(BenchGui, false)
	if ToolVisual then
		ToolVisual:Destroy()
		ToolVisual = nil
	end
	if ContactEffect then
		ContactEffect:Destroy()
		ContactEffect = nil
	end
	if ToolSound then
		ToolSound:Stop()
	end
end

local function EndJob()
	RestorationController.ExitBench()
	DestroyLocalModel()
	Job = nil
	RestorationController.JobChanged:Fire(nil)
end

local function OnJobUpdate(Update)
	if Update.Kind == "Start" then
		StartJob(Update)
	elseif not Job or Update.ItemUid ~= Job.ItemUid then
		return
	elseif Update.Kind == "Ack" then
		Reconcile(Update)
	elseif Update.Kind == "Stage" then
		SetStage(Update)
		Job.Progress = Update.Progress
		ShowRemainingMarkers(nil)
		UpdateHud()
		NotificationController.Show(`Next: {StageDefinitions[Update.StageId].DisplayName}`, "Info")
	elseif Update.Kind == "Completed" then
		EndJob()
		RestorationController.Completed:Fire(Update.Item)
	elseif Update.Kind == "Ended" then
		EndJob()
	end
end

function RestorationController.GetJob()
	return Job
end

function RestorationController.EnterBench()
	if not Job or not Job.LocalModel or InBench then
		return
	end
	PanelController.Close("Inventory")
	InBench = true
	local BoxCFrame, BoxSize = Job.LocalModel:GetBoundingBox()
	local Character = LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	local Offset = if Root then Root.Position - BoxCFrame.Position else Vector3.new(0, 0, 1)
	BenchCameraController.Enter(BoxCFrame.Position, math.atan2(Offset.X, Offset.Z), math.max(BoxSize.X, BoxSize.Y, BoxSize.Z))
	UiUtil.SetVisible(BenchGui, true)
	PrepareFeedback()
	RestorationController.RefreshToolBar()
	UpdateHud()
end

-- Rotates the local copy about its center. Contact math is pivot-relative, so this is purely
-- for reaching every surface.
function RestorationController.RotateItem(Rotation: CFrame)
	if not Job or not Job.LocalModel then
		return
	end
	local Center = Job.LocalModel:GetBoundingBox()
	local Upright = CFrame.new(Center.Position)
	Job.LocalModel:PivotTo(Upright * Rotation * Upright:Inverse() * Job.LocalModel:GetPivot())
end

local function EquippedTool()
	local State = StateController.Get()
	return State and State.EquippedTool, State and ToolDefinitions[State.EquippedTool]
end

local function UpdateToolVisual(Hit: RaycastResult?)
	local ToolId, Tool = EquippedTool()
	if not Tool then
		return
	end
	if not ToolVisual or ToolVisual.Name ~= ToolId then
		if ToolVisual then
			ToolVisual:Destroy()
		end
		local Template = FindAsset("Tools", ToolId)
		ToolVisual = Template and Template:Clone()
		if ToolVisual then
			ToolVisual.Name = ToolId
			for _, Descendant in ToolVisual:GetDescendants() do
				if Descendant:IsA("BasePart") then
					Descendant.Anchored = true
					Descendant.CanCollide = false
					Descendant.CanQuery = false
				end
			end
			ToolVisual.Parent = workspace
		end
	end
	local Camera = workspace.CurrentCamera
	if ToolVisual then
		if Hit then
			-- The tool model's LookVector (-Z) points into the surface.
			local ContactPoint = Hit.Position + Hit.Normal * 0.05
			ToolVisual:PivotTo(CFrame.lookAt(ContactPoint, ContactPoint - Hit.Normal, Camera.CFrame.UpVector))
		else
			ToolVisual:PivotTo(CFrame.new(0, -1000, 0))
		end
	end
	local Settings = StateController.Get().Settings
	if ContactEffect then
		local Emitter = ContactEffect:FindFirstChildWhichIsA("ParticleEmitter", true)
		if Emitter then
			Emitter.Enabled = Hit ~= nil and not Settings.ReducedEffects
		end
		if Hit and ContactEffect:IsA("BasePart") then
			ContactEffect.CFrame = CFrame.new(Hit.Position)
		end
	end
	if ToolSound then
		ToolSound.Volume = Settings.ToolVolume * (ToolSound:GetAttribute("BaseVolume") or 0.5)
		if Hit and Settings.SoundEffects and not ToolSound.IsPlaying then
			ToolSound:Play()
		elseif (not Hit or not Settings.SoundEffects) and ToolSound.IsPlaying then
			ToolSound:Stop()
		end
	end
end

PrepareFeedback = function()
	local ToolId, Tool = EquippedTool()
	local Material = MaterialDefinitions[Job.Definition.Material]
	if ContactEffect then
		ContactEffect:Destroy()
	end
	local EffectTemplate = FindAsset("Effects", `Contact_{Material.ParticleSet}`)
	ContactEffect = EffectTemplate and EffectTemplate:Clone()
	if ContactEffect then
		ContactEffect.Parent = workspace
	end
	if ToolSound then
		ToolSound:Destroy()
	end
	local SoundTemplate = Tool and (FindAsset("Sounds", `{Tool.SoundName}_{Material.SoundSet}`) or FindAsset("Sounds", Tool.SoundName))
	ToolSound = SoundTemplate and SoundTemplate:Clone()
	if ToolSound then
		ToolSound:SetAttribute("BaseVolume", SoundTemplate.Volume)
		ToolSound.Looped = true
		ToolSound.Parent = workspace.CurrentCamera
	end
	return ToolId
end

local function CastPointer(): RaycastResult?
	local Camera = workspace.CurrentCamera
	local Ray = Camera:ScreenPointToRay(PointerPosition.X, PointerPosition.Y)
	local Parameters = RaycastParams.new()
	Parameters.FilterType = Enum.RaycastFilterType.Include
	Parameters.FilterDescendantsInstances = { Job.LocalModel }
	return workspace:Raycast(Ray.Origin, Ray.Direction * 100, Parameters)
end

local function SendBatch(Now: number)
	local ToolId, Tool = EquippedTool()
	local DeltaTime = math.min(Now - LastSendAt, RestorationMath.MaxStrokeInterval)
	LastSendAt = Now
	if #BatchPoints == 0 or not Tool then
		return
	end
	local Points = BatchPoints
	BatchPoints = {}
	local Seq = NextSeq
	NextSeq += 1
	Remotes.Get("SubmitStrokes"):FireServer(Seq, ToolId, Points)

	local Stage = CurrentStage()
	if (Tool.StageMultipliers[Stage.Id] or 0) > 0 then
		local Changed = {}
		RestorationMath.ApplyBatch(Stage, Stage.Id, Tool, StateController.Get().Stats, Points, DeltaTime, Changed)
		table.insert(Job.Pending, { Seq = Seq, ToolId = ToolId, Points = Points, DeltaTime = DeltaTime })
		ApplyStageVisuals(Stage, Stage.Values)
	end
end

local function OnRenderStep()
	if not InBench or not Job or not Job.LocalModel then
		return
	end
	local Hit = nil
	if Brushing then
		Hit = CastPointer()
		if Hit then
			local LocalPoint = Job.LocalModel:GetPivot():PointToObjectSpace(Hit.Position)
			if
				(not LastPoint or (LocalPoint - LastPoint).Magnitude >= MinPointSpacing)
				and #BatchPoints < RestorationMath.MaxPointsPerBatch
			then
				table.insert(BatchPoints, LocalPoint)
				LastPoint = LocalPoint
			end
		end
	end
	UpdateToolVisual(Hit)
	local Now = os.clock()
	if Now - LastSendAt >= SendIntervalSeconds then
		SendBatch(Now)
	end
end

local function IsBrushInput(Input: InputObject): boolean
	if Input.UserInputType == Enum.UserInputType.MouseButton1 then
		return true
	end
	return Input.UserInputType == Enum.UserInputType.Touch and BenchCameraController.ActiveTouchCount() <= 1
end

local function OnInputBegan(Input: InputObject, Processed: boolean)
	if not InBench or Processed then
		return
	end
	if IsBrushInput(Input) then
		Brushing = true
		LastPoint = nil
		PointerPosition = Vector2.new(Input.Position.X, Input.Position.Y)
	elseif Input.KeyCode == Enum.KeyCode.Q then
		RestorationController.RotateItem(CFrame.Angles(0, math.rad(45), 0))
	elseif Input.KeyCode == Enum.KeyCode.E then
		RestorationController.RotateItem(CFrame.Angles(0, math.rad(-45), 0))
	elseif Input.KeyCode == Enum.KeyCode.F then
		RestorationController.RotateItem(CFrame.Angles(math.rad(180), 0, 0))
	end
end

local function OnInputChanged(Input: InputObject)
	if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
		PointerPosition = Vector2.new(Input.Position.X, Input.Position.Y)
	end
	if Brushing and Input.UserInputType == Enum.UserInputType.Touch and BenchCameraController.ActiveTouchCount() > 1 then
		Brushing = false
	end
end

local function OnInputEnded(Input: InputObject)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
		Brushing = false
	end
end

function RestorationController.RefreshToolBar()
	if not ToolBar or not ToolTemplate then
		return
	end
	UiUtil.ClearGenerated(ToolBar)
	local State = StateController.Get()
	local Ordered = {}
	for ToolId, Tool in ToolDefinitions do
		table.insert(Ordered, { Id = ToolId, Tool = Tool })
	end
	table.sort(Ordered, function(A, B)
		return A.Tool.Order < B.Tool.Order
	end)
	for _, Entry in Ordered do
		local Owned = StateController.OwnsTool(Entry.Id)
		local Button = UiUtil.CloneTemplate(ToolTemplate, ToolBar)
		Button.Name = Entry.Id
		Button.LayoutOrder = Entry.Tool.Order
		local Label = Entry.Tool.DisplayName .. (if Owned then "" else " (Locked)")
		UiUtil.SetText(Button:FindFirstChild("NameLabel") or Button, Label)
		Button:SetAttribute("Equipped", State.EquippedTool == Entry.Id)
		Button:SetAttribute("Locked", not Owned)
		UiUtil.Bind(Button, function()
			if not Owned then
				NotificationController.Show("Unlock this tool on the skill board.", "Info")
				return
			end
			if NotificationController.Report(Remotes.Request("EquipTool", Entry.Id)) and InBench and Job then
				PrepareFeedback()
			end
		end)
	end
end

function RestorationController.Init()
	BenchGui = UiUtil.WaitForGui("BenchGui")
	UiUtil.SetVisible(BenchGui, false)
	ToolBar = UiUtil.Find(BenchGui, "ToolBar")
	ToolTemplate = UiUtil.Find(ToolBar, "ToolTemplate")
	if ToolTemplate then
		ToolTemplate.Visible = false
	end
	StageLabel = UiUtil.Find(BenchGui, "StageLabel")
	ProgressBar = UiUtil.Find(BenchGui, "ProgressBar")
	HintLabel = UiUtil.Find(BenchGui, "HintLabel")

	UiUtil.Bind(UiUtil.Find(BenchGui, "ExitButton"), RestorationController.ExitBench)
	UiUtil.Bind(UiUtil.Find(BenchGui, "ShelveButton"), function()
		NotificationController.Report(Remotes.Request("ShelveJob"))
	end)
	UiUtil.Bind(UiUtil.Find(BenchGui, "FlipButton"), function()
		RestorationController.RotateItem(CFrame.Angles(math.rad(180), 0, 0))
	end)
	UiUtil.Bind(UiUtil.Find(BenchGui, "RotateLeftButton"), function()
		RestorationController.RotateItem(CFrame.Angles(0, math.rad(45), 0))
	end)
	UiUtil.Bind(UiUtil.Find(BenchGui, "RotateRightButton"), function()
		RestorationController.RotateItem(CFrame.Angles(0, math.rad(-45), 0))
	end)
	UiUtil.Bind(UiUtil.Find(BenchGui, "ZoomInButton"), function()
		BenchCameraController.Zoom(0.85)
	end)
	UiUtil.Bind(UiUtil.Find(BenchGui, "ZoomOutButton"), function()
		BenchCameraController.Zoom(1.15)
	end)

	Remotes.Get("JobUpdate").OnClientEvent:Connect(function(Update)
		local WasStart = Update.Kind == "Start"
		OnJobUpdate(Update)
		if WasStart and Job and PendingAutoEnter then
			PendingAutoEnter = false
			RestorationController.EnterBench()
		end
	end)

	StateController.Changed:Connect(function()
		if InBench then
			RestorationController.RefreshToolBar()
			UpdateHud()
		end
	end)

	UserInputService.InputBegan:Connect(OnInputBegan)
	UserInputService.InputChanged:Connect(OnInputChanged)
	UserInputService.InputEnded:Connect(OnInputEnded)
	RunService.RenderStepped:Connect(OnRenderStep)
end

-- Starts a job on the given item and enters the bench view once the server confirms it.
function RestorationController.RequestStart(ItemUid: string)
	PendingAutoEnter = true
	local Response = Remotes.Request("StartJob", ItemUid)
	if not NotificationController.Report(Response) then
		PendingAutoEnter = false
	elseif Job and Job.ItemUid == ItemUid then
		PendingAutoEnter = false
		RestorationController.EnterBench()
	end
end

function RestorationController.Start()
	UiUtil.ConnectPrompts("WorkshopBench", function(Prompt)
		local Plot = GetOwnPlot()
		if not Plot or not Prompt:IsDescendantOf(Plot) then
			return
		end
		if Job then
			RestorationController.EnterBench()
		else
			PanelController.Open("Inventory")
		end
	end)
end

return RestorationController
