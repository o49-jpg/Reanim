--//====================================================\\--
--||                Animator6D Pro V4 (R6)             ||--
--||  Author: gObl00x + GPT-5                         ||--
--||  Features: universal rig, local cache, safe play  ||--
--||           + Animation Serialization System        ||--
--\\====================================================//--

if getgenv().Animator6DLoadedPro then return end
getgenv().Animator6DLoadedPro = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")

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

local R6Map = {
	["Head"] = "Neck",
	["Torso"] = "RootJoint",
	["Right Arm"] = "Right Shoulder",
	["Left Arm"] = "Left Shoulder",
	["Right Leg"] = "Right Hip",
	["Left Leg"] = "Left Hip"
}

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
	for _, m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") then
			map[m.Name] = m
			lower[string.lower(m.Name)] = m
		end
	end
	return map, lower
end

local function FindMotor(poseName, map, lower)
	local match = R6Map[poseName] or poseName
	return map[match] or lower[string.lower(match)]
end

-- ========== ANIMATION SERIALIZATION SYSTEM ==========
-- (FIXED AND INTEGRATED WITH ANIMATOR6D)

-- Save KeyframeSequence to JSON string
local function SerializeAnimation(kfs)
	if not kfs or not kfs:IsA("KeyframeSequence") then
		warn("[Animator6D] ❌ Not a KeyframeSequence")
		return nil
	end

	local data = {
		Name = kfs.Name,
		Loop = kfs.Loop,
		Priority = kfs.Priority and kfs.Priority.Name or "Core",
		Keyframes = {}
	}

	for _, frame in ipairs(kfs:GetKeyframes()) do
		local frameData = {
			Time = frame.Time,
			Poses = {}
		}

		for _, pose in ipairs(frame:GetDescendants()) do
			if pose:IsA("Pose") and pose.Weight > 0 then
				local components = {pose.CFrame:GetComponents()}
				table.insert(frameData.Poses, {
					Name = pose.Name,
					CFrame = components,
					Weight = pose.Weight,
					Mask = pose.Mask
				})
			end
		end

		table.insert(data.Keyframes, frameData)
	end

	local success, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)

	if success then
		return json
	else
		warn("[Animator6D] ❌ Failed to encode animation")
		return nil
	end
end

-- Load KeyframeSequence from JSON string
local function DeserializeAnimation(json, newName)
	if not json then
		warn("[Animator6D] ❌ No JSON data")
		return nil
	end

	local success, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)

	if not success or not data then
		warn("[Animator6D] ❌ Failed to decode JSON")
		return nil
	end

	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = newName or data.Name or "Animation"
	kfs.Loop = data.Loop or false
	kfs.Priority = Enum.AnimationPriority[data.Priority] or Enum.AnimationPriority.Core

	for _, frameData in ipairs(data.Keyframes or {}) do
		local frame = Instance.new("Keyframe")
		frame.Time = frameData.Time or 0
		frame.Parent = kfs

		for _, poseData in ipairs(frameData.Poses or {}) do
			local pose = Instance.new("Pose")
			pose.Name = poseData.Name or "Unknown"

			if poseData.CFrame and #poseData.CFrame >= 12 then
				local cf = poseData.CFrame
				pose.CFrame = CFrame.new(
					cf[1], cf[2], cf[3],
					cf[4], cf[5], cf[6],
					cf[7], cf[8], cf[9],
					cf[10], cf[11], cf[12]
				)
			else
				pose.CFrame = CFrame.new()
			end

			pose.Weight = poseData.Weight or 1
			pose.Mask = poseData.Mask or 0
			pose.Parent = frame
		end
	end

	return kfs
end

-- Save animation to a string for permanent storage
local function SaveAnimationToLibrary(kfs, libraryName)
	local json = SerializeAnimation(kfs)
	if json then
		-- Store in getgenv() for persistence across script reloads
		if not getgenv().AnimationLibrary then
			getgenv().AnimationLibrary = {}
		end
		getgenv().AnimationLibrary[libraryName or kfs.Name] = json
		warn("[Animator6D] ✅ Saved animation to library:", libraryName or kfs.Name)
		return json
	end
	return nil
end

-- Load animation from library by name
local function LoadAnimationFromLibrary(libraryName, newName)
	if getgenv().AnimationLibrary and getgenv().AnimationLibrary[libraryName] then
		local kfs = DeserializeAnimation(getgenv().AnimationLibrary[libraryName], newName or libraryName)
		if kfs then
			warn("[Animator6D] ✅ Loaded from library:", libraryName)
			return kfs
		end
	end
	warn("[Animator6D] ❌ Animation not in library:", libraryName)
	return nil
end

-- ========== ANIM PLAYER ==========
local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rig, kfs)
	local self = setmetatable({}, AnimPlayer)
	self.rig = rig
	self.seq, self.looped = ConvertToTable(kfs)
	self.map, self.lower = BuildMotorMap(rig)
	self.time, self.playing = 0, false
	self.length = self.seq[#self.seq].Time
	self.speed = 1
	self.savedC0 = {}
	for _, m in pairs(self.map) do
		self.savedC0[m] = m.C0
	end
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

		local prev = self.seq[1]
		for i = 1, #self.seq do
			if self.seq[i].Time <= self.time then
				prev = self.seq[i]
			else
				break
			end
		end

		for joint, data in pairs(prev.Data) do
			local motor = FindMotor(joint, self.map, self.lower)
			if motor then
				pcall(function()
					motor.C0 = self.savedC0[motor] * data.CFrame
				end)
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

	-- Handle different input types
	if typeof(idOrInstance) == "Instance" then
		-- Direct instance
		kfs = idOrInstance:IsA("KeyframeSequence") and idOrInstance or idOrInstance:FindFirstChildOfClass("KeyframeSequence")
	elseif type(idOrInstance) == "string" then
		-- Try loading from library first (for saved animations)
		kfs = LoadAnimationFromLibrary(idOrInstance, idOrInstance)

		-- If not in library, try loading as asset ID
		if not kfs then
			local asset = LoadLocalAsset(idOrInstance)
			if asset then
				kfs = asset:FindFirstChildOfClass("KeyframeSequence") or asset
			end
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

	-- Return the animation for chaining
	return anim
end

getgenv().Animator6DStop = function()
	if getgenv().currentAnimator6D then
		pcall(function() getgenv().currentAnimator6D:Stop(true) end)
		getgenv().currentAnimator6D = nil
	end
end

-- ========== NEW: ANIMATION LIBRARY FUNCTIONS ==========

-- Save current or specified animation to library
getgenv().Animator6DSave = function(animationName, kfs)
	if not kfs and getgenv().currentAnimator6D then
		-- If no kfs provided, try to get from current animation
		-- Note: This requires storing the original kfs in AnimPlayer
		warn("[Animator6D] ❌ Please provide KeyframeSequence to save")
		return
	end

	if kfs then
		return SaveAnimationToLibrary(kfs, animationName)
	else
		warn("[Animator6D] ❌ No animation to save")
	end
end

-- Load animation from library
getgenv().Animator6DLoad = function(libraryName, speed, looped)
	local kfs = LoadAnimationFromLibrary(libraryName, libraryName)
	if kfs then
		return getgenv().Animator6D(kfs, speed, looped)
	else
		warn("[Animator6D] ❌ Animation not found in library:", libraryName)
	end
end

-- List all animations in library
getgenv().Animator6DList = function()
	if getgenv().AnimationLibrary then
		print("[Animator6D] 📚 Animations in library:")
		for name, _ in pairs(getgenv().AnimationLibrary) do
			print("  - " .. name)
		end
	else
		print("[Animator6D] 📚 Library is empty")
	end
end

-- ========== NOTIFY ==========
warn("[Animator6D Pro V4] ya.. Allah hotbar + Serialization System")
pcall(function()
	game:GetService("StarterGui"):SetCore("SendNotification", {
		Title = "Animator6D Pro V4",
		Text = "Loaded with Serialization Support!",
		Duration = 5
	})
end)

--[[
============================================================================
                           COMPLETE INSTRUCTIONS
============================================================================

1. BASIC USAGE (original):
   getgenv().Animator6D(1234567890, 1, true) -- idOrInstance, Speed, Looped?
   getgenv().Animator6DStop()

2. USING INSTANCES:
   local animInstance = game:GetObjects("rbxassetid://ID")[1] -- Path to KeyframeSequence
   getgenv().Animator6D(animInstance, 1, true)

3. SAVE ANIMATION TO LIBRARY (permanent storage in getgenv()):
   -- First, load an animation normally
   local anim = game:GetObjects("rbxassetid://118607369830566")[1]
   local kfs = anim:FindFirstChildOfClass("KeyframeSequence")
   
   -- Save it to the library with a name
   getgenv().Animator6DSave("MyIdle", kfs)
   
   -- Later, play it from library (even after script reload!)
   getgenv().Animator6DLoad("MyIdle", 1, true)

4. SERIALIZE TO JSON (for permanent storage outside Roblox):
   local anim = game:GetObjects("rbxassetid://118607369830566")[1]
   local kfs = anim:FindFirstChildOfClass("KeyframeSequence")
   local json = SerializeAnimation(kfs)
   print(json) -- Copy this JSON to save permanently

5. LOAD FROM JSON:
   local json = [[paste your JSON here]]
   local kfs = DeserializeAnimation(json, "MyAnimation")
   getgenv().Animator6D(kfs, 1, true)

6. LIST SAVED ANIMATIONS:
   getgenv().Animator6DList()

7. IMPORTANT NOTES:
   - The script automatically disables default Roblox animations
   - Only R6 rigs are supported (uses Motor6D joints)
   - Animations are cached locally to avoid 403 errors
   - The library in getgenv() persists across script reloads
   - JSON serialization allows permanent storage anywhere

============================================================================
--]]
