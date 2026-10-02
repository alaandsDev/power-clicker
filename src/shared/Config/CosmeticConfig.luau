--!strict
--[[
	CosmeticConfig
	Status you can SEE on another player (Phase 11). Nothing here changes power
	or economy — it is pure recognition:

		Aura  — a glowing ring at the feet + character outline, by rebirth count
		Badge — the overhead plate: name, rebirth count, current zone, VIP mark

	Tiers are checked from the highest down, so a player always gets the best
	tier whose Rebirths they reached.
]]

export type AuraTier = {
	Id: string,
	Rebirths: number, -- minimum rebirths
	DisplayName: string,
	Color: Color3,
	RingSize: number, -- diameter in studs
	LightRange: number,
	Outline: boolean, -- also outlines the character
}

local Tiers: { AuraTier } = {
	{ Id = "None", Rebirths = 0, DisplayName = "Iniciante", Color = Color3.fromRGB(200, 205, 225), RingSize = 0, LightRange = 0, Outline = false },
	{ Id = "Spark", Rebirths = 1, DisplayName = "Faísca", Color = Color3.fromRGB(120, 220, 255), RingSize = 6, LightRange = 10, Outline = false },
	{ Id = "Charged", Rebirths = 5, DisplayName = "Carregado", Color = Color3.fromRGB(70, 210, 110), RingSize = 7, LightRange = 12, Outline = false },
	{ Id = "Storm", Rebirths = 15, DisplayName = "Tempestade", Color = Color3.fromRGB(140, 90, 255), RingSize = 8, LightRange = 14, Outline = true },
	{ Id = "Radiant", Rebirths = 40, DisplayName = "Radiante", Color = Color3.fromRGB(255, 196, 45), RingSize = 9, LightRange = 18, Outline = true },
	{ Id = "Cosmic", Rebirths = 100, DisplayName = "Cósmico", Color = Color3.fromRGB(255, 80, 160), RingSize = 10, LightRange = 22, Outline = true },
}

return {
	Tiers = Tiers,

	Badge = {
		Height = 3.2, -- studs above the head
		MaxDistance = 90,
		VipColor = Color3.fromRGB(255, 196, 45),
	},
}
