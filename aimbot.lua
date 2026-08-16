local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Pf = _G.Pf or (getgenv and getgenv().Pf)

local function getLibrary()
	return _G.Library or (getgenv and getgenv().Library)
end

local function flag(name, default)
	local L = getLibrary()
	local v = L and L.Flags and L.Flags[name]
	if v == nil then return default end
	return v
end

local C = {}
local function RefreshCache()
	local L = getLibrary()
	local F = L and L.Flags or {}
	local function get(n, d)
		local v = F[n]
		if v == nil then return d end
		return v
	end
	C.Enabled = get("Aimbot_Enabled", true)
	C.Key = get("Aimbot_Key", false)
	C.Hitpart = get("Aimbot_Hitpart", "Head")
	C.Target = get("Aimbot_Target", "Closest to Crosshair")
	C.TeamCheck = get("Aimbot_TeamCheck", true)
	C.VisibleOnly = get("Aimbot_VisibleOnly", false)
	C.UseFov = get("Aimbot_FoV", true)
	C.FovSize = get("Aimbot_FoVSize", 50)
	C.Prediction = get("Aimbot_Prediction", false)
	C.PredAmount = get("Aimbot_PredAmount", 0.25)
	C.Smoothness = get("Aimbot_Smoothness", 0.2)
end

local function FovScreenRadius(fovDeg, viewportY, camFov)
	local theta = math.rad(math.clamp(fovDeg, 1, 179) / 2)
	local phi = math.rad(math.clamp(camFov, 1, 179) / 2)
	return (viewportY / 2) * (math.tan(theta) / math.tan(phi))
end

local function isHeadValid(head)
	if not head then return false end
	local character = head:FindFirstAncestorOfClass("Model")
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	local camera = Workspace.CurrentCamera
	if not camera then return false end
	local _, visible = camera:WorldToViewportPoint(head.Position)
	return visible
end

local function isVisible(camera, part)
	local character = part:FindFirstAncestorOfClass("Model")
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
	if not result then return true end
	if character and result.Instance and result.Instance:IsDescendantOf(character) then return true end
	return false
end

local function findHitpart(character, name)
	if not character then return nil end
	if name == "Head" then return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart") end
	if name == "HumanoidRootPart" then return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head") end
	if name == "Torso" then
		return character:FindFirstChild("UpperTorso")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("LowerTorso")
			or character:FindFirstChild("HumanoidRootPart")
	end
	return character:FindFirstChild(name) or character:FindFirstChild("Head")
end

local function acquireTarget(camera)
	local hitpartName = C.Hitpart
	local targetMode = C.Target
	local teamCheck = C.TeamCheck
	local visibleOnly = C.VisibleOnly
	local useFov = C.UseFov
	local fovSize = C.FovSize

	local camFov = camera.FieldOfView
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local radius = FovScreenRadius(fovSize, camera.ViewportSize.Y, camFov)

	local best, bestScore = nil, 1e9
	local LocalCharacter = LocalPlayer.Character

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local character = player.Character
			local part = findHitpart(character, hitpartName)
			if isHeadValid(part) and (not teamCheck or player.Team == nil or player.Team ~= LocalPlayer.Team) then
				if not visibleOnly or isVisible(camera, part) then
					local screen, onScreen = camera:WorldToViewportPoint(part.Position)
					if onScreen and screen.Z > 0 then
						local screenPoint = Vector2.new(screen.X, screen.Y)
						local dist = (screenPoint - center).Magnitude
						if not useFov or dist <= radius then
							local score
							if targetMode == "Lowest Health" then
								local humanoid = character:FindFirstChildOfClass("Humanoid")
								score = humanoid and humanoid.Health or 1e9
							elseif targetMode == "Closest to Player" then
								local root = character:FindFirstChild("HumanoidRootPart")
								local myRoot = LocalCharacter and LocalCharacter:FindFirstChild("HumanoidRootPart")
								if myRoot and root then
									score = (root.Position - myRoot.Position).Magnitude
								else
									score = 1e9
								end
							else
								score = dist
							end
							if score < bestScore then
								bestScore = score
								best = part
							end
						end
					end
				end
			end
		end
	end
	return best
end

local MoveMouse = mousemoverel
if type(MoveMouse) ~= "function" and getgenv then
	local ok = pcall(function() MoveMouse = getgenv().mousemoverel end)
	if not ok or type(MoveMouse) ~= "function" then MoveMouse = nil end
end

local function predictedPosition(camera, part)
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then return part.Position end
	local root = character:FindFirstChild("HumanoidRootPart") or part
	local velocity = root and root:IsA("BasePart") and root.AssemblyLinearVelocity or Vector3.new()
	if velocity.Magnitude < 0.1 then return part.Position end
	local amount = C.PredAmount
	local dist = (part.Position - camera.CFrame.Position).Magnitude
	return part.Position + velocity * (amount * (dist / 750))
end

local lastLock, lastLockTime = nil, 0

local function doAim()
	RefreshCache()
	if not C.Enabled then return end
	if not C.Key then return end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local target = acquireTarget(camera)
	if target then
		local now = os.clock()
		if target ~= lastLock and now - lastLockTime > 1 then
			lastLock, lastLockTime = target, now
			print(("[VisionWare] Aimbot locked onto %s"):format(target.Name))
		end
	else
		return
	end

	local aimPos = target.Position
	if C.Prediction then
		aimPos = predictedPosition(camera, target)
	end

	local smoothness = math.clamp(C.Smoothness, 0, 1)
	local factor = 1 - smoothness

	if MoveMouse then
		local screen = camera:WorldToViewportPoint(aimPos)
		if screen.Z > 0 then
			local delta = Vector2.new(screen.X, screen.Y) - UserInputService:GetMouseLocation()
			MoveMouse(delta.X * factor, delta.Y * factor)
		end
	else
		local pose = CFrame.new(camera.CFrame.Position, aimPos)
		camera.CFrame = camera.CFrame:Lerp(pose, math.clamp(factor, 0, 1))
	end
end

-- ============================================================
--  PHANTOM FORCES MODE
--  PF has no Humanoids/Teams we can read; enemies come from the
--  game's replication modules. Bullets drop, so we solve the
--  trajectory and write the game's internal camera angles.
-- ============================================================

local PfLastUpdate = 0
local PfAimTime = 0
local PfLocked = false

local function doPfAim(dt)
	RefreshCache()
	if not C.Enabled then
		if Pf then Pf.AimbotActive = false end
		return
	end
	if not C.Key then
		if Pf then Pf.AimbotActive = false end
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local now = os.clock()
	if now - PfLastUpdate < 1 / 30 then return end
	PfLastUpdate = now

	if not Pf then return end
	Pf.InstallCameraStepHook()

	local weapon = Pf.GetActiveWeapon()
	if not weapon then
		Pf.AimbotActive = false
		return
	end
	local weaponData = Pf.GetWeaponData(weapon)
	local speed = weaponData and weaponData.bulletspeed or 10000
	if not speed or speed <= 0 then speed = 10000 end

	local target, _, targetPlayer = Pf.PickTarget(camera, C.Hitpart, C.UseFov, C.FovSize, C.VisibleOnly, C.TeamCheck)
	if not target then
		Pf.AimbotActive = false
		return
	end

	local cameraObj = Pf.GetActiveCamera()
	if not cameraObj then return end
	if type(cameraObj._angles) ~= "userdata" then return end

	local aimPos = target
	-- bullet drop + target movement compensation
	local vel = Pf.SolveTrajectory(
		camera.CFrame * Vector3.new(0, 0, 0.5),
		Pf.GetBulletAcceleration(),
		aimPos,
		speed,
		Pf.GetTargetVelocity(targetPlayer)
	)
	if not vel then return end

	local pitch, yaw = Pf.VelocityToAngles(vel)

	-- clamp pitch into the weapon's allowed range so we never look at the floor/sky
	if type(cameraObj._minAngle) == "number" and type(cameraObj._maxAngle) == "number" then
		pitch = math.clamp(pitch, cameraObj._minAngle, cameraObj._maxAngle)
	end

	-- wrap yaw around the current camera yaw
	local cy = cameraObj._angles.Y
	local yawDelta = (yaw + math.pi - cy) % (math.pi * 2) - math.pi + cy

	local newAngles = Vector3.new(pitch, yawDelta, 0)

	local smoothness = math.clamp(C.Smoothness, 0, 1)
	if smoothness > 0 then
		if not PfLocked then
			PfAimTime = now
			PfLocked = true
		end
		-- quadratic ease-in: fast approach, slight settle
		local alpha = math.clamp(1 - smoothness + (now - PfAimTime) ^ 2, 0, 1)
		newAngles = cameraObj._angles:Lerp(newAngles, alpha)
	else
		PfLocked = false
	end

	cameraObj._delta = (newAngles - cameraObj._angles) / math.max(dt, 1e-4)
	cameraObj._angles = newAngles
	Pf.AimbotActive = true
end

RunService.RenderStepped:Connect(function(dt)
	if Pf and (Pf.Active or Pf.TemplateMode) then
		doPfAim(dt)
	else
		doAim()
	end
end)

print("[VisionWare] Aimbot loaded - hold the Activation Key (default: right-click) to aim.")