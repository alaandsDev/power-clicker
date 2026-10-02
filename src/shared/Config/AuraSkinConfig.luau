--!strict
--[[
	AuraSkinConfig
	Auras COSMÉTICAS: partículas e brilho em volta do personagem, por raridade.

	Por que existe um segundo sistema de aura: as auras do AuraConfig foram
	vendidas por gemas e dão velocidade e Power — quem comprou não pode perder
	o que pagou. O pedido, porém, quer uma coleção de auras por raridade que
	NÃO dê multiplicador. Então:

		AuraConfig     — compradas com gemas, dão velocidade e Power (aba "Poder")
		AuraSkinConfig — ganhas por progressão, só aparência (aba "Visual")

	Ambas podem estar ativas ao mesmo tempo: uma é o que você comprou, a outra
	é o que você conquistou.

	Orçamento de efeito (o pedido veta queda de FPS e veta tapar o personagem):
	- um emissor de partículas por jogador, com taxa máxima de MaxRate;
	- luz só nas duas raridades mais altas;
	- tamanho da partícula limitado para não cobrir o corpo nem a barreira.

	Ids são persistidos em PlayerData.AuraSkins — nunca renomear após o
	lançamento.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

export type AuraSkinData = {
	Id: string,
	Order: number,
	DisplayName: string,
	Rarity: Types.RarityId,
	Unlock: Types.SwordUnlock, -- mesma forma de desbloqueio das espadas
	Color: Color3,
	SecondaryColor: Color3,
	Rate: number, -- partículas por segundo (0 = só brilho)
	Size: number, -- studs
	Lifetime: number,
	Speed: number,
	LightRange: number, -- 0 = sem luz
	Ring: boolean, -- anel fino no chão
}

local function skin(
	id: string,
	order: number,
	name: string,
	rarity: Types.RarityId,
	unlock: Types.SwordUnlock,
	color: Color3,
	secondary: Color3,
	rate: number,
	size: number,
	lifetime: number,
	speed: number,
	light: number,
	ring: boolean
): AuraSkinData
	return {
		Id = id,
		Order = order,
		DisplayName = name,
		Rarity = rarity,
		Unlock = unlock,
		Color = color,
		SecondaryColor = secondary,
		Rate = rate,
		Size = size,
		Lifetime = lifetime,
		Speed = speed,
		LightRange = light,
		Ring = ring,
	}
end

local Skins: { [string]: AuraSkinData } = {
	None = skin(
		"None", 1, "Nenhuma", "Common",
		{ Kind = "Default" },
		Color3.fromRGB(200, 205, 225), Color3.fromRGB(200, 205, 225),
		0, 0, 0, 0, 0, false
	),
	Dust = skin(
		"Dust", 2, "Poeira de Treino", "Common",
		{ Kind = "Default" },
		Color3.fromRGB(226, 214, 180), Color3.fromRGB(190, 176, 140),
		4, 0.5, 0.8, 1.4, 0, false
	),
	Leaf = skin(
		"Leaf", 3, "Folhas", "Uncommon",
		{ Kind = "TowerStage", Stage = "Ruins" },
		Color3.fromRGB(104, 200, 110), Color3.fromRGB(70, 150, 80),
		6, 0.6, 1.1, 1.8, 0, false
	),
	Frost = skin(
		"Frost", 4, "Sopro Gelado", "Rare",
		{ Kind = "TowerStage", Stage = "Ice" },
		Color3.fromRGB(170, 230, 255), Color3.fromRGB(110, 180, 230),
		9, 0.7, 1.2, 2.2, 0, true
	),
	Spark = skin(
		"Spark", 5, "Faíscas", "Rare",
		{ Kind = "Rebirths", Value = 10 },
		Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 160, 50),
		11, 0.6, 0.9, 3, 0, true
	),
	Flame = skin(
		"Flame", 6, "Chama Viva", "Epic",
		{ Kind = "TowerStage", Stage = "Volcanic" },
		Color3.fromRGB(255, 130, 50), Color3.fromRGB(220, 50, 30),
		14, 0.8, 1, 2.6, 0, true
	),
	Void = skin(
		"Void", 7, "Névoa do Vazio", "Legendary",
		{ Kind = "Wins", Value = 3_000 },
		Color3.fromRGB(180, 110, 255), Color3.fromRGB(90, 40, 160),
		16, 0.9, 1.4, 2, 16, true
	),
	Celestial = skin(
		"Celestial", 8, "Coroa Celeste", "Mythic",
		{ Kind = "TowerStage", Stage = "Colossus" },
		Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 130, 230),
		18, 1, 1.6, 2.4, 22, true
	),
}

return {
	Skins = Skins,
	DefaultSkin = "None",

	--[[
		Tetos de segurança. Mesmo que alguém edite um valor alto demais, o
		servidor corta aqui: com 20 jogadores numa praça, é a diferença entre um
		jogo que roda no celular e um que não roda.
	]]
	MaxRate = 20,
	MaxSize = 1.2,
	-- Altura do emissor em relação ao centro do personagem.
	EmitterHeight = -1.2,
	RingSize = 7,
}
