-- // VisionWare Silent Aim
-- // Hooks raycast + Mouse.Hit/Target calls and redirects them to the best target.
-- // Uses the project Library (gui.lua) flags: SilentAim_*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
	C.Method = get("SilentAim_Method", "Raycast")
	C.TeamCheck = get("SilentAim_TeamCheck", false)
	C.VisibleCheck = get("SilentAim_VisibleCheck", false)
	C.FoV = get("SilentAim_FoV", true)
	C.FoVSize = get("SilentAim_FoVSize", 80)
	C.HitChance = get("SilentAim_HitChance", 100)
	C.ShowTarget = get("SilentAim_ShowTarget", false)
	C.Prediction = get("SilentAim_Prediction", false)
	C.PredAmount = get("SilentAim_PredAmount", 0.165)
end

-- cache exec-only hooks once (guarded so the script never hard-crashes)
local hookmetamethod = hookmetamethod or (getgenv and getgenv().hookmetamethod)
local newcclosure = newcclosure or (getgenv and getgenv().newcclosure)
local checkcaller = checkcaller or (getgenv and getgenv().checkcaller)
local getnamecallmethod = getnamecallmethod or (getgenv and getgenv().getnamecallmethod)
local HaveHooks = type(hookmetamethod) == "function"
	and type(newcclosure) == "function"
	and type(checkcaller) == "function"
	and type(getnamecallmethod) == "function"

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
	local target = part.Position
	local character = part:FindFirstAncestorOfClass("Model")
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(origin, target - origin, params)
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

local function getClosestPlayer(camera)
	local hitpartName = C.Hitpart
	local mouse = UserInputService:GetMouseLocation()
	local best, bestDist = nil, 1e9
	local camFov = camera.FieldOfView
	local radius = C.FoV and FovScreenRadius(C.FoVSize, camera.ViewportSize.Y, camFov) or 1e9

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

local function getDirection(origin, position)
	return (position - origin).Unit * 1000
end

-- ===== Target box overlay (line-based: this executor cannot render Drawing "Square") =====
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
	if not (C.ShowTarget and C.Enabled and camera) then
		hideTargetBox()
		return
	end
	local target = getClosestPlayer(camera)
	if not target then
		hideTargetBox()
		return
	end
	local root = (target:FindFirstAncestorOfClass("Model") or {}).PrimaryPart or target
	local screen, onScreen = camera:WorldToViewportPoint(root.Position)
	if not onScreen then
		hideTargetBox()
		return
	end
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
	for i = 9, #TargetPool do
		if TargetPool[i] then TargetPool[i].Visible = false end
	end
end)

-- ===== Hooks =====
if not HaveHooks then
	warn("[VisionWare] Silent Aim requires hookmetamethod/newcclosure/checkcaller - not available, silent aim disabled.")
else
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
		local self = ...
		if not (C.Enabled and self == Workspace and not checkcaller()) then
			return oldNamecall(...)
		end

		local method = getnamecallmethod()
		local args = { ... }

		if method == "Raycast" and C.Method == "Raycast" and #args >= 3 then
			if CalculateChance(C.HitChance) then
				local camera = Workspace.CurrentCamera
				local target = camera and getClosestPlayer(camera)
				if target then
					args[3] = getDirection(args[2], target.Position)
				end
			end
			return oldNamecall(unpack(args))
		end

		if (method == "FindPartOnRayWithIgnoreList" and C.Method == "FindPartOnRayWithIgnoreList")
			or (method == "FindPartOnRayWithWhitelist" and C.Method == "FindPartOnRayWithWhitelist")
			or ((method == "FindPartOnRay" or method == "findPartOnRay") and C.Method == "FindPartOnRay") then
			if #args >= 2 and CalculateChance(C.HitChance) then
				local camera = Workspace.CurrentCamera
				local target = camera and getClosestPlayer(camera)
				local aRay = args[2]
				if target and aRay then
					args[2] = Ray.new(aRay.Origin, getDirection(aRay.Origin, target.Position))
				end
			end
			return oldNamecall(unpack(args))
		end

		return oldNamecall(...)
	end))

	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, index)
		if C.Enabled and not checkcaller() and C.Method == "Mouse.Hit/Target"
			and self == LocalPlayer:GetMouse() then
			local target = getClosestPlayer(Workspace.CurrentCamera)
			if target then
				if index == "Target" or index == "target" then
					return target
				elseif index == "Hit" or index == "hit" then
					if C.Prediction and target:IsA("BasePart") then
						local v = target.AssemblyLinearVelocity
						return (target.CFrame + (v * C.PredAmount)).Position
					end
					return target.CFrame
				end
			end
		end
		return oldIndex(self, index)
	end))

	print("[VisionWare] Silent Aim loaded")
end