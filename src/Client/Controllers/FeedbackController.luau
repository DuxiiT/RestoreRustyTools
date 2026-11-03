-- One-shot sounds and celebration effects from ReplicatedStorage.Assets, respecting the
-- player's sound and reduced-effects settings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentConfig = require(ReplicatedStorage.Shared.Config.ContentConfig)
local StateController = require(script.Parent.StateController)

local FeedbackController = {}

local function FindAsset(FolderName: string, Name: string)
	local Assets = ReplicatedStorage:FindFirstChild(ContentConfig.AssetsFolderName)
	local Folder = Assets and Assets:FindFirstChild(FolderName)
	return Folder and Folder:FindFirstChild(Name)
end

function FeedbackController.PlaySound(Name: string)
	local State = StateController.Get()
	local Template = FindAsset("Sounds", Name)
	if not Template or not Template:IsA("Sound") or (State and not State.Settings.SoundEffects) then
		return
	end
	local Sound = Template:Clone()
	Sound.Parent = workspace.CurrentCamera
	Sound:Play()
	Sound.Ended:Once(function()
		Sound:Destroy()
	end)
end

-- Briefly emits a designer-made effect (a part or attachment holding ParticleEmitters) at a position.
function FeedbackController.Burst(EffectName: string, Position: Vector3)
	local State = StateController.Get()
	local Template = FindAsset("Effects", EffectName)
	if not Template or not Template:IsA("BasePart") or (State and State.Settings.ReducedEffects) then
		return
	end
	local Effect = Template:Clone()
	Effect.Anchored = true
	Effect.CanCollide = false
	Effect.CFrame = CFrame.new(Position)
	Effect.Parent = workspace
	for _, Emitter in Effect:GetDescendants() do
		if Emitter:IsA("ParticleEmitter") then
			Emitter:Emit(Emitter:GetAttribute("BurstCount") or 20)
		end
	end
	task.delay(3, function()
		Effect:Destroy()
	end)
end

return FeedbackController
