local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RawAnimationPlayer = require(ReplicatedStorage:WaitForChild('RawAnimationPlayer'))

local TestRig : Model = workspace.TestRig

-- animator test
local Animator = RawAnimationPlayer.CreateAnimatorForModel(TestRig)

-- animation track test
local AnimTrack = Animator:LoadAnimation( ReplicatedStorage.StunAnimation )
AnimTrack:Play()
AnimTrack.Looped = false
AnimTrack.DidLoop:Wait()
AnimTrack:Destroy()
print( AnimTrack.Destroyed )

Animator:Destroy()
print( Animator.Destroyed )
