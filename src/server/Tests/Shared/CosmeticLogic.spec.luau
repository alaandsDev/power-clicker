local Shared = game:GetService("ReplicatedStorage").Shared
local SwordLogic = require(Shared.Formulas.SwordLogic)
local AuraSkinLogic = require(Shared.Formulas.AuraSkinLogic)
local SwordConfig = require(Shared.Config.SwordConfig)
local AuraSkinConfig = require(Shared.Config.AuraSkinConfig)
local WallConfig = require(Shared.Config.WallConfig)

local function progress(rebirths: number, wins: number, cleared: { [string]: boolean })
	return { Rebirths = rebirths, Wins = wins, Cleared = cleared }
end

local function firstWith(kind: string)
	for _, sword in SwordConfig.Swords do
		if sword.Unlock.Kind == kind then
			return sword
		end
	end
	error("SwordConfig has no unlock of kind " .. kind)
end

return function(T)
	T.describe("SwordLogic", function()
		T.it("starts with the default blade equipped", function()
			local swords = SwordLogic.Fresh()
			T.expect(swords.Equipped).toBe(SwordConfig.DefaultSword)
			T.expect(SwordLogic.Equipped(swords).Id).toBe(SwordConfig.DefaultSword)
		end)

		T.it("refuses to equip a blade that was never unlocked", function()
			local swords = SwordLogic.Fresh()
			local locked = firstWith("TowerStage")
			local ok, code = SwordLogic.Equip(swords, locked.Id)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("NotOwned")
			T.expect(swords.Equipped).toBe(SwordConfig.DefaultSword)
		end)

		T.it("unlocks by rebirths, wins and tower stage", function()
			local byRebirth = firstWith("Rebirths")
			T.expect(SwordLogic.IsUnlocked(byRebirth, progress(byRebirth.Unlock.Value - 1, 0, {}))).toBe(false)
			T.expect(SwordLogic.IsUnlocked(byRebirth, progress(byRebirth.Unlock.Value, 0, {}))).toBe(true)

			local byWins = firstWith("Wins")
			T.expect(SwordLogic.IsUnlocked(byWins, progress(0, byWins.Unlock.Value - 1, {}))).toBe(false)
			T.expect(SwordLogic.IsUnlocked(byWins, progress(0, byWins.Unlock.Value, {}))).toBe(true)

			local byStage = firstWith("TowerStage")
			T.expect(SwordLogic.IsUnlocked(byStage, progress(99, 1e9, {}))).toBe(false)
			T.expect(SwordLogic.IsUnlocked(byStage, progress(0, 0, { [byStage.Unlock.Stage] = true }))).toBe(true)
		end)

		T.it("every unlock points at something that exists", function()
			local stageIds: { [string]: boolean } = {}
			for _, stage in WallConfig.Stages do
				stageIds[stage.Id] = true
			end
			for _, sword in SwordConfig.Swords do
				local unlock = sword.Unlock
				if unlock.Kind == "TowerStage" then
					T.expect(stageIds[unlock.Stage :: string]).toBe(true)
				elseif unlock.Kind == "Rebirths" or unlock.Kind == "Wins" then
					T.expect(type(unlock.Value) == "number" and unlock.Value > 0).toBe(true)
				else
					T.expect(unlock.Kind).toBe("Default")
				end
			end
		end)

		T.it("repairs a record pointing at a blade that no longer exists", function()
			local swords = { Owned = { Ghost = true }, Equipped = "Ghost" }
			T.expect(SwordLogic.Sanitize(swords :: any) > 0).toBe(true)
			T.expect(swords.Equipped).toBe(SwordConfig.DefaultSword)
			T.expect(swords.Owned.Ghost).toBe(nil)
		end)
	end)

	T.describe("AuraSkinLogic", function()
		T.it("starts with the default auras and none equipped", function()
			local skins = AuraSkinLogic.Fresh()
			T.expect(skins.Equipped).toBe(AuraSkinConfig.DefaultSkin)
			T.expect(AuraSkinLogic.Owns(skins, AuraSkinConfig.DefaultSkin)).toBe(true)
		end)

		T.it("keeps every effect inside the safety caps", function()
			-- O teto existe para servidor cheio não derrubar FPS de celular:
			-- vale para o que está no config hoje E para o que alguém editar.
			for _, skin in AuraSkinConfig.Skins do
				T.expect(AuraSkinLogic.SafeRate(skin) <= AuraSkinConfig.MaxRate).toBe(true)
				T.expect(AuraSkinLogic.SafeSize(skin) <= AuraSkinConfig.MaxSize).toBe(true)
			end
			local greedy = { Rate = 9999, Size = 50 }
			T.expect(AuraSkinLogic.SafeRate(greedy :: any)).toBe(AuraSkinConfig.MaxRate)
			T.expect(AuraSkinLogic.SafeSize(greedy :: any)).toBe(AuraSkinConfig.MaxSize)
		end)

		T.it("refuses to equip an aura that was not earned", function()
			local skins = AuraSkinLogic.Fresh()
			local locked
			for _, skin in AuraSkinConfig.Skins do
				if skin.Unlock.Kind ~= "Default" then
					locked = skin
					break
				end
			end
			local ok, code = AuraSkinLogic.Equip(skins, (locked :: any).Id)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("NotOwned")
		end)

		T.it("repairs a broken record", function()
			local skins = { Owned = { Ghost = true }, Equipped = "Ghost" }
			T.expect(AuraSkinLogic.Sanitize(skins :: any) > 0).toBe(true)
			T.expect(skins.Equipped).toBe(AuraSkinConfig.DefaultSkin)
			T.expect(skins.Owned.Ghost).toBe(nil)
		end)
	end)
end
