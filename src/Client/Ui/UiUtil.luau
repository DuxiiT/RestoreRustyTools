-- Helpers for binding to interface built in Studio (StarterGui). Nothing here creates UI;
-- lists are filled by cloning hidden templates the designer provides. Missing elements are
-- reported once and skipped so a partly built interface never breaks gameplay.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RarityConfig = require(Shared.Config.RarityConfig)
local ContentConfig = require(Shared.Config.ContentConfig)
local StageDefinitions = require(Shared.Config.StageDefinitions)
local ItemCatalog = require(Shared.Content.ItemCatalog)

local UiUtil = {}

local GeneratedAttribute = "Generated"
local Warned = {}

local function WarnOnce(Message: string)
	if not Warned[Message] then
		Warned[Message] = true
		warn(`[UI] {Message}`)
	end
end

function UiUtil.WaitForGui(Name: string): ScreenGui?
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Gui = PlayerGui:WaitForChild(Name, 5)
	if not Gui then
		WarnOnce(`ScreenGui {Name} not found in StarterGui; its features are disabled.`)
	end
	return Gui
end

-- Path uses "/" separators, for example "Window/PoolList/PoolTemplate".
function UiUtil.Find(Root: Instance?, Path: string): Instance?
	if not Root then
		return nil
	end
	local Current = Root
	for _, Name in string.split(Path, "/") do
		Current = Current:FindFirstChild(Name)
		if not Current then
			WarnOnce(`{Root:GetFullName()}/{Path} is missing.`)
			return nil
		end
	end
	return Current
end

function UiUtil.Bind(Button: Instance?, Callback)
	if Button and Button:IsA("GuiButton") then
		return Button.Activated:Connect(Callback)
	end
	return nil
end

function UiUtil.SetText(Label: Instance?, Text: string)
	if Label and (Label:IsA("TextLabel") or Label:IsA("TextButton") or Label:IsA("TextBox")) then
		Label.Text = Text
	end
end

function UiUtil.SetVisible(Target: Instance?, Visible: boolean)
	if not Target then
		return
	end
	if Target:IsA("LayerCollector") then
		Target.Enabled = Visible
	elseif Target:IsA("GuiObject") then
		Target.Visible = Visible
	end
end

function UiUtil.SetProgress(Bar: Instance?, Fraction: number)
	local Fill = Bar and Bar:FindFirstChild("Fill")
	if Fill and Fill:IsA("GuiObject") then
		Fill.Size = UDim2.fromScale(math.clamp(Fraction, 0, 1), 1)
	end
end

function UiUtil.ApplyRarity(Label: Instance?, Rarity: string)
	local Tier = RarityConfig.Tiers[Rarity]
	if Label and Tier and Label:IsA("TextLabel") then
		Label.Text = Tier.Label
		Label.TextColor3 = Tier.Color
	end
end

function UiUtil.CloneTemplate(Template: GuiObject, Parent: Instance?): GuiObject
	local Clone = Template:Clone()
	Clone:SetAttribute(GeneratedAttribute, true)
	Clone.Visible = true
	Clone.Parent = Parent or Template.Parent
	return Clone
end

function UiUtil.ClearGenerated(Container: Instance?)
	if not Container then
		return
	end
	for _, Child in Container:GetChildren() do
		if Child:GetAttribute(GeneratedAttribute) then
			Child:Destroy()
		end
	end
end

function UiUtil.GetItemTemplate(TypeId: string): Model?
	local Definition = ItemCatalog.Get(TypeId)
	local Assets = ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
	local Models = Assets and Assets:FindFirstChild(ContentConfig.ItemModelsFolderName)
	return Definition and Models and Models:FindFirstChild(Definition.ModelName)
end

-- Shows the item's real model in a ViewportFrame. Restored removes corrosion layers and keeps
-- only the variants listed in VisibleVariants.
function UiUtil.ShowItem(Viewport: Instance?, TypeId: string, Restored: boolean, VisibleVariants)
	if not Viewport or not Viewport:IsA("ViewportFrame") then
		return
	end
	Viewport:ClearAllChildren()
	local Template = UiUtil.GetItemTemplate(TypeId)
	if not Template then
		return
	end
	local Model = Template:Clone()
	local Variants = Model:FindFirstChild(ContentConfig.VariantsFolderName)
	if Variants then
		for _, Child in Variants:GetChildren() do
			if not (VisibleVariants and table.find(VisibleVariants, Child.Name)) then
				Child:Destroy()
			end
		end
	end
	if Restored then
		for _, Stage in StageDefinitions do
			local Layer = Model:FindFirstChild(Stage.LayerName)
			if Layer then
				Layer:Destroy()
			end
		end
	end
	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	Model:PivotTo(BoxCFrame:Inverse() * Model:GetPivot())
	Model.Parent = Viewport

	local Camera = Instance.new("Camera")
	local Distance = BoxSize.Magnitude * 1.1
	Camera.CFrame = CFrame.lookAt(Vector3.new(Distance * 0.6, Distance * 0.45, Distance * 0.7), Vector3.zero)
	Camera.FieldOfView = 40
	Camera.Parent = Viewport
	Viewport.CurrentCamera = Camera
end

-- Calls Callback(Prompt) when the local player triggers any ProximityPrompt carrying Tag,
-- including prompts added later (for example when a plot streams in).
function UiUtil.ConnectPrompts(Tag: string, Callback)
	local CollectionService = game:GetService("CollectionService")
	local function Hook(Prompt: Instance)
		if Prompt:IsA("ProximityPrompt") then
			Prompt.Triggered:Connect(function(PlayerWhoTriggered)
				if PlayerWhoTriggered == Players.LocalPlayer then
					Callback(Prompt)
				end
			end)
		end
	end
	for _, Prompt in CollectionService:GetTagged(Tag) do
		Hook(Prompt)
	end
	CollectionService:GetInstanceAddedSignal(Tag):Connect(Hook)
end

-- Simple yes/no dialog from DialogGui. Yields until the player answers.
function UiUtil.Confirm(Message: string): boolean
	local Gui = UiUtil.WaitForGui("DialogGui")
	local Dialog = UiUtil.Find(Gui, "Dialog")
	local ConfirmButton = UiUtil.Find(Dialog, "ConfirmButton")
	local CancelButton = UiUtil.Find(Dialog, "CancelButton")
	if not Dialog or not ConfirmButton or not CancelButton then
		return false
	end
	UiUtil.SetText(UiUtil.Find(Dialog, "MessageLabel"), Message)
	UiUtil.SetVisible(Gui, true)
	UiUtil.SetVisible(Dialog, true)

	local Answer = Instance.new("BindableEvent")
	local Connections = {
		UiUtil.Bind(ConfirmButton, function()
			Answer:Fire(true)
		end),
		UiUtil.Bind(CancelButton, function()
			Answer:Fire(false)
		end),
	}
	local Accepted = Answer.Event:Wait()
	for _, Connection in Connections do
		Connection:Disconnect()
	end
	Answer:Destroy()
	UiUtil.SetVisible(Dialog, false)
	return Accepted
end

return UiUtil
