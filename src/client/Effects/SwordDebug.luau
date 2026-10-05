--!strict
--[[
	SwordDebug
	Diagnóstico do corpo com espada (postura, golpe, combo) NO RUNTIME REAL.

	Ligado só no Roblox Studio (RunService:IsStudio()); em servidor publicado
	fica desligado sozinho: nenhum log, nenhum painel. Para desligar também
	no Studio, ENABLED_IN_STUDIO = false.

	Logs pelo Logger do projeto com a tag [SwordRuntime] (no Output aparece
	"[C][SwordRuntime] ..."), só em mudança de estado (nunca por quadro).
	Painel pequeno no canto (RIG / JOINT / BACKEND / STATE / COMBO / POSE).
	Controles pela barra de comando do Studio, sem publicar nada:

		workspace:SetAttribute("SwordMinimalTest", true)  -- teste mínimo:
		    -- clique = o braço direito sobe bem alto por ~0,2 s e volta; sem
		    -- postura, combo, respiração, corte nem partículas
		workspace:SetAttribute("SwordBackend", "Transform") -- ou "Offset"
		    -- força a camada que aplica a pose (padrão: automático, com
		    -- verificação no personagem)
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Utils"):WaitForChild("Logger"))

local log = Logger.new("SwordRuntime")

local SwordDebug = {}

SwordDebug.ENABLED_IN_STUDIO = true

local enabled: boolean? = nil
local panel: TextLabel? = nil
local panelText = ""

function SwordDebug.Enabled(): boolean
	if enabled == nil then
		local ok, studio = pcall(function()
			return RunService:IsStudio()
		end)
		enabled = SwordDebug.ENABLED_IN_STUDIO and ok and studio == true
	end
	return enabled :: boolean
end

-- Para os testes.
function SwordDebug.SetEnabled(value: boolean)
	enabled = value
end

function SwordDebug.Log(message: string)
	if SwordDebug.Enabled() then
		log:Info(message)
	end
end

local function attribute(name: string): any
	local ok, value = pcall(function()
		return Workspace:GetAttribute(name)
	end)
	return if ok then value else nil
end

-- Teste mínimo (só Studio): clique → braço sobe e volta; nada mais.
function SwordDebug.Minimal(): boolean
	return SwordDebug.Enabled() and attribute("SwordMinimalTest") == true
end

-- Camada forçada pela barra de comando (só Studio): "Transform" | "Offset".
function SwordDebug.ForcedBackend(): string?
	if not SwordDebug.Enabled() then
		return nil
	end
	local value = attribute("SwordBackend")
	return if value == "Transform" or value == "Offset" then value else nil
end

-- Painel no canto da tela (só Studio). Atualizar no máximo ~5x/s.
function SwordDebug.Panel(playerGui: Instance?, text: string)
	if not SwordDebug.Enabled() or not playerGui or text == panelText then
		return
	end
	panelText = text
	local label = panel
	if not label or not label.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "SwordDebug"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 1000
		local newLabel = Instance.new("TextLabel")
		newLabel.Name = "Info"
		newLabel.AnchorPoint = Vector2.new(0, 1)
		newLabel.Position = UDim2.new(0, 8, 1, -8)
		newLabel.Size = UDim2.fromOffset(340, 104)
		newLabel.BackgroundColor3 = Color3.new(0, 0, 0)
		newLabel.BackgroundTransparency = 0.35
		newLabel.TextColor3 = Color3.new(1, 1, 1)
		newLabel.Font = Enum.Font.Code
		newLabel.TextSize = 14
		newLabel.TextXAlignment = Enum.TextXAlignment.Left
		newLabel.TextYAlignment = Enum.TextYAlignment.Top
		newLabel.Parent = gui
		gui.Parent = playerGui
		label = newLabel
		panel = newLabel
	end
	(label :: TextLabel).Text = text
end

return SwordDebug
