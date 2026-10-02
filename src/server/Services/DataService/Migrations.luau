--!strict
--[[
	Migrations
	Steps[n] upgrades data FROM version n TO version n + 1, in place.

	Rules:
	- Never delete player progress. Rename/move values instead.
	- Steps must be deterministic and must not yield.
	- Once shipped, a step is never edited — add a new one.
	- DataService runs migrations on a deep copy; if any step errors, the
	  original data is left untouched and the player is kicked (not reset).

	Example for a future v2:
		Steps[1] = function(data)
			-- v1 -> v2: move Settings.Music to Settings.MusicVolume
			data.Settings.MusicVolume = if data.Settings.Music == false then 0 else 0.5
			data.Settings.Music = nil
		end
]]

export type Step = (data: { [string]: any }) -> ()

local Try = require(game:GetService("ReplicatedStorage").Shared.Utils.Try)

local Migrations = {}

Migrations.Steps = {} :: { [number]: Step }

-- v1 -> v2: season pass (Phase 12). Existing players start the season at 0.
Migrations.Steps[1] = function(data)
	if type(data.Season) ~= "table" then
		data.Season = { SeasonId = "", Xp = 0, ClaimedFree = {}, ClaimedVip = {} }
	end
end

--[[
	v2 -> v3: auras and runes (Phase 15). Everyone starts with the default
	(empty) aura equipped and no runes; nothing existing is touched.
]]
Migrations.Steps[2] = function(data)
	if type(data.Auras) ~= "table" then
		data.Auras = { Owned = { None = true }, Equipped = "None" }
	end
	if type(data.Runes) ~= "table" then
		data.Runes = { Owned = {}, Equipped = {} }
	end
end

--[[
	v3 -> v4: wins (Phase 16). A third currency that never resets, earned on the
	win pads behind the breakable walls. Nobody had any before, so it starts at 0.
]]
Migrations.Steps[3] = function(data)
	if type(data.Currencies) == "table" and type(data.Currencies.Wins) ~= "number" then
		data.Currencies.Wins = 0
	end
	if type(data.Stats) == "table" and type(data.Stats.TotalWinsEarned) ~= "number" then
		data.Stats.TotalWinsEarned = 0
	end
end

--[[
	v4 -> v5: the cut pads (Phase 16). Everyone gets the starter cut, which is
	the swing they already had, so nothing changes for an existing player.
]]
Migrations.Steps[4] = function(data)
	if type(data.Cuts) ~= "table" then
		data.Cuts = { Owned = { Cut1 = true } }
	end
end

--[[
	v5 -> v6: the tower (Fase B). Nobody had cleared a stage before, so the
	record starts empty — the first clear of each stage pays its gems from now
	on, including for players who already broke the old corridor.
]]
Migrations.Steps[5] = function(data)
	if type(data.Tower) ~= "table" then
		data.Tower = { Cleared = {}, Highest = 0 }
	end
end

--[[
	v6 -> v7: espadas cosméticas (Fase E). Todo mundo começa com a de ferro; as
	outras são concedidas pelo SwordService assim que a condição de progressão
	já cumprida é lida (quem já passou do estágio recebe a skin ao entrar).
]]
Migrations.Steps[6] = function(data)
	if type(data.Swords) ~= "table" then
		data.Swords = { Owned = { Iron = true }, Equipped = "Iron" }
	end
end

--[[
	v7 -> v8: auras cosméticas (Fase F). Começam com as de desbloqueio padrão;
	o AuraSkinService concede as outras conforme a progressão já cumprida.
	As auras de gemas (data.Auras) não são tocadas: quem comprou continua com
	velocidade e Power.
]]
Migrations.Steps[7] = function(data)
	if type(data.AuraSkins) ~= "table" then
		data.AuraSkins = { Owned = { None = true, Dust = true }, Equipped = "None" }
	end
end

-- Returns (true) on success, or (false, reason). Mutates `data`.
function Migrations.Run(data: { [string]: any }, targetVersion: number, steps: { [number]: Step }?): (boolean, string?)
	local stepTable = steps or Migrations.Steps
	local version = data.DataVersion
	if type(version) ~= "number" or version % 1 ~= 0 or version < 1 then
		return false, "invalid DataVersion " .. tostring(version)
	end
	if version > targetVersion then
		return false, string.format("data version %d is newer than server version %d", version, targetVersion)
	end
	while version < targetVersion do
		local step = stepTable[version]
		if not step then
			return false, string.format("missing migration step %d -> %d", version, version + 1)
		end
		local ok, err = Try.Call(step, data)
		if not ok then
			return false, string.format("migration %d -> %d failed: %s", version, version + 1, tostring(err))
		end
		version += 1
		data.DataVersion = version
	end
	return true, nil
end

return Migrations
