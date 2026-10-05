--!strict
--[[
	TrainingConfig
	O Campo de Treinamento do lobby: quatro alvos de treino; o jogador fica
	no pedestal de um deles e ganha Power continuamente enquanto está ali.

	Regra de equilíbrio que define tudo aqui: o treino NUNCA pode render mais
	que o clique ativo. O clique segurado dá 9 golpes por segundo
	(EconomyConfig.Click.HoldClicksPerSecond); o melhor alvo dá o
	equivalente a 1,8 — ou seja, um quinto. O treino existe para o jogador não
	ficar parado enquanto organiza pets, escolhe melhoria ou conversa; não para
	substituir o dedo no botão.

	`Rate` é em "cliques por segundo equivalentes": o servidor paga
	`poderPorClique × Rate × tempo`, então o treino acompanha
	automaticamente todo multiplicador que o jogador conquistar — nunca vira
	uma segunda economia com números próprios.

	Ids aparecem nas strings (`training.<Id>.name`) e nos atributos; renomear
	exige atualizar a localização.
]]

local Shared = script.Parent.Parent

export type Station = {
	Id: string,
	Order: number, -- I..IV (o algarismo romano da placa)
	DisplayName: string,
	Kind: string, -- como o StationMachines monta o boneco: Dummy / Scarecrow / Warrior / Guardian
	Local: Vector3, -- deslocamento dentro da área de treino (centro do pedestal)
	Radius: number, -- distância em que o treino conta (= meio pedestal)
	Rate: number, -- cliques/s equivalentes
	--[[
		Renascimentos necessários (Stats.Rebirths). Antes era em vitórias
		(0 / 10 / 60 / 300); trocado pela simulação em
		tools/simulate_training.py: com 0 / 1 / 3 / 6 o treino pesa no longo
		prazo o mesmo de antes (≈5% do Power do jogador ativo, ≈24% do
		casual) e cada estação nova vira um marco do Renascer. Nada disto é
		salvo: é só config, o save não muda.
	]]
	RequiredRebirths: number,
	Color: Color3,
}

--[[
	CAMPO DE TREINAMENTO: quatro alvos de treino em arco, do boneco de
	madeira ao Guardião de Poder. Rates IGUAIS aos da academia antiga.
	O arco é côncavo para a entrada (frente = -Z local da área, para a
	avenida); os raios não se cruzam (o serviço pega a primeira estação que
	contém o jogador).
]]
local Stations: { Station } = {
	{
		Id = "Dummy",
		Order = 1,
		DisplayName = "Boneco de Treino",
		Kind = "Dummy",
		Local = Vector3.new(-19, 0, -2),
		Radius = 4.5,
		Rate = 0.35,
		RequiredRebirths = 0,
		Color = Color3.fromRGB(196, 150, 96),
	},
	{
		Id = "Scarecrow",
		Order = 2,
		DisplayName = "Espantalho Reforçado",
		Kind = "Scarecrow",
		Local = Vector3.new(-7, 0, 5),
		Radius = 5,
		Rate = 0.7,
		RequiredRebirths = 1,
		Color = Color3.fromRGB(170, 178, 192),
	},
	{
		Id = "Warrior",
		Order = 3,
		DisplayName = "Guerreiro de Treino",
		Kind = "Warrior",
		Local = Vector3.new(6, 0, 5),
		Radius = 5.5,
		Rate = 1.2,
		RequiredRebirths = 3,
		Color = Color3.fromRGB(90, 200, 255),
	},
	{
		Id = "Guardian",
		Order = 4,
		DisplayName = "Guardião de Poder",
		Kind = "Guardian",
		Local = Vector3.new(19.5, 0, -2),
		Radius = 6,
		Rate = 1.8,
		RequiredRebirths = 6,
		Color = Color3.fromRGB(255, 170, 60),
	},
}

return {
	Stations = Stations,
	Area = "Training", -- área do LobbyConfig onde as máquinas ficam

	-- Um único laço no servidor cuida de todos os jogadores (um laço por
	-- jogador seria desperdício e vazaria conexões a cada respawn).
	TickSeconds = 0.5,

	--[[
		Teto de segurança: por mais que a config mude, o treino nunca paga mais
		que esta fração do clique segurado. Se alguém editar um Rate alto demais
		por engano, o servidor corta aqui em vez de arruinar a economia.
	]]
	MaxShareOfHoldClick = 0.25,

	-- O personagem precisa estar no chão da máquina: pulando ou caindo não
	-- treina (e também fecha a porta para quem tenta "voar" por cima dos pads).
	RequireGrounded = true,
}
