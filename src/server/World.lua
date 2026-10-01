--!strict
--[[
	World — everything static.

	Builds the spawn lobby, the vertical tower of stage slabs, the neon
	spine that ties the silhouette together, the void backdrop that gives
	the low stages a sense of height, and the checkpoint beacons.

	Everything is derived from Config, so re-theming or reordering stages
	is a one-file change.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local World = {}

export type StageRef = {
	stage: Config.Stage,
	biome: Config.Biome,
	origin: Vector3,
	checkpoint: BasePart,
	spawnCFrame: CFrame,
	folder: Folder,
	label: BillboardGui,
}

export type State = {
	root: Folder,
	lobby: Folder,
	tower: Folder,
	stages: { StageRef },
	lobbySpawn: CFrame,
}

local function clearOldWorld()
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local inst = Workspace:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
	local existing = Workspace:FindFirstChild("NeonAscent")
	if existing then
		existing:Destroy()
	end
end

--[[
	The lobby. A small, bright landing platform that frames the tower
	above so the first thing a player sees is the vertical scale.
]]
local function buildLobby(root: Folder, biome: Config.Biome): (Folder, CFrame)
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = root

	local deckSize = Vector3.new(120, 6, 120)
	local deckY = 6
	Util.part({
		Name = "Deck",
		Size = deckSize,
		CFrame = CFrame.new(0, deckY, 0),
		Color = Color3.fromRGB(10, 12, 26),
		Material = Enum.Material.Slate,
	}, lobby)

	-- Neon inlay border, four rule lines that read as a landing pad.
	local half = deckSize.X / 2
	for i = 0, 3 do
		local ang = i * math.pi / 2
		local offset = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (half - 2)
		Util.neonStrip(
			lobby,
			Vector3.new(deckSize.X - 6, 0.4, 1.6),
			CFrame.new(Vector3.new(0, deckY + 3.05, 0) + offset)
				* CFrame.Angles(0, ang + math.pi / 2, 0),
			i % 2 == 0 and biome.Primary or biome.Secondary,
			0.05
		)
	end

	-- Corner pylons.
	for _, corner in ipairs({
		Vector3.new(-half, 0, -half),
		Vector3.new(half, 0, -half),
		Vector3.new(-half, 0, half),
		Vector3.new(half, 0, half),
	}) do
		Util.part({
			Name = "CornerPylon",
			Size = Vector3.new(4, 34, 4),
			CFrame = CFrame.new(corner.X, deckY + 17, corner.Z),
			Color = Color3.fromRGB(14, 16, 32),
			Material = Enum.Material.Metal,
		}, lobby)
		local cap = Util.part({
			Name = "Cap",
			Size = Vector3.new(6, 2, 6),
			CFrame = CFrame.new(corner.X, deckY + 34, corner.Z),
			Color = biome.Primary,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}, lobby)
		Util.pointLight(cap, biome.Primary, 6, 40)
	end

	-- Title monolith at the back of the lobby.
	local mono = Util.part({
		Name = "TitleMonolith",
		Size = Vector3.new(96, 22, 3),
		CFrame = CFrame.new(0, deckY + 20, -54),
		Color = Color3.fromRGB(8, 10, 22),
		Material = Enum.Material.Metal,
	}, lobby)
	Util.neonStrip(
		mono,
		Vector3.new(96, 0.8, 3.4),
		mono.CFrame * CFrame.new(0, 11.1, 0),
		biome.Primary,
		0
	)
	Util.neonStrip(
		mono,
		Vector3.new(96, 0.8, 3.4),
		mono.CFrame * CFrame.new(0, -11.1, 0),
		biome.Secondary,
		0
	)
	local title = Util.billboard(mono, Config.TowerTitle, biome.Primary, 5.2, Config.TowerSubtitle)
	title.StudsOffsetWorldSpace = Vector3.new(0, 0, 2.4)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, deckY + 3.5, 20)
	spawn.Anchored = true
	spawn.Color = biome.Primary
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.3
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = lobby
	Util.pointLight(spawn, biome.Primary, 8, 50)

	return lobby, spawn.CFrame
end

--[[
	One stage slab: floor plate, neon border, corner towers, checkpoint
	beacon, and the title label. Returns the checkpoint part + spawn CFrame.
]]
local function buildSlab(tower: Folder, stage: Config.Stage, biome: Config.Biome): StageRef
	local origin = Vector3.new(0, Config.StageY(stage.Index), 0)
	local size = Config.PadSize

	local folder = Instance.new("Folder")
	folder.Name = string.format("Stage%02d_%s", stage.Index, stage.Key)
	folder.Parent = tower

	-- Floor: thick plate so the underside reads as solid structure.
	Util.part({
		Name = "Floor",
		Size = Vector3.new(size, 8, size),
		CFrame = CFrame.new(origin - Vector3.new(0, 4, 0)),
		Color = Color3.fromRGB(16, 18, 34),
		Material = Enum.Material.Slate,
	}, folder)

	-- Under-deck beams for silhouette depth when seen from below.
	for i = -2, 2 do
		Util.part({
			Name = "Beam",
			Size = Vector3.new(size - 6, 1.6, 2),
			CFrame = CFrame.new(origin + Vector3.new(0, -9.2, i * (size / 5))),
			Color = Color3.fromRGB(10, 12, 24),
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, folder)
	end

	-- Neon border inlay.
	local half = size / 2
	for i = 0, 3 do
		local ang = i * math.pi / 2
		local offset = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (half - 1.2)
		Util.neonStrip(
			folder,
			Vector3.new(size - 8, 0.5, 1.4),
			CFrame.new(origin + Vector3.new(0, 0.2, 0) + offset)
				* CFrame.Angles(0, ang + math.pi / 2, 0),
			i % 2 == 0 and biome.Primary or biome.Secondary,
			0.05
		)
	end

	-- Corner towers with neon caps: the tower's signature silhouette.
	local towerHeight = 16 + (stage.Index % 2) * 4
	for _, corner in ipairs({
		Vector3.new(-half + 3, 0, -half + 3),
		Vector3.new(half - 3, 0, -half + 3),
		Vector3.new(-half + 3, 0, half - 3),
		Vector3.new(half - 3, 0, half - 3),
	}) do
		local pos = origin + corner
		Util.part({
			Name = "CornerTower",
			Size = Vector3.new(5, towerHeight, 5),
			CFrame = CFrame.new(pos + Vector3.new(0, towerHeight / 2, 0)),
			Color = Color3.fromRGB(12, 14, 30),
			Material = Enum.Material.Metal,
		}, folder)
		local cap = Util.part({
			Name = "Cap",
			Size = Vector3.new(7, 1.6, 7),
			CFrame = CFrame.new(pos + Vector3.new(0, towerHeight, 0)),
			Color = biome.Primary,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}, folder)
		Util.pointLight(cap, biome.Primary, 5, 44)
	end

	-- Checkpoint beacon: safe pad at the back-left of the slab. Touching
	-- it saves your progress. Clearly signposted so it never feels hidden.
	local cpPos = origin + Vector3.new(-half + 12, 0, -half + 12)
	local pad = Util.part({
		Name = "Checkpoint",
		Size = Vector3.new(14, 0.6, 14),
		CFrame = CFrame.new(cpPos + Vector3.new(0, 0.32, 0)),
		Color = biome.Secondary,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
	}, folder)
	Util.pointLight(pad, biome.Secondary, 5, 34)
	local beam = Util.part({
		Name = "Beacon",
		Size = Vector3.new(0.6, 60, 0.6),
		CFrame = CFrame.new(cpPos + Vector3.new(0, 30, 0)),
		Color = biome.Secondary,
		Material = Enum.Material.Neon,
		Transparency = 0.72,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	}, folder)
	beam:SetAttribute("Beacon", true)

	-- Stage title.
	local marker = Util.part({
		Name = "StageMarker",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 26, half - 8)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, folder)
	local label = Util.billboard(
		marker,
		string.format("%02d · %s", stage.Index, stage.Title),
		biome.Primary,
		2.0,
		stage.Subtitle
	)

	return {
		stage = stage,
		biome = biome,
		origin = origin,
		checkpoint = pad,
		spawnCFrame = CFrame.new(cpPos + Vector3.new(0, 8, 0)),
		folder = folder,
		label = label,
	}
end

--[[
	The neon spine: four vertical light columns running the height of the
	tower, plus a rotating shard field in the void for depth.
]]
local function buildSpine(root: Folder, stages: { StageRef }, biome: Config.Biome)
	local spine = Instance.new("Folder")
	spine.Name = "Spine"
	spine.Parent = root

	local topY = Config.StageY(stages[#stages].Index) + 60
	local bottomY = -40
	local radius = Config.PadSize / 2 + 6

	for i = 0, 3 do
		local ang = i * math.pi / 2 + math.pi / 4
		local x = math.cos(ang) * radius
		local z = math.sin(ang) * radius
		Util.part({
			Name = "SpineColumn",
			Size = Vector3.new(2.2, topY - bottomY, 2.2),
			CFrame = CFrame.new(x, (topY + bottomY) / 2, z),
			Color = Color3.fromRGB(12, 14, 30),
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
		}, spine)
		Util.neonStrip(
			spine,
			Vector3.new(0.6, topY - bottomY, 0.6),
			CFrame.new(x, (topY + bottomY) / 2, z) * CFrame.new(0, 0, -1.4),
			biome.Primary,
			0.2
		)
	end

	-- Void shard field: distant floating monoliths. Purely atmospheric,
	-- never collidable, scattered on a deterministic seed.
	local rng = Util.newRng(20261001)
	local shards = Instance.new("Folder")
	shards.Name = "VoidShards"
	shards.Parent = root
	local shardCount = 90
	for i = 1, shardCount do
		local ang = rng:NextNumber() * math.pi * 2
		local dist = 160 + rng:NextNumber() * 520
		local y = bottomY + rng:NextNumber() * (topY - bottomY + 120)
		local h = 10 + rng:NextNumber() * 60
		local w = 4 + rng:NextNumber() * 16
		local s = Util.part({
			Name = "Shard",
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(math.cos(ang) * dist, y, math.sin(ang) * dist) * CFrame.Angles(
				rng:NextNumber() * 0.4,
				rng:NextNumber() * math.pi,
				rng:NextNumber() * 0.4
			),
			Color = Color3.fromRGB(10, 12, 28),
			Material = Enum.Material.Slate,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, shards)
		if i % 3 == 0 then
			Util.neonStrip(
				shards,
				Vector3.new(0.5, h * 0.8, 0.5),
				s.CFrame * CFrame.new(w / 2 + 0.2, 0, 0),
				(i % 6 == 0) and biome.Primary or biome.Secondary,
				0.35
			)
		end
	end
end

function World.build(): State
	clearOldWorld()

	local root = Instance.new("Folder")
	root.Name = "NeonAscent"
	root.Parent = Workspace

	local tower = Instance.new("Folder")
	tower.Name = "Tower"
	tower.Parent = root

	local baseBiome = Config.Biomes.Neon
	local lobby, lobbySpawn = buildLobby(root, baseBiome)

	local stages: { StageRef } = {}
	for _, stage in ipairs(Config.Stages) do
		-- Biome is declared on the stage itself (Config.Stages[i].Biome),
		-- so reordering or adding stages needs no change here.
		local biome = Config.Biomes[stage.Biome] or baseBiome
		table.insert(stages, buildSlab(tower, stage, biome))
	end

	buildSpine(root, stages, baseBiome)

	-- A warm rim light at the very base so the tower's underside reads.
	local rim = Util.part({
		Name = "RimLight",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, -30, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, root)
	Util.pointLight(rim, baseBiome.Primary, 3, 400)

	return {
		root = root,
		lobby = lobby,
		tower = tower,
		stages = stages,
		lobbySpawn = lobbySpawn,
	}
end

return World
