-- Client entry point. Controllers only present state and send requests; the server decides
-- every outcome.
local Controllers = script.Parent.Controllers

local OrderedControllers = {
	require(Controllers.StateController),
	require(Controllers.PanelController),
	require(Controllers.NotificationController),
	require(Controllers.FeedbackController),
	require(Controllers.BenchCameraController),
	require(Controllers.RestorationController),
	require(Controllers.HudController),
	require(Controllers.RollController),
	require(Controllers.InventoryController),
	require(Controllers.ResultController),
	require(Controllers.SkillTreeController),
	require(Controllers.CollectionController),
	require(Controllers.TutorialController),
	require(Controllers.CommissionController),
	require(Controllers.WorkshopController),
	require(Controllers.SettingsController),
}

for _, Controller in OrderedControllers do
	if Controller.Init then
		Controller.Init()
	end
end

for _, Controller in OrderedControllers do
	if Controller.Start then
		task.spawn(Controller.Start)
	end
end
