--!strict
--[[
	Util — small, dependency-free helpers shared by world building,
	obstacles, and effects. No game logic lives here.
]]

local Util = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Deterministic RNG so a given seed always rebuilds the same tower.
function Util.newRng(seed: number)
	local rng = Random.new(seed)
	return rng
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.round(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

--[[
	Create a part with sane defaults. `props` overrides anything.
	Anchored by default — moving parts opt out explicitly so that
	physics cost is never paid accidentally.
]]
function Util.part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = true
	p.CastShadow = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	if parent then
		p.Parent = parent
	end
	return p
end

--[[
	Neon strip used everywhere as the visual signature: a glowing
	inlay seated on top of a structural plate. `inset` keeps it inside
	the parent footprint so nothing z-fights.
]]
function Util.neonStrip(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	transparency: number?
): Part
	return Util.part({
		Name = "NeonTrim",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

function Util.pointLight(
	parent: Instance,
	color: Color3,
	brightness: number,
	range: number
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light.Parent = parent
	return light
end

function Util.surfaceLight(
	parent: Instance,
	color: Color3,
	brightness: number,
	range: number,
	angle: number?
)
	local light = Instance.new("SurfaceLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Angle = angle or 90
	light.Face = Enum.NormalId.Top
	light.Shadows = true
	light.Parent = parent
	return light
end

--[[
	A billboard label that always reads cleanly: dark plate, neon rule,
	wide letter spacing. Used for stage titles and checkpoint beacons.
]]
function Util.billboard(
	parent: Instance,
	text: string,
	color: Color3,
	scale: number?,
	subtext: string?
): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromScale(18 * (scale or 1), 4.6 * (scale or 1))
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	bb.MaxDistance = 900

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = Color3.fromRGB(6, 8, 18)
	plate.BackgroundTransparency = 0.25
	plate.BorderSizePixel = 0
	plate.Size = UDim2.fromScale(1, 1)
	plate.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = subtext and UDim2.fromScale(1, 0.62) or UDim2.fromScale(1, 1)
	label.Position = subtext and UDim2.fromScale(0, 0.04) or UDim2.fromScale(0, 0)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = plate

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = plate

	if subtext then
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(1, 0.34)
		sub.Position = UDim2.fromScale(0, 0.63)
		sub.Font = Enum.Font.GothamMedium
		sub.Text = string.upper(subtext)
		sub.TextColor3 = Color3.fromRGB(200, 215, 245)
		sub.TextScaled = true
		sub.TextTransparency = 0.15
		sub.Parent = plate
	end

	bb.Parent = parent
	return bb
end

-- Fire-and-forget tween with optional completion callback.
function Util.tween(inst: Instance, info: TweenInfo, goal: { [string]: any }, onDone: (() -> ())?)
	local t = TweenService:Create(inst, info, goal)
	if onDone then
		t.Completed:Once(onDone)
	end
	t:Play()
	return t
end

function Util.heartbeat(fn: (number) -> ()): RBXScriptConnection
	return RunService.Heartbeat:Connect(fn)
end

-- Build a ring of points around a circle, used by several generators.
function Util.ringPoints(
	center: Vector3,
	radius: number,
	count: number,
	phase: number?
): { Vector3 }
	local out = {}
	local start = phase or 0
	for i = 0, count - 1 do
		local a = start + (i / count) * math.pi * 2
		table.insert(out, center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
	end
	return out
end

return Util
