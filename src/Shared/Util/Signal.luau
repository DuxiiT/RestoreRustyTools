-- Minimal signal. Handlers run in their own thread so one failing listener cannot break others,
-- and they start immediately, so listeners observe state before the firing code continues.
local Signal = {}
Signal.__index = Signal

function Signal.New()
	return setmetatable({ Handlers = {} }, Signal)
end

function Signal:Connect(Handler)
	table.insert(self.Handlers, Handler)
	return function()
		local Index = table.find(self.Handlers, Handler)
		if Index then
			table.remove(self.Handlers, Index)
		end
	end
end

function Signal:Fire(...)
	for _, Handler in table.clone(self.Handlers) do
		task.spawn(Handler, ...)
	end
end

return Signal
