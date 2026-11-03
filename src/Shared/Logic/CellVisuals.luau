-- Maps a cell's coverage value to its visibility. The designer's transparency is the fully
-- corroded look; decals and textures on the cell fade with it.
local CellVisuals = {}

local BaseAttribute = "BaseTransparency"

local function BaseTransparency(Instance)
	local Base = Instance:GetAttribute(BaseAttribute)
	if Base == nil then
		Base = Instance.Transparency
		Instance:SetAttribute(BaseAttribute, Base)
	end
	return Base
end

local function VisibleTransparency(Base: number, Value: number): number
	if Value <= 0.01 then
		return 1
	end
	return 1 - (1 - Base) * Value
end

-- Records base transparency for a part and its surface images. Call once before any Apply.
function CellVisuals.Prepare(Part: BasePart)
	BaseTransparency(Part)
	for _, Child in Part:GetChildren() do
		if Child:IsA("Decal") then
			BaseTransparency(Child)
		end
	end
end

function CellVisuals.Apply(Part: BasePart, Value: number)
	Part.Transparency = VisibleTransparency(BaseTransparency(Part), Value)
	for _, Child in Part:GetChildren() do
		if Child:IsA("Decal") then
			Child.Transparency = VisibleTransparency(BaseTransparency(Child), Value)
		end
	end
end

return CellVisuals
