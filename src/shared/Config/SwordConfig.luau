--!strict
--[[
	SwordConfig
	As espadas são COSMÉTICAS. Elas mudam a aparência da lâmina, o rastro e o
	efeito do corte — e nada mais.

	Quem dá dano é o CORTE (CutConfig): aquilo o jogador compra com Power e
	entra na base da fórmula. A espada é só o visual desse poder. Essa separação
	é de propósito: ninguém deve precisar de uma espada rara para continuar
	avançando se a força já permitiria.

	Desbloqueio é por PROGRESSÃO, nunca por compra nova (monetização só com
	autorização): estágio da torre, renascimentos ou vitórias. O servidor
	concede sozinho quando a condição é atingida.

	Orçamento de efeito, por skin: um rastro, uma luz e o arco do clique. Nada
	de nuvem de partículas — um servidor cheio de gente com efeito pesado é
	queda de FPS no celular, que o pedido veta explicitamente.

	Ids são persistidos em PlayerData.Swords — nunca renomear após o
	lançamento.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

export type Unlock = {
	Kind: string, -- "Default" | "TowerStage" | "Rebirths" | "Wins"
	Stage: string?, -- Kind == "TowerStage": id do estágio em WallConfig
	Value: number?, -- Kind == "Rebirths" | "Wins"
}

export type SwordData = {
	Id: string,
	Order: number,
	DisplayName: string,
	Rarity: Types.RarityId,
	Unlock: Unlock,
	-- Lâmina
	BladeSize: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Neon: boolean,
	-- Efeito de corte
	TrailSeconds: number, -- 0 = sem rastro
	TrailWidth: number,
	LightRange: number, -- 0 = sem brilho
	ArcColor: Color3, -- cor do arco que aparece no clique
	ArcScale: number, -- tamanho do arco (1 = padrão)
}

local function sword(
	id: string,
	order: number,
	name: string,
	rarity: Types.RarityId,
	unlock: Unlock,
	blade: Vector3,
	color: Color3,
	material: Enum.Material,
	neon: boolean,
	trail: number,
	trailWidth: number,
	lightRange: number,
	arcColor: Color3,
	arcScale: number
): SwordData
	return {
		Id = id,
		Order = order,
		DisplayName = name,
		Rarity = rarity,
		Unlock = unlock,
		BladeSize = blade,
		Color = color,
		Material = material,
		Neon = neon,
		TrailSeconds = trail,
		TrailWidth = trailWidth,
		LightRange = lightRange,
		ArcColor = arcColor,
		ArcScale = arcScale,
	}
end

local Swords: { [string]: SwordData } = {
	Iron = sword(
		"Iron", 1, "Lâmina de Ferro", "Common",
		{ Kind = "Default" },
		Vector3.new(0.22, 4.2, 0.9), Color3.fromRGB(198, 203, 219), Enum.Material.Metal, false,
		0.14, 0.8, 0, Color3.fromRGB(225, 230, 245), 1
	),
	Bronze = sword(
		"Bronze", 2, "Alfanje de Bronze", "Common",
		{ Kind = "Rebirths", Value = 3 },
		Vector3.new(0.26, 4.6, 1.1), Color3.fromRGB(205, 140, 70), Enum.Material.CorrodedMetal, false,
		0.18, 0.9, 0, Color3.fromRGB(255, 190, 110), 1.05
	),
	Ice = sword(
		"Ice", 3, "Presa de Gelo", "Uncommon",
		{ Kind = "TowerStage", Stage = "Ice" },
		Vector3.new(0.3, 5, 1.2), Color3.fromRGB(150, 215, 245), Enum.Material.Ice, false,
		0.24, 1, 10, Color3.fromRGB(170, 230, 255), 1.1
	),
	Crystal = sword(
		"Crystal", 4, "Estilhaço de Cristal", "Rare",
		{ Kind = "TowerStage", Stage = "Crystal" },
		Vector3.new(0.3, 5.2, 1.3), Color3.fromRGB(120, 220, 255), Enum.Material.Glass, true,
		0.28, 1.1, 14, Color3.fromRGB(120, 230, 255), 1.15
	),
	Gold = sword(
		"Gold", 5, "Espada Dourada", "Rare",
		{ Kind = "TowerStage", Stage = "Gold" },
		Vector3.new(0.32, 5.4, 1.4), Color3.fromRGB(240, 196, 70), Enum.Material.Metal, false,
		0.3, 1.2, 16, Color3.fromRGB(255, 220, 120), 1.2
	),
	Volcano = sword(
		"Volcano", 6, "Montante Vulcânico", "Epic",
		{ Kind = "TowerStage", Stage = "Volcanic" },
		Vector3.new(0.36, 5.8, 1.5), Color3.fromRGB(255, 110, 40), Enum.Material.CrackedLava, true,
		0.34, 1.3, 20, Color3.fromRGB(255, 130, 50), 1.25
	),
	Void = sword(
		"Void", 7, "Fenda do Vazio", "Legendary",
		{ Kind = "Wins", Value = 1_500 },
		Vector3.new(0.34, 6, 1.4), Color3.fromRGB(120, 60, 200), Enum.Material.Neon, true,
		0.4, 1.4, 22, Color3.fromRGB(180, 110, 255), 1.3
	),
	Colossus = sword(
		"Colossus", 8, "Lâmina do Colosso", "Mythic",
		{ Kind = "TowerStage", Stage = "Colossus" },
		Vector3.new(0.42, 6.6, 1.8), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, true,
		0.5, 1.6, 28, Color3.fromRGB(255, 150, 240), 1.45
	),
}

return {
	Swords = Swords,
	DefaultSword = "Iron",

	-- Como a Tool é segurada (igual para todas as skins: o encaixe é do
	-- Humanoid, só a lâmina muda).
	Grip = {
		Offset = Vector3.new(0, -0.2, 0),
		Pitch = -20,
		GuardSize = Vector3.new(0.3, 0.3, 1.8),
		GripSize = Vector3.new(0.3, 1.2, 0.3),
	},
}
