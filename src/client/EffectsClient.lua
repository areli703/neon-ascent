--!strict
--[[
	EffectsClient — everything that sells the hit.

	All of it is local: hit flash, camera shake, impact particles, audio,
	checkpoint rings, and the climb haze. Because it is client-side, the
	effects are free — a 30-player lobby costs each client only its own.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local EffectsClient = {}

local shake = { trauma = 0 }
local flash = { alpha = 0, color = Color3.new(1, 1, 1) }
local flashGui: Frame? = nil

local SOUND_IDS: { [string]: string } = {
	Hazard = "rbxassetid://9120386434",
	Countdown = "rbxassetid://6895079853",
	Checkpoint = "rbxassetid://6895079853",
	Victory = "rbxassetid://1837879082",
	Step = "rbxassetid://6042053626",
}

local function ensureFlash()
	if flashGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "NeonFlash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	flashGui = f
end

--[[
	Camera shake via trauma^2 falloff — the standard trick for shakes that
	feel weighty at the start and settle cleanly.
]]
local function updateShake(dt: number)
	if shake.trauma <= 0 then
		return
	end
	shake.trauma = math.max(0, shake.trauma - dt * 1.6)
	local amount = shake.trauma * shake.trauma
	local t = os.clock() * 60
	local ox = math.sin(t * 0.9) * amount * 0.9
	local oy = math.cos(t * 1.3) * amount * 0.9
	local oz = math.sin(t * 0.7) * amount * 0.5
	local rz = math.sin(t * 1.1) * amount * 0.35
	camera.CFrame = camera.CFrame * CFrame.new(ox, oy, oz) * CFrame.Angles(0, 0, rz)
end

local function updateFlash()
	if not flashGui then
		return
	end
	if flash.alpha > 0 then
		flash.alpha = math.max(0, flash.alpha - 0.045)
		flashGui.BackgroundColor3 = flash.color
		flashGui.BackgroundTransparency = 1 - flash.alpha
	elseif flashGui.BackgroundTransparency < 1 then
		flashGui.BackgroundTransparency = 1
	end
end

function EffectsClient.shake(player: Player, intensity: number)
	if player ~= Players.LocalPlayer then
		return
	end
	shake.trauma = math.min(1, shake.trauma + intensity * 0.5)
end

function EffectsClient.flash(player: Player, color: Color3, alpha: number)
	if player ~= Players.LocalPlayer then
		return
	end
	ensureFlash()
	flash.color = color
	flash.alpha = math.max(flash.alpha, alpha)
end

--[[
	Play a raw asset id. The server sends ids (it owns the sound table),
	so the client never has to keep a second copy of the mapping in sync.
]]
function EffectsClient.playAudio(id: string, volume: number?)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

function EffectsClient.sound(player: Player, name: string, volume: number)
	if player ~= Players.LocalPlayer then
		return
	end
	local id = SOUND_IDS[name]
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

function EffectsClient.checkpoint(
	player: Player,
	position: Vector3,
	color: Color3,
	_index: number
): ()
	if player ~= Players.LocalPlayer then
		return
	end
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.3, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	local tween = TweenService:Create(
		ring,
		TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, 34, 34), Transparency = 1 }
	)
	tween:Play()
	Debris:AddItem(ring, 1.1)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 40
	light.Brightness = 6
	light.Parent = ring
	Debris:AddItem(light, 0.9)
end

function EffectsClient.celebrate(position: Vector3, color: Color3)
	for i = 1, 24 do
		task.delay(i * 0.03, function()
			local spark = Instance.new("Part")
			spark.Size = Vector3.new(0.4, 0.4, 0.4)
			spark.Anchored = false
			spark.CanCollide = false
			spark.CanQuery = false
			spark.Material = Enum.Material.Neon
			spark.Color = if i % 3 == 0 then Color3.fromRGB(255, 255, 255) else color
			spark.CFrame = CFrame.new(position + Vector3.new(0, 6, 0))
			spark.AssemblyLinearVelocity =
				Vector3.new(math.random(-40, 40), math.random(50, 110), math.random(-40, 40))
			spark.Parent = workspace
			Debris:AddItem(spark, 4)
		end)
	end
end

function EffectsClient.announce(text: string, color: Color3)
	local hud = require(script.Parent.HUD)
	hud.toast(text, color)
end

-- HUD lives in the same folder as this module (a fresh copy inside
-- StarterPlayerScripts), so script.Parent is the right require root.

function EffectsClient.stageTransition(player: Player, biome: any, index: number)
	if player ~= Players.LocalPlayer then
		return
	end
	EffectsClient.flash(player, biome.Primary, 0.28)
	task.delay(0.05, function()
		EffectsClient.announce(
			string.format("STAGE %d  ·  %s", index, string.upper(biome.Name)),
			biome.Primary
		)
	end)
end

--[[
	Per-player biome mood. The server tells each climber which biome they
	have entered; the client tweens its OWN Lighting so the atmosphere
	shifts for them alone. That is the whole trick behind every player
	having a different-looking tower while sharing one world.
]]
function EffectsClient.setBiome(name: string)
	local biome = Config.Biomes[name]
	if not biome then
		return
	end
	local info = TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

	TweenService:Create(Lighting, info, {
		FogColor = biome.Fog,
		Ambient = biome.Ambient,
		OutdoorAmbient = biome.Ambient:Lerp(biome.Fog, 0.4),
		ClockTime = biome.ClockTime,
		Brightness = if biome.ClockTime == 0 then 0.6 else 2,
	}):Play()

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, {
			Color = biome.Primary:Lerp(Color3.new(1, 1, 1), 0.3),
			Decay = biome.Secondary:Lerp(biome.Fog, 0.5),
		}):Play()
	end
end

function EffectsClient.init()
	camera = workspace.CurrentCamera
	ensureFlash()
	RunService.RenderStepped:Connect(function(dt)
		updateShake(dt)
		updateFlash()
	end)
end

return EffectsClient
