--!strict
--[[
	CombatFxController
	O "sentir" do combate nas barreiras do Caminho do Poder. Cada hit tem 4
	camadas que acontecem juntas, no IMPACTO do golpe:

		ESPADA    swing do personagem          (SwordSwingController)
		CORTE     slash/energia do Corte atual (SlashController -> CutFx)
		IMPACTO   no ponto em que a lâmina bate (BarrierFx.Impact, aqui)
		BARREIRA  reação ao dano               (flash da superfície, rachaduras,
		                                        número de dano, quebra)

	De onde vem cada coisa:
	- OnSwingImpact: chamado pelo SlashController no instante do impacto do
	  golpe. Se há uma fileira À FRENTE e ao alcance (a mesma regra do
	  servidor, WallController.TargetRow), o impacto nasce no ponto de contato
	  com a intensidade do Corte (CutVisuals.Recipe.Impact). É previsão VISUAL:
	  o dano continua sendo decidido no servidor.
	- WallController.RowDamaged / RowBroken / RowRestored: o estado DESTE
	  jogador (WallState). Rachaduras, número de dano real e quebra vêm daqui —
	  então nada do que outro jogador faz aparece como dano na barreira dele.

	Hit forte: quando o golpe tira STRONG_SHARE ou mais do HP da fileira, só o
	feedback cresce (impacto, onda, fragmentos, câmera). Nenhum dano muda.

	"Efeitos reduzidos": impacto só com o flash, sem partícula/fragmento/onda
	extra, sem tremor de câmera; rachaduras e números continuam (informação).
	Números de dano seguem "Mostrar números" (ShowFloatingNumbers).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local CutVisuals = require(Shared:WaitForChild("Formulas"):WaitForChild("CutVisuals"))

local BarrierFx = require(script.Parent.Parent.Effects.BarrierFx)
local BarrierThemes = require(script.Parent.Parent.Effects.BarrierThemes)
local CameraFx = require(script.Parent.Parent.Effects.CameraFx)
local CutFx = require(script.Parent.Parent.Effects.CutFx)
local DamageNumbers = require(script.Parent.Parent.Effects.DamageNumbers)
local WallController = require(script.Parent.WallController)
local DataController = require(script.Parent.DataController)
local GameStateController = require(script.Parent.GameStateController)
local SoundController = require(script.Parent.SoundController)
local SwordSwingController = require(script.Parent.SwordSwingController)

-- Um hit que tira isto (ou mais) do HP da fileira é "forte" (só visual).
local STRONG_SHARE = 0.25
-- Rachaduras só nas fileiras até esta distância do personagem.
local CRACK_DISTANCE = 120
-- "Hit stop" visual na quebra (segundos de pose segurada).
local HIT_STOP = 0.045
local FINAL_HIT_STOP = 0.06

local CombatFxController = {}

local fx: BarrierFx.Fx? = nil
local numbers: DamageNumbers.Numbers? = nil
local breakCut: CutFx.Rig? = nil
local lastPrune = 0

local function reduced(): boolean
	local settings = DataController.Get("Settings")
	return settings ~= nil and settings.ReducedEffects == true
end

local function showNumbers(): boolean
	local settings = DataController.Get("Settings")
	return not settings or settings.ShowFloatingNumbers ~= false
end

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function stageOf(stageId: any): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

-- O hit é "forte"? (fatia do HP da fileira que um golpe tira)
function CombatFxController.IsStrong(damage: number, maxHp: number): boolean
	return maxHp > 0 and damage / maxHp >= STRONG_SHARE
end

local function currentRecipe(): CutVisuals.Recipe
	return CutVisuals.ForBest(Players.LocalPlayer:GetAttribute("BestCut"))
end

-- Normal da face das fileiras: o corredor vai para +X, a face olha para -X.
local FACE_NORMAL = Vector3.new(-1, 0, 0)

--[[
	O impacto do golpe local (chamado pelo SlashController no instante do
	impacto). Devolve a fileira atingida (ou nil, se o golpe foi no ar).
]]
function CombatFxController.OnSwingImpact(recipe: CutVisuals.Recipe?): BasePart?
	local state = fx
	local position = rootPosition()
	if not state or not position then
		return nil
	end
	local row = WallController.TargetRow(position)
	if not row then
		return nil
	end
	local stage = stageOf(row:GetAttribute("StageId"))
	local theme = if stage then BarrierThemes.For(stage.Id) else nil
	if not stage or not theme then
		return nil
	end
	local cut = recipe or currentRecipe()
	local strong = CombatFxController.IsStrong(GameStateController.GetPowerInfo().PerClick, stage.Hp)
	local isReduced = reduced()
	BarrierFx.Impact(state, theme, WallController.ContactPoint(row, position), {
		Normal = FACE_NORMAL,
		Intensity = cut.Impact,
		CutColor = cut.Color,
		Strong = strong,
		Reduced = isReduced,
	})
	SoundController.Play("WallHit")
	if not isReduced then
		CameraFx.Shake(if strong then "Strong" else "Hit")
	end
	return row
end

local function nearRow(row: BasePart): boolean
	local position = rootPosition()
	return position ~= nil and (row.Position - position).Magnitude <= CRACK_DISTANCE
end

local function onDamaged(row: BasePart, stageId: string, before: number, after: number)
	local state = fx
	local stage = stageOf(stageId)
	local theme = BarrierThemes.For(stageId)
	if not state or not stage or not theme then
		return
	end
	if nearRow(row) then
		BarrierFx.SetCracks(state, row, theme, BarrierFx.CrackTier(after / stage.Hp), reduced())
	end
	local position = rootPosition()
	if numbers and position and showNumbers() then
		DamageNumbers.Show(numbers :: DamageNumbers.Numbers, row, WallController.ContactPoint(row, position), before - after, CombatFxController.IsStrong(before - after, stage.Hp), os.clock())
	end
end

local function onBroken(row: BasePart, stageId: string, final: boolean)
	local state = fx
	local theme = BarrierThemes.For(stageId)
	if not state or not theme then
		return
	end
	local isReduced = reduced()
	local cut = currentRecipe()
	BarrierFx.Break(state, theme, row, {
		Normal = FACE_NORMAL,
		Final = final,
		CutColor = cut.Color,
		Reduced = isReduced,
	})
	-- O Corte atravessa a parede: o mesmo corte do golpe, grande, no centro.
	if breakCut and not isReduced then
		local centre = row.Position
		CutFx.Play(breakCut :: CutFx.Rig, cut, CFrame.lookAt(centre, centre + FACE_NORMAL), math.min(row.Size.Y / CutVisuals.BASE_LENGTH, 4) * 0.6, 0)
	end
	SwordSwingController.HitStop(if final then FINAL_HIT_STOP else HIT_STOP)
	if not isReduced then
		CameraFx.Shake(if final and theme.Epic >= 2 then "Epic" elseif final then "Final" else "Break")
	end
end

local function onRestored(row: BasePart)
	if fx then
		local stageId = row:GetAttribute("StageId")
		local theme = if type(stageId) == "string" then BarrierThemes.For(stageId) else nil
		if theme then
			BarrierFx.SetCracks(fx :: BarrierFx.Fx, row, theme, 0, false)
		end
	end
end

-- Para os testes: o estado interno.
function CombatFxController.State(): (BarrierFx.Fx?, DamageNumbers.Numbers?)
	return fx, numbers
end

-- Uma vez por segundo, no máximo: tira rachaduras de fileiras longe (LOD).
function CombatFxController.Prune(now: number)
	if fx and now - lastPrune >= 1 then
		lastPrune = now
		BarrierFx.PruneCracks(fx :: BarrierFx.Fx, nearRow)
	end
end

function CombatFxController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "CombatFx"
	folder.Parent = Workspace.CurrentCamera or Workspace
	fx = BarrierFx.new(folder)
	numbers = DamageNumbers.new(folder, Players.LocalPlayer:WaitForChild("PlayerGui"))
	breakCut = CutFx.NewRig("BreakCut", folder, 2)
	WallController.RowDamaged:Connect(onDamaged)
	WallController.RowBroken:Connect(onBroken)
	WallController.RowRestored:Connect(onRestored)
end

--[[
	"Efeitos reduzidos" também vale para as auras de TODOS os personagens:
	as camadas secundárias (faíscas dos tiers altos e das auras raras) são
	desligadas neste cliente; os pontinhos de energia básicos continuam (o
	personagem segue legível e o poder continua visível).
]]
local SECONDARY_AURA = { PowerSparks = true, AuraTwinkle = true }
function CombatFxController.ApplyAuraBudget(isReduced: boolean)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			for _, item in character:GetDescendants() do
				if item:IsA("ParticleEmitter") and SECONDARY_AURA[item.Name] and item.Enabled == isReduced then
					item.Enabled = not isReduced
				end
			end
		end
	end
end

function CombatFxController.Start()
	CameraFx.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			CombatFxController.Prune(os.clock())
			CombatFxController.ApplyAuraBudget(reduced())
		end
	end)
end

return CombatFxController
