--[[
    Phantom Forces ESP
    Uses workspace.Players scanning with PlayerTag detection
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local TEAM_COLORS = {
    ["Phantoms"] = Color3.fromRGB(0, 100, 255),
    ["Ghosts"] = Color3.fromRGB(255, 140, 0),
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
    C.Enabled = get("ESP_Enabled", true)
    C.Panic = get("Misc_Panic", false)
    C.Range = get("ESP_Range", 1000)
    C.TeamCheck = get("ESP_TeamCheck", false)
    C.ShowTeam = get("ESP_ShowTeam", false)
    C.VisibleOnly = get("ESP_VisibleOnly", false)
    C.Boxes = get("ESP_Boxes", true)
    C.Names = get("ESP_Names", true)
    C.Tracers = get("ESP_Tracers", false)
    C.Health = get("ESP_Health", true)
    C.BoxThickness = get("ESP_BoxThickness", 2)
    C.TextSize = get("ESP_TextSize", 13)
    C.TracerThickness = get("ESP_TracerThickness", 1)
    C.EnemyColor = get("ESP_EnemyColor", Color3.fromRGB(255, 25, 25))
    C.TeamColor = get("ESP_TeamColor", Color3.fromRGB(86, 227, 120))
    C.ESPChams = get("ESP_Chams", true)
    C.ChamsColor = get("ESP_ChamsColor", Color3.fromRGB(255, 255, 255))
    C.Opacity = get("ESP_Opacity", 75)
    C.Status = get("ESP_Status", true)
end

-- ============================================================
--  ESP STATE
-- ============================================================

local Boxes = {}
local ChamHighlights = {}
local frameTick = 0

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

local function getModelBounds(model)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local onScreen = false
    
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local s = part.Size * 0.5
            local cf = part.CFrame
            local offsets = {
                Vector3.new(s.X, s.Y, s.Z), Vector3.new(-s.X, s.Y, s.Z),
                Vector3.new(s.X, -s.Y, s.Z), Vector3.new(-s.X, -s.Y, s.Z),
                Vector3.new(s.X, s.Y, -s.Z), Vector3.new(-s.X, s.Y, -s.Z),
                Vector3.new(s.X, -s.Y, -s.Z), Vector3.new(-s.X, -s.Y, -s.Z),
            }
            for _, offset in ipairs(offsets) do
                local screen, visible = Camera:WorldToViewportPoint(cf:PointToWorldSpace(offset))
                if visible then
                    onScreen = true
                    minX = math.min(minX, screen.X)
                    minY = math.min(minY, screen.Y)
                    maxX = math.max(maxX, screen.X)
                    maxY = math.max(maxY, screen.Y)
                end
            end
        end
    end
    
    if onScreen then
        return {
            X = minX,
            Y = minY,
            Width = maxX - minX,
            Height = maxY - minY,
        }
    end
    return nil
end

-- ============================================================
--  SCAN FOR ENEMIES
-- ============================================================

local function scanEnemies()
    local folder = Workspace:FindFirstChild("Players")
    if not folder then return end
    
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and not Boxes[model] then
            local tag = model:FindFirstChild("PlayerTag", true)
            if tag and tag:IsA("TextLabel") then
                local name = tag.Text:match("^%s*(.-)%s*$")
                if name and name ~= LocalPlayer.Name then
                    local player = Players:FindFirstChild(name)
                    if player and isEnemy(player) then
                        local color = TEAM_COLORS[TEAMS[tostring(player.TeamColor)] or "Unknown"] or Color3.fromRGB(255, 255, 255)
                        
                        -- ESP Box
                        local sq = Drawing.new("Square")
                        sq.Filled = false
                        sq.Thickness = C.BoxThickness or 2
                        sq.Color = color
                        sq.Visible = false
                        
                        -- Name Label
                        local label = Drawing.new("Text")
                        label.Text = name
                        label.Size = C.TextSize or 13
                        label.Font = Drawing.Fonts.UI
                        label.Color = color
                        label.Center = true
                        label.Outline = true
                        label.OutlineColor = Color3.fromRGB(0, 0, 0)
                        label.Visible = false
                        
                        -- Tracer
                        local tracer = Drawing.new("Line")
                        tracer.Color = color
                        tracer.Thickness = C.TracerThickness or 1
                        tracer.Visible = false
                        
                        -- Health Bar
                        local healthBar = Drawing.new("Line")
                        healthBar.Color = Color3.fromRGB(0, 255, 0)
                        healthBar.Thickness = 3
                        healthBar.Visible = false
                        
                        Boxes[model] = {
                            sq = sq,
                            label = label,
                            tracer = tracer,
                            healthBar = healthBar,
                            model = model,
                            player = player,
                            name = name,
                            isEnemy = true,
                        }
                    end
                end
            end
        end
    end
end

local function untrack(model)
    local data = Boxes[model]
    if data then
        pcall(function() data.sq:Remove() end)
        pcall(function() data.label:Remove() end)
        pcall(function() data.tracer:Remove() end)
        pcall(function() data.healthBar:Remove() end)
        Boxes[model] = nil
    end
end

-- ============================================================
--  CHAMS
-- ============================================================

local function applyChams(model)
    if not C.ESPChams then return end
    if not model or not model:IsA("Model") then return end
    if ChamHighlights[model] then return end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "VisionWareCham"
    highlight.Adornee = model
    highlight.FillColor = C.ChamsColor or Color3.fromRGB(255, 255, 255)
    highlight.OutlineColor = C.ChamsColor or Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 1 - (C.Opacity or 75) / 100
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    highlight.Parent = model
    
    ChamHighlights[model] = highlight
end

local function removeChams(model)
    local highlight = ChamHighlights[model]
    if highlight then
        pcall(function() highlight:Destroy() end)
        ChamHighlights[model] = nil
    end
end

local function updateChams()
    -- Clean up old chams
    for model in pairs(ChamHighlights) do
        if not model.Parent then
            removeChams(model)
        end
    end
    
    -- Apply chams to enemies
    local folder = Workspace:FindFirstChild("Players")
    if not folder then return end
    
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local tag = model:FindFirstChild("PlayerTag", true)
            if tag and tag:IsA("TextLabel") then
                local name = tag.Text:match("^%s*(.-)%s*$")
                local player = Players:FindFirstChild(name)
                if player and isEnemy(player) then
                    applyChams(model)
                end
            end
        end
    end
end

-- ============================================================
--  STATUS UI
-- ============================================================

local StatusGUI = nil
local StatusLabel = nil
local VisibleCount = 0
local PlayerCount = 0

local function SetupStatus()
    if StatusGUI then return end
    StatusGUI = Instance.new("ScreenGui")
    StatusGUI.Name = "VisionWareESPStatus"
    StatusGUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    StatusGUI.IgnoreGuiInset = true
    pcall(function() StatusGUI.Parent = game:GetService("CoreGui") end)
    if not StatusGUI.Parent then
        pcall(function() StatusGUI.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end)
    end
    if not StatusGUI.Parent then
        StatusGUI:Destroy()
        StatusGUI = nil
        return
    end
    
    StatusLabel = Instance.new("TextLabel", StatusGUI)
    StatusLabel.Name = "Status"
    StatusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    StatusLabel.BackgroundTransparency = 0.35
    StatusLabel.BorderSizePixel = 0
    StatusLabel.Font = Enum.Font.RobotoMono
    StatusLabel.TextColor3 = Color3.new(255, 255, 255)
    StatusLabel.TextSize = 13
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Position = UDim2.fromOffset(8, 8)
    StatusLabel.Size = UDim2.fromOffset(320, 30)
    StatusLabel.Text = "ESP - starting..."
end

local doneSetup = false

-- ============================================================
--  MAIN LOOP
-- ============================================================

RunService.Heartbeat:Connect(function()
    if not doneSetup then
        SetupStatus()
        doneSetup = true
    end
    
    RefreshCache()
    
    if not C.Enabled or C.Panic then
        -- Hide everything if disabled
        for model, data in pairs(Boxes) do
            data.sq.Visible = false
            data.label.Visible = false
            data.tracer.Visible = false
            data.healthBar.Visible = false
        end
        return
    end
    
    frameTick = frameTick + 1
    
    -- Scan for enemies every few frames
    if frameTick % 3 == 0 then
        scanEnemies()
        if C.ESPChams then
            updateChams()
        end
    end
    
    Camera = workspace.CurrentCamera
    if not Camera then return end
    
    local center = Camera.ViewportSize / 2
    PlayerCount = 0
    VisibleCount = 0
    
    -- Update ESP for each enemy
    for model, data in pairs(Boxes) do
        if not model.Parent then
            untrack(model)
            removeChams(model)
        elseif data.isEnemy then
            -- Check distance
            local headPart = getModelCenter(model)
            local dist = headPart and (headPart.Position - Camera.CFrame.Position).Magnitude or math.huge
            
            if dist > C.Range then
                data.sq.Visible = false
                data.label.Visible = false
                data.tracer.Visible = false
                data.healthBar.Visible = false
            else
                local bounds = getModelBounds(model)
                if bounds then
                    PlayerCount = PlayerCount + 1
                    VisibleCount = VisibleCount + 1
                    
                    -- Get color
                    local color = TEAM_COLORS[TEAMS[tostring(data.player and data.player.TeamColor)] or "Unknown"] or C.EnemyColor
                    
                    -- Update Box
                    data.sq.Position = Vector2.new(bounds.X, bounds.Y)
                    data.sq.Size = Vector2.new(bounds.Width, bounds.Height)
                    data.sq.Color = color
                    data.sq.Thickness = C.BoxThickness or 2
                    data.sq.Visible = C.Boxes
                    
                    -- Update Name
                    data.label.Position = Vector2.new(bounds.X + bounds.Width / 2, bounds.Y - 16)
                    data.label.Color = color
                    data.label.Size = C.TextSize or 13
                    data.label.Visible = C.Names
                    
                    -- Update Tracer
                    if C.Tracers and headPart then
                        local screenPos, visible = Camera:WorldToViewportPoint(headPart.Position)
                        if visible then
                            data.tracer.From = Vector2.new(center.X, Camera.ViewportSize.Y)
                            data.tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                            data.tracer.Color = color
                            data.tracer.Thickness = C.TracerThickness or 1
                            data.tracer.Visible = true
                        else
                            data.tracer.Visible = false
                        end
                    else
                        data.tracer.Visible = false
                    end
                    
                    -- Update Health Bar (PF doesn't expose health, show 100%)
                    if C.Health then
                        local healthPercent = 1.0  -- PF default
                        local barX = bounds.X - 6
                        local barY = bounds.Y
                        local barHeight = bounds.Height * healthPercent
                        
                        data.healthBar.From = Vector2.new(barX, barY + bounds.Height - barHeight)
                        data.healthBar.To = Vector2.new(barX, barY + bounds.Height)
                        data.healthBar.Color = Color3.fromRGB(255 * (1 - healthPercent), 255 * healthPercent, 0)
                        data.healthBar.Thickness = 3
                        data.healthBar.Visible = true
                    else
                        data.healthBar.Visible = false
                    end
                else
                    data.sq.Visible = false
                    data.label.Visible = false
                    data.tracer.Visible = false
                    data.healthBar.Visible = false
                end
            end
        end
    end
    
    -- Update status
    if StatusLabel and C.Status then
        local backend = "Drawing API"
        local line = "ESP [" .. backend .. "] visible: " .. VisibleCount .. "/" .. PlayerCount
        if not C.Enabled then
            line = "ESP DISABLED"
        elseif C.Panic then
            line = "ESP DISABLED (Panic ON)"
        end
        StatusLabel.Text = line
    end
end)

-- ============================================================
--  PLAYER EVENTS
-- ============================================================

Players.PlayerAdded:Connect(function(player)
    if player == LocalPlayer then return end
    player:GetPropertyChangedSignal("TeamColor"):Connect(function()
        for model, data in pairs(Boxes) do
            if data.name == player.Name then
                data.isEnemy = isEnemy(player)
                local color = TEAM_COLORS[TEAMS[tostring(player.TeamColor)] or "Unknown"] or C.EnemyColor
                data.sq.Color = color
                data.label.Color = color
                data.tracer.Color = color
                if not data.isEnemy then
                    data.sq.Visible = false
                    data.label.Visible = false
                    data.tracer.Visible = false
                    data.healthBar.Visible = false
                    removeChams(model)
                end
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    for model, data in pairs(Boxes) do
        if data.name == player.Name then
            untrack(model)
            removeChams(model)
        end
    end
end)

-- ============================================================
--  INITIAL SCAN
-- ============================================================

scanEnemies()
if C.ESPChams then
    updateChams()
end

print("[VisionWare] ESP loaded - PF Compatible")