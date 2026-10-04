--!strict
--[[
	CameraFx
	Tremor de câmera curto e controlado para o combate. Nada de enjoo: são
	impulsos de poucos décimos de grau que somem em 0,1–0,35 s; um novo impulso
	só substitui o atual se for mais forte.

		Hit     quase imperceptível
		Strong  um pouco maior (hit que tirou uma fatia grande da fileira)
		Break   curto e satisfatório (a fileira caiu)
		Final   a barreira abriu
		Epic    a barreira do Colosso abriu

	Uma única função por quadro, registrada logo depois da câmera do Roblox
	(BindToRenderStep), que não faz nada sem impulso ativo. Quem chama decide
	se pode tremer ("Efeitos reduzidos" desliga — CombatFxController).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Level = "Hit" | "Strong" | "Break" | "Final" | "Epic"

-- (graus, segundos)
local LEVELS: { [Level]: { number } } = {
	Hit = { 0.12, 0.08 },
	Strong = { 0.35, 0.12 },
	Break = { 0.8, 0.18 },
	Final = { 1.2, 0.25 },
	Epic = { 2, 0.35 },
}

local CameraFx = {}

local amplitude = 0
local duration = 0
local started = 0
local bound = false

function CameraFx.Levels(): { [Level]: { number } }
	return LEVELS
end

-- Ângulo (graus) do tremor `t` segundos depois do impulso (0 depois do fim).
function CameraFx.Offset(degrees: number, seconds: number, t: number): number
	if t < 0 or t >= seconds or seconds <= 0 then
		return 0
	end
	local decay = (1 - t / seconds) ^ 2
	return degrees * decay * math.sin(t * 90)
end

function CameraFx.Shake(level: Level)
	local spec = LEVELS[level]
	local now = os.clock()
	local current = if now - started < duration then amplitude * (1 - (now - started) / duration) ^ 2 else 0
	if spec[1] < current then
		return
	end
	amplitude, duration, started = spec[1], spec[2], now
end

function CameraFx.Active(): boolean
	return os.clock() - started < duration
end

function CameraFx.Start()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep("PowerClickerCameraFx", Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		if t >= duration then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local pitch = CameraFx.Offset(amplitude, duration, t)
		local yaw = CameraFx.Offset(amplitude * 0.6, duration, t + 0.013)
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
	end)
end

return CameraFx
