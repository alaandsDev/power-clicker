--[[
	Qual espada aparece na mão: SwordLogic.Equipped é o que o SwordService usa
	para montar a espada a cada spawn. Se o registro estiver quebrado, a mão
	recebe a espada inicial — nunca nada.
	(A montagem física no personagem é coberta pelo tools/lune/check_sword.luau
	e, de verdade, só no Studio.)
]]
local Shared = game:GetService("ReplicatedStorage").Shared
local SwordLogic = require(Shared.Formulas.SwordLogic)
local SwordConfig = require(Shared.Config.SwordConfig)
local Migrations = require(script.Parent.Parent.Parent.Services.DataService.Migrations)

local function otherSword(): string
	for id in SwordConfig.Swords do
		if id ~= SwordConfig.DefaultSword then
			return id
		end
	end
	error("SwordConfig has a single sword")
end

return function(T)
	T.describe("SwordLogic.Equipped (spawn)", function()
		T.it("new player shows the starter blade", function()
			T.expect(SwordLogic.Equipped(SwordLogic.Fresh()).Id).toBe(SwordConfig.DefaultSword)
		end)

		T.it("shows an owned blade that is equipped", function()
			local swords = SwordLogic.Fresh()
			local id = otherSword()
			swords.Owned[id] = true
			T.expect((SwordLogic.Equip(swords, id))).toBe(true)
			T.expect(SwordLogic.Equipped(swords).Id).toBe(id)
		end)

		T.it("falls back to the starter for a blade that is not owned", function()
			local swords = SwordLogic.Fresh()
			swords.Equipped = otherSword()
			T.expect(SwordLogic.Equipped(swords).Id).toBe(SwordConfig.DefaultSword)
		end)

		T.it("falls back to the starter for an unknown id or a missing record", function()
			local swords = SwordLogic.Fresh()
			swords.Equipped = "NoSuchBlade"
			T.expect(SwordLogic.Equipped(swords).Id).toBe(SwordConfig.DefaultSword)
			T.expect(SwordLogic.Equipped(nil).Id).toBe(SwordConfig.DefaultSword)
			T.expect(SwordLogic.Equipped({ Equipped = "Iron" } :: any).Id).toBe(SwordConfig.DefaultSword)
		end)

		T.it("migrated data (v6 -> v7) gets the starter equipped", function()
			local data: { [string]: any } = { DataVersion = 6 }
			Migrations.Steps[6](data)
			T.expect(SwordLogic.Equipped(data.Swords).Id).toBe(SwordConfig.DefaultSword)
		end)

		T.it("Sanitize repairs a blade equipped but not owned", function()
			local swords = SwordLogic.Fresh()
			swords.Equipped = otherSword()
			T.expect(SwordLogic.Sanitize(swords) > 0).toBe(true)
			T.expect(swords.Equipped).toBe(SwordConfig.DefaultSword)
		end)
	end)
end
