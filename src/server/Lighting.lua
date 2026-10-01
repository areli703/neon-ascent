--!strict
--[[
	Lighting — builds the full post-processing stack once, then
	crossfades between per-biome presets as the player climbs.

	Design intent: volumetric Future lighting, heavy atmosphere, and a
	tight bloom threshold so only the neon actually glows. Everything
	transitions with tweens — nothing ever snaps.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Lighting_ = {}

local FADE = TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local stack = {}

local function ensure(className: string, name: string): Instance
	local inst = Lighting:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end

function Lighting_.build()
	local atmosphere = ensure("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.16
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(140, 170, 255)
	atmosphere.Decay = Color3.fromRGB(60, 70, 130)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.6

	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 1.5
	bloom.Size = 34
	bloom.Threshold = 1.05

	local cc = ensure("ColorCorrectionEffect", "ColorGrade") :: ColorCorrectionEffect
	cc.Brightness = 0
	cc.Contrast = 0.14
	cc.Saturation = 0.24
	cc.TintColor = Color3.fromRGB(255, 250, 255)

	local rays = ensure("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.03
	rays.Spread = 0.9

	local blur = ensure("BlurEffect", "Blur") :: BlurEffect
	blur.Size = 0

	local dof = ensure("DepthOfFieldEffect", "Depth") :: DepthOfFieldEffect
	dof.FarIntensity = 0.06
	dof.FocusDistance = 120
	dof.InFocusRadius = 60
	dof.NearIntensity = 0.02

	-- A permanent slow drift in ClockTime would fight Future lighting
	-- perf; instead we keep time fixed per biome and animate the sky.
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true

	stack = {
		Atmosphere = atmosphere,
		Bloom = bloom,
		ColorGrade = cc,
		SunRays = rays,
		Blur = blur,
		Depth = dof,
	}

	Lighting_.apply(Config.Biomes.Neon, true)
end

--[[
	Crossfade to a biome's mood. `instant` skips the tween for the
	very first frame so the place doesn't load in a half-lit state.
]]
function Lighting_.apply(biome: Config.Biome, instant: boolean?)
	local atmo = stack.Atmosphere :: Atmosphere
	local bloom = stack.Bloom :: BloomEffect
	local cc = stack.ColorGrade :: ColorCorrectionEffect
	local rays = stack.SunRays :: SunRaysEffect

	local props = {
		{
			atmo,
			{
				Color = biome.Primary:Lerp(Color3.new(1, 1, 1), 0.3),
				Decay = biome.Secondary:Lerp(biome.Fog, 0.5),
			},
		},
		{ bloom, { Intensity = 1.5, Size = 34, Threshold = 1.05 } },
		{
			cc,
			{
				TintColor = Color3.new(1, 1, 1):Lerp(biome.Primary, 0.12),
				Contrast = 0.14,
				Saturation = 0.24,
			},
		},
	}

	local direct = {
		{
			Lighting,
			{ Ambient = biome.Ambient, OutdoorAmbient = biome.Ambient:Lerp(biome.Fog, 0.4) },
		},
		{
			Lighting,
			{ ClockTime = biome.ClockTime, Brightness = biome.ClockTime == 0 and 0.6 or 2 },
		},
		{ Lighting, { FogColor = biome.Fog, FogStart = 0, FogEnd = 2000 } },
		{ atmo, { Density = 0.16 } },
		{ rays, { Intensity = biome.ClockTime == 0 and 0.03 or 0.14 } },
	}

	local groups = { props, direct }
	for _, group in ipairs(groups) do
		for _, pair in ipairs(group :: any) do
			local inst, goal = pair[1], pair[2]
			if instant then
				for k, v in pairs(goal) do
					(inst :: any)[k] = v
				end
			else
				TweenService:Create(inst, FADE, goal):Play()
			end
		end
	end

	-- Per-biome fog distance so far stages feel denser and taller.
	Lighting.FogEnd = 1400 - (biome.Name == "Void" and 500 or 0)
end

--[[
	Dramatic, scripted moments. The client calls these through the
	Vfx remote; they run locally so they never affect other players.
]]
local function flash(color: Color3, length: number, peak: number)
	local cc = stack.ColorGrade :: ColorCorrectionEffect
	local base = cc.TintColor
	TweenService:Create(
		cc,
		TweenInfo.new(length * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TintColor = color, Brightness = peak }
	):Play()
	task.delay(length * 0.25, function()
		TweenService:Create(
			cc,
			TweenInfo.new(length, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ TintColor = base, Brightness = 0 }
		):Play()
	end)
end

function Lighting_.flashColor(color: Color3, length: number?)
	flash(color, length or 1.2, 0.25)
end

function Lighting_.pulseBloom(peak: number, length: number?)
	local bloom = stack.Bloom :: BloomEffect
	local base = bloom.Intensity
	bloom.Intensity = peak
	TweenService:Create(
		bloom,
		TweenInfo.new(length or 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Intensity = base }
	):Play()
end

function Lighting_.fadeToBlack(duration: number)
	local cc = stack.ColorGrade :: ColorCorrectionEffect
	TweenService:Create(
		cc,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = -1 }
	):Play()
end

function Lighting_.fadeIn(duration: number)
	local cc = stack.ColorGrade :: ColorCorrectionEffect
	TweenService:Create(
		cc,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	):Play()
end

return Lighting_
