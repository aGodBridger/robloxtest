-- // VisionWare Phantom Forces interface
-- // Phantom Forces hides enemy health / team / characters from the normal
-- // API (no meaningful Humanoids, Team is nil mid-match, and the *visible*
-- // characters are PF's custom third-person models, not player.Character).
-- // This module mirrors the Wapus approach:
-- //   - pull the game's internal module table out of the Lua heap (getgc)
-- //   - read the replicated entry data directly:
-- //       entry._isEnemy
-- //       entry._thirdPersonObject._characterModelHash.Head / .Torso
-- //       entry:getHealth(), entry:getThirdPersonObject():getCharacterModel()
-- //   - ReplicationInterface methods are called DOT-style exactly like the
-- //     game does (operateOnAllEntries / getEntry do NOT take self)
-- //   - if the game modules cannot be found, fall back to PF's replicated
-- //     custom character models under workspace.Players (TemplateMode).
-- //
-- // Exposes:
-- //   Pf.Active                    - true once the game modules are found
-- //   Pf.TemplateMode              - true when only workspace custom models are visible
-- //   Pf.Resolve(player)           - view = { Character, Root, Head, Hash, Size, Health, MaxHealth, Enemy }
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
	TemplateMode = false,
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
		if type(v) == "table" then
			-- main module cache (Wapus signature)
			if rawget(v, "ScreenCull") and rawget(v, "NetworkClient") then
				return v
			end
		end
	end
	return nil
end

-- The module cache entries are { module = <module> } (or the module itself).
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
	-- harden: if the primary scan missed the interface, search for it by field
	if not modules.ReplicationInterface then
		for name, data in pairs(cache) do
			if type(data) == "table" and rawget(data, "operateOnAllEntries") and rawget(data, "getEntry") then
				modules.ReplicationInterface = data
				break
			end
		end
	end
	return modules
end

local function install()
	if Pf.Active then return true end
	local cache = findModuleCache()
	if not cache then
		Pf.TemplateMode = Pf.HasCustomModels()
		return false
	end
	local modules = extractModules(cache)
	if not modules.ReplicationInterface then
		Pf.TemplateMode = Pf.HasCustomModels()
		return false
	end
	Pf.modules = modules
	Pf.Active = true
	return true
end

task.spawn(function()
	for _ = 1, 60 do
		if install() then
			if Pf.Active then
				print("[VisionWare] Phantom Forces interface ready")
			else
				print("[VisionWare] Phantom Forces template mode (workspace custom models)")
			end
			return
		end
		task.wait(2)
	end
	print("[VisionWare] Phantom Forces modules not found - running generic mode")
end)

-- ===== workspace fallback: PF's custom third-person models =====
-- PF replicates each player's visible character as a model under
-- workspace.Players, named after the player. These custom models are what
-- ESP / aimbot must use - player.Character is the default rig PF hides.

function Pf.HasCustomModels()
	local folder = Workspace:FindFirstChild("Players")
	return not not (folder and #folder:GetChildren() > 0)
end

local PF_TEAMS = {
	["Bright blue"] = "Phantoms",
	["Bright orange"] = "Ghosts",
}

-- PF never gives us a usable Playing-Team mid-match; it ONLY colors the
-- player's TeamColor (Bright blue = Phantoms, Bright orange = Ghosts).
-- Resolve the team name from a BrickColor so ESP/aimbot can do team checks.
function Pf.TeamName(teamColor)
	return PF_TEAMS[tostring(teamColor)] or nil
end

-- true/false when both players have a mapped PF team color, nil otherwise.
function Pf.IsEnemy(player)
	if not player then return false end
	local mine = Pf.TeamName(LocalPlayer and LocalPlayer.TeamColor)
	local theirs = Pf.TeamName(player and player.TeamColor)
	if not mine or not theirs then return nil end
	return theirs ~= mine
end

local function findCustomModel(player)
	if not player then return nil end

	-- match by PlayerTag label first (PF spawns these with the player name)
	local folder = Workspace:FindFirstChild("Players")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				local tag = m:FindFirstChild("PlayerTag", true)
				if tag and tag:IsA("TextLabel") then
					local name = (tag.Text or ""):match("^%s*(.-)%s*$") or ""
					if (name == player.Name)
						or (player.DisplayName and name == player.DisplayName) then
						if m:FindFirstChild("Head") or m:FindFirstChild("Torso") then
							return m
						end
					end
				end
			end
		end
		-- fall back to model name matching
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model")
				and (m.Name == player.Name or (player.DisplayName and m.Name == player.DisplayName)) then
				if m:FindFirstChild("Head") or m:FindFirstChild("Torso") then
					return m
				end
			end
		end
	end
	local direct = Workspace:FindFirstChild(player.Name)
	if direct and direct:IsA("Model") and direct:FindFirstChild("Head") then
		return direct
	end
	return nil
end

-- Exposed for ESP/other modules that need the replicated workspace model.
function Pf.FindCustomModel(player)
	return findCustomModel(player)
end

local function customModelParts(m)
	if not m then return nil, nil end
	local head = m:FindFirstChild("Head")
	local root = m:FindFirstChild("HumanoidRootPart")
			or m:FindFirstChild("Torso")
			or m:FindFirstChild("UpperTorso")
			or head
	return head, root
end

-- Highest BasePart in a model = the head position the aimbot aims at.
function Pf.GetModelCenter(model)
	local highestPart, highestY = nil, -math.huge
	if model then
		for _, v in ipairs(model:GetDescendants()) do
			if v:IsA("BasePart") and v.Position.Y > highestY then
				highestY = v.Position.Y
				highestPart = v
			end
		end
	end
	return highestPart and highestPart.Position or nil
end

-- Iterate every PF custom player model under workspace.Players, each with
-- its owning player + enemy state resolved via TeamColor.
function Pf.ForEachWorkspaceModel(cb)
	local folder = Workspace:FindFirstChild("Players")
	if not folder then return end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local tag = m:FindFirstChild("PlayerTag", true)
			local name = tag and tag:IsA("TextLabel") and (tag.Text or ""):match("^%s*(.-)%s*$") or nil
			local player = name and Players:FindFirstChild(name) or nil
			if player and player ~= LocalPlayer then
				local isEnemy = Pf.IsEnemy(player)
				if isEnemy == nil then isEnemy = true end
				pcall(cb, m, player, isEnemy)
			end
		end
	end
end

-- Bounding-box size of the hash parts (used when no character Model exists).
function Pf.HashSize(hash)
	if not hash then return nil end
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	for _, part in pairs(hash) do
		local ok, isBase = pcall(part.IsA, part, "BasePart")
		if ok and isBase then
			local p, s = part.Position, part.Size
			local loX, hiX = p.X - s.X / 2, p.X + s.X / 2
			local loY, hiY = p.Y - s.Y / 2, p.Y + s.Y / 2
			local loZ, hiZ = p.Z - s.Z / 2, p.Z + s.Z / 2
			if loX < minX then minX = loX end
			if hiX > maxX then maxX = hiX end
			if loY < minY then minY = loY end
			if hiY > maxY then maxY = hiY end
			if loZ < minZ then minZ = loZ end
			if hiZ > maxZ then maxZ = hiZ end
			found = true
		end
	end
	if not found then return nil end
	return Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

-- ===== ReplicationInterface access (dot-style, like the game itself) =====

function Pf.GetReplicationInterface()
	local m = Pf.modules
	return m and m.ReplicationInterface or nil
end

-- operateOnAllEntries(callback) -- the real PF client calls it without self
local function callEntries(ri, cb)
	if not ri then return false end
	local f = ri.operateOnAllEntries
	if type(f) ~= "function" then return false end
	local ok = pcall(f, cb)
	if ok then return true end
	-- belts and suspenders: some PF builds take self first
	local ok2 = pcall(f, ri, cb)
	return ok2
end

function Pf.ForEachEnemy(cb)
	if not Pf.Active then return end
	local ri = Pf.GetReplicationInterface()
	if callEntries(ri, cb) then return end
	-- fallback: per-player getEntry scan
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local entry = Pf.GetEntry(player)
			if entry then
				pcall(cb, player, entry)
			end
		end
	end
end

-- getEntry(player) -- dot-style
function Pf.GetEntry(player)
	local ri = Pf.GetReplicationInterface()
	if not ri then return nil end
	local f = ri.getEntry
	if type(f) ~= "function" then return nil end
	local ok, entry = pcall(f, player)
	if not ok or not entry then
		local ok2, entry2 = pcall(f, ri, player)
		if ok2 then entry = entry2 end
	end
	return entry or nil
end

-- entry._thirdPersonObject is a field; :getThirdPersonObject() is a method.
function Pf.GetThirdPerson(entry)
	if not entry then return nil end
	if entry._thirdPersonObject then return entry._thirdPersonObject end
	if type(entry.getThirdPersonObject) == "function" then
		local ok, tp = pcall(entry.getThirdPersonObject, entry)
		if ok then return tp end
	end
	return nil
end

-- The character hash is keyed by part name: Head, Torso, Left Arm, ...
function Pf.GetHash(tp)
	if not tp then return nil end
	return tp._characterModelHash or nil
end

function Pf.GetPart(tp, ...)
	local hash = Pf.GetHash(tp)
	if not hash then return nil end
	for _, name in ipairs({ ... }) do
		local p = hash[name]
		if p then
			local ok, isBase = pcall(p.IsA, p, "BasePart")
			if ok and isBase then return p end
		end
	end
	return nil
end

-- The rendered replicated character Model (the custom third-person model).
function Pf.GetModel(tp)
	if not tp then return nil end
	if type(tp.getCharacterModel) == "function" then
		local ok, m = pcall(tp.getCharacterModel, tp)
		if ok and m then
			local ok2, isModel = pcall(m.IsA, m, "Model")
			if ok2 and isModel then return m end
		end
	end
	local hash = Pf.GetHash(tp)
	if hash then
		for _, part in pairs(hash) do
			if part then
				local ok, isBase = pcall(part.IsA, part, "BasePart")
				if ok and isBase then
					local ok2, model = pcall(part.FindFirstAncestorOfClass, part, "Model")
					if ok2 and model then return model end
				end
			end
		end
	end
	return nil
end

function Pf.GetRoot(tp)
	if not tp then return nil end
	if tp._rootPart then return tp._rootPart end
	if type(tp.getRootPart) == "function" then
		local ok, r = pcall(tp.getRootPart, tp)
		if ok and r then return r end
	end
	return Pf.GetPart(tp, "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso")
end

function Pf.GetHead(tp)
	return Pf.GetPart(tp, "Head")
end

-- Mirrors a player's vital data, or nil if the player is unresolvable.
-- Works in full module mode AND in template mode (workspace custom models).
function Pf.Resolve(player)
	if not player or player == LocalPlayer then return nil end

	local entry, tp, hash, model, root
	if Pf.Active then
		entry = Pf.GetEntry(player)
		tp = entry and Pf.GetThirdPerson(entry)
		hash = tp and Pf.GetHash(tp)
		model = tp and Pf.GetModel(tp)
		root = tp and Pf.GetRoot(tp)
	end

	if not model then
		model = findCustomModel(player)
	end
	if not model and not (root or (hash and hash.Head)) then return nil end

	if not root then
		if model then
			local _, r = customModelParts(model)
			root = r
		end
		if not root and hash then
			root = hash.HumanoidRootPart or hash.Torso or hash.UpperTorso
		end
	end
	local head = (hash and hash.Head) or (model and model:FindFirstChild("Head")) or root
	if not (root or head) then return nil end

	local health, maxHealth = 100, 100
	if entry and type(entry.getHealth) == "function" then
		local ok, h = pcall(entry.getHealth, entry)
		if ok and type(h) == "number" then health = h end
	end

	local enemy = not not (entry and entry._isEnemy)
	if not entry then
		local pfEnemy = Pf.IsEnemy(player)
		if pfEnemy ~= nil then
			enemy = pfEnemy
		else
			enemy = not (player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team)
		end
	end

	return {
		Player = player,
		Entry = entry,
		ThirdPerson = tp,
		Character = model, -- may be nil; esp falls back to Root/Head/Hash
		Root = root,
		Head = head,
		Hash = hash,
		Health = health,
		MaxHealth = maxHealth,
		Enemy = enemy, -- truthy, same as the game
		Size = Pf.HashSize(hash) or (model and model:GetExtentsSize()) or nil,
	}
end

-- ===== target selection (nearest to crosshair on screen) =====

local function FovScreenRadius(fovDeg, viewportY, camFov)
	local theta = math.rad(math.clamp(fovDeg, 1, 179) / 2)
	local phi = math.rad(math.clamp(camFov, 1, 179) / 2)
	return (viewportY / 2) * (math.tan(theta) / math.tan(phi))
end

function Pf.RayVisible(camera, part)
	local pos
	if type(part) == "table" and typeof(part) == "Vector3" then
		pos = part
		part = nil
	elseif part then
		pcall(function() pos = part.Position end)
	end
	if not pos then return true end
	local ok, model = pcall(part.FindFirstAncestorOfClass, part, "Model")
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { model, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local rayOrigin = camera.CFrame.Position
	local result = Workspace:Raycast(rayOrigin, pos - rayOrigin, params)
	if not result then return true end
	if result.Instance and ok and model then
		local isDesc, okD = pcall(result.Instance.IsDescendantOf, result.Instance, model)
		if okD and isDesc then return true end
	end
	return false
end

-- Returns the world position of the best enemy part (or nil).
-- partName mapping follows the game's DesktopHitBox keys: "Head" / "Torso".
function Pf.PickTarget(camera, partName, useFoV, fovSize, visibleCheck, teamCheck)
	if not camera then return nil end
	partName = partName or "Head"
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local radius = useFoV and FovScreenRadius(fovSize or 50, camera.ViewportSize.Y, camera.FieldOfView) or 1e9
	local best, bestDist, bestPlayer, bestPart

	local function consider(part, player, isEnemy)
		if not part then return end
		local ok, isBase = pcall(part.IsA, part, "BasePart")
		if not (ok and isBase) then return end
		if teamCheck and not isEnemy then return end
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
	end

	if Pf.Active then
		Pf.ForEachEnemy(function(player, entry)
			local tp = entry._thirdPersonObject
			local hash = tp and tp._characterModelHash
			if not hash then return end
			local part
			if partName == "Torso" then
				part = hash.Torso or hash.UpperTorso or hash.LowerTorso or hash.HumanoidRootPart
			elseif partName == "HumanoidRootPart" or partName == "RootPart" then
				local r
				if tp then
					local okR, rr = pcall(function()
						if tp._rootPart then return tp._rootPart end
						if type(tp.getRootPart) == "function" then return tp:getRootPart() end
						return nil
					end)
					r = okR and rr or nil
				end
				part = r or hash.HumanoidRootPart or hash.Torso or hash.Head
			else
				part = hash[partName] or hash.Head
			end
			consider(part, player, not not entry._isEnemy)
		end)
	end

	-- workspace custom-model fallback (module mode miss or template mode)
	if not best then
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				local m = findCustomModel(player)
				if m then
					local isEnemy = Pf.IsEnemy(player)
					if isEnemy == nil then
						isEnemy = not (player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team)
					end
					local part
					if partName == "Torso" then
						part = m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
					elseif partName == "HumanoidRootPart" or partName == "RootPart" then
						part = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
					else
						part = m:FindFirstChild(partName) or m:FindFirstChild("Head")
					end
					consider(part, player, isEnemy)
				end
			end
		end
	end

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
		local tp = entry._thirdPersonObject
		local head = tp and tp._characterModelHash and tp._characterModelHash.Head
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
-- Fixed-point time-of-flight iteration (converges in a few steps for PF
-- bullet speeds; no quartic solver needed).
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

local function call(method, obj, ...)
	if type(method) ~= "function" then return nil end
	local ok, a = pcall(method, obj, ...)
	if not ok then return nil end
	return a
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
