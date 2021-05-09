


-- ########################################################

--[[ Array
    Provides a few helper function for array management.
--]]
Array = {}

function Array:fill(size, value)
  out = {}
  for i=1,size do
    out[i] = value
  end
  return out
end



-- ########################################################
function countColors(sprite)
  local palette = sprite.palettes[1]
  local numcol = #palette
  local solid = 0
  for i=0,numcol-1 do
    local col = palette:getColor(i)
    if col.alpha == 255 then solid = solid+1 end
  end
  return solid
end

-- ============================
function decodeTwocomplement6bits(num)
  local signBit = 0x20
	if num >= signBit then
		num = num - (2 * signBit)
	end
  return num
end



-- ########################################################

--[[ ColorYJK
    Provides a few function to manage YJK color space.
    http://map.grauw.nl/articles/yjk/
--]]
ColorYJK = {}

-- ============================
function ColorYJK:toRGB(y, j, k)
  local r, g, b

  r = y + j
  g = y + k
  b = math.ceil((5*y - 2*j - k) / 4.0)

  r = r * 255 // 31
  g = g * 255 // 31
  b = b * 255 // 31

  r = math.max(math.min(r, 255), 0)
  g = math.max(math.min(g, 255), 0)
  b = math.max(math.min(b, 255), 0)

  return Color(r, g, b)
end

-- ============================
function ColorYJK:toYJK(r, g, b)
  local y, j, k

  r = r * 31 / 255.0
  g = g * 31 / 255.0
  b = b * 31 / 255.0

  y = (4*b + 2*r + g) / 8.0
  j = math.ceil(r) - y
  k = math.ceil(g) - y

  return y, j, k
end



-- ########################################################

--[[ Binary
Binary provides a few helper function for decoding and comparing bytes.
--]]
Binary = {}

function Binary.toInt(str, bigendian, signed) -- use length of string to determine 8,16,32,64 bits
  if str == nil then return nil end
  local t={str:byte(1,-1)}
  if bigendian == true then
    local tt={}
    for k=1,#t do
        tt[#t-k+1]=t[k]
    end
    t=tt
  end
  local n=0
  for k=1,#t do
    n=n+t[k]*2^((k-1)*8)
  end
  if signed then
    n = (n > 2^(#t*8-1) -1) and (n - 2^(#t*8)) or n
  end
  return n
end

function Binary.int16ToBytes(num)
  if num < 0 then 
      num = num & 0xFFFF
  end

  highByte = (num & 0xFF00) >> 8
  lowByte  = num & 0xFF

  -- if bigendian == true then
  --     lowByte, highByte = highByte, lowByte
  -- end

  return string.char(lowByte, highByte)
end

function Binary.compareByte(a, b)
  if string.byte(a) == string.byte(b) then
    return true
  end
  return false
end

function Binary.compare(a, b)
  if string.len(a) ~= string.len(b) then
    return false
  end
  for i = 1, #a do
    if Binary.compareByte(a:sub(i,i), b:sub(i,i)) ~= true then
      return false
    end
  end
  return true
end



-- ########################################################

--[[ Err / Error
The Err type and helper creator Error(type, msg) provide an interface for
managing errors during the script's functioning.
--]]
local E = {
  EOF = 1,
  NOT_MSX_FILE = 2,
  BAD_DIMENSIONS = 3,
  DIMENSION_OVERFLOW = 4,
  PALETTE_NOT_FOUND = 5,
  TILESET_OVERFLOW = 6,
  strings = {
    "  End of file  ",
    "  Invalid MSX file  ",
    "  Bad dimensions  ",
    "  Dimension overflow  ",
    "  Palette not found  ",
    "  Tileset overflow  ",
  }
}
local Err = {
}
Err.__index = Err
function Err:new(t, m)
  local err = {}
  err.t = t
  err.m = m
  setmetatable(err, Err)
  return err
end
function Err:string()
  if self.m ~= nil then
    return E.strings[self.t] .. ": " .. self.m
  end
  return E.strings[self.t]
end
function Error(t, m)
  return Err:new(t, m)
end
