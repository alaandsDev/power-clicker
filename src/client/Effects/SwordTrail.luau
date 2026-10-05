--!strict
--[[
	SwordTrail
	A espada ATACANDO: durante o golpe acende o rastro da lâmina (na cor da
	skin, cosmético), o fio de energia das skins neon e a luz da lâmina; ao
	parar, tudo volta ao estado contido que o SwordService montou
	(IdleBrightness / IdleTransparency). A energia do ataque continua sendo do
	Corte (CutFx); isto é só a arma riscando o ar.

	Local: as duas Attachments e o Trail são criados neste cliente na lâmina
	que o servidor montou (não replicam). Se a skin já tem rastro próprio
	(SwordService cria um para skins com TrailSeconds > 0), ele é usado e nada
	novo é criado. Uma lâmina nova (troca de skin, respawn) ganha o próprio
	rastro na próxima vez; o antigo some junto com a lâmina destruída.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))

local LIFETIME = 0.12
local NAME = "SwingTrail"

local SwordTrail = {}

local function bladeOf(character: Model): BasePart?
	local tool = character:FindFirstChild("CutBlade")
	local blade = if tool then tool:FindFirstChild("Blade") else nil
	return if blade and blade:IsA("BasePart") then blade else nil
end

-- O rastro da lâmina deste personagem (cria o local se precisar).
function SwordTrail.Ensure(character: Model, swordId: any): Trail?
	local blade = bladeOf(character)
	if not blade then
		return nil
	end
	local own = blade:FindFirstChild(NAME)
	if own and own:IsA("Trail") then
		return own
	end
	local existing = blade:FindFirstChildOfClass("Trail")
	if existing then
		return nil -- a skin já risca o ar sozinha
	end
	local sword = if type(swordId) == "string" then SwordConfig.Swords[swordId] else nil
	sword = sword or SwordConfig.Swords[SwordConfig.DefaultSword]
	local half = blade.Size.Y / 2
	local tip = Instance.new("Attachment")
	tip.Name = NAME .. "Tip"
	tip.Position = Vector3.new(0, half, 0)
	tip.Parent = blade
	local base = Instance.new("Attachment")
	base.Name = NAME .. "Base"
	base.Position = Vector3.new(0, -half * 0.3, 0)
	base.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = NAME
	trail.Attachment0 = tip
	trail.Attachment1 = base
	trail.Color = ColorSequence.new((sword :: any).ArcColor)
	trail.Lifetime = LIFETIME
	trail.MinLength = 0.1
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.Enabled = false
	trail.Parent = blade
	return trail
end

function SwordTrail.Set(character: Model?, swordId: any, enabled: boolean)
	if not character then
		return
	end
	local blade = bladeOf(character)
	if not blade then
		return
	end
	if enabled then
		SwordTrail.Ensure(character, swordId)
	end
	-- Rastro (o da skin ou o local), luz e fio de energia.
	for _, child in blade:GetChildren() do
		if child:IsA("Trail") then
			child.Enabled = enabled
		elseif child:IsA("PointLight") then
			local idle = child:GetAttribute("IdleBrightness")
			local swing = child:GetAttribute("SwingBrightness")
			if type(idle) == "number" and type(swing) == "number" then
				child.Brightness = if enabled then swing else idle
			end
		end
	end
	local tool = blade.Parent
	if tool then
		for _, part in tool:GetChildren() do
			local idle = part:GetAttribute("IdleTransparency")
			if part:IsA("BasePart") and type(idle) == "number" then
				part.Transparency = if enabled then 0 else idle
			end
		end
	end
end

return SwordTrail
