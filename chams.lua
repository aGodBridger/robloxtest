-- Modified Highlight Service Script
-- This syncs with the VisionWare GUI Chams toggle and color picker
-- Place this in ServerScriptService

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Store highlights for cleanup
local activeHighlights = {}

-- Configuration that will be synced from GUI
local HIGHLIGHT_CONFIG = {
    FillColor = Color3.fromRGB(255, 255, 255),    -- Default white
    OutlineColor = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.5,
    OutlineTransparency = 0,
    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    Enabled = false  -- Starts disabled, will be enabled by GUI
}

-- Function to get the current state from GUI flags
local function getChamsStateFromGUI()
    if _G.Library and _G.Library.Flags then
        local isEnabled = _G.Library.Flags.ESP_Chams or false
        local color = _G.Library.Flags.ESP_ChamsColor or Color3.fromRGB(255, 255, 255)
        return isEnabled, color
    end
    return false, Color3.fromRGB(255, 255, 255)
end

-- Function to create a highlight for a character
local function createHighlightForCharacter(character, color)
    if not character or not character:IsA("Model") then
        return nil
    end
    
    local existingHighlight = character:FindFirstChild("PlayerHighlight")
    if existingHighlight then
        return existingHighlight
    end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "PlayerHighlight"
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = HIGHLIGHT_CONFIG.FillTransparency
    highlight.OutlineTransparency = HIGHLIGHT_CONFIG.OutlineTransparency
    highlight.DepthMode = HIGHLIGHT_CONFIG.DepthMode
    highlight.Enabled = true
    highlight.Adornee = character
    highlight.Parent = character
    
    activeHighlights[character] = highlight
    
    return highlight
end

-- Function to highlight all current players with given color
local function highlightAllPlayers(color)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            createHighlightForCharacter(player.Character, color)
        end
    end
end

-- Function to remove highlight from a character
local function removeHighlightFromCharacter(character)
    if character and character:IsA("Model") then
        local highlight = character:FindFirstChild("PlayerHighlight")
        if highlight then
            highlight:Destroy()
            activeHighlights[character] = nil
        end
    end
end

-- Function to update all highlights to a new color
local function updateAllHighlightColors(color)
    for character, highlight in pairs(activeHighlights) do
        if highlight and character and character:IsA("Model") then
            highlight.FillColor = color
            highlight.OutlineColor = color
        end
    end
end

-- Function to handle character removal
local function onCharacterRemoving(character)
    removeHighlightFromCharacter(character)
end

-- Function to handle character added
local function onCharacterAdded(character, player)
    task.wait(0.1)
    
    if character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
        local _, color = getChamsStateFromGUI()
        if HIGHLIGHT_CONFIG.Enabled then
            createHighlightForCharacter(character, color)
        end
    end
end

-- Function to handle player added
local function onPlayerAdded(player)
    if player.Character then
        onCharacterAdded(player.Character, player)
    end
    
    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(character, player)
    end)
    
    player.CharacterRemoving:Connect(function(character)
        onCharacterRemoving(character)
    end)
end

-- Function to handle player leaving
local function onPlayerRemoving(player)
    if player.Character then
        removeHighlightFromCharacter(player.Character)
    end
end

-- Initialize: Connect to existing players
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Main update loop that syncs with GUI
task.spawn(function()
    local lastEnabled = false
    local lastColor = Color3.fromRGB(255, 255, 255)
    
    while true do
        task.wait(0.1) -- Check GUI state every 100ms
        
        local isEnabled, currentColor = getChamsStateFromGUI()
        
        -- Handle toggle changes
        if isEnabled ~= lastEnabled then
            HIGHLIGHT_CONFIG.Enabled = isEnabled
            
            if isEnabled then
                -- Turn on: highlight all players
                highlightAllPlayers(currentColor)
                print("[Chams] Enabled via GUI")
            else
                -- Turn off: remove all highlights
                for character, highlight in pairs(activeHighlights) do
                    if highlight then
                        highlight:Destroy()
                    end
                end
                activeHighlights = {}
                print("[Chams] Disabled via GUI")
            end
            
            lastEnabled = isEnabled
            lastColor = currentColor
        end
        
        -- Handle color changes (only if enabled)
        if isEnabled and currentColor ~= lastColor then
            updateAllHighlightColors(currentColor)
            print("[Chams] Color updated via GUI")
            lastColor = currentColor
        end
    end
end)

-- Periodic cleanup of orphaned highlights
RunService.Heartbeat:Connect(function()
    for character, highlight in pairs(activeHighlights) do
        if not character or not character:IsA("Model") or not character:FindFirstChild("Humanoid") then
            if highlight then
                pcall(function() highlight:Destroy() end)
            end
            activeHighlights[character] = nil
        end
    end
end)

print("[Chams] Server script initialized - waiting for GUI...")