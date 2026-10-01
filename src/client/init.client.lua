--!strict
--[[
	Client bootstrap.

	One job: wire every server broadcast to the module that draws it.
	The server never touches the UI, and the client never decides game
	logic — it only renders what it is told. That split is what keeps
	the tower's frame budget predictable at 30 players.

	Order:
	  1. HUD       — build the interface first, so nothing arrives unseen
	  2. Effects   — camera / particles / audio
	  3. remotes   — subscribe last, once there is something to draw into
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local HUD = require(script.HUD)
local EffectsClient = require(script.EffectsClient)

local player = Players.LocalPlayer

-- ── build ───────────────────────────────────────────────────────────
HUD.init()
EffectsClient.init()

-- ── state feed ──────────────────────────────────────────────────────
-- The server pushes a full snapshot every half-second. Rendering is
-- idempotent, so a dropped or duplicated message is harmless.
local pushState = Remotes.get("PushState") :: RemoteEvent
pushState.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then
		return
	end
	HUD.setState(state)
end)

-- ── checkpoint feedback ─────────────────────────────────────────────
local checkpoint = Remotes.get("Checkpoint") :: RemoteEvent
checkpoint.OnClientEvent:Connect(function(position, color, index)
	EffectsClient.checkpoint(player, position, color, index)
end)

-- ── toasts ──────────────────────────────────────────────────────────
local notify = Remotes.get("Notify") :: RemoteEvent
notify.OnClientEvent:Connect(function(text, color)
	HUD.toast(text, color or Color3.fromRGB(235, 245, 255))
end)

-- ── world-space VFX ─────────────────────────────────────────────────
-- Payload kinds are dispatched here so EffectsClient owns the visual
-- vocabulary in one place.
local vfx = Remotes.get("Vfx") :: RemoteEvent
vfx.OnClientEvent:Connect(function(kind, payload)
	if typeof(payload) ~= "table" then
		return
	end
	if kind == "flash" then
		EffectsClient.flash(player, payload.color, payload.duration or 0.6)
	elseif kind == "shake" then
		EffectsClient.shake(player, payload.intensity or 0.5)
	elseif kind == "sound" then
		EffectsClient.playAudio(payload.id or "", payload.volume or 0.6)
	elseif kind == "lighting" then
		EffectsClient.setBiome(payload.biome or "Neon")
	elseif kind == "checkpoint" then
		EffectsClient.checkpoint(player, payload.position, payload.color, payload.index)
	elseif kind == "beacon" or kind == "confetti" or kind == "burst" then
		EffectsClient.celebrate(payload.position, payload.color)
	elseif kind == "stage" then
		EffectsClient.stageTransition(player, {
			Name = payload.title,
			Primary = payload.color,
		}, payload.index or 0)
	end
end)

-- ── boot ────────────────────────────────────────────────────────────
HUD.setBanner("CONNECTING", Color3.fromRGB(200, 215, 240), "waiting for the tower")
