--!strict
--[[
	TextCase
	MAIÚSCULAS com os acentos do português (string.upper só cuida de A–Z):
	"Rocha Vulcânica" → "ROCHA VULCÂNICA".
]]

local ACCENTS = {
	["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê",
	["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç",
}

local TextCase = {}

function TextCase.Upper(text: string): string
	local upper = string.upper(text)
	for lower, capital in ACCENTS do
		upper = string.gsub(upper, lower, capital)
	end
	return upper
end

return TextCase
