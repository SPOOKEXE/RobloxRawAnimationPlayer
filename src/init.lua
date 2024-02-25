local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')

local EventClassModule = require(script.Event)
local MaidClassModule = require(script.Maid)

export type MaidType = MaidClassModule.MaidType
export type AnimationType = KeyframeSequence | table

export type PoseKeyframe = {
	Parent : string,
	Weight : number,
	EasingDirection : Enum.EasingDirection,
	EasingStyle : Enum.EasingStyle,
	Transform : CFrame,
}

export type PoseKeypointsData = {
	TimeLength : number,
	PoseKeypoints : { { Time : number, Keyframes : { [string] : PoseKeyframe }, } },
	MarkerTimestamps : { [string] : { number }, },
	KeyframeTimestamps : { [string] : number, }
}

export type AnimationObjectType = {
	New : () -> AnimationObjectType,
	FromKeyframeSequence : (keyframeSequence : KeyframeSequence) -> AnimationObjectType,
	-- properties
	Animation : AnimationType,
	IsPlaying : boolean,
	Length : number,
	Looped : boolean,
	Priority : Enum.AnimationPriority,
	Speed : number,
	TimePosition : number,
	WeightFadeTime : number,
	WeightCurrent : number,
	WeightTarget : number,
	Destroyed : boolean,
	_Maid : MaidType,
	_PoseKeypointsData : PoseKeypointsData,
	_MarkerReachedEvents : { [string] : RBXScriptSignal },
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
	GetTransformationsAt : (timestamp : number) -> { [string] : CFrame },
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
	UUID : string,
	Destroyed : boolean,
	IsUpdating : boolean,
	Enabled : boolean,
	Deferred : boolean, -- is the thread task.defer'ed or task.spawn'ed
	_AnimationTracks : { AnimationObjectType },
	_Character : Instance,
	_JointMapping : { [string] : Motor6D },
	_Maid : MaidType,
	-- functions
	GetPlayingAnimationTracks : (self : AnimatorBackendType) -> { AnimationObjectType },
	LoadAnimation : (self : AnimatorBackendType, animation : AnimationType) -> AnimationObjectType,
	StepAnimations : (self : AnimatorBackendType, deltaTime : number) -> nil,
	Destroy : (self : AnimatorBackendType) -> nil,
	Enable : (self : AnimatorBackendType) -> nil,
	Disable : (self : AnimatorBackendType) -> nil,
	SetDeferredMode : (self : AnimatorBackendType, enabled : boolean) -> nil,
	-- events
	AnimationPlayed : RBXScriptSignal,
	AnimationStopped : RBXScriptSignal,
	AnimationPaused : RBXScriptSignal,
	AnimationResumed : RBXScriptSignal,
	AnimationDestroyed : RBXScriptSignal,
	Destroying : RBXScriptSignal,
}

local ActiveBackends : { AnimatorBackendType } = {}

local function FindDescendantMotor6Ds( Parent : Instance ) : { Motor6D }
	local motors = {}
	for _, object in ipairs( Parent:GetDescendants() ) do
		if object:IsA('Motor6D') then
			table.insert(motors, object)
		end
	end
	return motors
end

local function UpdateBackendObject( backendObject : AnimatorBackendType, deltaTime : number )
	if backendObject.Enabled and not backendObject.IsUpdating then
		backendObject.IsUpdating = true
		local threadedOption = backendObject.Deferred and task.defer or task.spawn
		threadedOption(function()
			if backendObject.Destroyed then
				return
			end
			debug.profilebegin('RawAnimationUpdate'..backendObject.UUID)
			backendObject:StepAnimations(deltaTime)
			debug.profileend()
			backendObject.IsUpdating = false
		end)
	end
end

local function KeyframeSequenceToPoseData( KeyframeSequence : KeyframeSequence ) : PoseKeypointsData
	local KeyframeTimestamps : { [string] : number } = {}
	local EventMarkerTimestamps : { [string] : {number} } = {}

	local KeyframeObjects : { Keyframe } = { }
	for _, Keyframe in ipairs( KeyframeSequence:GetChildren() ) do
		if Keyframe:IsA('Keyframe') then
			table.insert(KeyframeObjects, Keyframe)
			KeyframeTimestamps[Keyframe.Name] = Keyframe.Time
			for _, Object in ipairs( Keyframe:GetChildren() ) do
				if Object:IsA('KeyframeMarker') then
					if not EventMarkerTimestamps[Object.Name] then
						EventMarkerTimestamps[Object.Name] = {}
					end
					table.insert(EventMarkerTimestamps[Object.Name], Keyframe.Time)
				end
			end
		end
	end

	table.sort(KeyframeObjects, function(keyframe0 : Keyframe, keyframe1 : Keyframe)
		return keyframe0.Time < keyframe1.Time -- sort by time (0 -> TOTAL LENGTH)
	end)

	-- Compiled Per-Keyframe Pose Data
	local PoseKeypoints : PoseKeypointsData = {}
	for _, Keyframe in ipairs( KeyframeObjects ) do
		local Poses : { Pose } = Keyframe:GetDescendants()
		local PosesData : { [string] : PoseKeyframe } = {}
		for _, Pose in ipairs( Poses ) do
			if Pose:IsA('Pose') then
				PosesData[Pose.Name] = {
					Parent = Pose.Parent.Name,
					Weight = Pose.Weight,
					EasingDirection = Enum.EasingDirection[Pose.EasingDirection.Name],
					EasingStyle = Enum.EasingStyle[Pose.EasingStyle.Name],
					Transform = Pose.CFrame,
				}
			end
		end
		table.insert( PoseKeypoints, { TimeLength = Keyframe.Time, PoseKeypoints = PosesData })
	end

	-- Compiled Pose Data
	local PoseData : PoseKeypointsData = {}

	PoseData.TimeLength = KeyframeObjects[#KeyframeObjects].Time
	PoseData.KeyframeTimestamps = KeyframeTimestamps
	PoseData.MarkerTimestamps = EventMarkerTimestamps
	PoseData.PoseKeypoints = PoseKeypoints -- ALREADY SORTED BY TIME

	return PoseData
end

-- // AnimationObject Class // --
local AnimationObject = {}
AnimationObject.ClassName = 'AnimationObject'
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
		WeightFadeTime = 0,
		Destroyed = false,
		_Maid = MaidObject,
		_PoseKeypointsData = nil,
		_MarkerReachedEvents = { },
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

function AnimationObject.FromKeyframeSequence( KeyframeSequence : KeyframeSequence ) : AnimationObjectType
	local PoseData : PoseKeypointsData = KeyframeSequenceToPoseData( KeyframeSequence )
	local Animation : AnimationObjectType = AnimationObject.New()
	Animation.Animation = KeyframeSequence
	Animation.Priority = KeyframeSequence.Priority
	Animation.Looped = KeyframeSequence.Loop
	Animation.Length = PoseData.TimeLength
	Animation._PoseKeypointsData = PoseData
	return Animation
end

function AnimationObject:Play()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	self.TimePosition = 0
	self.IsPlaying = true
end

function AnimationObject:Pause()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	self.IsPlaying = false
end

function AnimationObject:Resume()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	self.IsPlaying = true
end

function AnimationObject:Stop()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	self.TimePosition = 0
	self.IsPlaying = false
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

function AnimationObject:AdjustSpeed(speed : number)
	self.Speed = speed
end

function AnimationObject:GetTimeOfKeyframe(keyframeName : string) : number
	return self._PoseKeypointsData and self._PoseKeypointsData.KeyframeTimestamps[keyframeName] or -1
end

function AnimationObject:AdjustWeight( weight : number, fadeTime : number? )
	self.WeightFadeTime = fadeTime
	self.WeightTarget = weight
end

function AnimationObject:GetMarkerReachedSignal( markerName : string ) : RBXScriptSignal
	if not self._MarkerReachedEvents[ markerName ] then
		local Event = EventClassModule.New()
		self._MarkerReachedEvents[ markerName ] = Event
		self._Maid:Give(Event)
	end
	return self._MarkerReachedEvents[ markerName ]
end

-- // AnimatorBackend Class // --
local AnimatorBackend = {}
AnimatorBackend.ClassName = 'AnimatorBackend'
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
		UUID = HttpService:GenerateGUID(false),
		Destroyed = false,
		IsUpdating = false,
		Enabled = true,
		Deferred = true,
		_Character = Humanoid.Parent,
		_JointMapping = {},
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

	FindDescendantMotor6Ds( Humanoid.Parent )

	MaidObject:Give(function()
		self.AnimationPlayed = nil
		self.AnimationStopped = nil
		self.AnimationPaused = nil
		self.AnimationResumed = nil
		self.AnimationDestroyed = nil
		self.Destroying = nil
	end)

	setmetatable(self, AnimatorBackend)

	table.insert(ActiveBackends, self)

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
		local ERROR_MESSAGE = 'Animation of type %s is unsupported. The only supported type is a KeyframeSequence Instance.'
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

	-- cleanup destroyed animation tracks
	local index = 1
	while index <= #self._AnimationTracks do
		if self._AnimationTracks[index].Destroyed then
			table.remove(self._AnimationTracks, index)
		else
			index += 1
		end
	end

	-- handle all animations and transformation to the character here
	print('Animation Transform Update: ', #self._AnimationTracks, deltaTime)

	-- step weights towards target weight
	for _, AnimObject in ipairs( self._AnimationTracks ) do
		local EPSILON = 0.05
		if math.abs(AnimObject.WeightTarget - AnimObject.WeightCurrent) > EPSILON then
			AnimObject.WeightCurrent += (AnimObject.WeightTarget - AnimObject.WeightCurrent) * ((1/AnimObject.WeightFadeTime) * deltaTime)
		else
			AnimObject.WeightCurrent = AnimObject.WeightTarget
		end
	end

	-- TODO:
	-- step all cframes after masking animations by priority

	-- find the offsets from the joints
	-- local timeDelta = (currentStamp - startTimeStamp) / (endTimeStamp - startTimeStamp)
	-- local tweenAlpha = TweenService:GetValue( timeDelta, pose.EasyingStyle, pose.EasyingDirection )
	-- joint.Transform = pose.StartTransform:Lerp( pose.EndTransform, tweenAlpha )

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
	if self._Maid then
		self._Maid:Cleanup()
		self._Maid = nil
	end
	self.Destroyed = true
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

function AnimatorBackend:SetDeferredMode( enabled : boolean )
	self.Deferred = enabled
end

-- // Module // --
local Module = {}

Module.AnimationObject = AnimationObject
Module.AnimatorBackend = AnimatorBackend

function Module.CreateAnimatorForHumanoid( Humanoid : Humanoid ) : AnimatorBackendType
	return AnimatorBackend.New( Humanoid )
end

function Module.Initialize()

	local SteppedEvent = RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped
	SteppedEvent:Connect(function(deltaTime : number)
		-- print(#ActiveBackends)
		debug.profilebegin('RawAnimationUpdateCheck')
		local index = 1
		while index <= #ActiveBackends do
			local backendObject : AnimatorBackendType = ActiveBackends[index]
			if backendObject.Destroyed then
				table.remove(ActiveBackends, index) -- no longer active as its destroyed
			else
				index += 1
				UpdateBackendObject( backendObject, deltaTime )
			end
		end
		debug.profileend()
	end)

end

task.spawn(Module.Initialize)

return Module
