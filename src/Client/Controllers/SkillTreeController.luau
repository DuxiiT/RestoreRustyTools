-- Workshop planning board. Node and connection visuals are clones of designer templates,
-- positioned from each node's grid Position. Selecting a node explains its state, price,
-- current and next effect, and for luck nodes the real odds before and after.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SkillTree = require(Shared.Config.SkillTree)
local SalvagePools = require(Shared.Config.SalvagePools)
local ToolDefinitions = require(Shared.Config.ToolDefinitions)
local SkillTreeRules = require(Shared.Logic.SkillTreeRules)
local StatCalculator = require(Shared.Logic.StatCalculator)
local Remotes = require(Shared.Net.Remotes)
local Format = require(Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)
local FeedbackController = require(script.Parent.FeedbackController)
local RollController = require(script.Parent.RollController)

local SkillTreeController = {}

local GridSpacing = 90
local LineThickness = 4
local MinZoom, MaxZoom = 0.6, 1.6
local StateColors = {
	Owned = Color3.fromRGB(110, 170, 90),
	Available = Color3.fromRGB(235, 185, 70),
	Locked = Color3.fromRGB(95, 95, 100),
}

local Gui, Board, Canvas, NodeTemplate, LineTemplate, Details, ResetButton
local Zoom = 1
local SelectedNodeId = "FirstWorkshop"
local NodeButtons = {}
local Lines = {}

local function CanvasBounds()
	local MinX, MaxX, MinY, MaxY = 0, 0, 0, 0
	for _, Node in SkillTree do
		MinX = math.min(MinX, Node.Position.X)
		MaxX = math.max(MaxX, Node.Position.X)
		MinY = math.min(MinY, Node.Position.Y)
		MaxY = math.max(MaxY, Node.Position.Y)
	end
	return MinX, MaxX, MinY, MaxY
end

local function NodePixel(Node): Vector2
	local MinX, _, MinY = CanvasBounds()
	local Spacing = GridSpacing * Zoom
	return Vector2.new((Node.Position.X - MinX + 1) * Spacing, (Node.Position.Y - MinY + 1) * Spacing)
end

local function Layout()
	local MinX, MaxX, MinY, MaxY = CanvasBounds()
	local Spacing = GridSpacing * Zoom
	local Width, Height = (MaxX - MinX + 2) * Spacing, (MaxY - MinY + 2) * Spacing
	Canvas.Size = UDim2.fromOffset(Width, Height)
	if Board:IsA("ScrollingFrame") then
		Board.CanvasSize = UDim2.fromOffset(Width, Height)
	end
	for NodeId, Button in NodeButtons do
		local Pixel = NodePixel(SkillTree[NodeId])
		Button.Position = UDim2.fromOffset(Pixel.X, Pixel.Y)
		Button.Size = UDim2.fromOffset(NodeTemplate.Size.X.Offset * Zoom, NodeTemplate.Size.Y.Offset * Zoom)
	end
	for _, Line in Lines do
		local From, To = NodePixel(SkillTree[Line.From]), NodePixel(SkillTree[Line.To])
		local Delta = To - From
		Line.Frame.Position = UDim2.fromOffset((From.X + To.X) / 2, (From.Y + To.Y) / 2)
		Line.Frame.Size = UDim2.fromOffset(Delta.Magnitude, LineThickness)
		Line.Frame.Rotation = math.deg(math.atan2(Delta.Y, Delta.X))
	end
end

local function NodeNames(NodeIds)
	local Names = {}
	for _, NodeId in NodeIds do
		table.insert(Names, SkillTree[NodeId].Name)
	end
	return table.concat(Names, ", ")
end

-- Luck nodes show the actual odds change on the crate they affect.
local function DescribeOddsChange(NodeId: string, State): string
	local Node = SkillTree[NodeId]
	local AffectsLuck, UnlockedPool = false, nil
	for _, Effect in Node.Effects do
		if Effect.Type == "Stat" and (Effect.Stat == "RarityLuck" or Effect.Stat == "PityReduction") then
			AffectsLuck = true
		elseif Effect.Type == "UnlockPool" then
			UnlockedPool = Effect.Pool
		end
	end
	if UnlockedPool then
		return `{SalvagePools[UnlockedPool].DisplayName} odds: {RollController.DescribeOdds(SalvagePools[UnlockedPool], State.Stats, 0)}`
	end
	if not AffectsLuck then
		return ""
	end
	local Pool = SalvagePools.HardwareCrate
	local Pity = State.Pity.HardwareCrate or 0
	local Rank = SkillTreeRules.GetRank(State.SkillNodes, NodeId)
	local Text = `Hardware Crate now: {RollController.DescribeOdds(Pool, State.Stats, Pity)}`
	if Rank < Node.MaxRank then
		local Upgraded = table.clone(State.SkillNodes)
		Upgraded[NodeId] = Rank + 1
		local NextStats = StatCalculator.Compute(Upgraded).Stats
		Text ..= `\nAfter next rank: {RollController.DescribeOdds(Pool, NextStats, Pity)}`
	end
	return Text
end

local function RefreshDetails()
	local State = StateController.Get()
	local Node = SkillTree[SelectedNodeId]
	if not State or not Details or not Node then
		return
	end
	local Rank = SkillTreeRules.GetRank(State.SkillNodes, SelectedNodeId)
	local NodeState = SkillTreeRules.GetState(State.SkillNodes, SelectedNodeId)
	local Price = SkillTreeRules.NextPrice(State.SkillNodes, SelectedNodeId)
	local Missing = SkillTreeRules.MissingPrerequisites(State.SkillNodes, SelectedNodeId)

	UiUtil.SetText(UiUtil.Find(Details, "NameLabel"), Node.Name)
	UiUtil.SetText(UiUtil.Find(Details, "DescriptionLabel"), Node.Description)
	UiUtil.SetText(
		UiUtil.Find(Details, "StateLabel"),
		if NodeState == "Owned"
			then "Owned (max rank)"
			elseif NodeState == "Locked" then `Locked: requires {NodeNames(Missing)}`
			else `Rank {Rank}/{Node.MaxRank}`
	)
	UiUtil.SetText(UiUtil.Find(Details, "PrereqLabel"), if #Node.Requires > 0 then `Requires: {NodeNames(Node.Requires)}` else "")
	UiUtil.SetText(UiUtil.Find(Details, "CostLabel"), if Price then Format.Money(Price) else "")
	UiUtil.SetText(UiUtil.Find(Details, "CurrentEffectLabel"), `Now: {SkillTreeRules.DescribeRank(SelectedNodeId, Rank)}`)
	UiUtil.SetText(
		UiUtil.Find(Details, "NextEffectLabel"),
		if Rank < Node.MaxRank then `Next: {SkillTreeRules.DescribeRank(SelectedNodeId, Rank + 1)}` else ""
	)
	UiUtil.SetText(UiUtil.Find(Details, "OddsLabel"), DescribeOddsChange(SelectedNodeId, State))

	local BuyButton = UiUtil.Find(Details, "BuyButton")
	local CanBuy = NodeState == "Available" and Price ~= nil and State.Money >= Price
	UiUtil.SetVisible(BuyButton, NodeState == "Available")
	UiUtil.SetText(BuyButton, if CanBuy then `Buy for {Format.Money(Price)}` else `Need {Format.Money(Price or 0)}`)
end

local function RefreshNodes()
	local State = StateController.Get()
	if not State then
		return
	end
	for NodeId, Button in NodeButtons do
		local Node = SkillTree[NodeId]
		local NodeState = SkillTreeRules.GetState(State.SkillNodes, NodeId)
		Button:SetAttribute("State", NodeState)
		Button.BackgroundColor3 = StateColors[NodeState]
		UiUtil.SetText(Button:FindFirstChild("RankLabel"), `{SkillTreeRules.GetRank(State.SkillNodes, NodeId)}/{Node.MaxRank}`)
	end
	for _, Line in Lines do
		local Owned = SkillTreeRules.GetRank(State.SkillNodes, Line.From) > 0
		Line.Frame.BackgroundColor3 = if Owned then StateColors.Owned else StateColors.Locked
	end
	RefreshDetails()
end

local function BuildBoard()
	if not Canvas or not NodeTemplate or not LineTemplate then
		return
	end
	NodeTemplate.Visible = false
	LineTemplate.Visible = false
	for NodeId, Node in SkillTree do
		for _, RequiredId in Node.Requires do
			local Frame = UiUtil.CloneTemplate(LineTemplate, Canvas)
			Frame.AnchorPoint = Vector2.new(0.5, 0.5)
			Frame.ZIndex = NodeTemplate.ZIndex - 1
			table.insert(Lines, { From = RequiredId, To = NodeId, Frame = Frame })
		end
		local Button = UiUtil.CloneTemplate(NodeTemplate, Canvas)
		Button.Name = NodeId
		Button.AnchorPoint = Vector2.new(0.5, 0.5)
		UiUtil.SetText(Button:FindFirstChild("NameLabel") or Button, Node.Name)
		Button:SetAttribute("Major", Node.Major == true)
		Button:SetAttribute("Branch", Node.Branch)
		UiUtil.Bind(Button, function()
			SelectedNodeId = NodeId
			RefreshDetails()
		end)
		NodeButtons[NodeId] = Button
	end
	Layout()
end

local function SetZoom(NewZoom: number)
	Zoom = math.clamp(NewZoom, MinZoom, MaxZoom)
	Layout()
end

local function ShowResetPreview()
	local Response = Remotes.Request("PreviewSkillReset")
	if not NotificationController.Report(Response) then
		return
	end
	local Preview = Response.Data
	if not Preview.CanReset then
		NotificationController.Show("You haven't bought any upgrades to reset.", "Info")
		return
	end
	local SummaryLines = {
		`Refund {Format.Money(Preview.Refund)} - fee {Format.Money(Preview.Fee)} = {Format.Money(Preview.Net)}`,
		`Resets: {NodeNames(Preview.AffectedNodes)}`,
	}
	if #Preview.LostTools > 0 then
		local Names = {}
		for _, ToolId in Preview.LostTools do
			table.insert(Names, ToolDefinitions[ToolId].DisplayName)
		end
		table.insert(SummaryLines, `Tools locked again: {table.concat(Names, ", ")} (your bench job stays workable with base tools)`)
	end
	if #Preview.LostPools > 0 then
		local Names = {}
		for _, PoolId in Preview.LostPools do
			table.insert(Names, SalvagePools[PoolId].DisplayName)
		end
		table.insert(SummaryLines, `Crates locked again: {table.concat(Names, ", ")}`)
	end
	if #Preview.LostFeatures > 0 then
		table.insert(SummaryLines, `Features locked again: {table.concat(Preview.LostFeatures, ", ")}`)
	end
	for _, Warning in Preview.Warnings do
		table.insert(SummaryLines, Warning)
	end
	table.insert(SummaryLines, "No items are ever removed by a reset.")
	if UiUtil.Confirm(table.concat(SummaryLines, "\n")) then
		NotificationController.Report(Remotes.Request("ResetSkillTree", true))
	end
end

function SkillTreeController.Init()
	Gui = UiUtil.WaitForGui("SkillTreeGui")
	PanelController.Register("SkillTree", Gui)
	Board = UiUtil.Find(Gui, "Window/Board")
	Canvas = UiUtil.Find(Board, "Canvas")
	NodeTemplate = UiUtil.Find(Canvas, "NodeTemplate")
	LineTemplate = UiUtil.Find(Canvas, "LineTemplate")
	Details = UiUtil.Find(Gui, "Window/Details")
	ResetButton = UiUtil.Find(Gui, "Window/ResetButton")

	UiUtil.Bind(UiUtil.Find(Gui, "Window/CloseButton"), function()
		PanelController.Close("SkillTree")
	end)
	UiUtil.Bind(UiUtil.Find(Gui, "Window/ZoomInButton"), function()
		SetZoom(Zoom + 0.2)
	end)
	UiUtil.Bind(UiUtil.Find(Gui, "Window/ZoomOutButton"), function()
		SetZoom(Zoom - 0.2)
	end)
	UiUtil.Bind(ResetButton, ShowResetPreview)
	UiUtil.Bind(UiUtil.Find(Details, "BuyButton"), function()
		local Response = Remotes.Request("PurchaseNode", SelectedNodeId)
		if NotificationController.Report(Response) then
			FeedbackController.PlaySound("Upgrade")
		end
	end)

	BuildBoard()
	StateController.Changed:Connect(function()
		if PanelController.IsOpen("SkillTree") then
			RefreshNodes()
		end
	end)
	PanelController.Opened:Connect(function(Name)
		if Name == "SkillTree" then
			RefreshNodes()
		end
	end)
end

function SkillTreeController.Start()
	local function Open()
		PanelController.Open("SkillTree")
	end
	UiUtil.ConnectPrompts("SkillBoardPrompt", Open)
	UiUtil.ConnectPrompts("WorkshopUpgradeBoard", Open)
end

return SkillTreeController
