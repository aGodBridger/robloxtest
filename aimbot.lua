local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function getLibrary()
	return _G.Library or (getgenv and getgenv().Library)
end

local function flag(name, default)
	local L = getLibrary()
	local v = L and L.Flags and L.Flags[name]
	if v == nil then return default end
	return v
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
	local hitpartName = flag("Aimbot_Hitpart", "Head")
	local targetMode = flag("Aimbot_Target", "Closest to Crosshair")
	local teamCheck = flag("Aimbot_TeamCheck", true)
	local visibleOnly = flag("Aimbot_VisibleOnly", false)
	local useFov = flag("Aimbot_FoV", true)
	local fovSize = flag("Aimbot_FoVSize", 50)

	local camFov = camera.FieldOfView
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local radius = FovScreenRadius(fovSize, camera.ViewportSize.Y, camFov)

	local best, bestScore = nil, 1e9
	local LocalCharacter = LocalPlayer.Character

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local character = player.Character
			local part = findHitpart(character, hitpartName)
			if isHeadValid(part) and (not teamCheck or player.Team ~= LocalPlayer.Team) then
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
	local amount = flag("Aimbot_PredAmount", 0.25)
	local dist = (part.Position - camera.CFrame.Position).Magnitude
	return part.Position + velocity * (amount * (dist / 750))
end

local function doAim()
	if not flag("Aimbot_Enabled", true) then return end
	if not flag("Aimbot_Key", false) then return end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local target = acquireTarget(camera)
	if not target then return end

	local aimPos = target.Position
	if flag("Aimbot_Prediction", false) then
		aimPos = predictedPosition(camera, target)
	end

	local smoothness = math.clamp(flag("Aimbot_Smoothness", 0.2), 0, 1)
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

RunService.RenderStepped:Connect(doAim)

print("[VisionWare] Aimbot loaded")