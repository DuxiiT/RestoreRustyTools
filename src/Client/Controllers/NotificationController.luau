-- Short toast messages from the server and from local request results.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local UiUtil = require(script.Parent.Parent.Ui.UiUtil)

local NotificationController = {}

local DisplaySeconds = 3.5
local MaxVisible = 4

local Container, Template
local Visible = {}

function NotificationController.Show(Message: string, Kind: string?)
	if not Template then
		print(`[Notice] {Message}`)
		return
	end
	local Toast = UiUtil.CloneTemplate(Template, Container)
	UiUtil.SetText(Toast, Message)
	Toast:SetAttribute("Kind", Kind or "Info")
	table.insert(Visible, Toast)
	if #Visible > MaxVisible then
		table.remove(Visible, 1):Destroy()
	end
	task.delay(DisplaySeconds, function()
		local Index = table.find(Visible, Toast)
		if Index then
			table.remove(Visible, Index)
		end
		Toast:Destroy()
	end)
end

-- Shows a failed request's message. Returns Response.Success for convenient chaining.
function NotificationController.Report(Response): boolean
	if not Response.Success then
		NotificationController.Show(Response.Message or "That didn't work.", "Warning")
	end
	return Response.Success
end

function NotificationController.Init()
	local Gui = UiUtil.WaitForGui("HudGui")
	Container = UiUtil.Find(Gui, "Notifications")
	Template = UiUtil.Find(Container, "NotificationTemplate")
	if Template then
		Template.Visible = false
	end
	Remotes.Get("Notify").OnClientEvent:Connect(NotificationController.Show)
end

return NotificationController
