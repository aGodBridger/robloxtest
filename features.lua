-- // VisionWare Features
-- // Implements everything the GUI exposes that the other modules don't cover:
-- // triggerbot, weapon hacks, visuals (lighting), movement, and utility.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function getLibrary()
	return _G.Library or (getgenv and getgenv().Library)
end

local Library = nil
local function flag(name, default)
	if Library == nil then
		Library = _G.Library or (getgenv and getgenv().Library)
	end
	local v = Library and Library.Flags and Library.Flags[name]
	if v == nil then return default end
	return v
end

-- Snapshot the flags we care about once per tick.
local C = {}
local function RefreshCache()
	local L = Library
	if L == nil then
		L = _G.Library or (getgenv and getgenv().Library)
		Library = L
	end
	local F = L and L.Flags or {}
	local function get(n, d)
		local v = F[n]
		if v == nil then return d end
		return v
	end
	C.Panic = get("Misc_Panic", false)
	-- triggerbot / weapon
	C.Triggerbot = get("Triggerbot_Enabled", false) and not C.Panic
	C.TriggerKey = get("Triggerbot_Key", false)
	C.FireRate = get("Triggerbot_FireRate", 10)
	C.NoRecoil = get("Weapons_NoRecoil", false) and not C.Panic
	C.NoSpread = get("Weapons_NoSpread", false) and not C.Panic
	-- visuals
	C.Fullbright = get("Visuals_Fullbright", true) and not C.Panic
	C.Brightness = get("Visuals_Brightness", false)
	C.BrightnessAmount = get("Visuals_BrightnessAmount", 3)
	C.NoFog = get("Visuals_NoFog", false)
	C.Skybox = get("Visuals_Skybox", false)
	C.NoClouds = get("Visuals_Clouds", false)
	C.Ambient = get("Visuals_Ambient", 3)
	C.Highlight = get("Visuals_Highlight", false)
	C.HighlightColor = get("Visuals_HighlightColor", Color3.fromRGB(255, 255, 255))
	C.NightVision = get("Visuals_NightVision", false)
	C.NightVisionColor = get("Visuals_NightVisionColor", Color3.fromRGB(60, 255, 120))
	-- movement
	C.Speed = get("Misc_Speed", false)
	C.SpeedAmount = get("Misc_SpeedAmount", 80)
	C.Jump = get("Misc_Jump", false)
	C.JumpPower = get("Misc_JumpPower", 100)
	C.JumpInfinite = get("Misc_JumpInfinite", false)
	C.Noclip = get("Misc_Noclip", false)
	C.Fly = get("Misc_Fly", false)
	C.FlySpeed = get("Misc_FlySpeed", 50)
	C.FlyKey = get("Misc_FlyKey", false)
	C.Strafe = get("Misc_Strafe", false)
	C.Velocity = get("Misc_Velocity", false)
	C.VelocityAmount = get("Misc_VelocityAmount", 1)
	-- utility
	C.AntiAFK = get("Misc_AntiAFK", true)
	C.ChatSpam = get("Misc_ChatSpam", false)
	C.SpamText = get("Misc_SpamText", "VisionWare on top!")
	C.SpamDelay = get("Misc_SpamDelay", 2)
	C.FPSMode = get("Misc_FPSMode", false)
end

-- ============================================================
--  TRIGGERBOT
-- ============================================================

local function rayFromCenter(camera)
	local vp = camera.ViewportSize
	local ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	return Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
end

local function isEnemyHit(result)
	if not (result and result.Instance) then return false end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if not model then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	local player = Players:GetPlayerFromCharacter(model)
	if not player or player == LocalPlayer then return false end
	if flag("Triggerbot_TeamCheck", false) and player.Team ~= nil and player.Team == LocalPlayer.Team then
		return false
	end
	return true
end

local TriggerCooldown = 0
RunService.RenderStepped:Connect(function(dt)
	RefreshCache()
	if not C.Triggerbot or not C.TriggerKey then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end

	TriggerCooldown = TriggerCooldown - dt
	if TriggerCooldown > 0 then return end

	local hit = rayFromCenter(camera)
	if isEnemyHit(hit) then
		-- click at the actual crosshair position (where the ray was cast),
		-- down then up with a small delay so games that listen for a full click fire
		local vp = camera.ViewportSize
		local x, y = vp.X / 2, vp.Y / 2
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		end)
		task.delay(0.03, function()
			pcall(function()
				VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
			end)
		end)

		-- fallback: activate an equipped tool directly (some games ignore mouse events)
		local char = LocalPlayer.Character
		local tool = char and char:FindFirstChildOfType("Tool")
		if tool then
			pcall(function()
				tool:Activate()
			end)
		end
		TriggerCooldown = 1 / math.max(C.FireRate, 1)
	end
end)

-- ============================================================
--  WEAPON: NO RECOIL / NO SPREAD (gun stab)
-- ============================================================

local LastShot = 0
local ActiveGun = nil
local GunRestCFrame = nil

local function GetGun()
	if not LocalPlayer.Character then return nil end
	local tool = LocalPlayer.Character:FindFirstChildOfType("Tool")
	if not tool then return nil end
	return tool:FindFirstChild("Handle") or tool.PrimaryPart or nil
end

-- Continuously correct the gun pose toward its resting CFrame (no recoil/no spread).
RunService.RenderStepped:Connect(function(dt)
	if not (C.NoRecoil or C.NoSpread) then
		ActiveGun = nil
		GunRestCFrame = nil
		return
	end

	local gun = GetGun()
	if not gun then
		ActiveGun = nil
		GunRestCFrame = nil
		return
	end

	if gun ~= ActiveGun then
		ActiveGun = gun
		GunRestCFrame = gun.CFrame
	end

	if not GunRestCFrame then return end

	-- When the gun settles (no recent shots), refresh the resting pose.
	if tick() - LastShot > 0.75 then
		GunRestCFrame = gun.CFrame
		return
	end

	-- Within the window after a shot, ease the gun back to rest (anti-kick / anti-spread).
	if GunRestCFrame then
		pcall(function()
			gun.CFrame = gun.CFrame:Lerp(GunRestCFrame, math.min(1, dt * 14))
		end)
	end
end)

-- Detect shots (mouse down with a gun equipped) and record the rest pose to correct back to.
UserInputService.InputBegan:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and (C.NoRecoil or C.NoSpread) then
		local gun = GetGun()
		if gun then
			LastShot = tick()
			GunRestCFrame = gun.CFrame
		end
	end
end)

-- ============================================================
--  VISUALS (LIGHTING)
-- ============================================================

local SavedLighting = nil
local SkyboxInstance, ColorCorrection = nil, nil
local Highlights = {}

local function snapshotLighting()
	if SavedLighting then return end
	SavedLighting = {
		Ambient = Lighting.Ambient,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		FogColor = Lighting.FogColor,
		GlobalShadows = Lighting.GlobalShadows,
		Technology = Lighting.Technology,
		Sky = Lighting:FindFirstChildOfClass("Sky"),
		Clouds = Lighting:FindFirstChildOfClass("Clouds"),
		ColorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect"),
	}
end

local function restoreLighting()
	if not SavedLighting then return end
	local s = SavedLighting
	pcall(function()
		Lighting.Ambient = s.Ambient
		Lighting.Brightness = s.Brightness
		Lighting.ClockTime = s.ClockTime
		Lighting.FogEnd = s.FogEnd
		Lighting.FogStart = s.FogStart
		Lighting.FogColor = s.FogColor
		Lighting.GlobalShadows = s.GlobalShadows
		Lighting.Technology = s.Technology
	end)
	if SkyboxInstance then pcall(function() SkyboxInstance:Destroy() end) end
	if ColorCorrection then pcall(function() ColorCorrection:Destroy() end) end
	SkyboxInstance, ColorCorrection = nil, nil, nil
	SavedLighting = nil
end

local function applyLighting()
	snapshotLighting()

	-- Fullbright + brightness handling
	if C.Fullbright then
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.GlobalShadows = false
	else
		if C.Brightness then
			Lighting.Brightness = C.BrightnessAmount
		else
			Lighting.Brightness = SavedLighting.Brightness
		end
		Lighting.Ambient = Color3.new(C.Ambient / 10, C.Ambient / 10, C.Ambient / 10)
		Lighting.GlobalShadows = true
	end

	-- Fog
	if C.NoFog then
		Lighting.FogEnd = 999999
		Lighting.FogStart = 0
	else
		Lighting.FogEnd = SavedLighting.FogEnd
		Lighting.FogStart = SavedLighting.FogStart
	end

-- Custom skybox: force bright daytime + hide clouds (simple, no network dependency)
	if C.Skybox then
		pcall(function()
			Lighting.ClockTime = 12
			Lighting.TimeOfDay = "12:00:00"
		end)
	else
		pcall(function()
			Lighting.ClockTime = SavedLighting.ClockTime
		end)
	end

	-- No clouds
	local clouds = Lighting:FindFirstChildOfClass("Clouds")
	if C.NoClouds then
		if clouds then clouds.Enabled = false end
	elseif clouds then
		clouds.Enabled = true
	end

	-- Night vision: green tint + boost
	if C.NightVision then
		if not ColorCorrection then
			ColorCorrection = Instance.new("ColorCorrectionEffect")
			ColorCorrection.Parent = Lighting
		end
		ColorCorrection.Brightness = 0.25
		ColorCorrection.Contrast = 0.2
		ColorCorrection.Saturation = -0.5
		ColorCorrection.TintColor = C.NightVisionColor
	elseif ColorCorrection then
		pcall(function() ColorCorrection:Destroy() end)
		ColorCorrection = nil
	end
end

-- ============================================================
--  PLAYER HIGHLIGHT
-- ============================================================

local function applyHighlight(player)
	if player == LocalPlayer then return end
	if not (player.Character and C.Highlight) then
		local existing = Highlights[player]
		if existing then
			pcall(function() existing:Destroy() end)
			Highlights[player] = nil
		end
		return
	end
	local existing = Highlights[player]
	if existing and existing.Parent then
		if existing.FillColor ~= C.HighlightColor then
			existing.FillColor = C.HighlightColor
		end
		return
	end
	local hl = Instance.new("Highlight")
	hl.Name = "VisionWareHighlight"
	hl.Adornee = player.Character
	hl.FillColor = C.HighlightColor
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.5
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = player.Character
	Highlights[player] = hl
end

local function refreshHighlights()
	for _, player in ipairs(Players:GetPlayers()) do
		applyHighlight(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		if C.Highlight then applyHighlight(player) end
	end)
	if C.Highlight then applyHighlight(player) end
end)

Players.PlayerRemoving:Connect(function(player)
	local existing = Highlights[player]
	if existing then
		pcall(function() existing:Destroy() end)
		Highlights[player] = nil
	end
end)

RunService.Heartbeat:Connect(function()
	RefreshCache()
	applyLighting()
	refreshHighlights()
end)

-- ============================================================
--  MOVEMENT
-- ============================================================

-- Remember original stats so toggling off restores them properly.
local OrigStats = { Speed = nil, JumpPower = nil }
local function cacheOriginals(humanoid)
	if OrigStats.Speed == nil and humanoid then
		OrigStats.Speed = humanoid.WalkSpeed
		OrigStats.JumpPower = humanoid.JumpPower
	end
end
local function restoreOriginals(humanoid)
	if OrigStats.Speed ~= nil and humanoid then
		humanoid.WalkSpeed = OrigStats.Speed
		humanoid.JumpPower = OrigStats.JumpPower
		OrigStats.Speed = nil
		OrigStats.JumpPower = nil
	end
end

-- Many games re-assert WalkSpeed/JumpPower from the server, so we
-- re-apply every frame instead of throttling.
local function applyMovement(dt)
	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	cacheOriginals(humanoid)

	-- WalkSpeed (every frame to fight server resets)
	if C.Speed then
		humanoid.WalkSpeed = C.SpeedAmount
	elseif OrigStats.Speed ~= nil then
		restoreOriginals(humanoid)
	end

	-- Jump power: force legacy JumpPower mode so the value always applies.
	if C.Jump then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = C.JumpPower
	elseif OrigStats.JumpPower ~= nil then
		restoreOriginals(humanoid)
	end

	-- Noclip
	if C.Noclip then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end

	-- Velocity multiplier
	if C.Velocity and C.VelocityAmount > 0 then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X * C.VelocityAmount, v.Y, v.Z * C.VelocityAmount)
	end
end

-- Infinite jump: re-jump if in mid-air and holding space
UserInputService.JumpRequest:Connect(function()
	if flag("Misc_JumpInfinite", false) and not flag("Misc_Panic", false) then
		local char = LocalPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid and (humanoid:GetState() == Enum.HumanoidStateType.Freefall or humanoid:GetState() == Enum.HumanoidStateType.Jumping) then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

-- Strafe: boost while airborne to preserve momentum (BHop-style)
local function applyStrafe()
	if not C.Strafe then return end
	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not (humanoid and root and camera) then return end
	if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then return end

	local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
	local speed = root.AssemblyLinearVelocity.Magnitude
	if speed < 32 then
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + forward * (dt or 0.016) * 400
	end
end

-- Fly with key (no physics, direct CFrame-based flight)
local FlyDirection = Vector3.new(0, 0, 0)
RunService.RenderStepped:Connect(function(dt)
	dt = dt or 0.016
	RefreshCache()
	applyMovement(dt)
	applyStrafe()

	-- Fly: toggle drives it; if a fly key is bound, require holding it.
	local keyBound = (Library and Library.Flags and Library.Flags["Misc_FlyKey_KEY"]) ~= nil
	local fly = false
	if C.Fly and not C.Panic then
		if keyBound then
			fly = C.FlyKey
		else
			fly = true
		end
	end
	if not fly then return end

	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not (humanoid and root and camera) then return end

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local moveVec = Vector3.new(0, 0, 0)
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVec = moveVec + camera.CFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVec = moveVec - camera.CFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVec = moveVec - camera.CFrame.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVec = moveVec + camera.CFrame.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVec = moveVec + Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveVec = moveVec - Vector3.new(0, 1, 0) end

	moveVec = moveVec.Unit or Vector3.new(0, 0, 0)
	root.CFrame = root.CFrame + (moveVec * C.FlySpeed * dt * 2.5)
end)

-- ============================================================
--  UTILITY (ANTI AFK / CHAT SPAM / FPS MODE)
-- ============================================================

-- Anti-AFK: wiggle the camera + capture controller so you never time out
local AntiAFKActive = false
task.spawn(function()
	while true do
		task.wait(60)
		RefreshCache()
		if C.AntiAFK and not C.Panic then
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:Button2Down(Vector2.new(0, 0))
				task.wait(0.1)
				VirtualUser:Button2Up(Vector2.new(0, 0))
			end)
		end
	end
end)

-- Chat spam
local SpamRunning = false
task.spawn(function()
	while true do
		task.wait(1)
		RefreshCache()
		if C.ChatSpam and not C.Panic and not SpamRunning then
			SpamRunning = true
			task.spawn(function()
				while flag("Misc_ChatSpam", false) and not flag("Misc_Panic", false) do
					pcall(function()
						local ChatRemote = game:GetService("ReplicatedStorage")
							and game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
							and game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents:FindFirstChild("SayMessageRequest")
						if ChatRemote then
							ChatRemote:FireServer(C.SpamText, "All")
						end
					end)
					task.wait(C.SpamDelay)
				end
				SpamRunning = false
			end)
		end
	end
end)

-- FPS mode: lower graphics + hide non-essential GUIs
local FPSApplied = false
RunService.Heartbeat:Connect(function()
	RefreshCache()
	if C.FPSMode and not FPSApplied then
		FPSApplied = true
		pcall(function()
			game:GetService("RenderingSettings").QualityLevel = Enum.QualityLevel.QualityLevel1
		end)
		pcall(function()
			settings().QualityLevel = 1
		end)
		pcall(function()
			for _, v in ipairs(LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
				if v:IsA("ScreenGui") and v.Name ~= "VisionWareESPStatus" then
					v.Enabled = false
				end
			end
		end)
	elseif not C.FPSMode and FPSApplied then
		FPSApplied = false
		pcall(function()
			game:GetService("RenderingSettings").QualityLevel = Enum.QualityLevel.QualityLevel10
		end)
		pcall(function()
			settings().QualityLevel = 21
		end)
		pcall(function()
			for _, v in ipairs(LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
				if v:IsA("ScreenGui") then
					v.Enabled = true
				end
			end
		end)
	end
end)

print("[VisionWare] Features loaded")