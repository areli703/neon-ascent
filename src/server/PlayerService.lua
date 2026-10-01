--!strict
--[[
	PlayerService — joins, respawns, and character hygiene.

	The only rule that matters: a player must never respawn somewhere
	that skips their progress, and must never respawn inside a hazard.
	Both are handled by asking GameMode where this player's current safe
	checkpoint is, then hard-teleporting the character there.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerService = {}

type Resolver = (player: Player) -> CFrame

local resolveSpawn: Resolver = function(_player: Player)
	return CFrame.new(0, 20, 0)
end

local SPAWN_GRACE = 0.6

--[[
	Character setup. We disable the default Roblox forcefield pop-in where
	possible and instead give a short, honest grace window so a player
	landing on a checkpoint isn't instantly killed by a passing bar.
]]
local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return
	end

	-- Move to the safe point.
	local target = resolveSpawn(player)
	character:PivotTo(target)

	humanoid.WalkSpeed = 18
	humanoid.JumpPower = 54
	humanoid.UseJumpPower = true
	humanoid.MaxSlopeAngle = 60

	-- Grace window: hazards ignore this player briefly.
	player:SetAttribute("Invulnerable", true)
	task.delay(SPAWN_GRACE, function()
		if player.Parent then
			player:SetAttribute("Invulnerable", false)
		end
	end)

	-- Keep the camera from clipping through the thick slabs.
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraSubject = humanoid
		camera.Focus = root
	end
end

function PlayerService.setSpawnResolver(fn: Resolver)
	resolveSpawn = fn
end

function PlayerService.getRespawn(player: Player): CFrame
	return resolveSpawn(player)
end

function PlayerService.teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function PlayerService.init()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
		if player.Character then
			task.spawn(setupCharacter, player, player.Character)
		end
	end)

	Players.PlayerRemoving:Connect(function(_player)
		-- nothing retained server-side; GameMode clears its own state
	end)

	-- Players who join before the round loop starts still need a spawn.
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
	end
end

return PlayerService
