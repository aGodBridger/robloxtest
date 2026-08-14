-- // VisionWare Complete Loader
-- // Just run this script - it handles EVERYTHING automatically

local Loader = {
	User = "aGodBridger",            -- GitHub username / owner
	Repo = "robloxtest",             -- Repo name
	Branch = "main",                 -- Branch (main or master)
	Files = {
		"gui.lua",
		"chams.lua"
		-- add more files below, e.g. "esp.lua",
	},
	Silent = false,                  -- true = hide "loaded" messages
}

local BaseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
	Loader.User, Loader.Repo, Loader.Branch
)

assert(#Loader.Files > 0, "No files to load!")

local Success, Errors = 0, {}

-- ===== STEP 1: Load GUI and other files from GitHub =====
for _, FileName in ipairs(Loader.Files) do
	local ok, Source = pcall(game.HttpGet, game, BaseUrl .. FileName)
	if ok and Source then
		local ok2, Loaded = pcall(loadstring, Source)
		if ok2 and Loaded then
			local ok3, run = pcall(Loaded)
			if ok3 then
				Success = Success + 1
				if not Loader.Silent then
					print("[VisionWare] Loaded " .. FileName)
				end
			else
				table.insert(Errors, FileName .. " errored while running: " .. tostring(run))
			end
		else
			table.insert(Errors, FileName .. " failed to compile: " .. tostring(Loaded))
		end
	else
		table.insert(Errors, FileName .. " failed to fetch (check username/repo/branch): " .. tostring(Source))
	end
end

-- ===== STEP 2: Load chams.lua as a server script =====
local ok, ChamsSource = pcall(game.HttpGet, game, BaseUrl .. "chams.lua")
if ok and ChamsSource then
	-- Create a Script instance in ServerScriptService
	local ServerScriptService = game:GetService("ServerScriptService")
	if ServerScriptService then
		local chamsScript = Instance.new("Script")
		chamsScript.Name = "ChamsScript"
		chamsScript.Source = ChamsSource
		chamsScript.Parent = ServerScriptService
		print("[VisionWare] Chams loaded as server script")
		Success = Success + 1
	else
		warn("[VisionWare] Could not access ServerScriptService")
		table.insert(Errors, "chams.lua - ServerScriptService not accessible")
	end
else
	table.insert(Errors, "chams.lua failed to fetch: " .. tostring(ChamsSource))
end



-- ===== Final Status =====
if #Errors > 0 then
	print("[VisionWare] " .. Success .. " loaded, " .. #Errors .. " failed")
	for _, Err in ipairs(Errors) do
		warn("[VisionWare] " .. Err)
	end
else
	print("[VisionWare] Loader finished - " .. Success .. " scripts loaded")
	print("[VisionWare] All systems ready! Toggle 'Chams' in the ESP section")
end