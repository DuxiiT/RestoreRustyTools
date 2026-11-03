-- Short contextual prompts for the current tutorial step plus a highlight on its target.
-- Progress is server-side; this only presents it.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local TutorialSteps = require(Shared.Config.TutorialSteps)
local ContentConfig = require(Shared.Config.ContentConfig)
local Remotes = require(Shared.Net.Remotes)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local NotificationController = require(script.Parent.NotificationController)
local RestorationController = require(script.Parent.RestorationController)

local TutorialController = {}

local Gui, Prompt
local Highlight
local ShownStepId = nil

local function OwnPlot()
	for _, Plot in CollectionService:GetTagged("WorkshopPlot") do
		if Plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			return Plot
		end
	end
	return nil
end

-- Prefers the tagged instance inside the player's own workshop; prompts adorn their parent.
local function ResolveTarget(Tag: string): Instance?
	if Tag == "ActiveItem" then
		local Job = RestorationController.GetJob()
		return Job and Job.LocalModel
	end
	local Plot = OwnPlot()
	local Fallback
	for _, Tagged in CollectionService:GetTagged(Tag) do
		local Target = if Tagged:IsA("ProximityPrompt") then Tagged.Parent else Tagged
		if Plot and Tagged:IsDescendantOf(Plot) then
			return Target
		end
		Fallback = Fallback or Target
	end
	return Fallback
end

local function ClearHighlight()
	if Highlight then
		Highlight:Destroy()
		Highlight = nil
	end
end

local function Refresh()
	local State = StateController.Get()
	if not State or not Prompt then
		return
	end
	local Step = if State.Tutorial.Completed then nil else TutorialSteps[State.Tutorial.Step]
	UiUtil.SetVisible(Prompt, Step ~= nil)
	if not Step then
		ClearHighlight()
		ShownStepId = nil
		return
	end
	UiUtil.SetText(UiUtil.Find(Prompt, "PromptLabel"), Step.Prompt)
	if ShownStepId == Step.Id and Highlight and Highlight.Adornee then
		return
	end
	ShownStepId = Step.Id
	ClearHighlight()
	local Assets = ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
	local Effects = Assets and Assets:FindFirstChild("Effects")
	local Template = Effects and Effects:FindFirstChild("TutorialHighlight")
	local Target = ResolveTarget(Step.Target)
	if Template and Target then
		Highlight = Template:Clone()
		Highlight.Adornee = Target
		Highlight.Parent = workspace.CurrentCamera
	end
end

function TutorialController.Init()
	Gui = UiUtil.WaitForGui("TutorialGui")
	Prompt = UiUtil.Find(Gui, "Prompt")
	UiUtil.SetVisible(Prompt, false)
	UiUtil.Bind(UiUtil.Find(Prompt, "SkipButton"), function()
		if UiUtil.Confirm("Skip the tutorial? You keep your starter bolt and money.") then
			NotificationController.Report(Remotes.Request("SkipTutorial"))
		end
	end)
	StateController.Changed:Connect(Refresh)
	RestorationController.JobChanged:Connect(function()
		ShownStepId = nil
		Refresh()
	end)
end

return TutorialController
