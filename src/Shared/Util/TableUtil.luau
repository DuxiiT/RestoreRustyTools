local TableUtil = {}

function TableUtil.DeepCopy(Source)
	if typeof(Source) ~= "table" then
		return Source
	end
	local Copy = {}
	for Key, Value in Source do
		Copy[Key] = TableUtil.DeepCopy(Value)
	end
	return Copy
end

-- Fills keys missing from Target with copies from Template. Existing values are never replaced.
function TableUtil.FillMissing(Target, Template)
	for Key, Value in Template do
		if Target[Key] == nil then
			Target[Key] = TableUtil.DeepCopy(Value)
		elseif typeof(Value) == "table" and typeof(Target[Key]) == "table" and next(Value) ~= nil then
			TableUtil.FillMissing(Target[Key], Value)
		end
	end
	return Target
end

function TableUtil.ToSet(List)
	local Set = {}
	for _, Value in List do
		Set[Value] = true
	end
	return Set
end

function TableUtil.CountKeys(Dictionary): number
	local Count = 0
	for _ in Dictionary do
		Count += 1
	end
	return Count
end

return TableUtil
