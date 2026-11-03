-- Cosmetic options. Models live in ReplicatedStorage.Assets.Customization.<Category>.<OptionId>
-- and are placed at the plot's Customization/<Category> anchor. Cosmetics never add an
-- active restoration slot.
return {
	PlotInteractionRadius = 60,
	Customization = {
		Lamp = {
			DisplayName = "Lamps",
			Options = {
				{ Id = "TaskLamp", Name = "Yellow Task Lamp", Price = 0, Default = true },
				{ Id = "BrassLamp", Name = "Brass Lamp", Price = 600 },
				{ Id = "Floodlight", Name = "Workshop Floodlight", Price = 1500 },
			},
		},
		Floor = {
			DisplayName = "Floors",
			Options = {
				{ Id = "Concrete", Name = "Worn Concrete", Price = 0, Default = true },
				{ Id = "Planks", Name = "Timber Planks", Price = 800 },
				{ Id = "Checker", Name = "Checker Tile", Price = 2000 },
			},
		},
		Sign = {
			DisplayName = "Wall Signs",
			Options = {
				{ Id = "PaintedBoard", Name = "Painted Board", Price = 0, Default = true },
				{ Id = "EnamelSign", Name = "Enamel Sign", Price = 1000 },
				{ Id = "NeonSign", Name = "Neon Sign", Price = 3500 },
			},
		},
		Shelving = {
			DisplayName = "Shelving",
			Options = {
				{ Id = "MetalShelves", Name = "Metal Shelves", Price = 0, Default = true },
				{ Id = "OakShelves", Name = "Oak Shelves", Price = 1200 },
			},
		},
		Bench = {
			DisplayName = "Benches",
			Options = {
				{ Id = "BasicBench", Name = "Basic Bench", Price = 0, Default = true },
				{ Id = "SteelBench", Name = "Steel Bench", Price = 2500 },
				{ Id = "MastersBench", Name = "Master's Bench", Price = 8000 },
			},
		},
		Cabinet = {
			DisplayName = "Cabinets",
			Options = {
				{ Id = "None", Name = "No Cabinet", Price = 0, Default = true },
				{ Id = "GlassCabinet", Name = "Glass Cabinet", Price = 3000 },
			},
		},
	},
}
