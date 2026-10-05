--[[
	check_polish.luau — a passada de polish visual/UX.

		lune run tools/lune/check_polish.luau [raiz]

	Verifica:
	  1. LUZ NO PERSONAGEM: nenhum sistema preso ao personagem cria luz
	     constante (aura de poder, aura cosmética, pets); a espada parada tem
	     luz contida e rastro desligado (o golpe acende — check_fx);
	  2. PETS: formação ATRÁS do jogador (1..8 pets: todas as vagas atrás,
	     simétricas, sem pets um dentro do outro), o pet persegue a vaga com
	     suavização, nunca atravessa o personagem quando ele vira 180°, e
	     reaparece direto na vaga depois de um teleporte;
	  3. tamanho dos pets ~25% menor.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: o clarão sumiu de verdade, legibilidade
	do avatar, movimento dos pets (suavidade, câmera), auras e espada.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local CF = roblox.CFrame

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end
local function source(path: string): string
	return fs.readFile(E.Root .. "/" .. path)
end
-- Código sem comentários (as explicações citam PointLight de propósito).
local function code(path: string): string
	local text = source(path)
	text = string.gsub(text, "%-%-%[%[.-%]%]", "")
	text = string.gsub(text, "%-%-[^\n]*", "")
	return text
end

-- 1. Luz constante presa ao personagem.
for _, path in {
	"src/server/Services/CosmeticService.luau",
	"src/server/Services/AuraSkinService.luau",
	"src/client/Controllers/PetFollowController.luau",
} do
	local text = code(path)
	check(not string.find(text, "PointLight", 1, true) and not string.find(text, "SpotLight", 1, true) and not string.find(text, "SurfaceLight", 1, true),
		"1. " .. path .. ": nenhuma luz constante no personagem (poder = partículas)")
end
local cosmetic = code("src/server/Services/CosmeticService.luau")
check(not string.find(cosmetic, "Material.Neon", 1, true) and string.find(cosmetic, "ParticleEmitter", 1, true), "1. aura de poder: sem anel Neon nos pés, com partículas de energia")
check(string.find(cosmetic, "OutlineTransparency = 0.6", 1, true), "1. contorno dos tiers altos suave (não estoura a silhueta)")
local skins = code("src/server/Services/AuraSkinService.luau")
check(not string.find(skins, "Material.Neon", 1, true) and string.find(skins, "AuraTwinkle", 1, true), "1. aura cosmética: rara = segunda camada de partícula, não mais luz")
local sword = code("src/server/Services/SwordService.luau")
local idle = tonumber(string.match(sword, "glow.Brightness = ([%d%.]+)"))
check(idle and idle <= 0.5 and string.find(sword, "SwingBrightness", 1, true), string.format("1. espada parada: luz contida (%s) e forte só no golpe", tostring(idle)))
check(string.find(sword, "trail.Enabled = false", 1, true), "1. espada parada: rastro desligado (o golpe liga)")
check(string.find(sword, "Enum.Material.SmoothPlastic else sword.Material", 1, true) and string.find(sword, "BladeEdge", 1, true), "1. skins neon: lâmina sólida com fio de energia nas bordas (formato legível)")

-- 2/3. Pets.
local Sig = { Connect = function()
	return { Disconnect = function() end }
end }
E.stubs.Players = { LocalPlayer = { Name = "L", UserId = 1 }, GetPlayers = function()
	return {}
end, PlayerAdded = Sig, PlayerRemoving = Sig }
local Pets = E.require(E.Client.Controllers.PetFollowController)
local petSource = source("src/client/Controllers/PetFollowController.luau")
local art = tonumber(string.match(petSource, "local ART_SIZE = ([%d%.]+)"))
check(art and art <= 3.8 * 0.8 and art >= 3.8 * 0.65, string.format("3. pets ~20–30%% menores (arte %s, antes 3.8)", tostring(art)))
check(not string.find(code("src/client/Controllers/PetFollowController.luau"), "math.cos(angle)", 1, true), "2. sem órbita: os pets não giram em volta do jogador")

local maxSlots = 8
for count = 1, maxSlots do
	local slots = {}
	local ok = true
	for index = 1, count do
		local slot = Pets.Slot(index, count)
		table.insert(slots, slot)
		if slot.Z < 3 then
			ok = false -- tem de estar atrás (+Z no espaço do jogador)
		end
	end
	local minGap = math.huge
	local sumX = 0
	for i = 1, #slots do
		sumX += slots[i].X
		for j = i + 1, #slots do
			minGap = math.min(minGap, (slots[i] - slots[j]).Magnitude)
		end
	end
	check(ok and minGap >= 2.5 and math.abs(sumX) < 1e-6, string.format("2. %d pet(s): todos atrás, simétricos e sem um dentro do outro (menor distância %.1f)", count, if count == 1 then 0 else minGap))
end
local one = Pets.Slot(1, 1)
local three = { Pets.Slot(1, 3), Pets.Slot(2, 3), Pets.Slot(3, 3) }
check(one.X == 0 and three[3].X == 0 and three[1].X == -three[2].X, "2. 1 pet no meio; 3 pets: dois lado a lado e o terceiro atrás no meio")

-- Virada de 180°: o pet vai para a nova vaga sem atravessar o jogador.
local root = V3.new(0, 3, 0)
local function base(yaw)
	return CF.new(root) * CF.Angles(0, yaw, 0)
end
local current = base(0) * CF.new(Pets.Slot(1, 1))
local closest = math.huge
for _ = 1, 240 do
	current = Pets.StepToward(current, base(math.pi) * CF.new(Pets.Slot(1, 1)), root, 0, 1 / 60)
	local flat = V3.new(current.Position.X - root.X, 0, current.Position.Z - root.Z)
	closest = math.min(closest, flat.Magnitude)
end
local final = (current.Position - (base(math.pi) * CF.new(Pets.Slot(1, 1))).Position).Magnitude
check(closest >= 2.5, string.format("2. jogador vira 180°: o pet contorna, nunca atravessa o personagem (mais perto: %.2f studs)", closest))
check(final < 0.3, string.format("2. e chega à nova vaga atrás (%.2f studs da vaga depois de 4 s)", final))

-- Suavização: um passo não pula para a vaga; teleporte longo reaparece direto.
local from = base(0) * CF.new(Pets.Slot(1, 1))
local target = from + V3.new(0, 0, 6)
local step = Pets.StepToward(from, target, root + V3.new(0, 0, 6), 0, 1 / 60)
check((step.Position - from.Position).Magnitude > 0 and (step.Position - target.Position).Magnitude > 1, "2. o pet persegue a vaga com suavização (pequeno atraso natural)")
local far = from + V3.new(300, 0, 0)
check((Pets.StepToward(from, far, root + V3.new(300, 0, 0), 0, 1 / 60).Position - far.Position).Magnitude < 1e-6, "2. teleporte (praça): o pet reaparece direto na vaga")
local back = Pets.StepToward(from, target, root, 3, 1 / 60)
check((back.Position - from.Position).Magnitude < (step.Position - from.Position).Magnitude, "2. fileiras de trás seguem com um pouco mais de atraso")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: personagem sem holofote, espada contida parada, pets menores em formação atrás.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: legibilidade do avatar, auras, espada e o movimento real dos pets.")
process.exit(0)
