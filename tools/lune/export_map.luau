--[[
	export_map.luau — roda o WorldBuilder fora do Studio e exporta as peças do
	mundo inicial (posição, rotação, tamanho, cor, material, forma) e os textos
	(BillboardGui com MaxDistance, SurfaceGui) para JSON. Quem desenha é o
	tools/render_map3d.py.

		lune run tools/lune/export_map.luau [raiz] [saída]

	Saída padrão: build/map_parts.json (build/ está no .gitignore).
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local E = require("./env")(process.args[1])
local out = process.args[2] or (E.Root .. "/build/map_parts.json")
local roblox = E.roblox
local WorldBuilder = E.require(E.Server.World.WorldBuilder)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local spawns = E.Instance.new("Folder")
local model = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], roblox.Vector3.new(0, 0, 0), E.Instance.new("Folder"), spawns, true)
local parts = {}
local function shapeOf(d)
	if d:IsA("Part") then
		local s = tostring(d.Shape)
		if s:find("Cylinder") then return "Cylinder" elseif s:find("Ball") then return "Ball" end
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		if mesh then return "Egg" end
		return "Block"
	end
	if d:IsA("WedgePart") then return "Wedge" end
	if d:IsA("CornerWedgePart") then return "CornerWedge" end
	return "Block"
end
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 0.98 then
		local cf = d.CFrame
		local r = { cf.RightVector, cf.UpVector, -cf.LookVector }
		local c = d.Color
		local bill = d:FindFirstChildOfClass("BillboardGui")
		local text = nil
		local surf = d:FindFirstChildOfClass("SurfaceGui")
		if surf then
			local lbl = surf:FindFirstChildOfClass("TextLabel")
			local tc = lbl.TextColor3
			table.insert(parts, { n = d.Name .. "_text", s = "None", p = { d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z }, r = {1,0,0,0,1,0,0,0,1}, z = {0,0,0}, c = {tc.R,tc.G,tc.B}, t = 1, m = "", l = false,
				b = { lbl.Text, 0, 1000, d.Size.X / 1.0, d.Size.Y * 0.8 } })
		end
		if bill then
			local lbl = bill:FindFirstChildOfClass("TextLabel")
			text = { lbl and lbl.Text or "", bill.StudsOffset.Y, bill.MaxDistance, bill.Size.X.Scale, bill.Size.Y.Scale }
		end
		table.insert(parts, {
			n = d.Name, s = shapeOf(d),
			p = { cf.Position.X, cf.Position.Y, cf.Position.Z },
			r = { r[1].X, r[1].Y, r[1].Z, r[2].X, r[2].Y, r[2].Z, r[3].X, r[3].Y, r[3].Z },
			z = { d.Size.X, d.Size.Y, d.Size.Z },
			c = { c.R, c.G, c.B }, t = d.Transparency,
			m = tostring(d.Material):gsub("Enum.Material.", ""),
			l = d:FindFirstChildOfClass("PointLight") ~= nil,
			b = text,
		})
	elseif d:IsA("BasePart") then
		local bill = d:FindFirstChildOfClass("BillboardGui")
		if bill then
			local lbl = bill:FindFirstChildOfClass("TextLabel")
			local c = lbl and lbl.TextColor3 or roblox.Color3.new(1,1,1)
			table.insert(parts, { n = d.Name, s = "None", p = { d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z }, r = {1,0,0,0,1,0,0,0,1}, z = {0,0,0}, c = {c.R,c.G,c.B}, t = 1, m = "", l = false,
				b = { lbl and lbl.Text or "", bill.StudsOffset.Y, bill.MaxDistance, bill.Size.X.Scale, bill.Size.Y.Scale } })
		end
	end
end
local spawn = spawns:GetChildren()[1]
local meta = { spawn = { spawn.CFrame.Position.X, spawn.CFrame.Position.Y, spawn.CFrame.Position.Z, spawn.CFrame.LookVector.X, spawn.CFrame.LookVector.Y, spawn.CFrame.LookVector.Z } }
local folder = string.match(out, "^(.*)/[^/]+$")
if folder and not fs.isDir(folder) then
	fs.writeDir(folder)
end
fs.writeFile(out, serde.encode("json", { parts = parts, meta = meta }))
print(string.format("%d peças/textos exportados para %s", #parts, out))
