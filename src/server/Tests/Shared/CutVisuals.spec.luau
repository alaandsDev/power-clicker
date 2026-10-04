--[[
	Identidade visual dos Cortes: toda estação tem efeito válido, cada tier é
	diferente do anterior, a receita vem só do CutConfig (golpe e vitrine leem
	a mesma) e o estado da estação é só leitura.
]]
local Shared = game:GetService("ReplicatedStorage").Shared
local CutConfig = require(Shared.Config.CutConfig)
local CutLogic = require(Shared.Formulas.CutLogic)
local CutVisuals = require(Shared.Formulas.CutVisuals)

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

return function(T)
	T.describe("CutVisuals", function()
		T.it("every cut has a valid visual config (no cut without colour/effect)", function()
			T.expect(#CutVisuals.Problems()).toBe(0)
			for cutId in CutConfig.Cuts do
				local recipe = CutVisuals.For(cutId)
				T.expect(recipe).toBeTruthy()
				T.expect(typeof(recipe.Color)).toBe("Color3")
				T.expect(recipe.Slashes >= 1).toBe(true)
				T.expect(recipe.Length > 0).toBe(true)
				T.expect(recipe.FadeSeconds > 0).toBe(true)
			end
		end)

		T.it("the recipe is read straight from CutConfig (one source)", function()
			for cutId, cut in CutConfig.Cuts do
				local recipe = CutVisuals.For(cutId)
				T.expect(recipe.Color).toBe(cut.Color)
				T.expect(recipe.Slashes).toBe(cut.Slashes)
				T.expect(recipe.Sparks).toBe(cut.Sparks)
				T.expect(recipe.LightRange).toBe(cut.LightRange)
				T.expect(recipe.Glow).toBe(cut.Neon)
				T.expect(recipe.FadeSeconds).toBeNear(CutVisuals.FLASH_SECONDS + cut.TrailSeconds, 1e-9)
				T.expect(recipe.Length).toBeNear(CutVisuals.BASE_LENGTH * cut.SlashScale, 1e-9)
			end
		end)

		T.it("each tier evolves: never weaker than the one before, never identical", function()
			local ordered = CutLogic.Ordered()
			for index = 2, #ordered do
				local before = CutVisuals.For(ordered[index - 1].Id)
				local now = CutVisuals.For(ordered[index].Id)
				T.expect(now.Slashes >= before.Slashes).toBe(true)
				T.expect(now.Sparks >= before.Sparks).toBe(true)
				T.expect(now.Length > before.Length).toBe(true)
				T.expect(now.FadeSeconds >= before.FadeSeconds).toBe(true)
				T.expect(now.LightRange >= before.LightRange).toBe(true)
				T.expect(now.Color ~= before.Color).toBe(true)
			end
		end)

		T.it("the gameplay recipe is the best cut owned, starter when unknown", function()
			T.expect(CutVisuals.ForBest("Cut5").CutId).toBe("Cut5")
			T.expect(CutVisuals.ForBest(nil).CutId).toBe(CutConfig.StarterCut)
			T.expect(CutVisuals.ForBest("NoSuchCut").CutId).toBe(CutConfig.StarterCut)
			T.expect(CutVisuals.For("NoSuchCut")).toBeNil()
		end)

		T.it("locked showcase keeps the shape but greys out and drops the glow", function()
			for cutId in CutConfig.Cuts do
				local recipe = CutVisuals.For(cutId)
				local locked = CutVisuals.Locked(recipe)
				T.expect(locked.Slashes).toBe(recipe.Slashes)
				T.expect(locked.Length).toBe(recipe.Length)
				T.expect(locked.LightRange).toBe(0)
				T.expect(locked.Glow).toBe(false)
				T.expect(locked.Sparks <= recipe.Sparks).toBe(true)
				-- A receita original não é alterada.
				T.expect(recipe.Color).toBe(CutConfig.Cuts[cutId].Color)
			end
		end)

		T.it("angles exist for every slash count used", function()
			for _, cut in CutConfig.Cuts do
				T.expect(#CutVisuals.Angles(cut.Slashes)).toBe(cut.Slashes)
			end
		end)
	end)

	T.describe("CutLogic.State", function()
		T.it("starter only: Cut1 active, Cut2 available with 1 win, locked with 0", function()
			local cuts = CutLogic.Fresh()
			T.expect(CutLogic.State(cuts, "Cut1", 0)).toBe("Active")
			T.expect(CutLogic.State(cuts, "Cut2", 0)).toBe("Locked")
			T.expect(CutLogic.State(cuts, "Cut2", 1)).toBe("Available")
		end)

		T.it("only the best owned cut is active; lower owned ones read as owned", function()
			local cuts = { Owned = { Cut1 = true, Cut2 = true, Cut3 = true } }
			T.expect(CutLogic.State(cuts, "Cut3", 5)).toBe("Active")
			T.expect(CutLogic.State(cuts, "Cut2", 5)).toBe("Owned")
			T.expect(CutLogic.State(cuts, "Cut1", 5)).toBe("Owned")
			T.expect(CutLogic.State(cuts, "Cut4", 5)).toBe("Locked")
			T.expect(CutLogic.State(cuts, "Cut4", 25)).toBe("Available")
		end)

		T.it("is read-only: never grants a cut nor changes the data", function()
			local cuts = { Owned = { Cut1 = true } }
			local before = deepCopy(cuts)
			for cutId in CutConfig.Cuts do
				CutLogic.State(cuts, cutId, 1e12)
			end
			T.expect(cuts).toEqual(before)
		end)

		T.it("missing data falls back to the starter cut", function()
			T.expect(CutLogic.State(nil, "Cut1", nil)).toBe("Active")
			T.expect(CutLogic.State(nil, "Cut2", nil)).toBe("Locked")
		end)

		T.it("the purchase rule is still CanBuy (server): Available does not bypass it", function()
			-- Disponível na placa não compra nada: quem decide é o CanBuy, e ele
			-- continua exigindo as vitórias.
			local cuts = CutLogic.Fresh()
			T.expect(CutLogic.State(cuts, "Cut3", 5)).toBe("Available")
			T.expect((CutLogic.CanBuy(cuts, "Cut3", 4))).toBe(false)
			T.expect((CutLogic.CanBuy(cuts, "Cut3", 5))).toBe(true)
			T.expect(cuts.Owned.Cut3).toBeNil()
		end)
	end)
end
