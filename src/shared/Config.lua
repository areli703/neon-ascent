--!strict
--[[
	Config — the single source of truth for NEON ASCENT's tower.
	Everything geometric is derived from this so the world is
	deterministic, rebuildable, and easy to re-theme.
]]

local Config = {}

Config.GameName = "NEON ASCENT"
Config.RoundTime = 360 -- seconds of climb time before results
Config.IntermissionTime = 18
Config.MinPlayers = 1
-- Must equal the number of stages, or a perfect run still fails to
-- qualify. Kept in sync with #Config.Stages via the assert below.
Config.CheckpointsToQualify = 5

-- Every stage sits on a vertical slab. Y is derived from index, so
-- stages can be reordered without touching geometry code.
Config.StageHeight = 190
Config.PadSize = 96
Config.BaseY = 120

Config.TowerTitle = "NEON ASCENT"
Config.TowerSubtitle = "CLIMB · DODGE · ASCEND"

-- Palette per biome. Colour-coded so the player always knows
-- where they are by looking at the light.
Config.Palette = {
	Sky = Color3.fromRGB(5, 6, 22),
	Deep = Color3.fromRGB(8, 10, 32),
	Grid = Color3.fromRGB(40, 60, 120),
	Pillar = Color3.fromRGB(14, 16, 40),
	Rail = Color3.fromRGB(70, 90, 160),
	Text = Color3.fromRGB(235, 245, 255),
	Dim = Color3.fromRGB(120, 135, 175),
}

export type Biome = {
	Name: string,
	Title: string,
	Primary: Color3, -- hazard / accent
	Secondary: Color3, -- floor + trim
	Fog: Color3,
	Ambient: Color3,
	ClockTime: number,
}

-- Stage type is a tag the server uses to pick the obstacle generator.
export type Stage = {
	Index: number,
	Key: string,
	Title: string,
	Subtitle: string,
	Kind: string, -- "spiral" | "gauntlet" | "sweep" | "pillars" | "crown"
	Biome: string, -- key into Config.Biomes
	FogDensity: number,
}

Config.Biomes = {
	Neon = {
		Name = "Neon",
		Title = "NEON GATE",
		Primary = Color3.fromRGB(0, 225, 255),
		Secondary = Color3.fromRGB(255, 0, 190),
		Fog = Color3.fromRGB(4, 6, 24),
		Ambient = Color3.fromRGB(22, 30, 60),
		ClockTime = 0,
	} :: Biome,
	Ember = {
		Name = "Ember",
		Title = "EMBER CORE",
		Primary = Color3.fromRGB(255, 120, 20),
		Secondary = Color3.fromRGB(255, 60, 40),
		Fog = Color3.fromRGB(20, 6, 6),
		Ambient = Color3.fromRGB(50, 24, 18),
		ClockTime = 0,
	} :: Biome,
	Glacier = {
		Name = "Glacier",
		Title = "GLACIER RUN",
		Primary = Color3.fromRGB(120, 230, 255),
		Secondary = Color3.fromRGB(190, 245, 255),
		Fog = Color3.fromRGB(6, 16, 26),
		Ambient = Color3.fromRGB(28, 48, 70),
		ClockTime = 5.5,
	} :: Biome,
	Void = {
		Name = "Void",
		Title = "VOID ASCENT",
		Primary = Color3.fromRGB(150, 80, 255),
		Secondary = Color3.fromRGB(90, 40, 200),
		Fog = Color3.fromRGB(8, 4, 20),
		Ambient = Color3.fromRGB(30, 18, 54),
		ClockTime = 0,
	} :: Biome,
}

Config.Stages = {
	{
		Index = 1,
		Key = "Gate",
		Title = "NEON GATE",
		Subtitle = "Read the pattern. Time the rhythm.",
		Kind = "spiral",
		Biome = "Neon",
		FogDensity = 0.16,
	},
	{
		Index = 2,
		Key = "Gauntlet",
		Title = "EMBER GAUNTLET",
		Subtitle = "Cross the beams. Do not stop.",
		Kind = "gauntlet",
		Biome = "Ember",
		FogDensity = 0.20,
	},
	{
		Index = 3,
		Key = "Sweep",
		Title = "GLACIER SWEEP",
		Subtitle = "Rotating arms. Slip between them.",
		Kind = "sweep",
		Biome = "Glacier",
		FogDensity = 0.24,
	},
	{
		Index = 4,
		Key = "Pillars",
		Title = "VOID PILLARS",
		Subtitle = "Rising pillars. Move before you think.",
		Kind = "pillars",
		Biome = "Void",
		FogDensity = 0.30,
	},
	{
		Index = 5,
		Key = "Crown",
		Title = "THE CROWN",
		Subtitle = "Everything at once. Earn the summit.",
		Kind = "crown",
		Biome = "Void",
		FogDensity = 0.36,
	},
}

function Config.StageY(index: number): number
	return Config.BaseY + (index - 1) * Config.StageHeight
end

-- A qualification target above the stage count makes a flawless run
-- un-winnable. Fail loudly at build time instead of shipping it.
assert(
	Config.CheckpointsToQualify <= #Config.Stages,
	string.format(
		"CheckpointsToQualify (%d) exceeds stage count (%d) — nobody could qualify",
		Config.CheckpointsToQualify,
		#Config.Stages
	)
)

return Config
