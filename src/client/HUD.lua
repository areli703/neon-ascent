--!strict
--[[
	HUD — the player's window into the round.

	Design brief: roomy, full-width, readable at a glance, and it should
	feel like part of the world rather than a bolted-on UI. Two elements
	only: a slim state banner up top, and a compact progress panel on the
	left. Everything animates; nothing blocks the view of the tower.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

export type PushState = {
	phase: string,
	phaseEndsAt: number,
	round: number,
	stageCount: number,
	players: { any },
}

local HUD = {}

local banner: Frame
local bannerText: TextLabel
local bannerSub: TextLabel
local stageLabel: TextLabel
local checkpointLabel: TextLabel
local timeLabel: TextLabel
local deathLabel: TextLabel
local progressFill: Frame
local toastHolder: Frame

local PHASE_COLOR: { [string]: Color3 } = {
	Intermission = Color3.fromRGB(130, 190, 255),
	Countdown = Color3.fromRGB(255, 205, 110),
	Climbing = Color3.fromRGB(130, 255, 185),
	Results = Color3.fromRGB(255, 205, 110),
}

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(
	parent: Instance,
	color: Color3,
	thickness: number,
	transparency: number?
): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NeonAscentHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- ── slim top banner ──────────────────────────────────────────
	local b = Instance.new("Frame")
	b.Name = "Banner"
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, 0, 0, -70)
	b.Size = UDim2.fromOffset(520, 58)
	b.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
	b.BackgroundTransparency = 0.12
	b.Parent = gui
	corner(b, 14)
	stroke(b, Color3.fromRGB(120, 200, 255), 1.5, 0.35)
	banner = b

	local bt = Instance.new("TextLabel")
	bt.Name = "Text"
	bt.BackgroundTransparency = 1
	bt.Size = UDim2.new(1, -24, 0.62, 0)
	bt.Position = UDim2.new(0, 12, 0.08, 0)
	bt.Font = Enum.Font.GothamBlack
	bt.Text = "NEON ASCENT"
	bt.TextColor3 = Color3.fromRGB(230, 240, 255)
	bt.TextScaled = true
	bt.TextXAlignment = Enum.TextXAlignment.Left
	bt.Parent = b
	bannerText = bt

	local bs = Instance.new("TextLabel")
	bs.Name = "Sub"
	bs.BackgroundTransparency = 1
	bs.Size = UDim2.new(1, -24, 0.3, 0)
	bs.Position = UDim2.new(0, 12, 0.66, 0)
	bs.Font = Enum.Font.GothamMedium
	bs.Text = "waiting for climbers"
	bs.TextColor3 = Color3.fromRGB(150, 170, 205)
	bs.TextScaled = true
	bs.TextXAlignment = Enum.TextXAlignment.Left
	bs.Parent = b
	bannerSub = bs

	-- ── progress panel, left edge ────────────────────────────────
	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0, 0.5)
	p.Position = UDim2.new(0, 18, 0.5, 0)
	p.Size = UDim2.fromOffset(268, 190)
	p.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
	p.BackgroundTransparency = 0.18
	p.Parent = gui
	corner(p, 16)
	stroke(p, Color3.fromRGB(90, 110, 155), 1.2, 0.55)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -28, 0, 24)
	title.Position = UDim2.fromOffset(14, 12)
	title.Font = Enum.Font.GothamBold
	title.Text = "CURRENT STAGE"
	title.TextColor3 = Color3.fromRGB(130, 155, 200)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = p
	local titleSize = title.TextSize

	local sl = Instance.new("TextLabel")
	sl.BackgroundTransparency = 1
	sl.Size = UDim2.new(1, -28, 0, 34)
	sl.Position = UDim2.fromOffset(14, 38)
	sl.Font = Enum.Font.GothamBlack
	sl.Text = "0 / " .. #Config.Stages
	sl.TextColor3 = Color3.fromRGB(235, 245, 255)
	sl.TextScaled = true
	sl.TextXAlignment = Enum.TextXAlignment.Left
	sl.Parent = p
	stageLabel = sl

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, -28, 0, 10)
	bar.Position = UDim2.fromOffset(14, 82)
	bar.BackgroundColor3 = Color3.fromRGB(24, 30, 50)
	bar.Parent = p
	corner(bar, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(130, 200, 255)
	fill.Parent = bar
	corner(fill, 5)
	progressFill = fill

	local function statRow(name: string, y: number): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -28, 0, 22)
		lbl.Position = UDim2.fromOffset(14, y)
		lbl.Font = Enum.Font.GothamMedium
		lbl.Text = name
		lbl.TextColor3 = Color3.fromRGB(200, 214, 240)
		lbl.TextScaled = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = p
		return lbl
	end

	checkpointLabel = statRow("checkpoint  —", 106)
	timeLabel = statRow("round time  —", 130)
	deathLabel = statRow("deaths      —", 154)

	-- ── toast stack, top-right ───────────────────────────────────
	local th = Instance.new("Frame")
	th.Name = "Toasts"
	th.AnchorPoint = Vector2.new(1, 0)
	th.Position = UDim2.new(1, -18, 0, 18)
	th.Size = UDim2.fromOffset(340, 220)
	th.BackgroundTransparency = 1
	th.Parent = gui
	toastHolder = th
	_ = titleSize
end

local function tween(instance: Instance, props: { [string]: any }, time: number?)
	TweenService:Create(
		instance,
		TweenInfo.new(time or 0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		props
	):Play()
end

function HUD.setBanner(text: string, color: Color3, sub: string?)
	bannerText.Text = text
	bannerText.TextColor3 = color
	if sub then
		bannerSub.Text = sub
	end
	stroke(banner, color, 1.5, 0.2)
	tween(banner, { Position = UDim2.new(0.5, 0, 0, 14) })
end

function HUD.toast(text: string, color: Color3)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0)
	card.Size = UDim2.new(1, 0, 0, 38)
	card.BackgroundColor3 = Color3.fromRGB(10, 13, 26)
	card.BackgroundTransparency = 0.15
	card.Parent = toastHolder
	corner(card, 10)
	stroke(card, color, 1.2, 0.3)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -20, 1, 0)
	lbl.Position = UDim2.fromOffset(10, 0)
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = card

	-- push existing toasts down
	local count = 0
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") and child ~= card then
			count += 1
			tween(child, { Position = UDim2.new(0.5, 0, 0, count * 44) }, 0.25)
		end
	end
	card.Position = UDim2.new(0.5, 0, 0, count * 44)
	tween(card, { Position = UDim2.new(0.5, 0, 0, count * 44) })

	task.delay(3.6, function()
		tween(card, { BackgroundTransparency = 1 }, 0.5)
		tween(lbl, { TextTransparency = 1 }, 0.5)
		task.wait(0.55)
		card:Destroy()
		local i = 0
		for _, child in ipairs(toastHolder:GetChildren()) do
			if child:IsA("Frame") then
				tween(child, { Position = UDim2.new(0.5, 0, 0, i * 44) }, 0.25)
				i += 1
			end
		end
	end)
end

function HUD.setState(state: PushState)
	local me = nil
	for _, p in ipairs(state.players) do
		if p.name == player.Name then
			me = p
			break
		end
	end

	local color = PHASE_COLOR[state.phase] or Color3.fromRGB(200, 215, 240)
	HUD.setBanner(
		state.phase,
		color,
		string.format("round %d  ·  %d stages", state.round, state.stageCount)
	)

	local cp = me and me.checkpoint or 0
	stageLabel.Text = string.format("%d / %d", cp, state.stageCount)
	stageLabel.TextColor3 = color

	local stage = Config.Stages[math.max(1, math.min(cp, #Config.Stages))]
	if stage then
		stageLabel.Text = stage.Title
	end

	local pct = math.clamp(cp / state.stageCount, 0, 1)
	tween(progressFill, { Size = UDim2.fromScale(pct, 1), BackgroundColor3 = color }, 0.4)

	checkpointLabel.Text = string.format("biome       %s", stage and stage.Biome or "Lobby")
	if me then
		timeLabel.Text = string.format(
			"finish      %s",
			me.finished and string.format("%.2fs", me.finishTime or 0) or "running"
		)
		deathLabel.Text = string.format("deaths      %d", me.deaths)
	end
end

function HUD.init()
	build()
end

return HUD
