--[[
	run_tests.luau — roda os specs de src/server/Tests (o mesmo TestRunner do
	Studio) fora do Roblox, com o Lune.

		lune run tools/lune/run_tests.luau [raiz]

	Sai com código 1 se algum teste falhar FORA da lista KNOWN_FAILURES.
	As falhas conhecidas já existiam antes do polimento (ver TESTING.md) e são
	mostradas separadas, para não esconderem uma regressão nova.

	Limites: tudo que o spec testar e depender do motor do Roblox (física,
	replicação, DataStore real) não roda aqui — os specs do projeto já só
	usam módulos puros e o MockDataStoreBackend.
]]
local process = require("@lune/process")
local E = require("./env")(process.args[1])

-- Prefixos de "Spec > describe > teste" que falham na main (TESTING.md).
local KNOWN_FAILURES = {
	"EconomyFormulas.spec > EconomyFormulas > RebirthGems and RebirthMultiplier",
	"AuraRuneLogic.spec > RuneLogic > drops nothing for a player who barely touched the boss",
	"LevelFormula.spec > LevelFormula > levels up exactly on the step cost",
}

local TestRunner = E.require(E.Server.Tests.TestRunner)
local result = TestRunner.RunAll(E.Server.Tests)

local known, unexpected = {}, {}
for _, failure in result.Failures do
	local isKnown = false
	for _, prefix in KNOWN_FAILURES do
		if string.sub(failure, 1, #prefix) == prefix then
			isKnown = true
		end
	end
	table.insert(if isKnown then known else unexpected, failure)
end
for _, failure in known do
	print("[conhecida] " .. failure)
end
for _, failure in unexpected do
	print("[FALHA] " .. failure)
end
print(string.format("[TESTS] %d passed, %d failed (%d conhecidas, %d novas)", result.Passed, result.Failed, #known, #unexpected))
process.exit(if #unexpected > 0 then 1 else 0)
