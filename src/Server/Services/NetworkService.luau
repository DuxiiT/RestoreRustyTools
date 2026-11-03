-- Creates every remote from RemoteContracts and guards each request with rate limiting,
-- argument validation, a loaded-profile check and a per-remote in-flight lock.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RemoteContracts = require(Shared.Net.RemoteContracts)
local Remotes = require(Shared.Net.Remotes)
local Result = require(Shared.Util.Result)

local Server = script.Parent.Parent
local RateLimiter = require(Server.Logic.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)

local NetworkService = {}

local RemoteInstances = {}
local Limiter = RateLimiter.New()
local InFlight = {}

local function ValidateArguments(Validators, ...): boolean
	if select("#", ...) > #Validators then
		return false
	end
	for Index, Validator in Validators do
		if not Validator((select(Index, ...))) then
			return false
		end
	end
	return true
end

local function DispatchRequest(Name: string, Contract, Handler, Player: Player, ...)
	if not Limiter:Allow(Player, Name, Contract.Rate) then
		return Result.Fail("You're doing that too quickly.", "RateLimited")
	end
	if not ValidateArguments(Contract.Args, ...) then
		return Result.Fail("That request wasn't valid.", "Invalid")
	end
	if not PlayerDataService.IsLoaded(Player) then
		return Result.Fail("Your workshop is still loading.", "Loading")
	end
	local Busy = InFlight[Player]
	if not Busy then
		Busy = {}
		InFlight[Player] = Busy
	end
	if Busy[Name] then
		return Result.Fail("Still working on your last request.", "Busy")
	end
	Busy[Name] = true
	local Success, Response = pcall(Handler, Player, ...)
	Busy[Name] = nil
	if not Success then
		warn(`[NetworkService] {Name} failed for {Player.Name}: {Response}`)
		return Result.Fail("Something went wrong. Please try again.", "Error")
	end
	return Response
end

function NetworkService.Init()
	local Folder = Instance.new("Folder")
	Folder.Name = Remotes.FolderName
	for Name, Contract in RemoteContracts do
		local Remote = Instance.new(if Contract.Kind == "Request" then "RemoteFunction" else "RemoteEvent")
		Remote.Name = Name
		Remote.Parent = Folder
		RemoteInstances[Name] = Remote
	end
	Folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(Player)
		Limiter:Forget(Player)
		InFlight[Player] = nil
	end)
end

-- Handler(Player, ...) must return a Result for Request remotes.
function NetworkService.Handle(Name: string, Handler)
	local Contract = RemoteContracts[Name]
	assert(Contract and Contract.Kind ~= "Push", `{Name} is not a client-to-server remote`)
	local Remote = RemoteInstances[Name]
	if Contract.Kind == "Request" then
		Remote.OnServerInvoke = function(Player, ...)
			return DispatchRequest(Name, Contract, Handler, Player, ...)
		end
	else
		Remote.OnServerEvent:Connect(function(Player, ...)
			if not Limiter:Allow(Player, Name, Contract.Rate) then
				return
			end
			if not ValidateArguments(Contract.Args, ...) or not PlayerDataService.IsLoaded(Player) then
				return
			end
			local Success, ErrorMessage = pcall(Handler, Player, ...)
			if not Success then
				warn(`[NetworkService] {Name} failed for {Player.Name}: {ErrorMessage}`)
			end
		end)
	end
end

function NetworkService.Push(Player: Player, Name: string, ...)
	assert(RemoteContracts[Name].Kind == "Push", `{Name} is not a push remote`)
	if Player.Parent then
		RemoteInstances[Name]:FireClient(Player, ...)
	end
end

function NetworkService.Notify(Player: Player, Message: string, Kind: string?)
	NetworkService.Push(Player, "Notify", Message, Kind or "Info")
end

return NetworkService
