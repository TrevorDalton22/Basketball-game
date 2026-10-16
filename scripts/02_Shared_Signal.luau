--!strict
-- Signal (ModuleScript) — ReplicatedStorage > Shared > Signal
-- Minimal event object for module-to-module communication on one machine.

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

local Signal = {}
Signal.ScriptFile = "02_Shared_Signal" -- Main/ClientMain compare this to spot another file's code pasted here

function Signal.new(): Signal
	local handlers: { [number]: (...any) -> () } = {}
	local nextId = 0

	local signal = {}

	function signal.Connect(_self: Signal, handler: (...any) -> ()): Connection
		nextId += 1
		local id = nextId
		handlers[id] = handler
		local connection = {}
		function connection.Disconnect(_: Connection)
			handlers[id] = nil
		end
		return connection :: any
	end

	function signal.Fire(_self: Signal, ...: any)
		-- Snapshot so handlers may connect/disconnect while firing
		local snapshot = table.clone(handlers)
		for _, handler in snapshot do
			local ok, err = pcall(handler :: any, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end

	return signal :: any
end

return Signal
