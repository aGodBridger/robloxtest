local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Pf = _G.Pf or (getgenv and getgenv().Pf)

-- TEAM DETECTION (from first script)
local TEAMS = {
    ["Bright blue"]   = "Phantoms",
    ["Bright orange"] = "Ghosts",
}

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

-- ============================================================
--  NEW TARGET ACQUISITION (from first script - PF compatible)
-- ============================================================

-- Get the highest part of the model (head)
local function getModelCenter(model)
    local highestPart = nil
    local highestY = -math.huge
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") and v.Position.Y > highestY then
            highestY = v.Position.Y
            highestPart = v
        end
    end
    return highestPart and highestPart.Position or nil
end

-- Check if part is visible on screen
local function isPartVisible(camera, pos)
    if not pos then return false end
    local screenPos, visible = camera:WorldToViewportPoint(pos)
    return visible and screenPos.Z > 0
end

-- Check if player is enemy based on team color
local function isEnemy(player)
    if not player then return false end
    if not C.TeamCheck then return true end
    local thisTeam = TEAMS[tostring(LocalPlayer.TeamColor)] or "Unknown"
    local enemyTeam = TEAMS[tostring(player.TeamColor)] or "Unknown"
    return enemyTeam ~= thisTeam and enemyTeam ~= "Unknown"
end

-- Tracked enemies from workspace
local trackedEnemies = {}

-- Find all enemy models in workspace
local function findEnemies()
    local enemies = {}
    local folder = Workspace:FindFirstChild("Players")
    if not folder then return enemies end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            -- Find player name from tag
            local tag = model:FindFirstChild("PlayerTag", true)
            if tag and tag:IsA("TextLabel") then
                local name = tag.Text:match("^%s*(.-)%s*$")
                if name and name ~= LocalPlayer.Name then
                    local player = Players:FindFirstChild(name)
                    if player and isEnemy(player) then
                        local pos = getModelCenter(model)
                        if pos then
                            table.insert(enemies, {
                                model = model,
                                player = player,
                                position = pos,
                                part = getHighestPart(model) -- for visibility checks
                            })
                        end
                    end
                end
            end
        end
    end
    return enemies
end

-- Get highest part (for raycast visibility)
local function getHighestPart(model)
    local highestPart = nil
    local highestY = -math.huge
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") and v.Position.Y > highestY then
            highestY = v.Position.Y
            highestPart = v
        end
    end
    return highestPart
end

-- Visibility check using raycast
local function isVisible(camera, part)
    if not part then return false end
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

-- NEW TARGET ACQUISITION function (PF compatible)
local function acquireTarget(camera)
    local hitpartName = C.Hitpart
    local targetMode = C.Target
    local visibleOnly = C.VisibleOnly
    local useFov = C.UseFov
    local fovSize = C.FovSize

    local camFov = camera.FieldOfView
    local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local radius = FovScreenRadius(fovSize, camera.ViewportSize.Y, camFov)

    local best, bestScore = nil, 1e9
    local LocalCharacter = LocalPlayer.Character

    -- Get enemies from workspace (PF compatible)
    local enemies = findEnemies()
    
    for _, enemy in ipairs(enemies) do
        local pos = enemy.position
        local model = enemy.model
        local player = enemy.player
        
        if pos then
            -- Check if on screen
            local screen, onScreen = camera:WorldToViewportPoint(pos)
            if onScreen and screen.Z > 0 then
                local screenPoint = Vector2.new(screen.X, screen.Y)
                local dist = (screenPoint - center).Magnitude
                
                -- FOV check
                if not useFov or dist <= radius then
                    -- Visibility check
                    if not visibleOnly or isVisible(camera, getHighestPart(model)) then
                        local score
                        if targetMode == "Lowest Health" then
                            local humanoid = model:FindFirstChildOfClass("Humanoid")
                            if humanoid then
                                score = humanoid.Health
                            else
                                -- PF might not have Humanoid, use distance as fallback
                                score = dist
                            end
                        elseif targetMode == "Closest to Player" then
                            local root = model:FindFirstChild("HumanoidRootPart")
                            local myRoot = LocalCharacter and LocalCharacter:FindFirstChild("HumanoidRootPart")
                            if myRoot and root then
                                score = (root.Position - myRoot.Position).Magnitude
                            else
                                score = dist
                            end
                        else
                            -- Default: Closest to Crosshair
                            score = dist
                        end
                        
                        if score < bestScore then
                            bestScore = score
                            best = {
                                position = pos,
                                model = model,
                                player = player,
                                part = getHighestPart(model)
                            }
                        end
                    end
                end
            end
        end
    end
    
    return best
end

-- ============================================================
--  REGULAR AIMBOT
-- ============================================================

local MoveMouse = mousemoverel
if type(MoveMouse) ~= "function" and getgenv then
    local ok = pcall(function() MoveMouse = getgenv().mousemoverel end)
    if not ok or type(MoveMouse) ~= "function" then MoveMouse = nil end
end

local function predictedPosition(camera, targetData)
    local model = targetData.model
    if not model then return targetData.position end
    local root = model:FindFirstChild("HumanoidRootPart") or targetData.part
    local velocity = root and root:IsA("BasePart") and root.AssemblyLinearVelocity or Vector3.new()
    if velocity.Magnitude < 0.1 then return targetData.position end
    local amount = C.PredAmount
    local dist = (targetData.position - camera.CFrame.Position).Magnitude
    return targetData.position + velocity * (amount * (dist / 750))
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
            print(("[Aimbot] Locked onto %s"):format(target.player and target.player.Name or "Enemy"))
        end
    else
        return
    end

    local aimPos = target.position
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
--  PHANTOM FORCES MODE (using new target system)
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

    -- Use NEW target acquisition
    local targetData = acquireTarget(camera)
    if not targetData then
        Pf.AimbotActive = false
        return
    end

    local cameraObj = Pf.GetActiveCamera()
    if not cameraObj then return end
    if type(cameraObj._angles) ~= "userdata" then return end

    local aimPos = targetData.position
    if C.Prediction then
        aimPos = predictedPosition(camera, targetData)
    end

    -- bullet drop + target movement compensation
    local vel = Pf.SolveTrajectory(
        camera.CFrame * Vector3.new(0, 0, 0.5),
        Pf.GetBulletAcceleration(),
        aimPos,
        speed,
        targetData.player and Pf.GetTargetVelocity(targetData.player) or Vector3.new()
    )
    if not vel then return end

    local pitch, yaw = Pf.VelocityToAngles(vel)

    -- clamp pitch into the weapon's allowed range
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
        local alpha = math.clamp(1 - smoothness + (now - PfAimTime) ^ 2, 0, 1)
        newAngles = cameraObj._angles:Lerp(newAngles, alpha)
    else
        PfLocked = false
    end

    cameraObj._delta = (newAngles - cameraObj._angles) / math.max(dt, 1e-4)
    cameraObj._angles = newAngles
    Pf.AimbotActive = true
end

-- ============================================================
--  MAIN LOOP
-- ============================================================

RunService.RenderStepped:Connect(function(dt)
    -- Full getgc module access: use the ballistic camera path.
    -- Otherwise (incl. TemplateMode / workspace models only) use the
    -- same workspace-based target picker + mousemoverel as the reference.
    if Pf and Pf.Active then
        doPfAim(dt)
    else
        doAim()
    end
end)

print("[Aimbot] Loaded - hold activation key to aim (default: right-click)")
print("[Aimbot] Using PF-compatible target detection from workspace")