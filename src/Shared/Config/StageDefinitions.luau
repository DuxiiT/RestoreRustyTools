-- Each stage is a coverage layer in the item model (a folder named LayerName holding cell parts).
-- EffortWeight splits an item's TargetSeconds between its stages.
-- ReferenceTool is the tool TargetSeconds is calibrated against.
return {
	Scrape = {
		Id = "Scrape",
		DisplayName = "Scrape",
		LayerName = "Layer_Scrape",
		EffortWeight = 0.8,
		ReferenceTool = "Scraper",
		Description = "Knock off thick, flaking buildup before finer work.",
	},
	Treat = {
		Id = "Treat",
		DisplayName = "Treat",
		LayerName = "Layer_Treat",
		EffortWeight = 0.35,
		ReferenceTool = "TreatmentBrush",
		Description = "Coat heavy corrosion with rust remover so it loosens.",
	},
	Grind = {
		Id = "Grind",
		DisplayName = "Grind",
		LayerName = "Layer_Grind",
		EffortWeight = 1.0,
		ReferenceTool = "RotaryGrinder",
		Description = "Grind away deep pitting and heavy corrosion.",
	},
	Brush = {
		Id = "Brush",
		DisplayName = "Brush",
		LayerName = "Layer_Brush",
		EffortWeight = 1.0,
		ReferenceTool = "WireBrush",
		Description = "Scrub loose rust off to reveal the metal underneath.",
	},
	Detail = {
		Id = "Detail",
		DisplayName = "Detail",
		LayerName = "Layer_Detail",
		EffortWeight = 0.6,
		ReferenceTool = "DetailPick",
		Description = "Clean grooves, engravings and tight corners.",
	},
	Polish = {
		Id = "Polish",
		DisplayName = "Polish",
		LayerName = "Layer_Polish",
		EffortWeight = 0.5,
		ReferenceTool = "PolishCloth",
		Description = "Buff the surface to bring back its original finish.",
	},
}
