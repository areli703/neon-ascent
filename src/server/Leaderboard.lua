--!strict
--[[
	Leaderboard — a physical, in-world scoreboard in the lobby, plus the
	data feed the HUD uses.

	It is rebuilt from GameMode's live ranking each time scores change,
	rather than being incrementally patched. Simple, and impossible to
	drift out of sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Leaderboard = {}

export type Row = {
	name: string,
	checkpoints: number,
	bestTime: number?,
	finished: boolean,
	rank: number,
}

local rowLabels: { TextLabel } = {}
local titleLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil

local MAX_ROWS = 10

--[[
	The physical board. A tall glass-and-metal slab in the lobby so the
	tower has a social anchor and players can see the race without a GUI.
]]
function Leaderboard.build(parent: Instance, position: Vector3, biome: Config.Biome)
	local body = Util.part({
		Name = "LeaderboardBody",
		Size = Vector3.new(40, 24, 2),
		CFrame = CFrame.new(position),
		Color = Color3.fromRGB(10, 12, 26),
		Material = Enum.Material.Metal,
		CanCollide = true,
	}, parent)

	Util.part({
		Name = "LeaderboardGlass",
		Size = Vector3.new(38, 22, 0.4),
		CFrame = CFrame.new(position) * CFrame.new(0, 0, 1.05),
		Color = Color3.fromRGB(8, 10, 20),
		Material = Enum.Material.Glass,
		Transparency = 0.12,
		CanCollide = false,
		CanQuery = false,
	}, parent)

	Util.neonStrip(
		parent,
		Vector3.new(40, 0.5, 2.4),
		CFrame.new(position) * CFrame.new(0, 12.1, 0),
		biome.Primary,
		0
	)
	Util.neonStrip(
		parent,
		Vector3.new(40, 0.5, 2.4),
		CFrame.new(position) * CFrame.new(0, -12.1, 0),
		biome.Secondary,
		0
	)
	Util.pointLight(body, biome.Primary, 4, 50)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 32
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = body

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.14)
	title.Position = UDim2.fromScale(0, 0.02)
	title.Font = Enum.Font.GothamBlack
	title.Text = "LIVE STANDINGS"
	title.TextColor3 = biome.Primary
	title.TextScaled = true
	title.Parent = gui
	titleLabel = title

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -20, 0.08, 0)
	status.Position = UDim2.new(0, 10, 0.88, 0)
	status.Font = Enum.Font.GothamMedium
	status.Text = "WAITING FOR CLIMBERS"
	status.TextColor3 = Color3.fromRGB(160, 175, 210)
	status.TextScaled = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = gui
	statusLabel = status

	rowLabels = {}
	for i = 1, MAX_ROWS do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -20, 0.066, 0)
		row.Position = UDim2.new(0, 10, 0.15 + (i - 1) * 0.072, 0)
		row.Font = Enum.Font.GothamMedium
		row.Text = ""
		row.TextColor3 = Color3.fromRGB(220, 232, 255)
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = gui
		table.insert(rowLabels, row)
	end
end

local function fmtTime(t: number?): string
	if not t then
		return "--:--"
	end
	local m = math.floor(t / 60)
	local s = math.floor(t % 60)
	local ms = math.floor((t - math.floor(t)) * 100)
	return string.format("%d:%02d.%02d", m, s, ms)
end

function Leaderboard.update(rows: { Row }, status: string?)
	for i = 1, MAX_ROWS do
		local label = rowLabels[i]
		if not label then
			break
		end
		local row = rows[i]
		if row then
			local tag = row.finished and "🏁"
				or string.format("%d/%d", row.checkpoints, Config.CheckpointsToQualify)
			label.Text = string.format(
				"%2d. %-14s  %-8s  %s",
				row.rank,
				string.sub(row.name, 1, 14),
				tag,
				fmtTime(row.bestTime)
			)
			label.TextColor3 = row.finished and Color3.fromRGB(150, 255, 200)
				or Color3.fromRGB(220, 232, 255)
		else
			label.Text = ""
		end
	end
	if statusLabel and status then
		statusLabel.Text = string.upper(status)
	end
end

function Leaderboard.setTitle(text: string, color: Color3)
	if titleLabel then
		titleLabel.Text = text
		titleLabel.TextColor3 = color
	end
end

return Leaderboard
