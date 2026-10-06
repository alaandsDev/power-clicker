--[[
	swing_poses.luau — diagnóstico do golpe da espada fora do Studio.
	Boneco R15 com proporções reais + espada, SwordSwing DE VERDADE (postura,
	A, B, C), juntas resolvidas como a física faria. Mede as PARTES (tronco,
	quadril, braço esquerdo, cabeça, espada) e o que a câmera de 3ª pessoa
	(atrás) enxerga na tela; salva as poses (STANCE, PREP/HIT/REC de A/B/C).

		lune run tools/lune/swing_poses.luau <raiz do repo> <saida.json>
		python tools/render_swing_poses.py <pasta com before.json e after.json>

	Aproximado: sem Animator (locomoção) e sem a pegada exata da Tool.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local root = process.args[1]
local out = process.args[2]
local E = require(root .. "/tools/lune/env")(root)
local V3, CF, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
local SwordSwing = E.require(E.Client.Effects.SwordSwing)

local function part(model, name, size, pos, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CF.new(pos)
	p.Color = color
	p.Parent = model
	return p
end
local function motor(name, p0, p1, jointWorld)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = p0, p1
	m.C0 = p0.CFrame:Inverse() * CF.new(jointWorld)
	m.C1 = p1.CFrame:Inverse() * CF.new(jointWorld)
	m.Transform = CF.identity
	m.Parent = p1
	return m
end
local skin, shirt, pants = roblox.Color3.fromRGB(240, 200, 160), roblox.Color3.fromRGB(70, 110, 200), roblox.Color3.fromRGB(50, 50, 70)
local char = Instance.new("Model")
char.Name = "Dummy"
local hrp = part(char, "HumanoidRootPart", V3.new(2, 2, 1), V3.new(0, 3, 0), skin)
local lt = part(char, "LowerTorso", V3.new(2, 0.4, 1), V3.new(0, 2.4, 0), pants)
local ut = part(char, "UpperTorso", V3.new(2, 1.6, 1), V3.new(0, 3.4, 0), shirt)
local head = part(char, "Head", V3.new(1.2, 1.2, 1.2), V3.new(0, 4.8, 0), skin)
local rua = part(char, "RightUpperArm", V3.new(1, 1.2, 1), V3.new(1.5, 3.6, 0), shirt)
local rla = part(char, "RightLowerArm", V3.new(1, 1.2, 1), V3.new(1.5, 2.4, 0), skin)
local rh = part(char, "RightHand", V3.new(1, 0.3, 1), V3.new(1.5, 1.65, 0), skin)
local lua = part(char, "LeftUpperArm", V3.new(1, 1.2, 1), V3.new(-1.5, 3.6, 0), shirt)
local lla = part(char, "LeftLowerArm", V3.new(1, 1.2, 1), V3.new(-1.5, 2.4, 0), skin)
local lh = part(char, "LeftHand", V3.new(1, 0.3, 1), V3.new(-1.5, 1.65, 0), skin)
local rl = part(char, "RightLeg", V3.new(1, 2.2, 1), V3.new(0.5, 1.1, 0), pants)
local ll = part(char, "LeftLeg", V3.new(1, 2.2, 1), V3.new(-0.5, 1.1, 0), pants)
local motors = {
	motor("Root", hrp, lt, V3.new(0, 2.2, 0)),
	motor("Waist", lt, ut, V3.new(0, 2.6, 0)),
	motor("Neck", ut, head, V3.new(0, 4.2, 0)),
	motor("RightShoulder", ut, rua, V3.new(1, 4.1, 0)),
	motor("RightElbow", rua, rla, V3.new(1.5, 3.0, 0)),
	motor("RightWrist", rla, rh, V3.new(1.5, 1.8, 0)),
	motor("LeftShoulder", ut, lua, V3.new(-1, 4.1, 0)),
	motor("LeftElbow", lua, lla, V3.new(-1.5, 3.0, 0)),
	motor("LeftWrist", lla, lh, V3.new(-1.5, 1.8, 0)),
	motor("RightHip", lt, rl, V3.new(0.5, 2.2, 0)),
	motor("LeftHip", lt, ll, V3.new(-0.5, 2.2, 0)),
}
-- Espada na mão (como a Tool: pegada girada, lâmina ao longo da pegada).
local handle = part(char, "Handle", V3.new(0.4, 1.2, 0.4), V3.new(1.5, 1.2, 0), roblox.Color3.fromRGB(90, 60, 40))
local blade = part(char, "Blade", V3.new(0.25, 4.2, 0.9), V3.new(1.5, 1.2, 0), roblox.Color3.fromRGB(220, 230, 255))
local gripC0 = CF.new(0, -0.15, 0) * CF.Angles(math.rad(-90), 0, 0)
local function solve()
	for _, m in motors do
		m.Part1.CFrame = m.Part0.CFrame * m.C0 * m.Transform * m.C1:Inverse()
	end
	handle.CFrame = rh.CFrame * gripC0
	blade.CFrame = handle.CFrame * CF.new(0, 2.6, 0)
end
local humanoid = Instance.new("Humanoid")
humanoid.Parent = char
local tool = Instance.new("Tool")
tool.Name = "CutBlade"
tool.Parent = char
char.Parent = E.Workspace
solve()

local rig = assert(SwordSwing.NewRig(char), "rig")
local t, dt = 0, 1 / 60
local function frame()
	t += dt
	SwordSwing.Settle(rig, t, dt, true, false, 4.2)
	SwordSwing.Step(rig, t)
	solve()
end
for _ = 1, 90 do
	frame()
end
local function rel(a, b)
	return a.CFrame:ToObjectSpace(b.CFrame)
end
local function ang(a, b)
	return SwordSwing.Angle(a, b)
end
-- Câmera de 3ª pessoa padrão: atrás e acima, olhando para frente (-Z).
local camPos = V3.new(0, 7, 12)
local camLook = (V3.new(0, 3.5, -8) - camPos).Unit
local camRight = camLook:Cross(V3.new(0, 1, 0)).Unit
local camUp = camRight:Cross(camLook)
local function screen(p)
	local d = p - camPos
	local z = d:Dot(camLook)
	return V3.new(d:Dot(camRight) / z, d:Dot(camUp) / z, 0)
end
-- Pontos que o olho lê no corpo (sem espada): ombros, cabeça, mão esquerda, quadril.
local function bodyPoints()
	return {
		ShoulderR = (ut.CFrame * CF.new(1, 0.8, 0)).Position,
		ShoulderL = (ut.CFrame * CF.new(-1, 0.8, 0)).Position,
		Head = head.CFrame.Position,
		LeftHand = lh.CFrame.Position,
		HipR = (lt.CFrame * CF.new(1, 0, 0)).Position,
		HipL = (lt.CFrame * CF.new(-1, 0, 0)).Position,
	}
end
local restPoints = bodyPoints()
local restTorso, restHip, restLeft, restHead, restNeck, restHand =
	rel(hrp, ut), rel(hrp, lt), rel(ut, lua), rel(hrp, head), rel(ut, head), rel(hrp, blade)
local function snapshot()
	local list = {}
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local cf = p.CFrame
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			table.insert(list, { n = p.Name, p = { cf.Position.X, cf.Position.Y, cf.Position.Z }, r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, z = { p.Size.X, p.Size.Y, p.Size.Z }, c = { p.Color.R, p.Color.G, p.Color.B }, m = "SmoothPlastic", s = "Block", t = 0, l = false })
		end
	end
	return list
end
local result = { poses = { STANCE = snapshot() }, stats = {} }
local winEnd = SwordSwing.WINDUP_END or 0.25
local strikeEnd = SwordSwing.STRIKE_END or 0.55
for _, variant in { "A", "B", "C" } do
	for _ = 1, 30 do
		frame()
	end
	local start = t
	if SwordSwing.Request then
		SwordSwing.Request(rig, t)
	else
		SwordSwing.Start(rig, t)
	end
	local peak = { Torso = 0, TorsoUL = 0, Hip = 0, Left = 0, Head = 0, Neck = 0, Hand = 0, Screen = 0, ScreenHead = 0, ScreenShoulders = 0, ScreenLeftHand = 0, TorsoPeakAt = 0, HandPeakAt = 0 }
	local snaps = {}
	while t - start < rig.Duration do
		frame()
		local u = (t - start) / rig.Duration
		local torso = ang(rel(hrp, ut), restTorso)
		if torso > peak.Torso then
			peak.Torso, peak.TorsoPeakAt = torso, u
		end
		peak.TorsoUL = math.max(peak.TorsoUL, ang(rel(lt, ut), restTorso.Rotation:Inverse() * restHip.Rotation * CF.identity) or 0)
		peak.Hip = math.max(peak.Hip, ang(rel(hrp, lt), restHip))
		peak.Left = math.max(peak.Left, ang(rel(ut, lua), restLeft))
		peak.Head = math.max(peak.Head, ang(rel(hrp, head), restHead))
		peak.Neck = math.max(peak.Neck, ang(rel(ut, head), restNeck))
		local hand = ang(rel(hrp, blade), restHand)
		if hand > peak.Hand then
			peak.Hand, peak.HandPeakAt = hand, u
		end
		local pts = bodyPoints()
		local function d(key)
			return (screen(pts[key]) - screen(restPoints[key])).Magnitude * 1000
		end
		peak.ScreenHead = math.max(peak.ScreenHead, d("Head"))
		peak.ScreenShoulders = math.max(peak.ScreenShoulders, math.max(d("ShoulderR"), d("ShoulderL")))
		peak.ScreenLeftHand = math.max(peak.ScreenLeftHand, d("LeftHand"))
		peak.Screen = math.max(peak.Screen, d("HipR"), d("HipL"))
		if not snaps.prep and u >= winEnd then
			snaps.prep = snapshot()
		end
		if not snaps.hit and u >= (winEnd + strikeEnd) / 2 then
			snaps.hit = snapshot()
		end
		if not snaps.rec and u >= 0.8 then
			snaps.rec = snapshot()
		end
	end
	result.stats[variant] = peak
	result.poses[variant .. " PREP"] = snaps.prep
	result.poses[variant .. " HIT"] = snaps.hit
	result.poses[variant .. " REC"] = snaps.rec
end
result.joints = {}
for key in rig.Joints do
	table.insert(result.joints, key)
end
fs.writeFile(out, serde.encode("json", result))
for _, v in { "A", "B", "C" } do
	local s = result.stats[v]
	print(string.format("%s: tronco %.0f° (pico em %.0f%%), quadril %.0f°, braço esq. %.0f°, cabeça %.0f° (pescoço %.0f°), espada %.0f° (pico %.0f%%) | TELA (milésimos): ombros %.0f, cabeça %.0f, mão esq. %.0f, quadril %.0f",
		v, s.Torso, s.TorsoPeakAt * 100, s.Hip, s.Left, s.Head, s.Neck, s.Hand, s.HandPeakAt * 100, s.ScreenShoulders, s.ScreenHead, s.ScreenLeftHand, s.Screen))
end
print("juntas: " .. table.concat(result.joints, ", "))
process.exit(0)
