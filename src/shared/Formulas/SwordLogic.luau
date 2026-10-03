--!strict
--[[
	SwordLogic
	Regras puras das espadas cosméticas: o que o jogador tem, o que ele pode
	equipar e qual condição falta para liberar cada skin.

	O servidor decide com isto (SwordService) e a UI mostra as mesmas
	respostas — uma condição de desbloqueio existe em um lugar só.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local SwordConfig = require(Shared.Config.SwordConfig)

type SwordsData = Types.SwordsData
type SwordData = Types.SwordData

local SwordLogic = {}

function SwordLogic.Fresh(): SwordsData
	return { Owned = { [SwordConfig.DefaultSword] = true }, Equipped = SwordConfig.DefaultSword }
end

function SwordLogic.Get(swordId: string): SwordData?
	return SwordConfig.Swords[swordId]
end

-- Ordenadas para a UI (da primeira à última).
function SwordLogic.Ordered(): { SwordData }
	local list: { SwordData } = {}
	for _, sword in SwordConfig.Swords do
		table.insert(list, sword)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function SwordLogic.Owns(swords: SwordsData, swordId: string): boolean
	return swords.Owned[swordId] == true
end

--[[
	A skin já foi conquistada? `progress` carrega o que o desbloqueio olha:
		Rebirths, Wins e Cleared (mapa estágio -> true, de PlayerData.Tower).
	Retorna true quando a condição está cumprida.
]]
export type Progress = {
	Rebirths: number,
	Wins: number,
	Cleared: { [string]: boolean },
}

function SwordLogic.IsUnlocked(sword: SwordData, progress: Progress): boolean
	local unlock = sword.Unlock
	if unlock.Kind == "Default" then
		return true
	elseif unlock.Kind == "Rebirths" then
		return progress.Rebirths >= (unlock.Value or 0)
	elseif unlock.Kind == "Wins" then
		return progress.Wins >= (unlock.Value or 0)
	elseif unlock.Kind == "TowerStage" then
		local stage = unlock.Stage
		return stage ~= nil and progress.Cleared[stage] == true
	end
	return false
end

-- Equipa uma skin que o jogador tem. (false, code) quando não tem.
function SwordLogic.Equip(swords: SwordsData, swordId: string): (boolean, string?)
	if not SwordConfig.Swords[swordId] then
		return false, "InvalidRequest"
	end
	if not SwordLogic.Owns(swords, swordId) then
		return false, "NotOwned"
	end
	swords.Equipped = swordId
	return true, nil
end

-- A skin equipada, ou a padrão quando o registro está quebrado: id que não
-- existe, skin que o jogador não possui ou registro ausente.
function SwordLogic.Equipped(swords: SwordsData?): SwordData
	local default = SwordConfig.Swords[SwordConfig.DefaultSword]
	if type(swords) ~= "table" or type(swords.Owned) ~= "table" then
		return default
	end
	local sword = SwordConfig.Swords[swords.Equipped]
	if not sword or swords.Owned[sword.Id] ~= true then
		return default
	end
	return sword
end

--[[
	Conserta um registro carregado: tira ids que não existem, devolve a skin
	padrão e cai para ela quando a equipada não é do jogador. Retorna quantos
	problemas foram corrigidos.
]]
function SwordLogic.Sanitize(swords: SwordsData): number
	local fixes = 0
	if type(swords.Owned) ~= "table" then
		swords.Owned = {}
		fixes += 1
	end
	for swordId in swords.Owned do
		if not SwordConfig.Swords[swordId] then
			swords.Owned[swordId] = nil
			fixes += 1
		end
	end
	if not swords.Owned[SwordConfig.DefaultSword] then
		swords.Owned[SwordConfig.DefaultSword] = true
		fixes += 1
	end
	if type(swords.Equipped) ~= "string" or not SwordLogic.Owns(swords, swords.Equipped) then
		swords.Equipped = SwordConfig.DefaultSword
		fixes += 1
	end
	return fixes
end

return SwordLogic
