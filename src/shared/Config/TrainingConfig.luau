--!strict
--[[
	TrainingConfig
	A área de treino do lobby: máquinas em que o jogador sobe e ganha Power
	continuamente enquanto está nelas.

	Regra de equilíbrio que define tudo aqui: o treino NUNCA pode render mais
	que o clique ativo. O clique segurado dá 9 golpes por segundo
	(EconomyConfig.Click.HoldClicksPerSecond); a melhor máquina dá o
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
	Order: number,
	DisplayName: string,
	Kind: string, -- como o WorldBuilder monta: Bag / Weights / Treadmill / Rack
	Local: Vector3, -- deslocamento dentro da área de treino
	Radius: number, -- distância em que o treino conta
	Rate: number, -- cliques/s equivalentes
	RequiredWins: number,
	Color: Color3,
}

local Stations: { Station } = {
	{
		Id = "Bag",
		Order = 1,
		DisplayName = "Saco de Pancada",
		Kind = "Bag",
		Local = Vector3.new(-16, 0, -10),
		Radius = 9,
		Rate = 0.35,
		RequiredWins = 0,
		Color = Color3.fromRGB(190, 120, 70),
	},
	{
		Id = "Weights",
		Order = 2,
		DisplayName = "Halteres",
		Kind = "Weights",
		Local = Vector3.new(16, 0, -10),
		Radius = 9,
		Rate = 0.7,
		RequiredWins = 10,
		Color = Color3.fromRGB(120, 130, 150),
	},
	{
		Id = "Treadmill",
		Order = 3,
		DisplayName = "Esteira",
		Kind = "Treadmill",
		Local = Vector3.new(-16, 0, 12),
		Radius = 10,
		Rate = 1.2,
		RequiredWins = 60,
		Color = Color3.fromRGB(80, 200, 255),
	},
	{
		Id = "Rack",
		Order = 4,
		DisplayName = "Máquina de Força",
		Kind = "Rack",
		Local = Vector3.new(16, 0, 12),
		Radius = 10,
		Rate = 1.8,
		RequiredWins = 300,
		Color = Color3.fromRGB(255, 150, 60),
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
