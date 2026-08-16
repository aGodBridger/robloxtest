-- // VisionWare Phantom Forces interface
-- // Phantom Forces hides enemy health / team / characters from the normal
-- // API (no meaningful Humanoids, Team is nil mid-match), so generic cheats
-- // see nothing. This module mirrors the Wapus approach: pull the game's
-- // internal module table out of the Lua heap with getgc, then read the
-- // *replicated* entry data (_isEnemy, character model hash, getHealth()).
-- //
-- // Exposes:
-- //   Pf.Active                    - true once the game modules are found
-- //   Pf.Resolve(player)           - view = { Character, Root, Head, Health, MaxHealth, Enemy }
-- //   Pf.ForEachEnemy(fn)          - iterate replicated enemy entries
-- //   Pf.PickTarget(...)           - crosshair-nearest enemy part
-- //   Pf.GetTargetVelocity(player) - enemy velocity estimate (movement buffer)
-- //   Pf.SolveTrajectory(...)      - ballistic muzzle velocity (drop+tvel)
-- //   Pf.GetActiveCamera/Weapon    - game camera/weapon objects
-- //   Pf.InstallBulletHook(fn)     - silent aim: rewrite outgoing bullet velocity
-- //   Pf.InstallCameraStepHook()   - freezes camera sway while aimbot is active

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Pf = {
	Active = false,
	modules = nil,
	AimbotActive = false,
}

-- ===== module extraction =====

local function getgcFn()
	local fn = getgc
	if fn ~= nil and type(fn) == "function" then return fn end
	local ok, v = pcall(function()
		return getgenv and getgenv().getgc
	end)
	if ok and type(v) == "function" then return v end
	return nil
end

local gcFn = getgcFn()

local function findModuleCache()
	if not gcFn then return nil end
	local ok, list = pcall(gcFn, true)
	if not ok or type(list) ~= "table" then
		local ok2, list2 = pcall(gcFn, false)
		if ok2 then list = list2 end
	end
	if type(list) ~= "table" then return nil end
	for _, v in next, list do
		if type(v) == "table" and rawget(v, "ScreenCull") and rawget(v, "NetworkClient") then
			return v
		end
	end
	return nil
end

local function extractModules(cache)
	local modules = {}
	for name, data in pairs(cache) do
		if type(name) == "string" and data then
			if type(data) == "table" then
				modules[name] = data.module
			else
				modules[name] = data
			end
		end
	end
	return modules
end

local function install()
	if Pf.Active then return true end
	local cache = findModuleCache()
	if not cache then return false end
	local modules = extractModules(cache)
	if not modules.ReplicationInterface then return false end
	Pf.modules = modules
	Pf.Active = true
	return true
end

task.spawn(function()
	for _ = 1, 60 do
		if install() then
			print("[VisionWare] Phantom Forces interface ready")
			return
		end
		task.wait(2)
	end
	print("[VisionWare] Phantom Forces modules not found - running generic mode")
end)

-- ===== safe accessors =====

local function call(method, obj, ...)
	if type(method) ~= "function" then return nil end
	local ok, a = pcall(method, obj, ...)
	if not ok then return nil end
	return a
end

function Pf.GetReplicationInterface()
	local m = Pf.modules
	return m and m.ReplicationInterface or nil
end

function Pf.GetEntry(player)
	local ri = Pf.GetReplicationInterface()
	if not ri or not player then return nil end
	local ok, entry = pcall(ri.getEntry, ri, player)
	if not ok or not entry then return nil end
	return entry
end

function Pf.GetThirdPerson(entry)
	if not entry then return nil end
	if type(entry.getThirdPersonObject) == "function" then
		return call(entry.getThirdPersonObject, entry)
	end
	return entry._thirdPersonObject
end

function Pf.GetHash(tp)
	if not tp then return nil end
	return tp._characterModelHash or nil
end

function Pf.GetPart(tp, ...)
	local hash = Pf.GetHash(tp)
	if not hash then return nil end
	for _, name in ipairs({ ... }) do
		local p = hash[name]
		if p and p:IsA("BasePart") then return p end
	end
	return nil
end

-- The rendered replicated character Model (workspace instance).
function Pf.GetModel(tp)
	if not tp then return nil end
	if type(tp.getCharacterModel) == "function" then
		local m = call(tp.getCharacterModel, tp)
		if m and m:IsA("Model") then return m end
	end
	local hash = Pf.GetHash(tp)
	if hash then
		for _, part in pairs(hash) do
			if part and type(part.IsA) == "function" and part:IsA("BasePart") then
				local model = part:FindFirstAncestorOfClass("Model")
				if model then return model end
			end
		end
	end
	return nil
end

function Pf.GetRoot(tp)
	if tp and type(tp.getRootPart) == "function" then
		local r = call(tp.getRootPart, tp)
		if r and r:IsA("BasePart") then return r end
	end
	return Pf.GetPart(tp, "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "RootPart")
end

function Pf.GetHead(tp)
	return Pf.GetPart(tp, "Head")
end

-- Mirrors a player's vital replicated data, or nil if absent/unready.
function Pf.Resolve(player)
	if not Pf.Active then return nil end
	local entry = Pf.GetEntry(player)
	if not entry then return nil end
	local tp = Pf.GetThirdPerson(entry)
	if not tp then return nil end
	local model = Pf.GetModel(tp)
	local root = Pf.GetRoot(tp)
	local head = Pf.GetHead(tp) or (model and model:FindFirstChild("Head")) or root
	if not (model and root) then return nil end

	local health, maxHealth = 100, 100
	if type(entry.getHealth) == "function" then
		local h = call(entry.getHealth, entry)
		if type(h) == "number" then health = h end
	end

	return {
		Player = player,
		Entry = entry,
		ThirdPerson = tp,
		Character = model,
		Root = root,
		Head = head,
		Health = health,
		MaxHealth = maxHealth,
		Enemy = entry._isEnemy == true,
	}
end

function Pf.ForEachEnemy(cb)
	if not Pf.Active then return end
	local ri = Pf.GetReplicationInterface()
	if not ri or type(ri.operateOnAllEntries) ~= "function" then return end
	pcall(ri.operateOnAllEntries, ri, function(player, entry)
		pcall(cb, player, entry)
	end)
end

-- ===== target selection (nearest to crosshair on screen) =====

local function FovScreenRadius(fovDeg, viewportY, camFov)
	local theta = math.rad(math.clamp(fovDeg, 1, 179) / 2)
	local phi = math.rad(math.clamp(camFov, 1, 179) / 2)
	return (viewportY / 2) * (math.tan(theta) / math.tan(phi))
end

function Pf.RayVisible(camera, part)
	local model = part:FindFirstAncestorOfClass("Model")
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { model, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
	if not result then return true end
	if result.Instance and result.Instance:IsDescendantOf(model or part) then return true end
	return false
end

-- Returns the world position of the best enemy part (or nil).
function Pf.PickTarget(camera, partName, useFoV, fovSize, visibleCheck, teamCheck)
	if not Pf.Active or not camera then return nil end
	partName = partName or "Head"
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local radius = useFoV and FovScreenRadius(fovSize or 50, camera.ViewportSize.Y, camera.FieldOfView) or 1e9
	local best, bestDist, bestPlayer, bestPart

	Pf.ForEachEnemy(function(player, entry)
		local tp = Pf.GetThirdPerson(entry)
		if not tp then return end
		local part
		if partName == "Torso" then
			part = Pf.GetPart(tp, "Torso", "UpperTorso", "LowerTorso", "HumanoidRootPart")
		elseif partName == "HumanoidRootPart" or partName == "RootPart" then
			part = Pf.GetRoot(tp) or Pf.GetPart(tp, "Torso", "Head")
		else
			part = Pf.GetPart(tp, partName, "Head")
		end
		if not part then return end
		if teamCheck and entry._isEnemy ~= true then return end
		if visibleCheck and not Pf.RayVisible(camera, part) then return end

		local screen, onScreen = camera:WorldToViewportPoint(part.Position)
		if onScreen and screen.Z > 0 then
			local d = (Vector2.new(screen.X, screen.Y) - center).Magnitude
			if d <= radius and d < (bestDist or 1e9) then
				bestDist = d
				best = part.Position
				bestPlayer = player
				bestPart = part
			end
		end
	end)

	return best, bestPart, bestPlayer
end

-- ===== movement buffer (enemy velocity estimate) =====

local mvPos, mvTime = {}, {}
local MV_SIZE = 15

RunService.Heartbeat:Connect(function()
	if not Pf.Active then return end
	local now = os.clock()
	table.insert(mvTime, 1, now)
	table.remove(mvTime, MV_SIZE + 1)
	Pf.ForEachEnemy(function(player, entry)
		local head = Pf.GetHead(Pf.GetThirdPerson(entry))
		if head then
			local list = mvPos[player]
			if not list then
				list = {}
				mvPos[player] = list
			end
			table.insert(list, 1, head.Position)
			table.remove(list, MV_SIZE + 1)
		end
	end)
end)

function Pf.GetTargetVelocity(player)
	local pos = mvPos[player]
	if not pos or #pos < 4 then return Vector3.new() end
	local t1, t2 = mvTime[1], mvTime[#mvTime]
	if not t1 or not t2 or t1 - t2 < 0.001 then return Vector3.new() end
	return (pos[1] - pos[#pos]) / (t1 - t2)
end

-- ===== ballistics =====

-- Muzzle velocity so a projectile of `speed` launched from `origin` under
-- `accel` hits `target` accounting for the target's velocity `tvel`.
-- Fixed-point time-of-flight iteration (no quartic solver needed; converges
-- in a few steps for PF bullet speeds).
function Pf.SolveTrajectory(origin, accel, target, speed, tvel)
	origin = origin or Vector3.new()
	accel = accel or Vector3.new(0, -Workspace.Gravity, 0)
	speed = speed or 10000
	tvel = tvel or Vector3.new()
	local ld = target - origin
	local t = math.clamp(ld.Magnitude / math.max(speed, 1), 0.001, 20)

	for _ = 1, 8 do
		local full = ld + tvel * t - accel * (0.5 * t * t)
		local mag = full.Magnitude
		if mag < 1e-4 then break end
		local tn = mag / speed
		if math.abs(tn - t) < 0.0001 then
			t = tn
			break
		end
		t = tn
	end

	local full = ld + tvel * t - accel * (0.5 * t * t)
	if full.Magnitude < 1e-4 then return nil end
	return full / t, t
end

function Pf.VelocityToAngles(v)
	local x, y, z = v.X, v.Y, v.Z
	local mag = math.sqrt(x * x + y * y + z * z)
	if mag < 1e-6 then return 0, 0 end
	local pitch = math.asin(math.clamp(y / mag, -1, 1))
	local yaw = math.atan2(-x, -z)
	return pitch, yaw
end

-- ===== game object accessors =====

function Pf.GetBulletAcceleration()
	local m = Pf.modules
	local ps = m and m.PublicSettings
	if ps then
		local ok, a = pcall(function() return ps.bulletAcceleration end)
		if ok and type(a) == "userdata" and typeof(a) == "Vector3" then return a end
	end
	return Vector3.new(0, -Workspace.Gravity, 0)
end

function Pf.GetActiveCamera()
	local m = Pf.modules
	local ci = m and m.CameraInterface
	if not ci or type(ci.getActiveCamera) ~= "function" then return nil end
	return call(ci.getActiveCamera, ci)
end

function Pf.GetActiveWeapon()
	local m = Pf.modules
	local wi = m and m.WeaponControllerInterface
	if not wi or type(wi.getActiveWeaponController) ~= "function" then return nil end
	local controller = call(wi.getActiveWeaponController, wi)
	if not controller then return nil end
	local ok, weapon = pcall(controller.getActiveWeapon, controller)
	if not ok then return nil end
	return weapon or nil
end

function Pf.GetWeaponData(weapon)
	if not weapon then return nil end
	if type(weapon.getWeaponData) == "function" then
		local d = call(weapon.getWeaponData, weapon)
		if d then return d end
	end
	return weapon._weaponData or nil
end

-- ===== silent aim: bullet velocity rewrite =====

local bulletHookInstalled = false

-- rewriteFn(origin, baseVelocity, acceleration) -> newVelocity or nil
function Pf.InstallBulletHook(rewriteFn)
	if bulletHookInstalled or not Pf.Active then return end
	local bo = Pf.modules and Pf.modules.BulletObject
	if not (bo and type(bo.new) == "function") then return end
	local orig = bo.new
	bo.new = function(bulletData)
		if rewriteFn and bulletData then
			local ok, newVel = pcall(rewriteFn,
				bulletData.position or bulletData.firepos,
				bulletData.velocity,
				bulletData.acceleration)
			if ok and newVel and typeof(newVel) == "Vector3" then
				bulletData.velocity = newVel
			end
		end
		return orig(bulletData)
	end
	bulletHookInstalled = true
end

-- ===== aimbot support: freeze camera sway while locked =====

local stepHookInstalled = false

function Pf.InstallCameraStepHook()
	if stepHookInstalled or not Pf.Active then return end
	local co = Pf.modules and Pf.modules.MainCameraObject
	if not (co and type(co.step) == "function") then return end
	local mainStep = co.step
	co.step = function(self, dt)
		if Pf.AimbotActive then
			mainStep(self, 0)
			self._lookDt = dt or self._lookDt
			return
		end
		return mainStep(self, dt)
	end
	stepHookInstalled = true
end

-- ===== expose =====

_G.Pf = Pf
pcall(function()
	if getgenv then getgenv().Pf = Pf end
end)

print("[VisionWare] Phantom Forces interface loaded (getgc: " .. tostring(gcFn ~= nil) .. ")")