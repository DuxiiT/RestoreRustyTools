-- Validates configuration and item models at startup and publishes which items are available.
-- An item is available only when its model exists with a cell layer for every stage, so rolls
-- can never hand out content that cannot be restored.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ContentConfig = require(Shared.Config.ContentConfig)
local StageDefinitions = require(Shared.Config.StageDefinitions)
local SalvagePools = require(Shared.Config.SalvagePools)
local CollectionSets = require(Shared.Config.CollectionSets)
local SkillTree = require(Shared.Config.SkillTree)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local SkillTreeRules = require(Shared.Logic.SkillTreeRules)

local ContentRegistry = {}

ContentRegistry.StateFolderName = "ContentState"
ContentRegistry.AvailableAttribute = "AvailableItems"

local Available = {}

local function GetModelsFolder()
	local Assets = ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
	return Assets and Assets:FindFirstChild(ContentConfig.ItemModelsFolderName)
end

local function LayerHasCells(Model: Model, StageId: string): boolean
	local Layer = Model:FindFirstChild(StageDefinitions[StageId].LayerName)
	if not Layer then
		return false
	end
	for _, Descendant in Layer:GetDescendants() do
		if Descendant:IsA("BasePart") then
			return true
		end
	end
	return false
end

local function ValidateModel(Definition, ModelsFolder)
	local Model = ModelsFolder and ModelsFolder:FindFirstChild(Definition.ModelName)
	if not Model or not Model:IsA("Model") then
		return false, "missing model"
	end
	for _, StageId in Definition.Stages do
		if not LayerHasCells(Model, StageId) then
			return false, `missing cells in {StageDefinitions[StageId].LayerName}`
		end
	end
	return true, nil
end

local function ValidateConfiguration()
	local Problems = SkillTreeRules.Validate()
	for PoolId, Pool in SalvagePools do
		if Pool.UnlockNode and not SkillTree[Pool.UnlockNode] then
			table.insert(Problems, `pool {PoolId} unlock node {Pool.UnlockNode} does not exist`)
		end
	end
	if #Problems > 0 then
		error("[ContentRegistry] Configuration errors:\n" .. table.concat(Problems, "\n"))
	end
end

function ContentRegistry.Init()
	ValidateConfiguration()

	local ModelsFolder = GetModelsFolder()
	local AvailableList = {}
	local Missing = {}
	for _, ItemId in ItemCatalog.GetOrderedIds() do
		local Valid, Reason = ValidateModel(ItemCatalog.Get(ItemId), ModelsFolder)
		if Valid then
			Available[ItemId] = true
			table.insert(AvailableList, ItemId)
		else
			table.insert(Missing, `{ItemId} ({Reason})`)
		end
	end

	for SetId, Set in CollectionSets do
		for _, ItemId in Set.Items do
			if not ItemCatalog.Exists(ItemId) then
				warn(`[ContentRegistry] Set {SetId} lists {ItemId}, which is not in an enabled phase.`)
			end
		end
	end

	if #Missing > 0 then
		warn(
			`[ContentRegistry] {#AvailableList} items available, {#Missing} unavailable until their models are built:\n{table.concat(
				Missing,
				", "
			)}`
		)
	end
	if #AvailableList == 0 and not RunService:IsStudio() then
		warn("[ContentRegistry] No item models found in ReplicatedStorage.Assets.ItemModels; nothing can be rolled.")
	end

	local StateFolder = Instance.new("Folder")
	StateFolder.Name = ContentRegistry.StateFolderName
	StateFolder:SetAttribute(ContentRegistry.AvailableAttribute, table.concat(AvailableList, ","))
	StateFolder.Parent = ReplicatedStorage
end

function ContentRegistry.IsAvailable(ItemId: string): boolean
	return Available[ItemId] == true
end

function ContentRegistry.GetModel(ItemId: string): Model?
	local Definition = ItemCatalog.Get(ItemId)
	local ModelsFolder = GetModelsFolder()
	return Definition and ModelsFolder and ModelsFolder:FindFirstChild(Definition.ModelName)
end

return ContentRegistry
