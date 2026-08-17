--[[
    Phantom Forces Aimbot
    Uses workspace.Players scanning with PlayerTag detection
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================
--  TEAM DETECTION
-- ============================================================

local TEAMS = {
    ["Bright blue"] = "Phantoms",
    ["Bright orange"] = "Ghosts",
}

local localTeamName = TEAMS[tostring(LocalPlayer.TeamColor)] or "Unknown"

local function isEnemy(player)
    if not player then return false end
    local enemyTeam = TEAMS[tostring(player.TeamColor)] or "Unknown"
    return enemyTeam ~= localTeamName and enemyTeam ~= "Unknown"
end

-- ============================================================
--  FLAG SYSTEM
-- ============================================================

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
    C.TargetSwitchDelay = get("Aimbot_TargetSwitchDelay", 0.15)
end

-- ============================================================
--  FOV CALCULATION (Convert degrees to pixels)
-- ============================================================

local function FovScreenRadius(fovDeg, viewportY, camFov)
    local theta = math.rad(math.clamp(fovDeg, 1, 179) / 2)
    local phi = math.rad(math.clamp(camFov, 1, 179) / 2)
    return (viewportY / 2) * (math.tan(theta) / math.tan(phi))
end

-- ============================================================
--  MODEL FUNCTIONS
-- ============================================================

local function getModelCenter(model)
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

-- ============================================================
--  SCAN FOR ENEMIES
-- ============================================================

local function findEnemies()
    local enemies = {}
    local folder = Workspace:FindFirstChild("Players")
    if not folder then return enemies end
    
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local tag = model:FindFirstChild("PlayerTag", true)
            if tag and tag:IsA("TextLabel") then
                local name = tag.Text:match("^%s*(.-)%s*$")
                if name and name ~= LocalPlayer.Name then
                    local player = Players:FindFirstChild(name)
                    if player and isEnemy(player) then
                        local headPart = getModelCenter(model)
                        if headPart then
                            table.insert(enemies, {
                                model = model,
                                player = player,
                                headPart = headPart,
                            })
                        end
                    end
                end
            end
        end
    end
    return enemies
end

-- ============================================================
--  VISIBILITY CHECK
-- ============================================================

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

-- ============================================================
--  TARGET ACQUISITION
-- ============================================================

local function acquireTarget(camera)
    if not camera then return nil end
    
    local targetMode = C.Target
    local useFov = C.UseFov
    local fovSize = C.FovSize
    local visibleOnly = C.VisibleOnly
    
    local camFov = camera.FieldOfView
    local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local radius = useFov and FovScreenRadius(fovSize, camera.ViewportSize.Y, camFov) or math.huge
    
    local best = nil
    local bestScore = math.huge
    local camPos = camera.CFrame.Position
    local LocalCharacter = LocalPlayer.Character
    
    local enemies = findEnemies()
    
    for _, enemy in ipairs(enemies) do
        local headPart = enemy.headPart
        if headPart then
            -- Check distance
            local dist = (headPart.Position - camPos).Magnitude
            if dist > 1000 then continue end
            
            -- Check if on screen
            local screen, onScreen = camera:WorldToViewportPoint(headPart.Position)
            if not (onScreen and screen.Z > 0) then continue end
            
            -- Check visibility
            if visibleOnly and not isVisible(camera, headPart) then continue end
            
            local screenPoint = Vector2.new(screen.X, screen.Y)
            local screenDist = (screenPoint - center).Magnitude
            
            -- FOV check
            if useFov and screenDist > radius then continue end
            
            local score
            if targetMode == "Lowest Health" then
                -- PF doesn't expose health, use distance
                score = dist
            elseif targetMode == "Closest to Player" then
                local myRoot = LocalCharacter and LocalCharacter:FindFirstChild("HumanoidRootPart")
                if myRoot then
                    score = (headPart.Position - myRoot.Position).Magnitude
                else
                    score = dist
                end
            else
                -- Closest to Crosshair
                score = screenDist
            end
            
            if score < bestScore then
                bestScore = score
                best = enemy
            end
        end
    end
    
    return best
end

-- ============================================================
--  PREDICTION
-- ============================================================

local function predictedPosition(headPart, camera)
    if not C.Prediction or not headPart then return headPart.Position end
    local velocity = headPart.AssemblyLinearVelocity or Vector3.new()
    if velocity.Magnitude < 0.1 then return headPart.Position end
    local amount = C.PredAmount or 0.25
    local dist = (headPart.Position - camera.CFrame.Position).Magnitude
    return headPart.Position + velocity * (amount * (dist / 750))
end

-- ============================================================
--  AIMBOT STATE
-- ============================================================

local lastTarget = nil
local lastTargetLostTime = nil
local aimbotActive = false

-- ============================================================
--  KEYBIND HANDLER
-- ============================================================

-- Handle Library keybind
local function isKeyPressed()
    if C.Key == nil then return false end
    if C.Key == true then return true end
    if type(C.Key) == "boolean" then return C.Key end
    
    -- Check if it's a keybind from Library
    local keyFlag = C.Key
    if type(keyFlag) == "table" then
        -- Library keybind format
        return keyFlag.current or false
    end
    
    return false
end

-- Also handle direct key check from Library flags
local function checkKey()
    local L = getLibrary()
    if L and L.Flags then
        local keyState = L.Flags["Aimbot_Key"]
        if keyState ~= nil then
            return keyState
        end
    end
    return false
end

-- ============================================================
--  MOUSE MOVEMENT
-- ============================================================

local MoveMouse = mousemoverel
if type(MoveMouse) ~= "function" and getgenv then
    local ok = pcall(function() MoveMouse = getgenv().mousemoverel end)
    if not ok or type(MoveMouse) ~= "function" then MoveMouse = nil end
end

-- ============================================================
--  MAIN LOOP
-- ============================================================

RunService.Heartbeat:Connect(function()
    RefreshCache()
    
    if not C.Enabled then
        if aimbotActive then
            aimbotActive = false
            lastTarget = nil
            lastTargetLostTime = nil
        end
        return
    end
    
    -- Check if key is pressed
    local keyPressed = checkKey()
    if not keyPressed then
        if aimbotActive then
            aimbotActive = false
            lastTarget = nil
            lastTargetLostTime = nil
        end
        return
    end
    
    Camera = workspace.CurrentCamera
    if not Camera then return end
    
    aimbotActive = true
    
    local target = acquireTarget(Camera)
    
    -- Target switching logic with delay
    if target ~= lastTarget then
        if lastTarget ~= nil then
            if lastTargetLostTime == nil then
                lastTargetLostTime = tick()
            end
            if (tick() - lastTargetLostTime) < C.TargetSwitchDelay then
                target = nil
            else
                lastTarget = target
                lastTargetLostTime = nil
            end
        else
            lastTarget = target
            lastTargetLostTime = nil
        end
    else
        lastTargetLostTime = nil
    end
    
    if target then
        local headPart = target.headPart
        if headPart then
            local aimPos = headPart.Position
            if C.Prediction then
                aimPos = predictedPosition(headPart, Camera)
            end
            
            local screen, visible = Camera:WorldToViewportPoint(aimPos)
            if visible and screen.Z > 0 then
                local center = Camera.ViewportSize / 2
                local targetPos = Vector2.new(screen.X, screen.Y)
                
                -- Calculate smooth movement
                local smoothness = math.clamp(C.Smoothness or 0.2, 0.01, 1)
                local factor = 1 - smoothness
                
                if MoveMouse then
                    local delta = targetPos - UserInputService:GetMouseLocation()
                    MoveMouse(delta.X * factor, delta.Y * factor)
                else
                    -- Fallback: direct camera movement
                    local pose = CFrame.new(Camera.CFrame.Position, aimPos)
                    Camera.CFrame = Camera.CFrame:Lerp(pose, math.clamp(factor, 0, 1))
                end
            end
        end
    end
end)

-- ============================================================
--  INITIALIZE
-- ============================================================

print("[VisionWare] Aimbot loaded - PF Compatible")
print("[VisionWare] Hold right-click (or your bind) to aim")