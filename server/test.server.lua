local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RawAnimationPlayer = require(ReplicatedStorage:WaitForChild('RawAnimationPlayer'))

-- animator test
local Animator = RawAnimationPlayer.CreateAnimatorForHumanoid(workspace.TestRig.Humanoid)
print(Animator)

-- animation track test
local AnimTrack = Animator:LoadAnimation( ReplicatedStorage.StunAnimation )
print( AnimTrack )

--[[
	AnimTrack:Play()
	AnimTrack.Looped = false
	task.delay(3, function()
		AnimTrack.DidLoop:Fire()
	end)
	AnimTrack.DidLoop:Wait()

	AnimTrack:Destroy()
	Animator:Destroy()

	print('Completed and Destroyed')
	print( Animator )
	print( AnimTrack )
]]
