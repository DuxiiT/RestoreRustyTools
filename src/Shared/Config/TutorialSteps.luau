-- Action-based steps. Each completes when its gameplay Event fires on the server.
-- Target is a CollectionService tag (or "ActiveItem") the client highlights.
return {
	{ Id = "PlaceStarter", Event = "JobStarted", Target = "WorkshopBench", Prompt = "Open your bench and place the rusty bolt." },
	{
		Id = "RestoreStarter",
		Event = "ItemCompleted",
		Target = "ActiveItem",
		Prompt = "Hold and drag across the bolt to scrub the rust away.",
	},
	{ Id = "SellStarter", Event = "ItemSold", Target = "WorkshopSellCounter", Prompt = "Sell your restored bolt." },
	{ Id = "BuyUpgrade", Event = "NodePurchased", Target = "SkillBoard", Prompt = "Open the skill board and buy Stiffer Bristles." },
	{
		Id = "RollItem",
		Event = "ItemRolled",
		Target = "SalvageDepot",
		Prompt = "Roll for a new find at the salvage depot. The scrap bin is free!",
	},
}
