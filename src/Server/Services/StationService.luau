-- Proximity checks against tagged world stations (CollectionService tags placed in Studio).
-- If the map has no station with a tag yet, the check passes so the loop stays playable
-- while the map is being built; a warning is printed once.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)

local StationService = {}

StationService.Tags = table.freeze({
	SalvageDepot = "SalvageDepot",
	Buyer = "Buyer",
	SkillBoard = "SkillBoard",
	CollectionGallery = "CollectionGallery",
	CommissionBoard = "CommissionBoard",
	DeliveryTruck = "DeliveryTruck",
})

local WarnedTags = {}

function StationService.GetPosition(Instance: Instance): Vector3?
	if Instance:IsA("BasePart") then
		return Instance.Position
	elseif Instance:IsA("Model") then
		return Instance:GetPivot().Position
	elseif Instance:IsA("Attachment") then
		return Instance.WorldPosition
	end
	return nil
end

function StationService.GetCharacterPosition(Player: Player): Vector3?
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	return Root and Root.Position
end

function StationService.IsNear(Player: Player, Tag: string, Range: number?): boolean
	local Stations = CollectionService:GetTagged(Tag)
	if #Stations == 0 then
		if not WarnedTags[Tag] then
			WarnedTags[Tag] = true
			warn(`[StationService] No instance tagged {Tag}; proximity checks for it are skipped.`)
		end
		return true
	end
	local Position = StationService.GetCharacterPosition(Player)
	if not Position then
		return false
	end
	local MaxDistance = Range or EconomyConfig.StationRange
	for _, Station in Stations do
		local StationPosition = StationService.GetPosition(Station)
		if StationPosition and (StationPosition - Position).Magnitude <= MaxDistance then
			return true
		end
	end
	return false
end

return StationService
