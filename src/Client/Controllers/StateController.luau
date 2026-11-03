-- Holds the latest server snapshot of this player's state. Presentation reads from here and
-- never decides outcomes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)

local StateController = {}

StateController.Changed = Signal.New()
StateController.State = nil

local ServerTimeOffset = 0
local AvailableItems = {}

function StateController.Get()
	return StateController.State
end

function StateController.ServerNow(): number
	return os.time() + ServerTimeOffset
end

function StateController.IsItemAvailable(ItemId: string): boolean
	return AvailableItems[ItemId] == true
end

function StateController.OwnsTool(ToolId: string): boolean
	local State = StateController.State
	return State ~= nil and table.find(State.Tools, ToolId) ~= nil
end

function StateController.HasFeature(Feature: string): boolean
	local State = StateController.State
	return State ~= nil and table.find(State.Features, Feature) ~= nil
end

function StateController.HasPool(PoolId: string): boolean
	local State = StateController.State
	return State ~= nil and table.find(State.Pools, PoolId) ~= nil
end

-- Count of items that take a storage slot (everything except displayed items).
function StateController.StoredCount(): number
	local Count = 0
	for _, Item in StateController.State.Items do
		if Item.State ~= "Display" then
			Count += 1
		end
	end
	return Count
end

function StateController.Init()
	local ContentState = ReplicatedStorage:WaitForChild("ContentState")
	local function ReadAvailability()
		local Raw = ContentState:GetAttribute("AvailableItems") or ""
		AvailableItems = TableUtil.ToSet(string.split(Raw, ","))
	end
	ReadAvailability()
	ContentState:GetAttributeChangedSignal("AvailableItems"):Connect(ReadAvailability)

	Remotes.Get("StateSnapshot").OnClientEvent:Connect(function(State)
		ServerTimeOffset = State.ServerTime - os.time()
		StateController.State = State
		StateController.Changed:Fire(State)
	end)
end

return StateController
