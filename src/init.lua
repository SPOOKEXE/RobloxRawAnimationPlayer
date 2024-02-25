
export type AnimationType = KeyframeSequence | table

export type AnimationObjectType = {
	New : () -> AnimationObjectType,
	FromKeyframeSequence : (keyframeSequence : KeyframeSequence) -> AnimationObjectType,
	FromCFrameData : (CFrameData : {}) -> AnimationObjectType,
	-- properties
	Animation : AnimationType,
	IsPlaying : boolean,
	Length : number,
	Looped : boolean,
	Priority : Enum.AnimationPriority,
	Speed : number,
	TimePosition : number,
	WeightCurrent : number,
	WeightTarget : number,
	Destroyed : boolean,
	-- methods
	AdjustSpeed : (self : AnimationObjectType, speed : number) -> nil,
	AdjustWeight : (self : AnimationObjectType, weight : number, fadeTime : number?) -> nil,
	GetMarkerReachedSignal : (self : AnimationObjectType, name : string) -> RBXScriptSignal,
	GetTimeOfKeyframe : (self : AnimationObjectType, keyframeName : string) -> number,
	Play : (self : AnimationObjectType, fadeTime : number?, weight : number?, speed : number?) -> nil,
	Stop : (self : AnimationObjectType, fadeTime : number?) -> nil,
	Destroy : (self : AnimationObjectType) -> nil,
	-- events
	DidLoop : RBXScriptSignal,
	Ended : RBXScriptSignal,
	KeyframeReached : RBXScriptSignal, -- callback gives keyframeName that is reached (except for 'Default' keyframe)
	Stopped : RBXScriptSignal,
	Paused : RBXScriptSignal,
}

export type AnimatorBackendType = {
	New : (Character : Model) -> AnimatorBackendType,
	-- properties
	Destroyed : boolean,
	IsUpdating : boolean,
	Enabled : boolean,
	Deferred : boolean, -- is the thread task.defer'ed or task.spawn'ed
	AnimationTracks : { AnimationObjectType },
	-- functions
	GetPlayingAnimationTracks : (self : AnimatorBackendType) -> { AnimationObjectType },
	LoadAnimation : (self : AnimatorBackendType, animation : AnimationType) -> AnimationObjectType,
	StepAnimations : (self : AnimatorBackendType, deltaTime : number) -> nil,
	Destroy : (self : AnimatorBackendType) -> nil,
	Enable : (self : AnimatorBackendType) -> nil,
	Disable : (self : AnimatorBackendType) -> nil,
	-- events
	AnimationPlayed : RBXScriptSignal, -- calback gives the AnimationObject of the animation that is now playing
}

local RunService = game:GetService('RunService')

local ActiveBackends = {}

-- // AnimationObject Class // --
local AnimationObject = {}
AnimationObject.__index = AnimationObject

function AnimationObject.New() : AnimationObjectType
	local self = {}
	setmetatable(self, AnimationObject)
	return self
end

function AnimationObject.FromKeyframeSequence( KeyframeSequenceObject : KeyframeSequence ) : AnimationObjectType
	error('NotImplementedError')
	-- local baseObject = AnimationObject.New()
	-- return baseObject
end

function AnimationObject.FromCFrameData( CFrameData : {} ) : AnimationObjectType
	error('CFrameData is currently not supported. Only KeyframeSequences are supported as of now.')
end

function AnimationObject:Play()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	-- self.TimePosition = 0
	-- self.IsPlaying = true
end

function AnimationObject:Pause()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	-- self.IsPlaying = false
end

function AnimationObject:Resume()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	-- self.IsPlaying = true
end

function AnimationObject:Stop()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	-- self.TimePosition = 0
	-- self.IsPlaying = false
end

function AnimationObject:Destroy()
	self:Stop()
	self.Destroyed = true
end

-- // AnimatorBackend Class // --
local AnimatorBackend = {}
AnimatorBackend.__index = AnimatorBackend

function AnimatorBackend.New( Character : Model ) : AnimatorBackendType
	local self = {
		Destroyed = false,
		IsUpdating = false,
		Enabled = true,
		Deferred = true,
		AnimationTracks = {},
	}

	setmetatable(self, AnimatorBackend)

	return self
end

function AnimatorBackend:LoadAnimation( animation : AnimationType ) : AnimationObjectType
	local Object = nil
	if typeof(animation) == 'Instance' and animation:IsA('KeyframeSequence') then
		Object = AnimationObject.FromKeyframeSequence( animation )
	elseif typeof(animation) == 'table' and #animation >= 2 then
		Object = AnimationObject.FromCFrameData( animation )
	end
	if not Object then
		local ERROR_MESSAGE = 'Animation of type %s is unsupported. The supported types are KeyframeSequence Instances and Arrays of CFrameData.'
		error(string.format(ERROR_MESSAGE, typeof(Object)))
	end
	return Object
end

function AnimatorBackend:StepAnimations( deltaTime : number )
	if self.Destroyed then
		return -- cannot be called anymore
	end

	-- handle all animations and transformation to the character here
	print(#self.AnimationTracks)
end

function AnimatorBackend:Enable()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	if not table.find(ActiveBackends, self) then
		table.insert(ActiveBackends, self)
	end
end

function AnimatorBackend:Disable()
	local index = table.find(ActiveBackends, self)
	if index then
		table.remove(ActiveBackends, index)
	end
end

function AnimatorBackend:Destroy()
	self:Stop()
	self.Destroyed = true
end

-- // Module // --
local Module = {}

Module.AnimationObject = AnimationObject
Module.AnimatorBackend = AnimatorBackend

function Module.CreateAnimatorForModel( Model : Model ) : AnimatorBackendType

end

function Module.Initialize()

	local SteppedEvent = RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped
	SteppedEvent:Connect(function(deltaTime : number)
		local index = 1
		while index <= #ActiveBackends do
			local backendObject : AnimatorBackendType = ActiveBackends[index]
			if backendObject.Destroyed then
				table.remove(ActiveBackends, index) -- no longer active as its destroyed
			elseif backendObject.Enabled and not backendObject.IsUpdating then
				backendObject.IsUpdating = true
				local threadedOption = backendObject.Deferred and task.defer or task.spawn
				threadedOption(function()
					backendObject:StepAnimations(deltaTime)
					backendObject.IsUpdating = false
				end)
			end
		end
	end)

end

return Module
