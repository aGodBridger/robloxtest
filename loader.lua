-- // VisionWare Loader
-- // Change the three lines below to match your GitHub repo, then run this script

local Loader = {
	User = "aGodBridger",            -- GitHub username / owner
	Repo = "robloxtest",             -- Repo name
	Branch = "main",                 -- Branch (main or master)
	Files = {
		"chams.lua",
		"gui.lua",
		-- add more files below, e.g. "esp.lua",
	},
	Silent = false,                  -- true = hide "loaded" messages
}

local BaseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
	Loader.User, Loader.Repo, Loader.Branch
)

assert(#Loader.Files > 0, "No files to load!")

local Success, Errors = 0, {}

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

if #Errors > 0 then
	print("[VisionWare] " .. Success .. " loaded, " .. #Errors .. " failed")
	for _, Err in ipairs(Errors) do
		warn("[VisionWare] " .. Err)
	end
else
	print("[VisionWare] Loader finished - " .. Success .. "/" .. #Loader.Files .. " scripts loaded")
end