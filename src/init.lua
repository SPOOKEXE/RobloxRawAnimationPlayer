local RunService = game:GetService('RunService')

local EventClassModule = require(script.Event)
local MaidClassModule = require(script.Maid)

export type MaidType = MaidClassModule.MaidType
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
	_Maid : MaidType,
	-- methods
	AdjustSpeed : (self : AnimationObjectType, speed : number) -> nil,
	AdjustWeight : (self : AnimationObjectType, weight : number, fadeTime : number?) -> nil,
	GetMarkerReachedSignal : (self : AnimationObjectType, name : string) -> RBXScriptSignal,
	GetTimeOfKeyframe : (self : AnimationObjectType, keyframeName : string) -> number,
	Play : (self : AnimationObjectType, fadeTime : number?, weight : number?, speed : number?) -> nil,
	Stop : (self : AnimationObjectType, fadeTime : number?) -> nil,
	Pause : (self : AnimationObjectType, fadeTime : number?) -> nil,
	Resume : (self : AnimationObjectType, fadeTime : number?) -> nil,
	Destroy : (self : AnimationObjectType) -> nil,
	-- events
	DidLoop : RBXScriptSignal,
	Ended : RBXScriptSignal,
	KeyframeReached : RBXScriptSignal, -- callback gives keyframeName that is reached (except for 'Default' keyframe)
	Stopped : RBXScriptSignal,
	Paused : RBXScriptSignal,
	Destroying : RBXScriptSignal,
}

export type AnimatorBackendType = {
	New : (Humanoid : Humanoid) -> AnimatorBackendType,
	-- properties
	Destroyed : boolean,
	IsUpdating : boolean,
	Enabled : boolean,
	Deferred : boolean, -- is the thread task.defer'ed or task.spawn'ed
	_AnimationTracks : { AnimationObjectType },
	_Character : Instance,
	_Maid : MaidType,
	-- functions
	GetPlayingAnimationTracks : (self : AnimatorBackendType) -> { AnimationObjectType },
	LoadAnimation : (self : AnimatorBackendType, animation : AnimationType) -> AnimationObjectType,
	StepAnimations : (self : AnimatorBackendType, deltaTime : number) -> nil,
	Destroy : (self : AnimatorBackendType) -> nil,
	Enable : (self : AnimatorBackendType) -> nil,
	Disable : (self : AnimatorBackendType) -> nil,
	-- events
	AnimationPlayed : RBXScriptSignal,
	AnimationStopped : RBXScriptSignal,
	AnimationPaused : RBXScriptSignal,
	AnimationResumed : RBXScriptSignal,
	AnimationDestroyed : RBXScriptSignal,
	Destroying : RBXScriptSignal,
}

local ActiveBackends : { AnimatorBackendType } = {}

-- // AnimationObject Class // --
local AnimationObject = {}
AnimationObject.__index = AnimationObject

function AnimationObject.New() : AnimationObjectType
	local DidLoop = EventClassModule.New()
	local Ended = EventClassModule.New()
	local KeyframeReached = EventClassModule.New()
	local Stopped = EventClassModule.New()
	local Paused = EventClassModule.New()
	local Destroying = EventClassModule.New()

	local MaidObject = MaidClassModule.New()
	MaidObject:Give(
		DidLoop, Ended, KeyframeReached,
		Stopped, Paused, Destroying
	)

	local self = {
		-- properties
		Animation = nil,
		IsPlaying = false,
		Length = 0,
		Looped  = false,
		Priority = Enum.AnimationPriority.Core,
		Speed = 1,
		TimePosition = 0,
		WeightCurrent = 1,
		WeightTarget = 1,
		Destroyed = false,
		_Maid = MaidObject,
		-- events
		DidLoop = DidLoop,
		Ended = Ended,
		KeyframeReached = KeyframeReached,
		Stopped = Stopped,
		Paused = Paused,
		Destroying = Destroying,
	}

	setmetatable(self, AnimationObject)

	return self
end

function AnimationObject.FromKeyframeSequence( KeyframeSequenceObject : KeyframeSequence ) : AnimationObjectType
	-- error('NotImplementedError')
	local baseObject = AnimationObject.New()

	return baseObject
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
	if self.Destroyed then
		return
	end
	self.Destroying:Fire()
	self:Stop()
	self.Destroyed = true
	self._Maid:Cleanup()
	self._Maid = nil
end

--[[
	AdjustSpeed : (self : AnimationObjectType, speed : number) -> nil,
	AdjustWeight : (self : AnimationObjectType, weight : number, fadeTime : number?) -> nil,
	GetMarkerReachedSignal : (self : AnimationObjectType, name : string) -> RBXScriptSignal,
	GetTimeOfKeyframe : (self : AnimationObjectType, keyframeName : string) -> number,
]]

-- // AnimatorBackend Class // --
local AnimatorBackend = {}
AnimatorBackend.__index = AnimatorBackend

function AnimatorBackend.New( Humanoid : Humanoid ) : AnimatorBackendType
	local AnimationPlayed = EventClassModule.New()
	local AnimationStopped = EventClassModule.New()
	local AnimationPaused = EventClassModule.New()
	local AnimationResumed = EventClassModule.New()
	local AnimationDestroyed = EventClassModule.New()
	local Destroying = EventClassModule.New()

	local MaidObject = MaidClassModule.New()
	MaidObject:Give(
		AnimationPlayed, AnimationStopped, AnimationPaused,
		AnimationResumed, AnimationDestroyed, Destroying
	)

	local self = {
		-- properties
		Destroyed = false,
		IsUpdating = false,
		Enabled = true,
		Deferred = true,
		_Character = Humanoid.Parent,
		_AnimationTracks = {},
		_Maid = MaidObject,
		-- events
		AnimationPlayed = AnimationPlayed,
		AnimationStopped = AnimationStopped,
		AnimationPaused = AnimationPaused,
		AnimationResumed = AnimationResumed,
		AnimationDestroyed = AnimationDestroyed,
		Destroying = Destroying,
	}

	MaidObject:Give(function()
		self.AnimationPlayed = nil
		self.AnimationStopped = nil
		self.AnimationPaused = nil
		self.AnimationResumed = nil
		self.AnimationDestroyed = nil
		self.Destroying = nil
	end)

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
	table.insert(self._AnimationTracks, Object)
	self._Maid:Give(Object)
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
	if self.Destroyed then
		return
	end
	self.Destroying:Fire()
	self:Disable()
	self.Destroyed = true
	if self._Maid then
		self._Maid:Cleanup()
		self._Maid = nil
	end
end

function AnimatorBackend:GetPlayingAnimationTracks()
	local Animations = {}
	for _, Animation in ipairs( self._AnimationTracks ) do
		if Animation.IsPlaying then
			table.insert(Animations, Animation)
		end
	end
	return Animations
end

function AnimatorBackend:PauseAllAnimationTracks()
	for _, Animation in ipairs( self._AnimationTracks ) do
		Animation:Pause()
	end
end

function AnimatorBackend:StopAllAnimationTracks()
	for _, Animation in ipairs( self._AnimationTracks ) do
		Animation:Stop()
	end
end

-- // Module // --
local Module = {}

Module.AnimationObject = AnimationObject
Module.AnimatorBackend = AnimatorBackend

function Module.CreateAnimatorForHumanoid( Humanoid : Humanoid ) : AnimatorBackendType
	return AnimatorBackend.New( Humanoid )
end

function Module.Initialize()

	print('Initializing')

	local SteppedEvent = RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped
	SteppedEvent:Connect(function(deltaTime : number)
		print(#ActiveBackends)
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

task.spawn(Module.Initialize)

return Module
