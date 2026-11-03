-- Player controls over repetitive sounds, effects and roll presentation. Saved on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Format = require(ReplicatedStorage.Shared.Util.Format)

local UiUtil = require(script.Parent.Parent.Ui.UiUtil)
local StateController = require(script.Parent.StateController)
local PanelController = require(script.Parent.PanelController)
local NotificationController = require(script.Parent.NotificationController)

local SettingsController = {}

local VolumeStep = 0.1

local Toggles = {
	SoundToggle = { Key = "SoundEffects", Label = "Sound effects" },
	EffectsToggle = { Key = "ReducedEffects", Label = "Reduced effects" },
	SkipRollToggle = { Key = "SkipRollAnimation", Label = "Skip dice animation" },
}

local Gui, Window

local function Refresh()
	local State = StateController.Get()
	if not State or not Window then
		return
	end
	for ButtonName, Toggle in Toggles do
		UiUtil.SetText(Window:FindFirstChild(ButtonName), `{Toggle.Label}: {if State.Settings[Toggle.Key] then "On" else "Off"}`)
	end
	UiUtil.SetText(Window:FindFirstChild("VolumeLabel"), `Tool volume {Format.Percent(State.Settings.ToolVolume, 0)}`)
	UiUtil.SetVisible(Window:FindFirstChild("SkipTutorialButton"), not State.Tutorial.Completed)
end

local function ChangeVolume(Delta: number)
	local State = StateController.Get()
	if State then
		local Volume = math.clamp(math.floor((State.Settings.ToolVolume + Delta) * 10 + 0.5) / 10, 0, 1)
		NotificationController.Report(Remotes.Request("UpdateSetting", "ToolVolume", Volume))
	end
end

function SettingsController.Init()
	Gui = UiUtil.WaitForGui("SettingsGui")
	PanelController.Register("Settings", Gui)
	Window = UiUtil.Find(Gui, "Window")
	UiUtil.Bind(UiUtil.Find(Window, "CloseButton"), function()
		PanelController.Close("Settings")
	end)
	for ButtonName, Toggle in Toggles do
		UiUtil.Bind(Window and Window:FindFirstChild(ButtonName), function()
			local State = StateController.Get()
			if State then
				NotificationController.Report(Remotes.Request("UpdateSetting", Toggle.Key, not State.Settings[Toggle.Key]))
			end
		end)
	end
	UiUtil.Bind(Window and Window:FindFirstChild("VolumeUpButton"), function()
		ChangeVolume(VolumeStep)
	end)
	UiUtil.Bind(Window and Window:FindFirstChild("VolumeDownButton"), function()
		ChangeVolume(-VolumeStep)
	end)
	UiUtil.Bind(Window and Window:FindFirstChild("SkipTutorialButton"), function()
		if UiUtil.Confirm("Skip the tutorial? You keep your starter bolt and money.") then
			NotificationController.Report(Remotes.Request("SkipTutorial"))
		end
	end)
	StateController.Changed:Connect(Refresh)
end

return SettingsController
