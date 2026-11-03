-- Assigns each player a workshop plot (tagged "WorkshopPlot" in Studio), releases it on leave,
-- and owns every physical object placed in it: the active item, tray, displays and cosmetics.
-- Only this server code writes to plots, so other players can never modify them.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ContentConfig = require(Shared.Config.ContentConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local StageDefinitions = require(Shared.Config.StageDefinitions)
local WorkshopConfig = require(Shared.Config.WorkshopConfig)
local VariantDefinitions = require(Shared.Config.VariantDefinitions)
local RarityConfig = require(Shared.Config.RarityConfig)
local ItemCatalog = require(Shared.Content.ItemCatalog)
local Signal = require(Shared.Util.Signal)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local ContentRegistry = require(script.Parent.ContentRegistry)
local StationService = require(script.Parent.StationService)

local WorkshopService = {}

WorkshopService.PlotTag = "WorkshopPlot"
WorkshopService.Assigned = Signal.New() -- (Player, Plot, Profile)

local PlotOwners = {}
local PlayerPlots = {}
local RuntimeState = {}

local function GetRuntimeFolder(Plot: Instance): Folder
	local Folder = Plot:FindFirstChild("Runtime")
	if not Folder then
		Folder = Instance.new("Folder")
		Folder.Name = "Runtime"
		Folder.Parent = Plot
	end
	return Folder
end

local function PrepareParts(Model: Model)
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.Anchored = true
			Descendant.CanCollide = false
			Descendant.CanTouch = false
			Descendant.CanQuery = true
		end
	end
end

local function ScaleForMount(Model: Model, Mount: string)
	local _, Size = Model:GetBoundingBox()
	local Largest = math.max(Size.X, Size.Y, Size.Z)
	if Largest > 0 then
		Model:ScaleTo(Model:GetScale() * ContentConfig.MountTargetExtent[Mount] / Largest)
	end
end

-- Rests the model's bounding box on top of the anchor part, keeping the anchor's facing.
local function PlaceOnAnchor(Model: Model, Anchor: BasePart)
	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	local PivotOffset = BoxCFrame:ToObjectSpace(Model:GetPivot())
	local TargetBox = Anchor.CFrame * CFrame.new(0, Anchor.Size.Y / 2 + BoxSize.Y / 2, 0)
	Model:PivotTo(TargetBox * PivotOffset)
end

local function SetPersistentFor(Model: Model, Player: Player)
	Model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	Model:AddPersistentPlayer(Player)
end

function WorkshopService.GetPlot(Player: Player)
	return PlayerPlots[Player]
end

function WorkshopService.GetAnchor(Player: Player, Mount: string): BasePart?
	local Plot = PlayerPlots[Player]
	if not Plot then
		return nil
	end
	if Mount == "Stand" then
		local Stand = Plot:FindFirstChild("StandAnchor")
		if Stand then
			return Stand
		end
	end
	return Plot:FindFirstChild("BenchAnchor")
end

function WorkshopService.IsNearOwnWorkshop(Player: Player): boolean
	local Plot = PlayerPlots[Player]
	local Position = StationService.GetCharacterPosition(Player)
	if not Plot or not Position then
		return false
	end
	return (Plot:GetPivot().Position - Position).Magnitude <= WorkshopConfig.PlotInteractionRadius
end

function WorkshopService.IsNearBench(Player: Player, Mount: string): boolean
	local Anchor = WorkshopService.GetAnchor(Player, Mount)
	local Position = StationService.GetCharacterPosition(Player)
	if not Anchor or not Position then
		return false
	end
	return (Anchor.Position - Position).Magnitude <= EconomyConfig.BenchRange
end

-- Places a working copy of the item on the bench or project stand. Returns the model.
function WorkshopService.PlaceActiveItem(Player: Player, Item): Model?
	local Definition = ItemCatalog.Get(Item.TypeId)
	local Template = ContentRegistry.GetModel(Item.TypeId)
	local Anchor = WorkshopService.GetAnchor(Player, Definition.Mount)
	if not Template or not Anchor then
		return nil
	end
	WorkshopService.ClearActiveItem(Player)

	local Model = Template:Clone()
	Model.Name = "ActiveItem"
	PrepareParts(Model)
	ScaleForMount(Model, Definition.Mount)
	PlaceOnAnchor(Model, Anchor)
	Model:SetAttribute("ItemUid", Item.Uid)
	Model:SetAttribute("TypeId", Item.TypeId)
	Model:SetAttribute("OwnerUserId", Player.UserId)
	SetPersistentFor(Model, Player)
	Model.Parent = GetRuntimeFolder(PlayerPlots[Player])
	RuntimeState[Player].ActiveModel = Model
	return Model
end

function WorkshopService.ClearActiveItem(Player: Player)
	local State = RuntimeState[Player]
	if State and State.ActiveModel then
		State.ActiveModel:Destroy()
		State.ActiveModel = nil
	end
end

-- Detaches variant folders: owned-but-unrevealed ones are returned (to be parented back on
-- reveal) and variants the item does not have are destroyed. Unrevealed folders never
-- replicate, so clients cannot peek at hidden features.
function WorkshopService.SplitVariants(Model: Model, Item)
	local Hidden = {}
	local Folder = Model:FindFirstChild(ContentConfig.VariantsFolderName)
	if not Folder then
		return Hidden
	end
	for _, Child in Folder:GetChildren() do
		if table.find(Item.RevealedTraits, Child.Name) then
			continue
		elseif table.find(Item.Traits, Child.Name) then
			Hidden[Child.Name] = Child
			Child.Parent = nil
		else
			Child:Destroy()
		end
	end
	return Hidden
end

-- A finished-look copy: corrosion layers removed, only the item's own variants kept.
function WorkshopService.CreateRestoredModel(Item): Model?
	local Template = ContentRegistry.GetModel(Item.TypeId)
	if not Template then
		return nil
	end
	local Model = Template:Clone()
	for _, Stage in StageDefinitions do
		local Layer = Model:FindFirstChild(Stage.LayerName)
		if Layer then
			Layer:Destroy()
		end
	end
	local Variants = Model:FindFirstChild(ContentConfig.VariantsFolderName)
	if Variants then
		for _, Child in Variants:GetChildren() do
			if not table.find(Item.RevealedTraits, Child.Name) then
				Child:Destroy()
			end
		end
	end
	PrepareParts(Model)
	ScaleForMount(Model, "Bench")
	return Model
end

local function PublicItemAttributes(Model: Model, Item, OwnerName: string)
	local Definition = ItemCatalog.Get(Item.TypeId)
	local TraitNames = {}
	for _, VariantId in Item.RevealedTraits do
		table.insert(TraitNames, VariantDefinitions[VariantId].Name)
	end
	Model:SetAttribute("ItemName", Definition.Name)
	Model:SetAttribute("Rarity", RarityConfig.Tiers[Definition.Rarity].Label)
	Model:SetAttribute("Traits", table.concat(TraitNames, ", "))
	Model:SetAttribute("OwnerName", OwnerName)
end

local function AttachInspectPrompt(Model: Model)
	local Assets = ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
	local Prompts = Assets and Assets:FindFirstChild("Prompts")
	local Template = Prompts and Prompts:FindFirstChild("InspectPrompt")
	local Host = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)
	if Template and Host then
		Template:Clone().Parent = Host
	end
end

function WorkshopService.RefreshTray(Player: Player, Profile)
	local State = RuntimeState[Player]
	local Plot = PlayerPlots[Player]
	if not State or not Plot then
		return
	end
	local Latest
	for _, Item in Profile.Items do
		if Item.State == "Tray" and (not Latest or (Item.CompletedAt or 0) > (Latest.CompletedAt or 0)) then
			Latest = Item
		end
	end
	if State.TrayModel and State.TrayModel:GetAttribute("ItemUid") == (Latest and Latest.Uid) then
		return
	end
	if State.TrayModel then
		State.TrayModel:Destroy()
		State.TrayModel = nil
	end
	local Anchor = Plot:FindFirstChild("TrayAnchor")
	local Model = Latest and Anchor and WorkshopService.CreateRestoredModel(Latest)
	if Model then
		Model.Name = "TrayItem"
		PlaceOnAnchor(Model, Anchor)
		Model:SetAttribute("ItemUid", Latest.Uid)
		PublicItemAttributes(Model, Latest, Player.DisplayName)
		Model.Parent = GetRuntimeFolder(Plot)
		State.TrayModel = Model
	end
end

function WorkshopService.GetDisplaySlotIds(Player: Player)
	local Plot = PlayerPlots[Player]
	local Folder = Plot and Plot:FindFirstChild("DisplaySlots")
	local SlotIds = {}
	if Folder then
		for _, Slot in Folder:GetChildren() do
			if Slot:IsA("BasePart") then
				table.insert(SlotIds, Slot.Name)
			end
		end
	end
	table.sort(SlotIds)
	return SlotIds
end

function WorkshopService.RefreshDisplays(Player: Player, Profile)
	local State = RuntimeState[Player]
	local Plot = PlayerPlots[Player]
	local Folder = Plot and Plot:FindFirstChild("DisplaySlots")
	if not State or not Folder then
		return
	end
	for SlotId, Model in State.DisplayModels do
		if Profile.Workshop.Displays[SlotId] ~= Model:GetAttribute("ItemUid") then
			Model:Destroy()
			State.DisplayModels[SlotId] = nil
		end
	end
	for SlotId, Uid in Profile.Workshop.Displays do
		local Slot = Folder:FindFirstChild(SlotId)
		local Item = Profile.Items[Uid]
		if State.DisplayModels[SlotId] or not Slot or not Item then
			continue
		end
		local Model = WorkshopService.CreateRestoredModel(Item)
		if Model then
			Model.Name = `Display_{SlotId}`
			PlaceOnAnchor(Model, Slot)
			Model:SetAttribute("ItemUid", Uid)
			PublicItemAttributes(Model, Item, Player.DisplayName)
			AttachInspectPrompt(Model)
			Model.Parent = GetRuntimeFolder(Plot)
			State.DisplayModels[SlotId] = Model
		end
	end
end

function WorkshopService.GetDefaultCosmetic(Category: string): string?
	for _, Option in WorkshopConfig.Customization[Category].Options do
		if Option.Default then
			return Option.Id
		end
	end
	return nil
end

function WorkshopService.RefreshCustomization(Player: Player, Profile)
	local State = RuntimeState[Player]
	local Plot = PlayerPlots[Player]
	local Anchors = Plot and Plot:FindFirstChild("CustomizationAnchors")
	local Assets = ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
	local Library = Assets and Assets:FindFirstChild("Customization")
	if not State or not Anchors or not Library then
		return
	end
	for Category in WorkshopConfig.Customization do
		local OptionId = Profile.Workshop.Customization[Category] or WorkshopService.GetDefaultCosmetic(Category)
		local Current = State.CosmeticModels[Category]
		if Current and Current.Name == OptionId then
			continue
		end
		if Current then
			Current:Destroy()
			State.CosmeticModels[Category] = nil
		end
		local Anchor = Anchors:FindFirstChild(Category)
		local CategoryFolder = Library:FindFirstChild(Category)
		local Template = CategoryFolder and OptionId and CategoryFolder:FindFirstChild(OptionId)
		if Anchor and Template then
			local Model = Template:Clone()
			Model.Name = OptionId
			Model:PivotTo(Anchor.CFrame)
			Model.Parent = GetRuntimeFolder(Plot)
			State.CosmeticModels[Category] = Model
		end
	end
end

local function SetOwnerSign(Plot: Instance, Text: string)
	local Sign = Plot:FindFirstChild("OwnerSign")
	local Label = Sign and Sign:FindFirstChild("OwnerLabel", true)
	if Label and Label:IsA("TextLabel") then
		Label.Text = Text
	end
end

local function MoveCharacterToPlot(Player: Player, Plot: Instance)
	local Spawn = Plot:FindFirstChild("OwnerSpawn")
	if not Spawn or not Spawn:IsA("BasePart") then
		return
	end
	if Spawn:IsA("SpawnLocation") then
		Player.RespawnLocation = Spawn
	end
	local Character = Player.Character
	if Character then
		Character:PivotTo(Spawn.CFrame + Vector3.new(0, 4, 0))
	end
end

local function OnProfileLoaded(Player: Player, Profile)
	local ChosenPlot
	for _, Plot in CollectionService:GetTagged(WorkshopService.PlotTag) do
		if not PlotOwners[Plot] then
			ChosenPlot = Plot
			break
		end
	end
	if not ChosenPlot then
		warn("[WorkshopService] No free workshop plot. Add one tagged WorkshopPlot per server slot.")
		-- In Studio the map may not exist yet; keep the tester in so menus and rolling can be checked.
		if not RunService:IsStudio() then
			Player:Kick("Every workshop on this server is taken. Please join another server.")
		end
		return
	end

	PlotOwners[ChosenPlot] = Player
	PlayerPlots[Player] = ChosenPlot
	RuntimeState[Player] = { DisplayModels = {}, CosmeticModels = {} }
	ChosenPlot:SetAttribute("OwnerUserId", Player.UserId)
	ChosenPlot:SetAttribute("OwnerName", Player.DisplayName)
	SetOwnerSign(ChosenPlot, `{Player.DisplayName}'s Workshop`)
	MoveCharacterToPlot(Player, ChosenPlot)

	WorkshopService.RefreshTray(Player, Profile)
	WorkshopService.RefreshDisplays(Player, Profile)
	WorkshopService.RefreshCustomization(Player, Profile)
	WorkshopService.Assigned:Fire(Player, ChosenPlot, Profile)
end

local function OnProfileReleasing(Player: Player)
	local Plot = PlayerPlots[Player]
	if not Plot then
		return
	end
	GetRuntimeFolder(Plot):ClearAllChildren()
	Plot:SetAttribute("OwnerUserId", nil)
	Plot:SetAttribute("OwnerName", nil)
	SetOwnerSign(Plot, "Available Workshop")
	PlotOwners[Plot] = nil
	PlayerPlots[Player] = nil
	RuntimeState[Player] = nil
end

function WorkshopService.Init()
	local PlotCount = #CollectionService:GetTagged(WorkshopService.PlotTag)
	local MaxPlayers = game:GetService("Players").MaxPlayers
	if PlotCount < MaxPlayers then
		warn(`[WorkshopService] {PlotCount} plots for {MaxPlayers} max players; extra players cannot get a workshop.`)
	end
	GameEvents.ProfileLoaded:Connect(OnProfileLoaded)
	GameEvents.ProfileReleasing:Connect(OnProfileReleasing)
end

return WorkshopService
