--!strict
--[[
	GameMode — the round loop.

	Intermission  → free roam in the lobby, tower disarmed, admire the work.
	Countdown     → 5..1, players placed at their checkpoint, hazards live at 0.
	Climbing      → hazards armed, checkpoints award progress, timer runs.
	Results       → standings, celebration, then a new round.

	State machine is intentionally explicit and single-threaded so there is
	never ambiguity about what the tower is doing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local PlayerService = require(script.Parent.PlayerService)
local Obstacles = require(script.Parent.Obstacles)
local Effects = require(script.Parent.Effects)
local Leaderboard = require(script.Parent.Leaderboard)

local GameMode = {}

export type PlayerState = {
	checkpoint: number,
	finished: boolean,
	startTime: number,
	finishTime: number?,
	deaths: number,
	lastStageSent: number,
}

type WorldState = {
	stages: { any },
	lobbySpawn: CFrame,
}

local state: { [Player]: PlayerState } = {}
local world: WorldState
local phase = "Boot"
local phaseEndsAt = 0
local roundNumber = 0

local FINISH_INDEX = #Config.Stages

local function now(): number
	return os.clock()
end

local function getState(player: Player): PlayerState
	local s = state[player]
	if not s then
		s = {
			checkpoint = 0,
			finished = false,
			startTime = now(),
			finishTime = nil,
			deaths = 0,
			lastStageSent = 0,
		}
		state[player] = s
	end
	return s
end

--[[
	Where a player should appear. Checkpoint 0 means the lobby; anything
	else drops them onto the saved stage slab.
]]
local function spawnFor(player: Player): CFrame
	local s = getState(player)
	if s.checkpoint <= 0 then
		return world.lobbySpawn
	end
	local ref = world.stages[s.checkpoint]
	if not ref then
		return world.lobbySpawn
	end
	return ref.spawnCFrame
end

local function broadcastState()
	local remote = Remotes.get("PushState") :: RemoteEvent
	local payload = {
		phase = phase,
		phaseEndsAt = phaseEndsAt,
		round = roundNumber,
		stageCount = FINISH_INDEX,
		players = {},
	}
	for player, s in pairs(state) do
		table.insert(payload.players, {
			name = player.Name,
			displayName = player.DisplayName,
			checkpoint = s.checkpoint,
			finished = s.finished,
			finishTime = s.finishTime,
			deaths = s.deaths,
		})
	end
	remote:FireAllClients(payload)
end

local function ranking()
	local rows = {}
	for player, s in pairs(state) do
		table.insert(rows, {
			name = player.DisplayName ~= "" and player.DisplayName or player.Name,
			checkpoints = s.checkpoint,
			bestTime = s.finishTime,
			finished = s.finished,
			rank = 0,
			_sortFinished = s.finished and 0 or 1,
			_sortCp = -s.checkpoint,
			_sortTime = s.finishTime or math.huge,
		})
	end
	table.sort(rows, function(a, b)
		if a._sortFinished ~= b._sortFinished then
			return a._sortFinished < b._sortFinished
		end
		if a._sortCp ~= b._sortCp then
			return a._sortCp < b._sortCp
		end
		return a._sortTime < b._sortTime
	end)
	for i, row in ipairs(rows) do
		row.rank = i
	end
	return rows
end

local function refreshBoard(status: string?)
	Leaderboard.update(ranking(), status)
end

--[[
	Death handling. The player is put back on their last checkpoint with a
	short grace window; deaths are counted and shown, because a climb
	with a death count is a climb with a story.
]]
local function onKill(player: Player)
	if player:GetAttribute("Invulnerable") then
		return
	end
	local s = getState(player)
	player:SetAttribute("Invulnerable", true)
	s.deaths += 1
	Obstacles.setArmed(false)
	Effects.shake(player, 1.2, 0.5)
	Effects.sound(player, "Hazard", 0.7)
	Effects.flash(player, Color3.fromRGB(255, 60, 60), 0.6)
	task.wait(0.12)
	local target = spawnFor(player)
	local character = player.Character
	if character then
		character:PivotTo(target)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	Obstacles.setArmed(phase == "Climbing")
	task.delay(1.0, function()
		if player.Parent then
			player:SetAttribute("Invulnerable", false)
		end
	end)
	broadcastState()
end

--[[
	Checkpoint detection runs on the server's own heartbeat against the
	player's Y position. No Touched events, no race conditions, no way to
	spoof it from the client.
]]
local function watchProgress()
	RunService.Heartbeat:Connect(function()
		if phase ~= "Climbing" then
			return
		end
		for player, s in pairs(state) do
			if s.finished then
				continue
			end
			local character = player.Character
			if not character then
				continue
			end
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end
			local y = root.Position.Y
			-- Highest stage this player is standing on or above. Starts at
			-- ZERO, not one: the lobby sits below stage 1, and counting it
			-- as a checkpoint would hand every player progress for free.
			local reached = 0
			for i, ref in ipairs(world.stages) do
				if y >= ref.origin.Y + 2 then
					reached = i
				end
			end
			if reached > s.checkpoint then
				s.checkpoint = reached
				local ref = world.stages[reached]
				Effects.checkpoint(player, ref.checkpoint.Position, ref.biome.Primary, reached)
				local cpRemote = Remotes.get("Checkpoint") :: RemoteEvent
				cpRemote:FireClient(player, ref.checkpoint.Position, ref.biome.Primary, reached)
				Effects.announce(
					string.format(
						"%s reached %s  (%d/%d)",
						player.DisplayName,
						ref.stage.Title,
						reached,
						FINISH_INDEX
					),
					ref.biome.Primary
				)
				refreshBoard()
				broadcastState()
				if reached >= FINISH_INDEX then
					s.finished = true
					if not s.finishTime then
						s.finishTime = now() - s.startTime
					end
					Effects.sound(player, "Victory", 0.8)
					Effects.celebrate(ref.checkpoint.Position, ref.biome.Primary)
					Effects.announce(
						string.format("%s ASCENDED in %.2fs!", player.DisplayName, s.finishTime),
						Color3.fromRGB(150, 255, 200)
					)
					refreshBoard()
				end
			end
			-- Per-player lighting crossfade as they climb into a new biome.
			local ref = reached > 0 and world.stages[math.min(reached, FINISH_INDEX)] or nil
			if ref and ref.stage.Index ~= s.lastStageSent then
				s.lastStageSent = ref.stage.Index
				Effects.stageTransition(player, ref.biome, ref.stage.Index)
			end
		end
	end)
end

local function teleportAllToSpawns()
	for player in pairs(state) do
		if player.Parent and player.Character then
			local character = player.Character
			character:PivotTo(spawnFor(player))
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

local function resetForRound()
	for player in pairs(state) do
		state[player] = {
			checkpoint = 0,
			finished = false,
			startTime = now(),
			finishTime = nil,
			deaths = 0,
			lastStageSent = 0,
		}
	end
	-- Stage everyone at their respawn point (the lobby at round start).
	teleportAllToSpawns()
end

local function run()
	-- Boot: build everything, then breathe for a moment.
	phase = "Intermission"
	phaseEndsAt = now() + Config.IntermissionTime
	refreshBoard("Intermission")
	broadcastState()

	while true do
		-- ---- INTERMISSION ------------------------------------------
		phase = "Intermission"
		phaseEndsAt = now() + Config.IntermissionTime
		Leaderboard.setTitle("NEXT CLIMB", Color3.fromRGB(120, 220, 255))
		refreshBoard("Intermission")
		broadcastState()
		while now() < phaseEndsAt do
			task.wait(0.5)
			broadcastState()
		end

		-- ---- COUNTDOWN ---------------------------------------------
		roundNumber += 1
		resetForRound()
		phase = "Countdown"
		phaseEndsAt = now() + 5
		Leaderboard.setTitle("ROUND " .. roundNumber, Color3.fromRGB(255, 210, 120))
		refreshBoard("Round " .. roundNumber .. " starting")
		broadcastState()

		for i = 5, 1, -1 do
			Effects.announce(string.format("STARTING IN %d", i), Color3.fromRGB(255, 210, 120))
			for player in pairs(state) do
				Effects.sound(player, "Countdown", 0.5)
			end
			task.wait(1)
		end
		Effects.announce("CLIMB!", Color3.fromRGB(150, 255, 200))

		-- ---- CLIMBING ----------------------------------------------
		for _, s in pairs(state) do
			s.startTime = now()
		end
		phase = "Climbing"
		phaseEndsAt = now() + Config.RoundTime
		Obstacles.setArmed(true)
		Leaderboard.setTitle("LIVE STANDINGS", Color3.fromRGB(120, 255, 180))
		broadcastState()

		while now() < phaseEndsAt do
			task.wait(1)
			local allDone = true
			for _, s in pairs(state) do
				if not s.finished then
					allDone = false
					break
				end
			end
			broadcastState()
			if allDone then
				break
			end
		end

		-- ---- RESULTS -----------------------------------------------
		Obstacles.setArmed(false)
		phase = "Results"
		phaseEndsAt = now() + 12
		local rows = ranking()
		Leaderboard.setTitle("ROUND " .. roundNumber .. " RESULTS", Color3.fromRGB(255, 210, 120))
		refreshBoard("Round " .. roundNumber .. " complete")
		for _, row in ipairs(rows) do
			if row.rank == 1 and row.finished then
				Effects.announce("WINNER: " .. row.name, Color3.fromRGB(255, 220, 120))
			end
		end
		broadcastState()

		local t = now() + 12
		while now() < t do
			task.wait(1)
			broadcastState()
		end
		phaseEndsAt = now() + Config.IntermissionTime
	end
end

function GameMode.init(worldState: WorldState)
	world = worldState
	PlayerService.setSpawnResolver(spawnFor)

	Players.PlayerAdded:Connect(function(player)
		getState(player)
		broadcastState()
	end)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		getState(player)
	end

	Obstacles.init(onKill)
	watchProgress()
	task.spawn(run)
end

return GameMode
