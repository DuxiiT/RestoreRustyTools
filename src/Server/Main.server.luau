-- Server entry point. Init registers handlers and listeners in dependency order; Start begins
-- loops and player handling once every service is ready.
local Services = script.Parent.Services

local OrderedServices = {
	require(Services.ContentRegistry),
	require(Services.PlayerDataService),
	require(Services.NetworkService),
	require(Services.StateReplicator),
	require(Services.WorkshopService),
	require(Services.RestorationService),
	require(Services.RollService),
	require(Services.SalesService),
	require(Services.DisplayService),
	require(Services.InventoryService),
	require(Services.SkillTreeService),
	require(Services.CollectionIndexService),
	require(Services.TutorialService),
	require(Services.ScheduleService),
	require(Services.CommissionService),
	require(Services.AutoRollService),
}

for _, Service in OrderedServices do
	if Service.Init then
		Service.Init()
	end
end

for _, Service in OrderedServices do
	if Service.Start then
		Service.Start()
	end
end
