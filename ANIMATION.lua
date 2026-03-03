--//====================================================\\--
--||             Animator6D Pro V4 (R6/R15)            ||--
--||  Author: gObl00x + GPT-5                         ||--
--||  Features: universal rig, local cache, safe play  ||--
--||           + R15 Support Added                     ||--
--\\====================================================//--

if getgenv().Animator6DLoadedPro then return end
getgenv().Animator6DLoadedPro = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")

-- ========== RIG TYPE DETECTION ==========
local function getRigType(rig)
	-- Check if R15 by looking for R15-specific parts
	local hasR15Parts = false
	local r15Parts = {"UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", 
					  "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", 
					  "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
	
	for _, partName in ipairs(r15Parts) do
		if rig:FindFirstChild(partName) then
			hasR15Parts = true
			break
		end
	end
	
	return hasR15Parts and "R15" or "R6"
end

-- ========== MOTOR MAPS FOR BOTH RIG TYPES ==========
local R6Map = {
	["Head"] = "Neck",
	["Torso"] = "RootJoint",
	["Right Arm"] = "Right Shoulder",
	["Left Arm"] = "Left Shoulder",
	["Right Leg"] = "Right Hip",
	["Left Leg"] = "Left Hip"
}

local R15Map = {
	-- Core body parts
	["Head"] = "Neck",
	["UpperTorso"] = "Waist",
	["LowerTorso"] = "Root",
	
	-- Right arm chain
	["RightUpperArm"] = "RightShoulder",
	["RightLowerArm"] = "RightElbow",
	["RightHand"] = "RightWrist",
	
	-- Left arm chain
	["LeftUpperArm"] = "LeftShoulder",
	["LeftLowerArm"] = "LeftElbow",
	["LeftHand"] = "LeftWrist",
	
	-- Right leg chain
	["RightUpperLeg"] = "RightHip",
	["RightLowerLeg"] = "RightKnee",
	["RightFoot"] = "RightAnkle",
	
	-- Left leg chain
	["LeftUpperLeg"] = "LeftHip",
	["LeftLowerLeg"] = "LeftKnee",
	["LeftFoot"] = "LeftAnkle"
}

-- Reverse map for finding motors by their names
local R15ReverseMap = {}
for poseName, motorName in pairs(R15Map) do
	R15ReverseMap[motorName] = poseName
end

-- ========== LOCAL CACHE / 403 EVASION ==========
local LocalAssetCache = {}
local fullModel = nil
pcall(function()
	fullModel = game:GetObjects("rbxassetid://107495486817639")[1]
	if fullModel then
		fullModel.Parent = workspace
	end
end)

local function LoadLocalAsset(id)
	id = tostring(id):gsub("^rbxassetid://", "")
	if LocalAssetCache[id] then
		return LocalAssetCache[id]
	end

	local found = fullModel and fullModel:FindFirstChild(id, true)
	if found then
		LocalAssetCache[id] = found
		warn("[Animator6D] ✅ Loaded from local cache:", id)
		return found
	end

	local ok, obj = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)[1]
	end)
	if ok and obj then
		LocalAssetCache[id] = obj
		warn("[Animator6D] ✅ Loaded via GetObjects👍👍:", id)
		return obj
	end

	warn("[Animator6D] ts is bad, failed to load animation:", id)
	return nil
end
-- ===============================================

-- ========== KEYFRAME PARSER ==========
local function ConvertToTable(kfs)
	if not (kfs and typeof(kfs) == "Instance" and kfs:IsA("KeyframeSequence")) then
		if typeof(kfs) == "Instance" then
			for _, obj in ipairs(kfs:GetDescendants()) do
				if obj:IsA("KeyframeSequence") then
					kfs = obj
					break
				end
			end
		end
	end

	assert(kfs and typeof(kfs) == "Instance" and kfs:IsA("KeyframeSequence"), "Expected KeyframeSequence")

	local seq = {}
	for _, frame in ipairs(kfs:GetKeyframes()) do
		local entry = { Time = frame.Time, Data = {} }
		for _, pose in ipairs(frame:GetDescendants()) do
			if pose:IsA("Pose") and pose.Weight > 0 then
				entry.Data[pose.Name] = { CFrame = pose.CFrame }
			end
		end
		table.insert(seq, entry)
	end
	table.sort(seq, function(a, b) return a.Time < b.Time end)
	return seq, kfs.Loop
end

-- ========== MOTOR MAP ==========
local function BuildMotorMap(rig)
	local map, lower = {}, {}
	local rigType = getRigType(rig)
	
	for _, m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") then
			map[m.Name] = m
			lower[string.lower(m.Name)] = m
		end
	end
	
	return map, lower, rigType
end

-- ========== FIND MOTOR BY POSE NAME (RIG AWARE) ==========
local function FindMotor(poseName, map, lower, rigType)
	if rigType == "R6" then
		local match = R6Map[poseName] or poseName
		return map[match] or lower[string.lower(match)]
	else -- R15
		-- Try direct motor name match first
		if map[poseName] then
			return map[poseName]
		end
		
		-- Try R15 map
		local motorName = R15Map[poseName]
		if motorName and map[motorName] then
			return map[motorName]
		end
		
		-- Try lowercase
		return lower[string.lower(poseName)]
	end
end

-- ========== CONVERT R6 ANIMATIONS TO R15 ==========
local function convertPoseForR15(poseName, poseCFrame, rigType)
	if rigType == "R15" then
		-- Handle special conversions if needed
		-- For example, if an R6 animation targets "Torso", we might need to split between UpperTorso/LowerTorso
		if poseName == "Torso" then
			-- Return both UpperTorso and LowerTorso with appropriate CFrames
			return {
				["UpperTorso"] = { CFrame = poseCFrame },
				["LowerTorso"] = { CFrame = poseCFrame }
			}
		elseif poseName == "Right Arm" then
			return {
				["RightUpperArm"] = { CFrame = poseCFrame },
				["RightLowerArm"] = { CFrame = poseCFrame },
				["RightHand"] = { CFrame = poseCFrame }
			}
		elseif poseName == "Left Arm" then
			return {
				["LeftUpperArm"] = { CFrame = poseCFrame },
				["LeftLowerArm"] = { CFrame = poseCFrame },
				["LeftHand"] = { CFrame = poseCFrame }
			}
		elseif poseName == "Right Leg" then
			return {
				["RightUpperLeg"] = { CFrame = poseCFrame },
				["RightLowerLeg"] = { CFrame = poseCFrame },
				["RightFoot"] = { CFrame = poseCFrame }
			}
		elseif poseName == "Left Leg" then
			return {
				["LeftUpperLeg"] = { CFrame = poseCFrame },
				["LeftLowerLeg"] = { CFrame = poseCFrame },
				["LeftFoot"] = { CFrame = poseCFrame }
			}
		end
	end
	-- Return original for R6 or unmapped R15 poses
	return { [poseName] = { CFrame = poseCFrame } }
end

-- ========== ANIM PLAYER ==========
local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rig, kfs)
	local self = setmetatable({}, AnimPlayer)
	self.rig = rig
	self.seq, self.looped = ConvertToTable(kfs)
	self.map, self.lower, self.rigType = BuildMotorMap(rig)
	self.time, self.playing = 0, false
	self.length = self.seq[#self.seq].Time
	self.speed = 1
	self.savedC0 = {}
	
	-- Save original C0 for all motors
	for _, m in pairs(self.map) do
		self.savedC0[m] = m.C0
	end
	
	warn("[Animator6D] 🎯 Rig type detected:", self.rigType)
	return self
end

function AnimPlayer:Play(speed, loop)
	if self.playing then return end
	self.playing, self.speed = true, speed or 1
	self.looped = (loop == nil) and true or loop

	self.conn = RunService.Heartbeat:Connect(function(dt)
		if not self.playing then return end
		self.time += dt * self.speed

		if self.time > self.length then
			if self.looped then
				self.time -= self.length
			else
				self:Stop(true)
				return
			end
		end

		-- Find current keyframe
		local prev = self.seq[1]
		for i = 1, #self.seq do
			if self.seq[i].Time <= self.time then
				prev = self.seq[i]
			else
				break
			end
		end

		-- Apply poses
		for joint, data in pairs(prev.Data) do
			if self.rigType == "R15" then
				-- For R15, we might need to convert the pose
				local convertedPoses = convertPoseForR15(joint, data.CFrame, self.rigType)
				for convertedJoint, convertedData in pairs(convertedPoses) {
					local motor = FindMotor(convertedJoint, self.map, self.lower, self.rigType)
					if motor then
						pcall(function()
							motor.C0 = self.savedC0[motor] * convertedData.CFrame
						end)
					end
				}
			else
				-- R6 - direct mapping
				local motor = FindMotor(joint, self.map, self.lower, self.rigType)
				if motor then
					pcall(function()
						motor.C0 = self.savedC0[motor] * data.CFrame
					end)
				end
			end
		end
	end)
end

function AnimPlayer:Stop(restore)
	self.playing = false
	if self.conn then self.conn:Disconnect() self.conn = nil end
	if restore then
		for motor, origC0 in pairs(self.savedC0) do
			pcall(function() motor.C0 = origC0 end)
		end
	else
		for _, m in pairs(self.map) do
			pcall(function() m.Transform = CFrame.new() end)
		end
	end
end

-- ========== DISABLE DEFAULT ANIMS ==========
local function disableDefaultAnimations(char)
	if not hum then return end
	for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
	local animScript = char:FindFirstChild("Animate")
	if animScript then animScript.Disabled = true end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then animator:Destroy() end
end

-- ========== GLOBAL INTERFACE ==========
getgenv().Animator6D = function(idOrInstance, speed, looped)
	local kfs
	if typeof(idOrInstance) == "Instance" then
		kfs = idOrInstance:IsA("KeyframeSequence") and idOrInstance or idOrInstance:FindFirstChildOfClass("KeyframeSequence")
	else
		local asset = LoadLocalAsset(idOrInstance)
		if asset then
			kfs = asset:FindFirstChildOfClass("KeyframeSequence") or asset
		end
	end

	if not kfs then
		warn("[Animator6D] yo sorry could not load animation:", idOrInstance)
		return
	end

	disableDefaultAnimations(character)

	if getgenv().currentAnimator6D then
		pcall(function()
			getgenv().currentAnimator6D:Stop(true)
		end)
	end

	local anim = AnimPlayer.new(character, kfs)
	getgenv().currentAnimator6D = anim
	anim:Play(speed or 1, looped)
	
	-- Return rig type info
	return anim, anim.rigType
end

getgenv().Animator6DStop = function()
	if getgenv().currentAnimator6D then
		pcall(function() getgenv().currentAnimator6D:Stop(true) end)
		getgenv().currentAnimator6D = nil
	end
end

-- ========== UTILITY FUNCTIONS ==========
getgenv().Animator6DGetRigType = function()
	if getgenv().currentAnimator6D then
		return getgenv().currentAnimator6D.rigType
	end
	local rigType = getRigType(character)
	return rigType
end

-- ========== NOTIFY ==========
local rigType = getRigType(character)
warn("[Animator6D Pro V4] ya.. Allah hotbar | Detected: " .. rigType)
pcall(function()
	game:GetService("StarterGui"):SetCore("SendNotification", {
		Title = "Animator6D Pro V4",
		Text = "Loaded with " .. rigType .. " Support!",
		Duration = 5
	})
end)

--
--[[
(pls, If ur down here, read these instructions)
Instructions:
--
If u want to play the anim outside ts loadstring, then:
getgenv().Animator6D(1234567890, 1, true) -- idOrInstance, Speed, Looped? --
--
If u will be using an instance and not an ID, then:
local animInstance = game:GetObjects("rbxassetid://ID")[1]..Here the KeyframeSequence Path -- replace ID with the ID --
getgenv().Animator6D(animInstance, 1, true) -- or false if u want the anim to have a loop
--
If u want to stop the anim outside ts loadstring, then:
getgenv().Animator6DStop()
--
NEW R15 FEATURES:
getgenv().Animator6DGetRigType() -- Returns "R6" or "R15" for current character
--
The script now automatically detects R6 vs R15 and handles both!
R6 animations will be automatically converted to work on R15 rigs.
--]]
