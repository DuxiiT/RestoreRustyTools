-- Keeps at most one full-screen panel open so menus never stack on small screens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local UiUtil = require(script.Parent.Parent.Ui.UiUtil)

local PanelController = {}

PanelController.Opened = Signal.New() -- (Name)

local Panels = {}
local OpenPanel = nil

function PanelController.Register(Name: string, Gui: ScreenGui?)
	if Gui then
		Panels[Name] = Gui
		UiUtil.SetVisible(Gui, false)
	end
end

function PanelController.Open(Name: string)
	if not Panels[Name] then
		return
	end
	if OpenPanel and OpenPanel ~= Name then
		UiUtil.SetVisible(Panels[OpenPanel], false)
	end
	OpenPanel = Name
	UiUtil.SetVisible(Panels[Name], true)
	PanelController.Opened:Fire(Name)
end

function PanelController.Close(Name: string)
	if Panels[Name] then
		UiUtil.SetVisible(Panels[Name], false)
	end
	if OpenPanel == Name then
		OpenPanel = nil
	end
end

function PanelController.Toggle(Name: string)
	if OpenPanel == Name then
		PanelController.Close(Name)
	else
		PanelController.Open(Name)
	end
end

function PanelController.IsOpen(Name: string): boolean
	return OpenPanel == Name
end

return PanelController
