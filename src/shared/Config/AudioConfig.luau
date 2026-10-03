--!strict
--[[
	AudioConfig
	Sound registry. Every SoundId is empty (TODO_ASSET) until licensed/owned
	audio is uploaded; SoundController silently skips empty ids.
	Only use audio you own or that is licensed for use (e.g. Roblox-provided
	audio in the Creator Store marked as free to use).
]]

export type SoundData = {
	SoundId: string, -- "rbxassetid://..." or "" (TODO_ASSET)
	Volume: number,
	-- Minimum seconds between plays (prevents 20 click sounds per second).
	MinInterval: number,
	PitchVariation: number, -- random ± pitch for repeated sounds
}

local Sounds: { [string]: SoundData } = {
	Click = { SoundId = "", Volume = 0.4, MinInterval = 0.05, PitchVariation = 0.08 }, -- TODO_ASSET
	ComboTier = { SoundId = "", Volume = 0.5, MinInterval = 0.2, PitchVariation = 0 }, -- TODO_ASSET
	Upgrade = { SoundId = "", Volume = 0.6, MinInterval = 0.05, PitchVariation = 0.05 }, -- TODO_ASSET
	Rebirth = { SoundId = "", Volume = 0.8, MinInterval = 0.5, PitchVariation = 0 }, -- TODO_ASSET
	OverdriveStart = { SoundId = "", Volume = 0.8, MinInterval = 0.5, PitchVariation = 0 }, -- TODO_ASSET
	OverdriveEnd = { SoundId = "", Volume = 0.5, MinInterval = 0.5, PitchVariation = 0 }, -- TODO_ASSET
	Egg = { SoundId = "", Volume = 0.7, MinInterval = 0.2, PitchVariation = 0 }, -- TODO_ASSET
	RarePet = { SoundId = "", Volume = 0.8, MinInterval = 0.2, PitchVariation = 0 }, -- TODO_ASSET
	Legendary = { SoundId = "", Volume = 0.9, MinInterval = 0.5, PitchVariation = 0 }, -- TODO_ASSET
	Mythic = { SoundId = "", Volume = 1, MinInterval = 0.5, PitchVariation = 0 }, -- TODO_ASSET
	Purchase = { SoundId = "", Volume = 0.7, MinInterval = 0.2, PitchVariation = 0 }, -- TODO_ASSET
	Reward = { SoundId = "", Volume = 0.7, MinInterval = 0.2, PitchVariation = 0 }, -- TODO_ASSET
	Error = { SoundId = "", Volume = 0.5, MinInterval = 0.2, PitchVariation = 0 }, -- TODO_ASSET
	-- Caminho do Poder: golpe na barreira e fileira quebrando (madeira, pedra...).
	WallHit = { SoundId = "", Volume = 0.45, MinInterval = 0.08, PitchVariation = 0.1 }, -- TODO_ASSET
	WallBreak = { SoundId = "", Volume = 0.8, MinInterval = 0.15, PitchVariation = 0.05 }, -- TODO_ASSET
}

return {
	Sounds = Sounds,
}
