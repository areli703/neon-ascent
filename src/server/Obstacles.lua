--!strict
--[[
	Obstacles — the hazard engine.

	Every moving hazard is registered here with a step function, and a
	single server Heartbeat advances all of them. That keeps hundreds of
	moving parts cheap (no per-part Heartbeat connections) and makes the
	whole tower deterministic and reproducible from Config.

	Kinds:
	  spiral   rotating bars around a central mast
	  gauntlet rotating bar pairs sweeping a walkway + static blockers
	  sweep    long low arms you must slip between
	  pillars  columns that rise and fall on a phase-shifted sine
	  crown    a fusion of the above for the finale
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Obstacles = {}

type Stepper = (dt: number) -> ()
type Entry = {
	root: BasePart,
	targets: { BasePart },
	onKill: (player: Player) -> (),
	active: boolean,
}

local steppers: { Stepper } = {}
local hazardParts: { BasePart } = {}
local killHandler: ((player: Player) -> ())? = nil

--[[
	Register a part as lethal. We use Touched rather than region queries
	because hazard counts here are low (< 400) and Touched is reliable
	when both sides are CanTouch. A short per-player cooldown stops a
	single pass from firing the kill dozens of times.

	The kill handler is resolved LAZILY (module-level `killHandler`), not
	captured when the part is built. That way hazards can be constructed
	before GameMode exists, and the order of boot steps stops mattering.
	The `_onKill` parameter is accepted for signature compatibility and
	intentionally ignored.
]]
local cooldown: { [Player]: number } = {}
local function armHazard(part: BasePart, _onKill: (player: Player) -> ())
	part:SetAttribute("Lethal", true)
	table.insert(hazardParts, part)
	part.Touched:Connect(function(hit)
		if not part:GetAttribute("Armed") then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local player = game:GetService("Players"):GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local now = os.clock()
		if cooldown[player] and now - cooldown[player] < 1.1 then
			return
		end
		cooldown[player] = now
		local handler = killHandler
		if handler then
			handler(player)
		end
	end)
end

local function newPivot(name: string, position: Vector3, parent: Instance): BasePart
	local pivot = Util.part({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Anchored = true,
	}, parent)
	return pivot
end

--[[
	Build a glowing hazard bar attached to a pivot so rotation happens
	once, at the pivot, instead of per-part.
]]
local function makeBar(pivot: BasePart, length: number, color: Color3, thickness: number?): BasePart
	local t = thickness or 2.6
	local bar = Util.part({
		Name = "HazardBar",
		Size = Vector3.new(length, t, t),
		CFrame = pivot.CFrame * CFrame.new(length / 2, 0, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = true,
		CanQuery = true,
		CastShadow = false,
	}, pivot)

	-- Dark structural core so it reads as engineered, not a bare stick.
	local core = Util.part({
		Name = "Core",
		Size = Vector3.new(length * 0.98, t * 0.5, t * 0.5),
		CFrame = bar.CFrame,
		Color = Color3.fromRGB(18, 20, 30),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, pivot)

	local weldBar = Instance.new("WeldConstraint")
	weldBar.Part0 = pivot
	weldBar.Part1 = bar
	weldBar.Parent = bar
	local weldCore = Instance.new("WeldConstraint")
	weldCore.Part0 = pivot
	weldCore.Part1 = core
	weldCore.Parent = core

	Util.pointLight(bar, color, 4, length * 0.8)
	return bar
end

local function makePylon(
	parent: Instance,
	position: Vector3,
	height: number,
	color: Color3,
	radius: number?
): BasePart
	local r = radius or 1.6
	local pylon = Util.part({
		Name = "Pylon",
		Size = Vector3.new(r, height, r),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)),
		Color = Color3.fromRGB(16, 18, 32),
		Material = Enum.Material.Metal,
		CanCollide = true,
	}, parent)
	local cap = Util.part({
		Name = "Cap",
		Size = Vector3.new(r * 1.6, 0.9, r * 1.6),
		CFrame = CFrame.new(position + Vector3.new(0, height, 0)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	Util.pointLight(cap, color, 5, 26)
	return pylon
end

-- ---------------------------------------------------------------------
-- Generators. Each returns nothing; they register their own steppers.
-- ---------------------------------------------------------------------

local function buildSpiral(
	_stage: Config.Stage,
	origin: Vector3,
	biome: Config.Biome,
	parent: Instance,
	onKill: (player: Player) -> ()
)
	local mast = Util.part({
		Name = "Mast",
		Size = Vector3.new(4, 46, 4),
		CFrame = CFrame.new(origin + Vector3.new(0, 23, 0)),
		Color = Color3.fromRGB(14, 16, 30),
		Material = Enum.Material.Metal,
		CanCollide = true,
	}, parent)
	Util.pointLight(mast, biome.Primary, 6, 60)

	local armCount = 3
	for i = 1, armCount do
		local y = 3 + (i - 1) * 2.4
		local pivot = newPivot("SpiralPivot" .. i, origin + Vector3.new(0, y, 0), parent)
		local bar = makeBar(pivot, 40, biome.Primary, 2.2)
		armHazard(bar, onKill)
		local speed = (1.1 + i * 0.25) * (i % 2 == 0 and -1 or 1)
		local phase = i * (math.pi / 3)
		table.insert(steppers, function(_dt: number)
			local t = os.clock()
			pivot.CFrame = CFrame.new(origin + Vector3.new(0, y, 0))
				* CFrame.Angles(0, phase + t * speed, 0)
		end)
	end

	-- Outer ring of pylons with neon caps to frame the arena.
	for idx, p in ipairs(Util.ringPoints(origin, 44, 8)) do
		makePylon(parent, p, 12, idx % 2 == 0 and biome.Primary or biome.Secondary, 1.4)
	end
end

local function buildGauntlet(
	_stage: Config.Stage,
	origin: Vector3,
	biome: Config.Biome,
	parent: Instance,
	onKill: (player: Player) -> ()
)
	-- Two rotating cross-beams sweeping the walkway from opposite sides.
	for i = 1, 2 do
		local side = i == 1 and -34 or 34
		local base = origin + Vector3.new(side, 0, -30)
		local pivot = newPivot("GauntletPivot" .. i, base + Vector3.new(0, 2.4, 0), parent)
		local bar = makeBar(pivot, 58, biome.Primary, 2.4)
		armHazard(bar, onKill)
		local dir = i == 1 and 1 or -1
		table.insert(steppers, function(_dt: number)
			local t = os.clock()
			pivot.CFrame = CFrame.new(base + Vector3.new(0, 2.4, 0))
				* CFrame.Angles(0, math.sin(t * 0.8 * dir) * math.rad(72), 0)
		end)
	end

	-- Slow-blocking crates: safe cover you can weave behind.
	local rng = Util.newRng(4401)
	for i = 1, 6 do
		local x = (rng:NextNumber() - 0.5) * 70
		local z = -20 + i * 7
		local c = Util.part({
			Name = "Blocker",
			Size = Vector3.new(6, 8, 6),
			CFrame = CFrame.new(origin + Vector3.new(x, 4, z)),
			Color = Color3.fromRGB(20, 22, 40),
			Material = Enum.Material.Slate,
			CanCollide = true,
		}, parent)
		Util.neonStrip(
			c,
			Vector3.new(6.4, 0.5, 6.4),
			c.CFrame * CFrame.new(0, 4.1, 0),
			biome.Secondary,
			0.1
		)
	end

	for idx, p in ipairs(Util.ringPoints(origin, 44, 10)) do
		makePylon(parent, p, 10, idx % 2 == 0 and biome.Primary or biome.Secondary, 1.3)
	end
end

local function buildSweep(
	_stage: Config.Stage,
	origin: Vector3,
	biome: Config.Biome,
	parent: Instance,
	onKill: (player: Player) -> ()
)
	-- Long, low arms that skim the floor: jump timing puzzle.
	local arms = 3
	for i = 1, arms do
		local y = 2.2
		local pivot = newPivot("SweepPivot" .. i, origin + Vector3.new(0, y, 0), parent)
		local bar = makeBar(pivot, 88, biome.Primary, 2.0)
		local bar2 = makeBar(pivot, 88, biome.Secondary, 2.0)
		bar2.CFrame = pivot.CFrame * CFrame.new(-88 / 2, 0, 0)
		armHazard(bar, onKill)
		armHazard(bar2, onKill)
		local speed = 0.65 + i * 0.12
		local phase = (i - 1) * (math.pi * 2 / arms)
		table.insert(steppers, function(_dt: number)
			pivot.CFrame = CFrame.new(origin + Vector3.new(0, y, 0))
				* CFrame.Angles(0, phase + os.clock() * speed, 0)
		end)
	end

	-- Central safe island with a beacon so the pattern is readable.
	local hub = Util.part({
		Name = "Hub",
		Size = Vector3.new(14, 1.6, 14),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.8, 0)),
		Color = biome.Secondary,
		Material = Enum.Material.Neon,
		CanCollide = true,
	}, parent)
	Util.pointLight(hub, biome.Secondary, 4, 40)

	for idx, p in ipairs(Util.ringPoints(origin, 48, 12)) do
		makePylon(parent, p, 9, idx % 2 == 0 and biome.Primary or biome.Secondary, 1.2)
	end
end

local function buildPillars(
	_stage: Config.Stage,
	origin: Vector3,
	biome: Config.Biome,
	parent: Instance,
	onKill: (player: Player) -> ()
)
	local rng = Util.newRng(9917)
	local cols = 5
	local rows = 5
	for cx = 1, cols do
		for cz = 1, rows do
			if not (cx == 3 and cz == 3) then
				local x = (cx - 3) * 14
				local z = (cz - 3) * 14
				local phase = rng:NextNumber() * math.pi * 2
				local speed = 0.9 + rng:NextNumber() * 0.7
				local height = 16
				local pillar = Util.part({
					Name = "Riser",
					Size = Vector3.new(6, height, 6),
					CFrame = CFrame.new(origin + Vector3.new(x, height / 2, z)),
					Color = Color3.fromRGB(18, 20, 38),
					Material = Enum.Material.Metal,
					CanCollide = true,
				}, parent)
				local top = Util.part({
					Name = "Top",
					Size = Vector3.new(6.4, 0.6, 6.4),
					CFrame = CFrame.new(origin + Vector3.new(x, height, z)),
					Color = biome.Primary,
					Material = Enum.Material.Neon,
					CanCollide = false,
					CastShadow = false,
				}, parent)
				Util.pointLight(top, biome.Primary, 3, 22)
				table.insert(steppers, function(_dt: number)
					local y = origin.Y + 4 + math.sin(os.clock() * speed + phase) * 6
					local cf = CFrame.new(Vector3.new(origin.X + x, y + height / 2, origin.Z + z))
					pillar.CFrame = cf
					top.CFrame = CFrame.new(Vector3.new(origin.X + x, y + height, origin.Z + z))
				end)
			end
		end
	end

	-- Rising pillars also crush: a player who rides one to the top is
	-- fine, but the moving body itself is lethal on contact.
	for _, p in ipairs(parent:GetChildren()) do
		if p:IsA("BasePart") and p.Name == "Riser" then
			armHazard(p, onKill)
		end
	end

	for idx, p in ipairs(Util.ringPoints(origin, 46, 10)) do
		makePylon(parent, p, 11, idx % 2 == 0 and biome.Primary or biome.Secondary, 1.3)
	end
end

local function buildCrown(
	_stage: Config.Stage,
	origin: Vector3,
	biome: Config.Biome,
	parent: Instance,
	onKill: (player: Player) -> ()
)
	-- The finale fuses a slow sweep with a fast inner spiral and a
	-- pillar ring, so every learned skill gets tested together.
	local outer = newPivot("CrownOuter", origin + Vector3.new(0, 2.4, 0), parent)
	local outerBar = makeBar(outer, 100, biome.Primary, 2.4)
	local outerBar2 = makeBar(outer, 100, biome.Secondary, 2.4)
	outerBar2.CFrame = outer.CFrame * CFrame.new(-50, 0, 0)
	armHazard(outerBar, onKill)
	armHazard(outerBar2, onKill)

	local inner = newPivot("CrownInner", origin + Vector3.new(0, 6.2, 0), parent)
	local innerBar = makeBar(inner, 46, biome.Secondary, 2.0)
	armHazard(innerBar, onKill)

	table.insert(steppers, function(_dt: number)
		local t = os.clock()
		outer.CFrame = CFrame.new(origin + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, t * 0.6, 0)
		inner.CFrame = CFrame.new(origin + Vector3.new(0, 6.2, 0)) * CFrame.Angles(0, -t * 1.6, 0)
	end)

	local rng = Util.newRng(5150)
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local pos = origin + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30)
		local height = 12
		local riser = Util.part({
			Name = "Riser",
			Size = Vector3.new(5, height, 5),
			CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)),
			Color = Color3.fromRGB(18, 20, 38),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, parent)
		armHazard(riser, onKill)
		local phase = rng:NextNumber() * math.pi * 2
		table.insert(steppers, function(_dt: number)
			local y = origin.Y + 3 + math.sin(os.clock() * 1.1 + phase) * 5
			riser.CFrame = CFrame.new(Vector3.new(pos.X, y + height / 2, pos.Z))
		end)
	end

	-- Crown jewel: a rotating neon halo high above, purely for the shot.
	local halo = Util.part({
		Name = "Halo",
		Size = Vector3.new(70, 1.2, 70),
		CFrame = CFrame.new(origin + Vector3.new(0, 34, 0)),
		Color = biome.Primary,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
	Util.pointLight(halo, biome.Primary, 8, 120)
	table.insert(steppers, function(_dt: number)
		halo.CFrame = CFrame.new(origin + Vector3.new(0, 34, 0))
			* CFrame.Angles(0, os.clock() * 0.25, 0)
	end)

	for idx, p in ipairs(Util.ringPoints(origin, 52, 14)) do
		makePylon(parent, p, 14, idx % 2 == 0 and biome.Primary or biome.Secondary, 1.5)
	end
end

local GENERATORS = {
	spiral = buildSpiral,
	gauntlet = buildGauntlet,
	sweep = buildSweep,
	pillars = buildPillars,
	crown = buildCrown,
}

-- ---------------------------------------------------------------------

function Obstacles.init(onKill: (player: Player) -> ())
	killHandler = onKill
end

function Obstacles.buildStage(
	stage: Config.Stage,
	origin: Vector3,
	biome: Config.Biome,
	parent: Instance
)
	local gen = GENERATORS[stage.Kind]
	assert(gen, "unknown stage kind: " .. tostring(stage.Kind))
	gen(stage, origin, biome, parent, killHandler :: any)
end

function Obstacles.start()
	RunService.Heartbeat:Connect(function(dt)
		for _, step in ipairs(steppers) do
			step(dt)
		end
	end)
end

--[[
	Arm/disarm hazards. During the pre-round countdown nothing should
	kill anyone, so the tower can be admired safely.
]]
function Obstacles.setArmed(armed: boolean)
	for _, part in ipairs(hazardParts) do
		if part.Parent then
			part:SetAttribute("Armed", armed)
		end
	end
end

function Obstacles.count(): number
	return #hazardParts
end

return Obstacles
