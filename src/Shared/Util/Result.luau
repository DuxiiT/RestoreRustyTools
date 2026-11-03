-- Every request handler returns one of these so the client always gets a clear outcome.
local Result = {}

function Result.Ok(Data)
	return { Success = true, Data = Data }
end

function Result.Fail(Message: string, Code: string?)
	return { Success = false, Message = Message, Code = Code }
end

return Result
