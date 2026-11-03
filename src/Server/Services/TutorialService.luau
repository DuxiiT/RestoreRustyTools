-- Action-based tutorial. Steps advance only when the matching gameplay event happens, and
-- progress is saved. Skipping keeps every starter resource.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local TutorialSteps = require(Shared.Config.TutorialSteps)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local GameEvents = require(Server.GameEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)
local StateReplicator = require(script.Parent.StateReplicator)
local NetworkService = require(script.Parent.NetworkService)

local TutorialService = {}

local function Advance(Player: Player, EventName: string)
	local Profile = PlayerDataService.Get(Player)
	if not Profile or Profile.Tutorial.Completed then
		return
	end
	local Step = TutorialSteps[Profile.Tutorial.Step]
	if not Step or Step.Event ~= EventName then
		return
	end
	Profile.Tutorial.Step += 1
	if Profile.Tutorial.Step > #TutorialSteps then
		Profile.Tutorial.Completed = true
		NetworkService.Notify(Player, "Tutorial complete. The workshop is yours!", "Info")
	end
	StateReplicator.MarkDirty(Player)
end

function TutorialService.Skip(Player: Player)
	local Profile = PlayerDataService.Get(Player)
	Profile.Tutorial.Completed = true
	Profile.Tutorial.Skipped = true
	StateReplicator.MarkDirty(Player)
	return Result.Ok({})
end

function TutorialService.Init()
	local Connected = {}
	for _, Step in TutorialSteps do
		if not Connected[Step.Event] then
			Connected[Step.Event] = true
			assert(GameEvents[Step.Event], `Tutorial step {Step.Id} uses unknown event {Step.Event}`)
			GameEvents[Step.Event]:Connect(function(Player)
				Advance(Player, Step.Event)
			end)
		end
	end
	NetworkService.Handle("SkipTutorial", TutorialService.Skip)
end

return TutorialService
