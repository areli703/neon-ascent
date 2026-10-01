--!strict
--[[
	Effects — server-side VFX and audio dispatch.

	All visual work happens on the client (Effects.client.lua) so that
	one player's celebration never costs another player frames. The
	server only decides *what happened* and broadcasts the event.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Effects = {}

local SFX = {
	Checkpoint = "rbxassetid://9114363065",
	Qualify = "rbxassetid://9114490302",
	Hazard = "rbxassetid://9114236385",
	Countdown = "rbxassetid://9114363065",
	Victory = "rbxassetid://9120386436",
	Defeat = "rbxassetid://9114236385",
	Whoosh = "rbxassetid://9114385566",
}

function Effects.ids(): { [string]: string }
	return SFX
end

local function vfx(player: Player?, kind: string, payload: { [string]: any })
	local remote = Remotes.get("Vfx") :: RemoteEvent
	if player then
		remote:FireClient(player, kind, payload)
	else
		remote:FireAllClients(kind, payload)
	end
end

function Effects.burst(player: Player, position: Vector3, color: Color3, count: number?)
	vfx(player, "burst", { position = position, color = color, count = count or 24 })
end

function Effects.checkpoint(player: Player, position: Vector3, color: Color3, index: number)
	vfx(nil, "checkpoint", { position = position, color = color, index = index })
	vfx(player, "sound", { id = SFX.Checkpoint, volume = 0.55 })
	vfx(player, "shake", { intensity = 0.45, duration = 0.35 })
end

function Effects.flash(player: Player, color: Color3, duration: number?)
	vfx(player, "flash", { color = color, duration = duration or 1.0 })
end

function Effects.sound(player: Player, name: string, volume: number?)
	local id = SFX[name]
	if not id then
		return
	end
	vfx(player, "sound", { id = id, volume = volume or 0.6 })
end

function Effects.shake(player: Player, intensity: number, duration: number)
	vfx(player, "shake", { intensity = intensity, duration = duration })
end

function Effects.announce(text: string, color: Color3?)
	local notify = Remotes.get("Notify") :: RemoteEvent
	notify:FireAllClients(text, color or Color3.fromRGB(235, 245, 255))
end

--[[
	A world-space pillar of light, used for checkpoint confirmation and
	the finish-line celebration. Broadcast to everyone so the tower
	feels alive when someone is climbing.
]]
function Effects.beacon(position: Vector3, color: Color3, height: number?)
	vfx(nil, "beacon", { position = position, color = color, height = height or 90 })
end

function Effects.celebrate(position: Vector3, color: Color3)
	vfx(nil, "confetti", { position = position, color = color })
end

function Effects.stageTransition(player: Player, biome: { [string]: any }, index: number)
	vfx(player, "stage", {
		color = biome.Primary,
		fog = biome.Fog,
		title = biome.Title,
		index = index,
	})
	-- The client tweens its own Lighting so each climber's tower has its
	-- own atmosphere, even though everyone shares the same world.
	vfx(player, "lighting", { biome = biome.Name })
end

return Effects
