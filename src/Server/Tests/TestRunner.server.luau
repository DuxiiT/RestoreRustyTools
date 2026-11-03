-- Runs every *.spec module in this folder when playing in Studio with the workspace attribute
-- RunTests set to true. Specs return function(Test, Expect).
local RunService = game:GetService("RunService")

if not RunService:IsStudio() or workspace:GetAttribute("RunTests") ~= true then
	return
end

local Passed, Failed = 0, 0
local Failures = {}

local function FormatValue(Value)
	return if typeof(Value) == "string" then `"{Value}"` else tostring(Value)
end

local Expect = {}

function Expect.Equal(Actual, Expected, Label: string?)
	if Actual ~= Expected then
		error(`{Label or "values"}: expected {FormatValue(Expected)}, got {FormatValue(Actual)}`, 2)
	end
end

function Expect.True(Condition, Label: string?)
	if not Condition then
		error(`{Label or "condition"} was not true`, 2)
	end
end

function Expect.Near(Actual: number, Expected: number, Tolerance: number, Label: string?)
	if math.abs(Actual - Expected) > Tolerance then
		error(`{Label or "value"}: expected {Expected} ± {Tolerance}, got {Actual}`, 2)
	end
end

for _, Module in script.Parent:GetChildren() do
	if not Module:IsA("ModuleScript") or not string.match(Module.Name, "%.spec$") then
		continue
	end
	local Spec = require(Module)
	Spec(function(Name: string, Body)
		local Success, ErrorMessage = pcall(Body)
		if Success then
			Passed += 1
		else
			Failed += 1
			table.insert(Failures, `[{Module.Name}] {Name}: {ErrorMessage}`)
		end
	end, Expect)
end

print(`[Tests] {Passed} passed, {Failed} failed`)
for _, Failure in Failures do
	warn(Failure)
end
