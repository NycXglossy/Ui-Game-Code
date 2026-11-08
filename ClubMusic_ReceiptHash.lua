--!strict
-- ClubMusic_ReceiptHash
-- Place as a ModuleScript named ClubMusic_ReceiptHash in ServerStorage.
-- SHA-256-derived 160-bit key suffix for durable per-purchase journal keys.
-- The full PurchaseId is always stored and compared in the journal value as a
-- second collision check; never use this digest as an authentication token.

local bit = bit32
local MOD = 4294967296

local K = {
	0x428A2F98,0x71374491,0xB5C0FBCF,0xE9B5DBA5,0x3956C25B,0x59F111F1,0x923F82A4,0xAB1C5ED5,
	0xD807AA98,0x12835B01,0x243185BE,0x550C7DC3,0x72BE5D74,0x80DEB1FE,0x9BDC06A7,0xC19BF174,
	0xE49B69C1,0xEFBE4786,0x0FC19DC6,0x240CA1CC,0x2DE92C6F,0x4A7484AA,0x5CB0A9DC,0x76F988DA,
	0x983E5152,0xA831C66D,0xB00327C8,0xBF597FC7,0xC6E00BF3,0xD5A79147,0x06CA6351,0x14292967,
	0x27B70A85,0x2E1B2138,0x4D2C6DFC,0x53380D13,0x650A7354,0x766A0ABB,0x81C2C92E,0x92722C85,
	0xA2BFE8A1,0xA81A664B,0xC24B8B70,0xC76C51A3,0xD192E819,0xD6990624,0xF40E3585,0x106AA070,
	0x19A4C116,0x1E376C08,0x2748774C,0x34B0BCB5,0x391C0CB3,0x4ED8AA4A,0x5B9CCA4F,0x682E6FF3,
	0x748F82EE,0x78A5636F,0x84C87814,0x8CC70208,0x90BEFFFA,0xA4506CEB,0xBEF9A3F7,0xC67178F2,
}

local INITIAL = {
	0x6A09E667,0xBB67AE85,0x3C6EF372,0xA54FF53A,
	0x510E527F,0x9B05688C,0x1F83D9AB,0x5BE0CD19,
}

local function add32(...: number): number
	local total = 0
	for _, value in ipairs({...}) do total += value end
	return total % MOD
end

local function digest(input: string): string
	local bytes = {string.byte(input, 1, #input)}
	local bitLength = #bytes * 8
	table.insert(bytes, 0x80)
	while (#bytes % 64) ~= 56 do table.insert(bytes, 0) end
	local high = math.floor(bitLength / MOD)
	local low = bitLength % MOD
	for shift = 24, 0, -8 do table.insert(bytes, bit.band(bit.rshift(high, shift), 0xFF)) end
	for shift = 24, 0, -8 do table.insert(bytes, bit.band(bit.rshift(low, shift), 0xFF)) end

	local H = table.clone(INITIAL)
	local W = table.create(64, 0)
	for offset = 1, #bytes, 64 do
		for i = 0, 15 do
			local j = offset + i * 4
			W[i + 1] = bytes[j] * 0x1000000 + bytes[j + 1] * 0x10000 + bytes[j + 2] * 0x100 + bytes[j + 3]
		end
		for i = 17, 64 do
			local x = W[i - 15]
			local y = W[i - 2]
			local s0 = bit.bxor(bit.rrotate(x, 7), bit.rrotate(x, 18), bit.rshift(x, 3))
			local s1 = bit.bxor(bit.rrotate(y, 17), bit.rrotate(y, 19), bit.rshift(y, 10))
			W[i] = add32(W[i - 16], s0, W[i - 7], s1)
		end

		local a,b,c,d,e,f,g,h = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
		for i = 1, 64 do
			local sum1 = bit.bxor(bit.rrotate(e, 6), bit.rrotate(e, 11), bit.rrotate(e, 25))
			local choose = bit.bxor(bit.band(e, f), bit.band(bit.bnot(e), g))
			local t1 = add32(h, sum1, choose, K[i], W[i])
			local sum0 = bit.bxor(bit.rrotate(a, 2), bit.rrotate(a, 13), bit.rrotate(a, 22))
			local majority = bit.bxor(bit.band(a, b), bit.band(a, c), bit.band(b, c))
			local t2 = add32(sum0, majority)
			h,g,f,e,d,c,b,a = g,f,e,add32(d,t1),c,b,a,add32(t1,t2)
		end
		H[1]=add32(H[1],a); H[2]=add32(H[2],b); H[3]=add32(H[3],c); H[4]=add32(H[4],d)
		H[5]=add32(H[5],e); H[6]=add32(H[6],f); H[7]=add32(H[7],g); H[8]=add32(H[8],h)
	end

	local out = ""
	for i = 1, 8 do out ..= string.format("%08x", H[i]) end
	return out
end

local ReceiptHash = {}

function ReceiptHash.KeySuffix(purchaseId: string): string
	assert(typeof(purchaseId) == "string" and #purchaseId > 0 and #purchaseId <= 128, "invalid PurchaseId")
	return string.sub(digest(purchaseId), 1, 40)
end

return ReceiptHash
