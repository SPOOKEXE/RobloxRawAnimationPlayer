
export type AnimationType = Animation | KeyframeSequence | string | table

export type AnimationObject = {
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
	-- methods
	AdjustSpeed : (number) -> nil,
	AdjustWeight : (number, number?) -> nil,
	GetMarkerReachedSignal : (string) -> RBXScriptSignal,
	GetTimeOfKeyframe : (string) -> number,
	Play : (number?, number?, number?) -> nil,
	Stop : (number?) -> nil,
	-- events
	DidLoop : RBXScriptSignal,
	Ended : RBXScriptSignal,
	KeyframeReached : RBXScriptSignal, -- callback gives keyframeName that is reached (except for 'Default' keyframe)
	Stopped : RBXScriptSignal,
	Paused : RBXScriptSignal,
}

export type AnimatorBackend = {
	-- functions
	GetPlayingAnimationTracks : () -> { AnimationObject },
	LoadAnimation : (AnimationType) -> AnimationObject,
	StepAnimations : (number) -> nil,
	-- events
	AnimationPlayed : RBXScriptSignal, -- calback gives the AnimationObject of the animation that is now playing
}

local RunService = game:GetService('RunService')

local ActiveBackends = {}

-- // Animation Object // --
local AnimationObject = {}
AnimationObject.__index = AnimationObject

function AnimationObject.New( ) : AnimationObject
	local self = {
		Animation = nil,
		IsPlaying = false,
	}

	setmetatable(self, AnimationObject)

	return self
end

function AnimationObject.FromKeyframeSequence( KeyframeSequenceObject : KeyframeSequence )

end

function AnimationObject.FromAnimationObject( AnimationObject : Animation )

end

function AnimationObject:Play()

end

function AnimationObject:Pause()

end

function AnimationObject:Stop()

end

-- // AnimatorBackend // --
local AnimatorBackend = {}
AnimatorBackend.__index = AnimatorBackend

function AnimatorBackend.New( Model : Model ) : AnimatorBackend
	local self = {
		Destroyed = false, -- will prevent function calls
	}

	setmetatable(self, AnimatorBackend)

	return self
end

function AnimatorBackend:StepAnimations( dt : number )
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end

end

function AnimatorBackend:Start()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
	end
	if not table.find(ActiveBackends, self) then
		table.insert(ActiveBackends, self)
	end
end

function AnimatorBackend:Stop()
	if self.Destroyed then
		error('The class has been destroyed, it cannot be called anymore.') -- cannot call anymore
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

function Module.CreateAnimatorForModel( Model : Model ) : AnimatorBackend

end

return Module
