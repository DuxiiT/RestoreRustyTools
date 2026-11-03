-- Stable orbit camera for the bench. PC: right-drag orbits, wheel zooms. Touch: two fingers
-- orbit and pinch to zoom, leaving one finger free for the tool. Character movement is
-- disabled while inspecting so input never fights walking.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BenchCameraController = {}

local RenderStepName = "BenchCamera"
local MouseOrbitSpeed = 0.008
local TouchOrbitSpeed = 0.006
local MinPitch, MaxPitch = math.rad(-80), math.rad(80)

local Camera = workspace.CurrentCamera
local Active = false
local Focus = Vector3.zero
local Yaw, Pitch, Distance = 0, math.rad(25), 6
local MinDistance, MaxDistance = 2, 12
local SavedCameraType
local Controls
local Connections = {}
local Touches = {}
local LastTouchCentroid, LastTouchSpread

local function GetControls()
	if not Controls then
		local PlayerModule = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		Controls = require(PlayerModule):GetControls()
	end
	return Controls
end

local function UpdateCamera()
	Camera.CFrame = CFrame.new(Focus) * CFrame.Angles(0, Yaw, 0) * CFrame.Angles(-Pitch, 0, 0) * CFrame.new(0, 0, Distance)
end

function BenchCameraController.Orbit(DeltaYaw: number, DeltaPitch: number)
	Yaw -= DeltaYaw
	Pitch = math.clamp(Pitch + DeltaPitch, MinPitch, MaxPitch)
end

function BenchCameraController.Zoom(Factor: number)
	Distance = math.clamp(Distance * Factor, MinDistance, MaxDistance)
end

function BenchCameraController.ActiveTouchCount(): number
	local Count = 0
	for _ in Touches do
		Count += 1
	end
	return Count
end

local function TouchGestureState()
	local Positions = {}
	for _, Position in Touches do
		table.insert(Positions, Position)
	end
	if #Positions < 2 then
		return nil, nil
	end
	return (Positions[1] + Positions[2]) / 2, (Positions[1] - Positions[2]).Magnitude
end

local function OnInputChanged(Input: InputObject, _Processed: boolean)
	if
		Input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	then
		BenchCameraController.Orbit(Input.Delta.X * MouseOrbitSpeed, Input.Delta.Y * MouseOrbitSpeed)
	elseif Input.UserInputType == Enum.UserInputType.MouseWheel then
		BenchCameraController.Zoom(if Input.Position.Z > 0 then 0.9 else 1.1)
	elseif Input.UserInputType == Enum.UserInputType.Touch and Touches[Input] then
		Touches[Input] = Vector2.new(Input.Position.X, Input.Position.Y)
		local Centroid, Spread = TouchGestureState()
		if Centroid and LastTouchCentroid then
			local Delta = Centroid - LastTouchCentroid
			BenchCameraController.Orbit(Delta.X * TouchOrbitSpeed, Delta.Y * TouchOrbitSpeed)
			if LastTouchSpread > 0 and Spread > 0 then
				BenchCameraController.Zoom(LastTouchSpread / Spread)
			end
		end
		LastTouchCentroid, LastTouchSpread = Centroid, Spread
	end
end

local function OnInputBegan(Input: InputObject, Processed: boolean)
	if Input.UserInputType == Enum.UserInputType.Touch and not Processed then
		Touches[Input] = Vector2.new(Input.Position.X, Input.Position.Y)
		LastTouchCentroid, LastTouchSpread = TouchGestureState()
	end
end

local function OnInputEnded(Input: InputObject)
	if Touches[Input] then
		Touches[Input] = nil
		LastTouchCentroid, LastTouchSpread = TouchGestureState()
	end
end

-- Extent is the item's largest dimension; zoom limits scale with it.
function BenchCameraController.Enter(FocusPosition: Vector3, FacingYaw: number, Extent: number)
	if Active then
		BenchCameraController.Exit()
	end
	Active = true
	Focus = FocusPosition
	Yaw = FacingYaw
	Pitch = math.rad(25)
	MinDistance = Extent * 0.9
	MaxDistance = Extent * 3.2
	Distance = Extent * 1.7
	SavedCameraType = Camera.CameraType
	Camera.CameraType = Enum.CameraType.Scriptable
	GetControls():Disable()
	Touches = {}

	table.insert(Connections, UserInputService.InputBegan:Connect(OnInputBegan))
	table.insert(Connections, UserInputService.InputChanged:Connect(OnInputChanged))
	table.insert(Connections, UserInputService.InputEnded:Connect(OnInputEnded))
	RunService:BindToRenderStep(RenderStepName, Enum.RenderPriority.Camera.Value + 1, UpdateCamera)
end

function BenchCameraController.Exit()
	if not Active then
		return
	end
	Active = false
	RunService:UnbindFromRenderStep(RenderStepName)
	for _, Connection in Connections do
		Connection:Disconnect()
	end
	Connections = {}
	Touches = {}
	Camera.CameraType = SavedCameraType or Enum.CameraType.Custom
	GetControls():Enable()
end

function BenchCameraController.IsActive(): boolean
	return Active
end

return BenchCameraController
