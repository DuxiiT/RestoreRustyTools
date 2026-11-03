-- Client-side access to remotes created by the server's NetworkService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContracts = require(script.Parent.RemoteContracts)

local Remotes = {}

Remotes.FolderName = "Remotes"

local Cache = {}

function Remotes.Get(Name: string)
	assert(RemoteContracts[Name], `Unknown remote {Name}`)
	if not Cache[Name] then
		Cache[Name] = ReplicatedStorage:WaitForChild(Remotes.FolderName):WaitForChild(Name)
	end
	return Cache[Name]
end

-- Invokes a Request remote and always returns a Result-shaped table, even on failure.
function Remotes.Request(Name: string, ...)
	local Remote = Remotes.Get(Name)
	local Success, Response = pcall(Remote.InvokeServer, Remote, ...)
	if not Success or typeof(Response) ~= "table" then
		return { Success = false, Message = "The workshop didn't respond. Try again." }
	end
	return Response
end

return Remotes
