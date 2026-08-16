-- // VisionWare Silent Aim (Body-Rotate mode)
-- // The camera is NEVER touched/moved. Instead the character's HumanoidRootPart
-- // is yaw-rotated to face the best target, so shots travel toward the enemy
-- // while you keep full, independent control of the camera.
-- // Uses the project Library (gui.lua) flags: SilentAim_*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function getLibrary()
	return _G.Library or (getgenv and getgenv().Library)
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
	C.Enabled = get("SilentAim_Enabled", true) and not get("Misc_Panic", false)
	C.Hitpart = get("SilentAim_Hitpart", "Head")
	C.TeamCheck = get("SilentAim_TeamCheck", false)
	C.VisibleCheck = get("SilentAim_VisibleCheck", false)
	C.FoV = get("SilentAim_FoV", true)
	C.FoVSize = get("SilentAim_FoVSize", 80)
	C.HitChance = get("SilentAim_HitChance", 100)
	C.ShowTarget = get("SilentAim_ShowTarget", false)
	C.Prediction = get("SilentAim_Prediction", false)
	C.PredAmount = get("SilentAim_PredAmount", 0.165)
end

local function FindPart(character, partName)
	if not character then return nil end
	local part = character:FindFirstChild(partName)
	if part then return part end
	if partName == "Torso" then
		return character:FindFirstChild("UpperTorso")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("LowerTorso")
			or character:FindFirstChild("HumanoidRootPart")
	end
	return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function isVisible(camera, part)
	local origin = camera.CFrame.Position
	local character = part:FindFirstAncestorOfClass("Model")
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(origin, part.Position - origin, params)
	if not result then return true end
	if character and result.Instance and result.Instance:IsDescendantOf(character) then return true end
	return false
end

local function FovScreenRadius(fovDeg, viewportY, camFov)
	local theta = math.rad(math.clamp(fovDeg, 1, 179) / 2)
	local phi = math.rad(math.clamp(camFov, 1, 179) / 2)
	return (viewportY / 2) * (math.tan(theta) / math.tan(phi))
end

local function CalculateChance(percentage)
	return math.random() * 100 <= (percentage or 100)
end

local function predictedPoint(part, camera)
	if not C.Prediction or not part:IsA("BasePart") then return part.Position end
	local v = part.AssemblyLinearVelocity
	return part.Position + (v * C.PredAmount)
end

local function getClosestTarget(camera)
	if not camera then return nil end
	local hitpartName = C.Hitpart
	local UIS = game:GetService("UserInputService")
	local mouse = UIS:GetMouseLocation()
	local best, bestDist = nil, 1e9
	local radius = C.FoV and FovScreenRadius(C.FoVSize, camera.ViewportSize.Y, camera.FieldOfView) or 1e9

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			if not (C.TeamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team) then
				local character = player.Character
				local part = FindPart(character, hitpartName)
				if part then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 and (not C.VisibleCheck or isVisible(camera, part)) then
						local screen, onScreen = camera:WorldToViewportPoint(part.Position)
						if onScreen then
							local dist = (Vector2.new(screen.X, screen.Y) - mouse).Magnitude
							if dist <= radius and dist < bestDist then
								bestDist = dist
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

-- ===== Body rotation =====
local function rotateCharacterTo(target)
	local character = LocalPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local aimPoint = predictedPoint(target, Workspace.CurrentCamera)
	local pos = root.Position
	local dir = Vector3.new(aimPoint.X - pos.X, 0, aimPoint.Z - pos.Z)
	if dir.Magnitude < 0.01 then return end

	-- yaw-only rotation so the character stays upright and the camera is untouched
	local yaw = math.atan2(dir.X, dir.Z)
	root.CFrame = CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(0, yaw, 0)
end

-- ===== Target box overlay (line-based: executor can't render Drawing "Square") =====
local TargetPool = {}
do
	for i = 1, 8 do
		local ok, line = pcall(Drawing.new, "Line")
		if ok and line then
			line.Visible = false
			line.Color = Color3.fromRGB(54, 57, 241)
			line.Thickness = 1
			TargetPool[i] = line
		end
	end
end

local function hideTargetBox()
	for _, line in ipairs(TargetPool) do
		if line then line.Visible = false end
	end
end

RunService.RenderStepped:Connect(function()
	RefreshCache()
	local camera = Workspace.CurrentCamera
	if not (C.Enabled and camera) then
		hideTargetBox()
		return
	end

	local target = getClosestTarget(camera)
	if target and CalculateChance(C.HitChance) then
		rotateCharacterTo(target)
	else
		hideTargetBox()
	end

	if C.ShowTarget and target then
		local screen, onScreen = camera:WorldToViewportPoint(target.Position)
		if onScreen then
			local cx, cy = screen.X, screen.Y
			local s = 12
			local segs = {
				{ cx - s, cy - s, cx - s / 2, cy - s },
				{ cx + s / 2, cy - s, cx + s, cy - s },
				{ cx - s, cy + s / 2, cx - s, cy + s },
				{ cx + s / 2, cy + s, cx + s, cy + s },
				{ cx - s, cy - s, cx - s, cy - s / 2 },
				{ cx - s, cy + s, cx - s, cy + s / 2 },
				{ cx + s, cy - s, cx + s, cy - s / 2 },
				{ cx + s, cy + s, cx + s, cy + s / 2 },
			}
			for i, p in ipairs(segs) do
				local line = TargetPool[i]
				if line then
					line.From = Vector2.new(p[1], p[2])
					line.To = Vector2.new(p[3], p[4])
					line.Visible = true
				end
			end
		else
			hideTargetBox()
		end
	else
		hideTargetBox()
	end
	for i = 9, #TargetPool do
		if TargetPool[i] then TargetPool[i].Visible = false end
	end
end)

print("[VisionWare] Silent Aim loaded (body-rotate mode, camera is never moved)")