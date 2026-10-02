local Shared = game:GetService("ReplicatedStorage").Shared
local Text = require(Shared.Localization)
local NumberFormat = require(Shared.Utils.NumberFormat)
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)

local function placeholders(template: string): { [string]: boolean }
	local found = {}
	for name in string.gmatch(template, "{(%w+)}") do
		found[name] = true
	end
	return found
end

return function(T)
	T.describe("Localization", function()
		local locales = Text.AllLocales()

		T.it("every locale has exactly the same keys", function()
			local problems = {}
			for localeA, stringsA in locales do
				for localeB, stringsB in locales do
					for key in stringsA do
						if stringsB[key] == nil then
							table.insert(problems, localeB .. " missing " .. key .. " (present in " .. localeA .. ")")
						end
					end
				end
			end
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)

		T.it("translations use the same placeholders", function()
			local problems = {}
			local fallback = locales[GameConfig.Localization.Fallback]
			for locale, strings in locales do
				for key, template in strings do
					local expected = placeholders(fallback[key] or "")
					local actual = placeholders(template)
					for name in expected do
						if not actual[name] then
							table.insert(problems, string.format("%s %s lacks {%s}", locale, key, name))
						end
					end
				end
			end
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)

		T.it("every upgrade and world has a translated name in every locale", function()
			for locale, strings in locales do
				for id in UpgradeConfig.Temporary do
					T.expect(strings["upgrade." .. id .. ".name"] ~= nil).toBe(true)
				end
				for id in UpgradeConfig.Permanent do
					T.expect(strings["upgrade." .. id .. ".desc"] ~= nil).toBe(true)
				end
				for id in PetConfig.Pets do
					if strings["pet." .. id .. ".name"] == nil then
						error(locale .. " missing pet." .. id .. ".name")
					end
				end
				for id in EggConfig.Eggs do
					if strings["egg." .. id .. ".name"] == nil then
						error(locale .. " missing egg." .. id .. ".name")
					end
				end
				for id in PetConfig.Rarities do
					if strings["rarity." .. id] == nil then
						error(locale .. " missing rarity." .. id)
					end
				end
				for id in WorldConfig.Worlds do
					if strings["world." .. id .. ".name"] == nil then
						error(locale .. " missing world." .. id .. ".name")
					end
				end
			end
		end)

		T.it("formats placeholders and falls back to the key when missing", function()
			-- "debug.added" is "Debug: +{amount}" in every locale.
			T.expect(Text.GetFor("en", "debug.added", { amount = "5" })).toBe("Debug: +5")
			T.expect(Text.GetFor("en", "no.such.key")).toBe("no.such.key")
		end)

		T.it("resolves Roblox locale ids", function()
			if GameConfig.Localization.ForceLocale then
				T.expect(Text.Resolve("en-us")).toBe(GameConfig.Localization.ForceLocale)
			else
				T.expect(Text.Resolve("pt_BR")).toBe("pt-br")
				T.expect(Text.Resolve("pt-pt")).toBe("pt-br")
				T.expect(Text.Resolve("xx-yy")).toBe(GameConfig.Localization.Fallback)
			end
		end)

		T.it("number separators follow the locale and can be restored", function()
			NumberFormat.SetSeparators(",", ".")
			T.expect(NumberFormat.Short(2540)).toBe("2,54K")
			T.expect(NumberFormat.Commas(1234567)).toBe("1.234.567")
			NumberFormat.SetSeparators(".", ",")
			T.expect(NumberFormat.Short(2540)).toBe("2.54K")
		end)
	end)
end
