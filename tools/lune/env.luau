--[[
	env.luau — ambiente mínimo "tipo Roblox" em cima do Lune.

	Monta src/shared, src/server e src/client como instâncias (mesmas regras
	do Rojo: *.server.luau = Script, *.client.luau = LocalScript, pasta com
	init.luau = ModuleScript) e oferece um `require` que carrega o Source de
	cada ModuleScript com `script`, `game`, `workspace`, `task`, `Random` e os
	tipos do Roblox (Vector3, CFrame, Instance...).

	Serviços que não existem fora do Roblox (RunService, Players, HttpService,
	TweenService...) são stubs. NÃO é o Roblox: não tem física, render,
	replicação nem DataStore — serve para lógica pura, para o WorldBuilder e
	para montar a UI e medir posições.

	Uso (dentro de outro script Lune):
		local E = require("./env")(raizDoRepo)
		local WorldBuilder = E.require(E.Server.World.WorldBuilder)
]]
local process = require("@lune/process")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local registered = false

return function(ROOT_ARG)
local M = {}

local ROOT = ROOT_ARG or process.cwd
ROOT = string.gsub(ROOT, "/+$", "")
if not fs.isDir(ROOT .. "/src/shared") then
	error("raiz do repositório não encontrada em " .. ROOT .. " (rode a partir da raiz ou passe o caminho)")
end

-- Métodos que o Lune não tem; registrados uma vez por processo.
if not registered then
	registered = true
	roblox.implementMethod("Instance", "WaitForChild", function(self, name)
		local c = self:FindFirstChild(name)
		if not c then error("WaitForChild timeout: " .. name .. " in " .. self:GetFullName()) end
		return c
	end)
	roblox.implementMethod("Model", "PivotTo", function() end)
	roblox.implementMethod("Model", "GetPivot", function() return roblox.CFrame.new() end)
end

-- Random determinístico (LCG). Não reproduz a sequência do Roblox, só a forma.
local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ s = (seed or 1) % 2147483647 }, Random)
end
function Random:_next()
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	a = a or 0; b = b or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local game = Instance.new("DataModel")
M.realGame = game
local IS_STUDIO = false
-- RunService:IsStudio() devolve isto (padrão: false = servidor publicado).
M.SetStudio = function(v) IS_STUDIO = v end

local stubs = {
	RunService = { IsStudio = function() return IS_STUDIO end, IsServer = function() return true end, IsClient = function() return false end,
		Heartbeat = { Connect = function() return { Disconnect = function() end } end } },
	Players = { LocalPlayer = nil, GetPlayers = function() return {} end,
		PlayerAdded = { Connect = function() end }, PlayerRemoving = { Connect = function() end } },
	LocalizationService = { RobloxLocaleId = "pt-br", SystemLocaleId = "pt-br" },
	HttpService = { GenerateGUID = (function() local n = 0 return function() n += 1 return "guid-" .. n end end)(), JSONEncode = function(_, t) return serde.encode("json", t) end, JSONDecode = function(_, s) return serde.decode("json", s) end },
}
local gameProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				if stubs[name] then return stubs[name] end
				return game:GetService(name)
			end
		end
		return game[k]
	end,
})

local function mount(path, parent, name)
	local isDir = fs.isDir(path)
	local inst
	if isDir then
		if fs.isFile(path .. "/init.luau") then
			inst = Instance.new("ModuleScript")
			inst.Source = fs.readFile(path .. "/init.luau")
		else
			inst = Instance.new("Folder")
		end
		inst.Name = name
		for _, entry in fs.readDir(path) do
			if entry ~= "init.luau" then
				local child = path .. "/" .. entry
				local childName = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
				mount(child, inst, childName)
			end
		end
	else
		if path:match("%.server%.luau$") then inst = Instance.new("Script")
		elseif path:match("%.client%.luau$") then inst = Instance.new("LocalScript")
		elseif path:match("%.luau$") then inst = Instance.new("ModuleScript")
		else return end
		inst.Name = name
		inst.Source = fs.readFile(path)
	end
	inst.Parent = parent
	return inst
end

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
mount(ROOT .. "/src/shared", RS, "Shared")
mount(ROOT .. "/src/server", SSS, "Server")
local SPS = game:GetService("StarterPlayer")
mount(ROOT .. "/src/client", SPS, "Client")
M.Client = SPS.Client
M.Shared = RS.Shared
M.Server = SSS.Server
M.Workspace = game:GetService("Workspace")

--[[
	O CFrame.lookAt do Lune 0.8.9 espelha o eixo Z (bug do Lune, não do
	projeto). Os módulos carregados por este ambiente recebem uma versão
	correta, montada com fromMatrix.
]]
local RealCFrame = roblox.CFrame
M.CFrame = setmetatable({
	lookAt = function(at, target, up)
		up = up or roblox.Vector3.new(0, 1, 0)
		local look = (target - at).Unit
		local right = look:Cross(up)
		if right.Magnitude < 1e-6 then right = roblox.Vector3.new(1, 0, 0) end
		right = right.Unit
		local realUp = right:Cross(look)
		return RealCFrame.fromMatrix(at, right, realUp)
	end,
}, { __index = RealCFrame })
local cache = {}
-- Ajustes SÓ no texto carregado aqui (o arquivo do repo não muda):
M.patches = {} -- [fullName] = { {trecho, substituto, "all"?}, ... } (busca literal)
M.stubModules = {} -- [fullName] = valor devolvido no lugar do módulo
M.extraGlobals = {} -- globais extras para os módulos (ex.: TweenInfo)
local requireFn
local function makeEnv(scriptInst)
	local env = {
		script = scriptInst, game = gameProxy, workspace = M.Workspace,
		require = function(x) return requireFn(x) end,
		task = task, Random = Random, typeof = roblox and typeof,
		tick = os.clock, warn = function(...) end, print = function(...) end,
	}
	for k, v in roblox do env[k] = v end
	env.CFrame = M.CFrame
	for k, v in M.extraGlobals do env[k] = v end
	return setmetatable(env, { __index = _G })
end
requireFn = function(mod)
	if type(mod) == "string" then return require(mod) end
	local full = mod:GetFullName()
	if cache[full] ~= nil then return cache[full] end
	if M.stubModules[full] ~= nil then cache[full] = M.stubModules[full] return cache[full] end
	local src = mod.Source
	for _, pair in M.patches[full] or {} do
		if pair[3] == "all" then
			-- Troca TODAS as ocorrências (busca literal).
			local escaped = string.gsub(pair[1], "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
			local replacement = string.gsub(pair[2], "%%", "%%%%")
			local count
			src, count = string.gsub(src, escaped, replacement)
			if count == 0 then error("patch not found in " .. full .. ": " .. pair[1]) end
		else
			local a, b = string.find(src, pair[1], 1, true)
			if not a then error("patch not found in " .. full .. ": " .. pair[1]) end
			src = string.sub(src, 1, a - 1) .. pair[2] .. string.sub(src, b + 1)
		end
	end
	local fn = luau.load(luau.compile(src), { debugName = mod:GetFullName(), environment = makeEnv(mod) })
	local result = fn()
	cache[full] = result
	return result
end
M.require = requireFn
M.Root = ROOT
M.stubs = stubs
M.Instance = Instance
M.roblox = roblox
return M
end
