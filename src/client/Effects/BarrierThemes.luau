--!strict
--[[
	BarrierThemes
	A identidade VISUAL de cada barreira quando apanha e quando quebra. As
	cores vêm do WallConfig (Color = a barreira, Accent = a energia do tema):
	aqui fica só o que é próprio do efeito — material dos fragmentos, poeira,
	partícula temática e o quanto a quebra é grandiosa.

	Puro: nenhuma instância, nenhum estado. BarrierFx lê.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))

-- Partícula temática do impacto (texturas que já vêm com o Roblox).
export type Particle = "Sparkle" | "Ember" | "Smoke" | "Electric"

export type Theme = {
	StageId: string,
	Chip: Color3, -- fragmentos (cor da barreira)
	ChipMaterial: Enum.Material,
	ChipGlow: boolean, -- fragmentos incandescentes/brilhantes
	Dust: Color3, -- poeira/névoa
	Energy: Color3, -- faíscas/energia (acento do tema)
	Particle: Particle,
	Smoke: boolean, -- fumaça na quebra (vulcânico)
	Epic: number, -- 1 = normal; o Colosso é a quebra mais grandiosa
}

local TEXTURES: { [Particle]: string } = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Ember = "rbxasset://textures/particles/fire_sparks_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Electric = "rbxasset://textures/particles/sparkles_main.dds",
}

-- O que cada tema tem de próprio (as cores ficam no WallConfig).
local KINDS: { [string]: { ChipMaterial: Enum.Material, ChipGlow: boolean, Dust: Color3, Particle: Particle, Smoke: boolean, Epic: number } } = {
	Wood = { ChipMaterial = Enum.Material.Wood, ChipGlow = false, Dust = Color3.fromRGB(196, 168, 120), Particle = "Smoke", Smoke = false, Epic = 1 },
	Ruins = { ChipMaterial = Enum.Material.Slate, ChipGlow = false, Dust = Color3.fromRGB(170, 170, 176), Particle = "Smoke", Smoke = false, Epic = 1 },
	Ice = { ChipMaterial = Enum.Material.Ice, ChipGlow = false, Dust = Color3.fromRGB(220, 240, 255), Particle = "Sparkle", Smoke = false, Epic = 1.1 },
	Crystal = { ChipMaterial = Enum.Material.Glass, ChipGlow = true, Dust = Color3.fromRGB(170, 235, 255), Particle = "Sparkle", Smoke = false, Epic = 1.15 },
	Gold = { ChipMaterial = Enum.Material.Metal, ChipGlow = false, Dust = Color3.fromRGB(255, 226, 150), Particle = "Ember", Smoke = false, Epic = 1.2 },
	Ancient = { ChipMaterial = Enum.Material.Sandstone, ChipGlow = false, Dust = Color3.fromRGB(200, 180, 140), Particle = "Sparkle", Smoke = false, Epic = 1.25 },
	Volcanic = { ChipMaterial = Enum.Material.Basalt, ChipGlow = true, Dust = Color3.fromRGB(80, 70, 70), Particle = "Ember", Smoke = true, Epic = 1.3 },
	Magma = { ChipMaterial = Enum.Material.CrackedLava, ChipGlow = true, Dust = Color3.fromRGB(120, 70, 50), Particle = "Ember", Smoke = true, Epic = 1.35 },
	Tech = { ChipMaterial = Enum.Material.DiamondPlate, ChipGlow = true, Dust = Color3.fromRGB(150, 200, 255), Particle = "Electric", Smoke = false, Epic = 1.4 },
	Colossus = { ChipMaterial = Enum.Material.Marble, ChipGlow = true, Dust = Color3.fromRGB(235, 225, 255), Particle = "Electric", Smoke = true, Epic = 2 },
}

local BarrierThemes = {}

function BarrierThemes.Texture(particle: Particle): string
	return TEXTURES[particle]
end

function BarrierThemes.For(stageId: string): Theme?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			local kind = KINDS[stage.Id] or KINDS.Ruins
			return {
				StageId = stage.Id,
				Chip = stage.Color,
				ChipMaterial = kind.ChipMaterial,
				ChipGlow = kind.ChipGlow,
				Dust = kind.Dust,
				Energy = stage.Accent,
				Particle = kind.Particle,
				Smoke = kind.Smoke,
				Epic = kind.Epic,
			}
		end
	end
	return nil
end

-- Todos os estágios do WallConfig têm tema próprio? (para os testes)
function BarrierThemes.Missing(): { string }
	local missing = {}
	for _, stage in WallConfig.Stages do
		if not KINDS[stage.Id] then
			table.insert(missing, stage.Id)
		end
	end
	return missing
end

return BarrierThemes
