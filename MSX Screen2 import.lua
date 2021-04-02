--[[
	####### Aseprite MSX Screen 2 importer script #######

  by Natalia Pujol under MIT license.

	Inspired by https://github.com/kettek/aseprite-scripts/blob/master/import-apng.lua
	like a source base.
 --]]



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
    "End of file",
    "Invalid MSX SC2 file...",
    "Bad dimensions",
    "Dimension overflow",
    "MSX1 Palette not found",
    "Tileset overflow",
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



--[[ Reader
The Reader is the state machine that is responsible for decoding an SC2
file into the active Aseprite sprite.
--]]
local msxHeader = "\xFE\x00\x00"
Reader = {
  filename = nil,     -- filename of the SC2 file
  file = nil,         -- file reader from io
  spr = nil,          -- Sprite object
  img = nil,          -- Image object
  sc2 = {             -- SC2 data
    maxWidth = 256,
    maxHeight = 192,
    tilePatterns = nil,
    tileMap = nil,
    sprAtribs = nil,
    tileColors = nil,
    sprPatterns = nil,
  },
}
Reader.__index = Reader

function Reader:new(o)
  local rdr = {}
  setmetatable(rdr, Reader)
  rdr.filename = o.filename
  rdr.file = io.open(o.filename, "rb")
  return rdr
end

function Reader:decode()
  -- check header
  local err = self:checkHeader()
  if err ~= nil then return err end

  -- create the new image
  self:createImage()

  -- parse the SC2
  err = self:parseVRAM()
  if err ~= nil then return err end

  -- paint tiles
  err = self:paintBitmapScreen()
  if err ~= nil then return err end

  return err
end

function Reader:checkHeader()
  local buffer = self.file:read(3)
  if buffer == nil then return Error(E.EOF) end
  if Binary.compare(buffer, msxHeader) ~= true then
    return Error(E.NOT_MSX_FILE)
  end
  self.file:read(4)     -- skip rest of the header
  return nil
end

function Reader:createImage()
  self.spr = Sprite(self.sc2.maxWidth, self.sc2.maxHeight, ColorMode.INDEXED)
  self.spr.filename = self.filename .. ".png"
  local palette = Palette{ fromResource="MSX1" }
  if palette == nil then
    self.spr:close()
    return Error(E.PALETTE_NOT_FOUND)
  end
  self.spr:setPalette(palette)
  self.filename = "image.png"
  self.img = self.spr.cels[1].image
end

function Reader:parseVRAM()
  -- Tile Patterns (1 byte = 8 horizontal pixels)
  self.sc2.tilePatterns = self.file:read(0x1800)
  if self.sc2.tilePatterns == nil then return Error(E.EOF) end
  -- Tile Map
  self.sc2.tileMap = self.file:read(0x300)
  if self.sc2.tileMap == nil then return Error(E.EOF) end
  -- Sprites Attributes
  self.sc2.sprAtribs = self.file:read(0x80)
  if self.sc2.sprAtribs == nil then return Error(E.EOF) end
  -- Unused VRAM
  self.file:read(0x480)
  -- Tile Colors (1 byte = 2 colors (2x4 bits) for each tile pattern byte)
  self.sc2.tileColors = self.file:read(0x1800)
  if self.sc2.tileColors == nil then return Error(E.EOF) end
  -- Sprites Patterns
  self.sc2.sprPatterns = self.file:read(0x800)
end

function Reader:paintBitmapScreen()
  local tile = 0
  local offset = 0
  local x = 0
  local y = 0
  local err = nil

  for t=1,0x300 do
    tile = self.sc2.tileMap:byte(t)
    offset = 0x800 * math.floor(y/64) -- banks offset
    offset = offset + tile * 8        -- adding tile offset

    err = self:paintBitmapTile(x, y, offset)
    if err ~= nil then return err end

    x = x + 8
    if x == self.sc2.maxWidth then
      x = 0
      y = y + 8
    end
  end
end

function Reader:paintBitmapTile(x, y, offset)
  if offset >= self.sc2.tileColors:len() then
    return Error(E.TILESET_OVERFLOW);
  end

  local colPixel = 0

  for yt=0,7 do
    local pattern = self.sc2.tilePatterns:byte(offset + yt + 1)
    local color = self.sc2.tileColors:byte(offset + yt + 1)
    local fgcol = (color >> 4) & 0x0f
    local bgcol = (color & 0x0f)

    for xt=0,7 do
      if (pattern & 1) == 1 then
        colPixel = fgcol
      else
        colPixel = bgcol
      end
      self.img:putPixel(x+7-xt, y+yt, colPixel)
      pattern = pattern // 2
    end
  end

  return nil
end



--! Script Body !--
if not app.isUIAvailable then
  return
end

local dlg = Dialog()
local data = dlg
                  :file{
                    id="sc2file",
                    title="Open file",
                    label="Select a MSX Screen2 file:",
                    open=true,
                    filetypes={ "SC2" } }
                  :separator()
                  :button{ id="ok", text="OK" }
                  :button{ id="cancel", text="Cancel" }
                  :show().data
if data.ok then
  if data.sc2file == "" then
    app.alert("Select a file first")
    return
  end
  -- Load our SC2 image so we can get a base idea for setup.
  -- From here we can read sprite.filename into our SC2 reader.
  local rdr = Reader:new{ filename = data.sc2file }
  local err = rdr:decode()
  if err ~= nil then
    app.alert(err:string())
  end
end

