--!strict
-- ClubMusicBootstrap
-- Place as LocalScript: StarterPlayer/StarterPlayerScripts/ClubMusicBootstrap.client.lua
-- This small entry point is required because ModuleScripts do not execute on their own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local networkModule = ReplicatedStorage:WaitForChild("UI_Network")
local rendererModule = ReplicatedStorage:WaitForChild("UI_Renderer")

local Network = require(networkModule)
local Renderer = require(rendererModule)

Network.Init()
local mounted = Renderer.Mount(player, Network)

script.Destroying:Connect(function()
    if mounted and mounted.Destroy then
        mounted.Destroy()
    end
    if Network.Destroy then
        Network.Destroy()
    end
end)
