--!strict
--[[
	Server bootstrap. Order matters:
	  1. remotes   — clients may attach at any moment
	  2. world     — geometry the rest of the system references
	  3. obstacles — hazards, built per stage folder
	  4. effects   — dispatch layer
	  5. players   — spawn resolution needs the world
	  6. game mode — the loop that drives everything
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local World = require(script.World)
local Obstacles = require(script.Obstacles)
local PlayerService = require(script.PlayerService)
local Leaderboard = require(script.Leaderboard)
local GameMode = require(script.GameMode)
local Lighting = require(script.Lighting)

print(string.format("[%s] booting…", Config.GameName))

Remotes.setup()
Lighting.build()

local world = World.build()
print(string.format("[%s] world built: %d stages", Config.GameName, #world.stages))

-- Hazards live inside each stage's own folder, so clearing a stage
-- folder removes its obstacles with it.
for _, ref in ipairs(world.stages) do
	Obstacles.buildStage(ref.stage, ref.origin, ref.biome, ref.folder)
end
Obstacles.start()
print(string.format("[%s] %d hazard bodies armed", Config.GameName, Obstacles.count()))

-- Lobby leaderboard, offset behind the spawn so it frames the tower.
Leaderboard.build(world.lobby, Vector3.new(0, 24, -40), Config.Biomes.Neon)
do
	local gui = world.lobby:FindFirstChild("LeaderboardBody")
	if gui then
		gui.CFrame = CFrame.new(0, 24, -40) * CFrame.Angles(0, math.pi, 0)
	end
end

PlayerService.init()
GameMode.init(world)

print(string.format("[%s] ready. %s", Config.GameName, "climb!"))
