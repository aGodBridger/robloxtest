-- // VisionWare Silent Aim
-- // Redirects the shot toward the best target WITHOUT moving the camera.
-- // Hooks multiple shooting vectors so it works across games:
-- //   - Workspace:Raycast / FindPartOnRay*  (via game:__namecall)
-- //   - Mouse.Hit / Mouse.Target            (via Mouse class __index)
-- //   - Camera:ScreenPointToRay             (via camera __namecall)

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

-- cache exec-only functions once (guarded)
local hookmetamethod = hookmetamethod or (getgenv and getgenv().hookmetamethod)
local newcclosure = newcclosure or (getgenv and getgenv().newcclosure)
local checkcaller = checkcaller or (getgenv and getgenv().checkcaller)
local getnamecallmethod = getnamecallmethod or (getgenv and getgenv().getnamecallmethod)
local getrawmetatable = getrawmetatable or (getgenv and getgenv().getrawmetatable)

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

local function predictedPoint(part)
	if not C.Prediction or not part:IsA("BasePart") then return part.Position end
	local v = part.AssemblyLinearVelocity
	return part.Position + (v * C.PredAmount)
end

local function getClosestTarget(camera)
	if not camera then return nil end
	local hitpartName = C.Hitpart
	local mouse = UserInputService:GetMouseLocation()
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

-- once-per-method debug print so you can see which vector the game uses
local Logged = {}
local function debugHit(method)
	if Logged[method] then return end
	Logged[method] = true
	print(("[VisionWare] Silent Aim redirect fired via %s"):format(method))
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
	if C.ShowTarget then
		local target = getClosestTarget(camera)
		if target then
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
	end
	for i = 9, #TargetPool do
		if TargetPool[i] then TargetPool[i].Visible = false end
	end
end)

if not HaveHooks then
	warn("[VisionWare] Silent Aim needs hookmetamethod/newcclosure/checkcaller - disabled.")
	return
end

local WorkspaceHookMetatable = Workspace

-- ===== Hook 1: Workspace raycast family (game:__namecall) =====
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
	local self = ...
	if not (C.Enabled and self == Workspace and not checkcaller()) then
		return oldNamecall(...)
	end

	local method = getnamecallmethod()
	local args = { ... }

	if method == "Raycast" and (C.Method == "Raycast" or C.Method == "All") and #args >= 3 then
		if CalculateChance(C.HitChance) then
			local target = getClosestTarget(Workspace.CurrentCamera)
			if target then
				local origin = args[2]
				args[3] = (predictedPoint(target) - origin).Unit * 1000
				debugHit("Workspace:Raycast")
			end
		end
		return oldNamecall(unpack(args))
	end

	if method == "FindPartOnRayWithIgnoreList" and (C.Method == "FindPartOnRayWithIgnoreList" or C.Method == "All") and #args >= 2 then
		if CalculateChance(C.HitChance) then
			local target = getClosestTarget(Workspace.CurrentCamera)
			local aRay = args[2]
			if target and aRay then
				args[2] = Ray.new(aRay.Origin, (predictedPoint(target) - aRay.Origin).Unit * 1000)
				debugHit("FindPartOnRayWithIgnoreList")
			end
		end
		return oldNamecall(unpack(args))
	end

	if method == "FindPartOnRayWithWhitelist" and (C.Method == "FindPartOnRayWithWhitelist" or C.Method == "All") and #args >= 2 then
		if CalculateChance(C.HitChance) then
			local target = getClosestTarget(Workspace.CurrentCamera)
			local aRay = args[2]
			if target and aRay then
				args[2] = Ray.new(aRay.Origin, (predictedPoint(target) - aRay.Origin).Unit * 1000)
				debugHit("FindPartOnRayWithWhitelist")
			end
		end
		return oldNamecall(unpack(args))
	end

	if (method == "FindPartOnRay" or method == "findPartOnRay") and (C.Method == "FindPartOnRay" or C.Method == "All") and #args >= 2 then
		if CalculateChance(C.HitChance) then
			local target = getClosestTarget(Workspace.CurrentCamera)
			local aRay = args[2]
			if target and aRay then
				args[2] = Ray.new(aRay.Origin, (predictedPoint(target) - aRay.Origin).Unit * 1000)
				debugHit("FindPartOnRay")
			end
		end
		return oldNamecall(unpack(args))
	end

	return oldNamecall(...)
end))

-- ===== Hook 2: Camera:ScreenPointToRay (what a lot of FPS games use to fire) =====
local oldCamera
do
	local cam = Workspace.CurrentCamera
	if cam then
		oldCamera = getnamecallmethod and hookmetamethod(cam, "__namecall", newcclosure(function(...)
			local self = ...
			if not (C.Enabled and self == Workspace.CurrentCamera and not checkcaller()) then
				return oldCamera(...)
			end
			local method = getnamecallmethod()
			if (method == "ScreenPointToRay") and (C.Method == "Raycast" or C.Method == "All") then
				local target = getClosestTarget(self)
				if target and CalculateChance(C.HitChance) then
					debugHit("Camera:ScreenPointToRay")
					return Ray.new(self.CFrame.Position, (predictedPoint(target) - self.CFrame.Position).Unit * 1000)
				end
			end
			return oldCamera(...)
		end))
	end
end

-- ===== Hook 3: Mouse.Hit / Mouse.Target (via the Mouse __index) =====
local oldMouseIndex
do
	local mouse = LocalPlayer:GetMouse()
	local mm = getrawmetatable and getrawmetatable(mouse)
	if type(mm) == "table" and type(oldMouseIndex) ~= "function" then
		oldMouseIndex = hookmetamethod(mm, "__index", newcclosure(function(self, index)
			if self == mouse and C.Enabled and not checkcaller() and (C.Method == "Mouse.Hit/Target" or C.Method == "All") then
				local target = getClosestTarget(Workspace.CurrentCamera)
				if target then
					if index == "Target" or index == "target" then
						return target
					elseif index == "Hit" or index == "hit" then
						debugHit("Mouse.Hit")
						return CFrame.new(predictedPoint(target))
					elseif index == "X" or index == "x" then
						return self.X
					elseif index == "Y" or index == "y" then
						return self.Y
					elseif index == "UnitRay" then
						return Ray.new(self.Origin, (self.Hit - self.Origin).Unit)
					end
				end
			end
			return oldMouseIndex(self, index)
		end))
	end
end

print("[VisionWare] Silent Aim loaded (camera is never moved)")