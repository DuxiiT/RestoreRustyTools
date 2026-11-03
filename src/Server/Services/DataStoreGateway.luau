-- Session-locked profile storage. Each record is { Data, Lock = { JobId, Time } }.
-- A server only writes while it holds the lock, so two servers can never overwrite each other
-- (for example a fast rejoin while the old server is still saving). Autosaves refresh the lock,
-- and a lock older than LockTimeoutSeconds is treated as abandoned by a crashed server.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataStoreGateway = {}

local StoreName = "PlayerProfiles_v1"
local LockTimeoutSeconds = 30 * 60
local LoadAttempts = 6
local LockedRetrySeconds = 6
local ErrorRetrySeconds = 2

local Backend

-- In-memory stand-in for Studio sessions without API access. Mirrors UpdateAsync semantics.
local function CreateMemoryBackend()
	local Records = {}
	return {
		IsMemory = true,
		UpdateAsync = function(_, Key, Transform)
			local Copy = Records[Key] and table.clone(Records[Key]) or nil
			local NewValue = Transform(Copy)
			if NewValue ~= nil then
				Records[Key] = NewValue
			end
			return NewValue
		end,
	}
end

function DataStoreGateway.Init()
	local Success, Store = pcall(DataStoreService.GetDataStore, DataStoreService, StoreName)
	if Success and RunService:IsStudio() then
		-- GetDataStore succeeds without API access; a read is the real test.
		Success = pcall(Store.GetAsync, Store, "StudioAccessProbe")
	end
	if Success then
		Backend = Store
	elseif RunService:IsStudio() then
		warn("[DataStoreGateway] DataStores unavailable in Studio; using temporary memory storage. Enable API Services to test saving.")
		Backend = CreateMemoryBackend()
	else
		error("[DataStoreGateway] DataStoreService unavailable")
	end
end

function DataStoreGateway.IsUsingMemory(): boolean
	return Backend ~= nil and Backend.IsMemory == true
end

local function KeyFor(UserId: number): string
	return `Player_{UserId}`
end

-- Returns Success, Data (nil for a brand-new player), FailureReason.
function DataStoreGateway.LoadAndLock(UserId: number)
	for Attempt = 1, LoadAttempts do
		local Status, LoadedData
		local Success, ErrorMessage = pcall(function()
			Backend:UpdateAsync(KeyFor(UserId), function(Record)
				Status, LoadedData = nil, nil
				Record = Record or {}
				local Lock = Record.Lock
				if Lock and Lock.JobId ~= game.JobId and os.time() - (Lock.Time or 0) < LockTimeoutSeconds then
					Status = "Locked"
					return nil
				end
				Record.Lock = { JobId = game.JobId, Time = os.time() }
				LoadedData = Record.Data
				Status = "Acquired"
				return Record
			end)
		end)

		if Success and Status == "Acquired" then
			return true, LoadedData, nil
		elseif Success and Status == "Locked" then
			if Attempt < LoadAttempts then
				task.wait(LockedRetrySeconds)
			end
		else
			warn(`[DataStoreGateway] Load attempt {Attempt} for {UserId} failed: {ErrorMessage}`)
			if Attempt < LoadAttempts then
				task.wait(ErrorRetrySeconds * Attempt)
			end
		end
	end
	return false, nil, "Your save is still in use or unavailable."
end

-- Writes Data only if this server still owns the lock. Release clears the lock afterwards.
-- Returns Success, Reason.
function DataStoreGateway.Save(UserId: number, Data, Release: boolean)
	local Status
	local Success, ErrorMessage = pcall(function()
		Backend:UpdateAsync(KeyFor(UserId), function(Record)
			Status = nil
			Record = Record or {}
			if Record.Lock and Record.Lock.JobId ~= game.JobId then
				Status = "LockLost"
				return nil
			end
			Record.Data = Data
			Record.Lock = if Release then nil else { JobId = game.JobId, Time = os.time() }
			Status = "Saved"
			return Record
		end)
	end)
	if not Success then
		return false, ErrorMessage
	end
	return Status == "Saved", Status
end

return DataStoreGateway
