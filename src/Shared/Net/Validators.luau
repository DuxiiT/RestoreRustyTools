-- Argument validators for remote contracts. Every client argument is untrusted.
local Validators = {}

local function IsFinite(Value: number): boolean
	return Value == Value and Value ~= math.huge and Value ~= -math.huge
end

function Validators.Identifier()
	return function(Value)
		return typeof(Value) == "string" and #Value > 0 and #Value <= 64 and string.match(Value, "^[%w_]+$") ~= nil
	end
end

function Validators.ItemUid()
	return function(Value)
		return typeof(Value) == "string" and #Value <= 40 and string.match(Value, "^%d+%-%d+$") ~= nil
	end
end

function Validators.Boolean()
	return function(Value)
		return typeof(Value) == "boolean"
	end
end

function Validators.Integer(Minimum: number, Maximum: number)
	return function(Value)
		return typeof(Value) == "number" and IsFinite(Value) and Value % 1 == 0 and Value >= Minimum and Value <= Maximum
	end
end

function Validators.Number(Minimum: number, Maximum: number)
	return function(Value)
		return typeof(Value) == "number" and IsFinite(Value) and Value >= Minimum and Value <= Maximum
	end
end

function Validators.OneOf(Options)
	local Set = {}
	for _, Option in Options do
		Set[Option] = true
	end
	return function(Value)
		return Set[Value] == true
	end
end

function Validators.AnyOf(...)
	local Inner = { ... }
	return function(Value)
		for _, Validator in Inner do
			if Validator(Value) then
				return true
			end
		end
		return false
	end
end

function Validators.Optional(Inner)
	return function(Value)
		return Value == nil or Inner(Value)
	end
end

function Validators.Vector3Array(MaxCount: number, MaxMagnitude: number)
	return function(Value)
		if typeof(Value) ~= "table" or #Value == 0 or #Value > MaxCount then
			return false
		end
		local Count = 0
		for _, Point in Value do
			Count += 1
			if typeof(Point) ~= "Vector3" or not IsFinite(Point.X) or not IsFinite(Point.Y) or not IsFinite(Point.Z) then
				return false
			end
			if Point.Magnitude > MaxMagnitude then
				return false
			end
		end
		return Count == #Value
	end
end

return Validators
