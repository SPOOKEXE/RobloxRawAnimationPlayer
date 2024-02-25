local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RawAnimationPlayer = require(ReplicatedStorage:WaitForChild('RawAnimationPlayer'))

local TestAnimation = ReplicatedStorage.TestKeyframeSequence
local TestRig = workspace.TestRig

local Animator = RawAnimationPlayer.CreateAnimatorForModel(TestRig)
-- Animator
