--!strict
--[[
	Remotes — a single typed factory for every RemoteEvent / RemoteFunction.
	Created on the server, awaited on the client. Keeps the network
	surface in one auditable place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
		end
	end
	return folder :: Folder
end

-- name -> className
local DEFINITIONS = {
	PushState = "RemoteEvent", -- server -> client : full game state snapshot
	Checkpoint = "RemoteEvent", -- server -> client : you tagged a checkpoint
	Notify = "RemoteEvent", -- server -> client : toast message
	Shake = "RemoteEvent", -- server -> client : camera impulse
	Vfx = "RemoteEvent", -- server -> client : world particle events
	RequestState = "RemoteFunction", -- client -> server : ask for a resync
}

function Remotes.get(name: string): Instance
	local folder = getFolder()
	if RunService:IsServer() then
		local inst = folder:FindFirstChild(name)
		if not inst then
			local className = DEFINITIONS[name] or "RemoteEvent"
			inst = Instance.new(className)
			inst.Name = name
			inst.Parent = folder
		end
		return inst
	end
	return folder:WaitForChild(name, 30)
end

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup must run on the server")
	for name in pairs(DEFINITIONS) do
		Remotes.get(name)
	end
end

return Remotes
