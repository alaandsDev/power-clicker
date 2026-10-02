--!strict
--[[
	AuraSkinLogic
	Regras puras das auras cosméticas: posse, equipar e condição de
	desbloqueio. Mesma forma do SwordLogic, de propósito — os dois sistemas são
	coleções conquistadas por progressão, e manter a forma igual significa uma
	regra para entender em vez de duas.

	Nada aqui toca em multiplicador: aura cosmética é aparência.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local AuraSkinConfig = require(Shared.Config.AuraSkinConfig)

type AuraSkinsData = Types.AuraSkinsData
type AuraSkinData = AuraSkinConfig.AuraSkinData

local AuraSkinLogic = {}

function AuraSkinLogic.Fresh(): AuraSkinsData
	local owned: { [string]: boolean } = {}
	-- As de desbloqueio "Default" já vêm liberadas.
	for id, skin in AuraSkinConfig.Skins do
		if skin.Unlock.Kind == "Default" then
			owned[id] = true
		end
	end
	return { Owned = owned, Equipped = AuraSkinConfig.DefaultSkin }
end

function AuraSkinLogic.Get(skinId: string): AuraSkinData?
	return AuraSkinConfig.Skins[skinId]
end

function AuraSkinLogic.Ordered(): { AuraSkinData }
	local list: { AuraSkinData } = {}
	for _, skin in AuraSkinConfig.Skins do
		table.insert(list, skin)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function AuraSkinLogic.Owns(skins: AuraSkinsData, skinId: string): boolean
	return skins.Owned[skinId] == true
end

-- A condição de progressão já foi cumprida? (mesma Progress das espadas)
function AuraSkinLogic.IsUnlocked(skin: AuraSkinData, progress: { Rebirths: number, Wins: number, Cleared: { [string]: boolean } }): boolean
	local unlock = skin.Unlock
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

function AuraSkinLogic.Equip(skins: AuraSkinsData, skinId: string): (boolean, string?)
	if not AuraSkinConfig.Skins[skinId] then
		return false, "InvalidRequest"
	end
	if not AuraSkinLogic.Owns(skins, skinId) then
		return false, "NotOwned"
	end
	skins.Equipped = skinId
	return true, nil
end

function AuraSkinLogic.Equipped(skins: AuraSkinsData): AuraSkinData
	local skin = AuraSkinConfig.Skins[skins.Equipped]
	return skin or AuraSkinConfig.Skins[AuraSkinConfig.DefaultSkin]
end

-- Valores já dentro dos tetos de segurança do config.
function AuraSkinLogic.SafeRate(skin: AuraSkinData): number
	return math.clamp(skin.Rate, 0, AuraSkinConfig.MaxRate)
end

function AuraSkinLogic.SafeSize(skin: AuraSkinData): number
	return math.clamp(skin.Size, 0, AuraSkinConfig.MaxSize)
end

function AuraSkinLogic.Sanitize(skins: AuraSkinsData): number
	local fixes = 0
	if type(skins.Owned) ~= "table" then
		skins.Owned = {}
		fixes += 1
	end
	for skinId in skins.Owned do
		if not AuraSkinConfig.Skins[skinId] then
			skins.Owned[skinId] = nil
			fixes += 1
		end
	end
	if not skins.Owned[AuraSkinConfig.DefaultSkin] then
		skins.Owned[AuraSkinConfig.DefaultSkin] = true
		fixes += 1
	end
	if type(skins.Equipped) ~= "string" or not AuraSkinLogic.Owns(skins, skins.Equipped) then
		skins.Equipped = AuraSkinConfig.DefaultSkin
		fixes += 1
	end
	return fixes
end

return AuraSkinLogic
