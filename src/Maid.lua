
export type MaidType = {
	New : (...any) -> MaidType,
	AttachInstance : ( self : MaidType, targetInstance : Instance ) -> nil,
	Cleanup : ( self : MaidType ) -> nil,
	Give : ( self : MaidType, ...any? ) -> nil,
}

local Maid = {}
Maid.__index = Maid
Maid.ClassName = "Maid"

function Maid.New(...)
	return setmetatable({_tasks = {...}, _instances = {}}, Maid)
end

function Maid:AttachInstance( TargetInstance )
	if table.find(self._instances, TargetInstance) then
		return
	end
	table.insert(self._instances, TargetInstance)

	self:Give(TargetInstance.Destroying:Connect(function()
		self:Cleanup()
	end))
end

function Maid:Cleanup()
	self._instances = { }
	for _, _task in ipairs( self._tasks ) do
		if typeof(_task) == 'RBXScriptConnection' then
			_task:Disconnect()
		elseif typeof(_task) == 'function' then
			task.defer(_task)
		elseif typeof(_task) == 'Instance' then
			_task:Destroy()
		elseif typeof(_task) == 'table' then
			if _task.ClassName == Maid.ClassName then
				_task:Cleanup()
			elseif _task.Disconnect then
				_task:Disconnect()
			elseif _task.ClassName == 'AnimationObject' or _task.ClassName == 'AnimatorBackend' or _task.Destroy then
				_task:Destroy()
			else
				warn('Invalid task type; ', typeof(_task), _task)
			end
		else
			warn('Invalid task type; ', typeof(_task), _task)
		end
	end
	self._tasks = {}
end

function Maid:Give( ... )
	local tasks = {...}
	for _, _task in ipairs( tasks ) do
		if table.find(self._tasks, _task) then
			warn('Task already exists in the Maid : '..tostring(_task))
		else
			table.insert(self._tasks, _task)
		end
	end
end

return Maid
