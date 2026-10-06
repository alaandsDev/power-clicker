--[[
	econ_profiles.luau — perfis de jogador da auditoria de economia.

	Nada aqui é do jogo: são SUPOSIÇÕES de comportamento, escritas para serem
	discutidas. O que é regra do jogo vem das configs (econ_model.luau).

	Campos:
		HoursPerDay     horas de jogo ATIVO por dia (variação diária ±Jitter)
		Sessions        sessões por dia (barreira parcial se perde ao sair:
		                o estado do corredor é por servidor)
		AfkHoursPerDay  horas AFK por dia (pedestal de treino; auto click se
		                tiver o passe). Exige anti-AFK: o Roblox derruba quem
		                fica 20 min sem input.
		HoldShare       fração do tempo ativo segurando o clique (9/s)
		HoldJitter      variação por jogador do HoldShare (±)
		TrainShare      do tempo SEM clicar, fração no pedestal de treino
		WallShare       dos golpes, fração dada na barreira da vez (o resto é
		                no boss, na praça, andando)
		Burst/Pause     padrão do clique (s segurando / s parado) → combo médio
		                calculado com o ComboLogic real
		BossJoin        chance de participar de cada boss (a cada 7 min)
		BossShare       fração do dano do boss (chance de runa)
		OthersKillBoss  chance de OUTRO jogador matar o boss (servidor público):
		                o Power2x de 15 min vai para todos no mundo
		OrbCatch        chance de pegar cada orbe (a cada 22 s)
		Patience        luta mais longa (s) que o jogador aceita encarar numa
		                barreira nova; acima disso farma vitórias ou só clica
		ChipsBeyondPatience  raspa a barreira a sessão inteira mesmo assim
		RebirthAt       renasce quando o saldo passa de RebirthAt × custo
		                (1 = assim que pode)
		SaveAt          para de comprar melhoria temporária quando o saldo
		                passa desta fração do ponto de renascer
		GemPatience     true = guarda gema para a melhor compra; false = compra
		                a melhor que cabe agora
		BuysLuck        considera o Lucky Charm
		Passes          { DoublePower = true, VIP = true, ExtraPets = true, ... }
		AutoClick       tem o passe Auto Click e deixa ligado
		StartWeekday    1 = domingo … 2 = segunda (Happy Hour de fim de semana)
]]

local Profiles = {}

Profiles.Casual = {
	Id = "Casual",
	Name = "Casual",
	HoursPerDay = 0.5,
	Sessions = 1,
	Jitter = 0.5,
	HoldShare = 0.45,
	HoldJitter = 0.2,
	TrainShare = 0.4,
	WallShare = 0.6,
	Burst = 15,
	Pause = 8,
	BossJoin = 0.2,
	BossShare = 0.3,
	OthersKillBoss = 0.4,
	OrbCatch = 0.2,
	Patience = 300,
	RebirthAt = 3,
	SaveAt = 1.0,
	GemPatience = false,
	StartWeekday = 2,
}

Profiles.Ativo = {
	Id = "Ativo",
	Name = "Ativo",
	HoursPerDay = 1.5,
	Sessions = 2,
	Jitter = 0.4,
	HoldShare = 0.75,
	HoldJitter = 0.15,
	TrainShare = 0.3,
	WallShare = 0.8,
	Burst = 45,
	Pause = 5,
	BossJoin = 0.35,
	BossShare = 0.4,
	OthersKillBoss = 0.4,
	OrbCatch = 0.5,
	Patience = 600,
	RebirthAt = 1.5,
	SaveAt = 0.5,
	GemPatience = true,
	StartWeekday = 2,
}

Profiles.MuitoAtivo = {
	Id = "MuitoAtivo",
	Name = "Muito ativo",
	HoursPerDay = 4,
	Sessions = 2,
	Jitter = 0.3,
	HoldShare = 0.9,
	HoldJitter = 0.08,
	TrainShare = 0.2,
	WallShare = 0.85,
	Burst = 90,
	Pause = 3,
	BossJoin = 0.5,
	BossShare = 0.5,
	OthersKillBoss = 0.4,
	OrbCatch = 0.7,
	Patience = 1200,
	RebirthAt = 1.2,
	SaveAt = 0.5,
	GemPatience = true,
	StartWeekday = 2,
}

Profiles.Afk = {
	Id = "Afk",
	Name = "Auto Click/AFK",
	HoursPerDay = 1,
	Sessions = 1,
	Jitter = 0.3,
	AfkHoursPerDay = 8,
	AutoClick = true,
	Passes = { AutoClick = true },
	HoldShare = 0.5,
	HoldJitter = 0.15,
	TrainShare = 0.8,
	WallShare = 0.8,
	Burst = 30,
	Pause = 6,
	BossJoin = 0.2,
	BossShare = 0.3,
	OthersKillBoss = 0.4,
	OrbCatch = 0.3,
	Patience = 600,
	RebirthAt = 1.5,
	SaveAt = 0.5,
	GemPatience = true,
	StartWeekday = 2,
}

Profiles.Otimizador = {
	Id = "Otimizador",
	Name = "Otimizador",
	HoursPerDay = 6,
	Sessions = 3,
	Jitter = 0.2,
	HoldShare = 0.97,
	HoldJitter = 0.02,
	TrainShare = 0.1,
	WallShare = 0.9,
	Burst = 300,
	Pause = 2,
	BossJoin = 0.8,
	BossShare = 0.8,
	OthersKillBoss = 0.4,
	OrbCatch = 0.9,
	Patience = 2400,
	RebirthAt = 1,
	SaveAt = 0.3,
	GemPatience = true,
	BuysLuck = true,
	StartWeekday = 2,
}

--[[
	Hipóteses para o caso real (≈4B de Power em ≈2 dias). Não são perfis de
	jogador "normais": servem para ver o que reproduz o número.
	- Dono do jogo: o criador do place é dono dos próprios passes no Roblox
	  (UserOwnsGamePassAsync = true) → 2x Power + VIP + 3 pets + Auto Click.
	  REQUER VALIDAÇÃO NO ROBLOX STUDIO / no jogo publicado.
	- Servidor sozinho: ninguém mais mata o boss (só o Power2x de quem mata).
]]
Profiles.DonoComPasses = {
	Id = "DonoComPasses",
	Name = "Dono (passes) muito ativo",
	HoursPerDay = 4,
	Sessions = 2,
	Jitter = 0,
	AfkHoursPerDay = 2,
	AutoClick = true,
	Passes = { DoublePower = true, VIP = true, ExtraPets = true, AutoClick = true },
	HoldShare = 0.9,
	HoldJitter = 0,
	TrainShare = 0.2,
	WallShare = 0.85,
	Burst = 90,
	Pause = 3,
	BossJoin = 0.9,
	BossShare = 1,
	OthersKillBoss = 0,
	OrbCatch = 0.9,
	Patience = 1200,
	RebirthAt = 1.2,
	SaveAt = 0.5,
	GemPatience = true,
	StartWeekday = 7, -- começou num sábado (Happy Hour ×2)
}

Profiles.Order = { "Casual", "Ativo", "MuitoAtivo", "Afk", "Otimizador" }

return Profiles
