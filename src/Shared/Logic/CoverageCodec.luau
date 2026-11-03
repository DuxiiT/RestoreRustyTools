-- Encodes per-cell coverage (0 = clean, 1 = fully corroded) as one printable character per
-- cell with 64 levels. Printable ASCII keeps it valid for DataStores and cheap to replicate.
local CoverageCodec = {}

local Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local MaxLevel = 63
local LevelByByte = {}
for Index = 1, #Alphabet do
	LevelByByte[string.byte(Alphabet, Index)] = Index - 1
end

CoverageCodec.Levels = MaxLevel

function CoverageCodec.Quantize(Value: number): number
	return math.clamp(math.floor(Value * MaxLevel + 0.5), 0, MaxLevel) / MaxLevel
end

function CoverageCodec.Encode(Values): string
	local Characters = table.create(#Values)
	for Index, Value in Values do
		local Level = math.clamp(math.floor(Value * MaxLevel + 0.5), 0, MaxLevel)
		Characters[Index] = string.sub(Alphabet, Level + 1, Level + 1)
	end
	return table.concat(Characters)
end

-- Returns nil if the string is malformed or does not match the expected cell count.
function CoverageCodec.Decode(Encoded: string, ExpectedCount: number?)
	if typeof(Encoded) ~= "string" then
		return nil
	end
	if ExpectedCount and #Encoded ~= ExpectedCount then
		return nil
	end
	local Values = table.create(#Encoded)
	for Index = 1, #Encoded do
		local Level = LevelByByte[string.byte(Encoded, Index)]
		if not Level then
			return nil
		end
		Values[Index] = Level / MaxLevel
	end
	return Values
end

return CoverageCodec
