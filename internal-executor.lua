-- i made this for using multi instance when there is no internal executor
local keyBind = getgenv().executorKeyBind or "RightControl"
local scale = getgenv().executorScale or 0.66

local screenGui = game:GetObjects("rbxassetid://76806698067626")[1]
screenGui.Parent = gethui() or game:GetService("CoreGui")

local main = screenGui:WaitForChild("Frame")
local scroll = main:WaitForChild("ScrollingFrame")
local textbox = scroll:WaitForChild("TextBox")
local execute = main:WaitForChild("ExecuteButton")
local clear = main:WaitForChild("ClearButton")
local executeClipboard = main:WaitForChild("ExecuteClipboardButton")

for _, object in screenGui:GetDescendants() do
    local size = object.AbsoluteSize
    object.Size = UDim2.new(0, size.X * scale, 0, size.Y * scale)
end

textbox.TextSize = textbox.TextSize * scale

main.Active = true
main.Draggable = true
scroll.BorderSizePixel = 1

function getclipboard()
	local screen = Instance.new("ScreenGui", gethui() or game:GetService("CoreGui"))
	local textBox = Instance.new("TextBox", screen)
	textBox.TextTransparency = 1
	textBox:CaptureFocus()
	keypress(0x11)  
	keypress(0x56)
	task.wait(1/60)
	keyrelease(0x11)
	keyrelease(0x56)
	textBox:ReleaseFocus()
	local captured = textBox.Text
	textBox:Destroy()
	screen:Destroy()
	return captured
end

execute.MouseButton1Click:Connect(function()
    loadstring(textbox.Text)()
end)

clear.MouseButton1Click:Connect(function()
    textbox.Text = ""
end)

executeClipboard.MouseButton1Click:Connect(function()
    loadstring(getclipboard())()
end)

local userInputService = game:GetService("UserInputService")
userInputService.InputBegan:Connect(function(input)
    if input.KeyCode.Name == keyBind then
        screenGui.Enabled = not screenGui.Enabled
    end
end)

screenGui.Enabled = not screenGui.Enabled
