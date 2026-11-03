-- Content phases match the numbered expansion tasks. Items also need a valid model in
-- ReplicatedStorage.Assets.ItemModels before they can appear in any pool, so enabling a
-- phase whose models are not built yet is safe; those items simply stay unavailable.
return {
	EnabledPhases = { 1, 2, 3, 4, 5, 6, 7 },

	-- Largest dimension, in studs, an item is scaled to when placed. Keeps tool radii consistent.
	MountTargetExtent = {
		Bench = 3.5,
		Stand = 7,
	},

	AssetsFolderName = "Assets",
	ItemModelsFolderName = "ItemModels",
	VariantsFolderName = "Variants",
	CellSurfaceAttribute = "Surface",
	DefaultSurface = "Metal",
}
