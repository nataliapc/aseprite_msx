--[[
	####### Aseprite MSX Screen 2 importer script #######
  Copyright by Natalia Pujol (2021)
  This file is released under the terms of the MIT license.

  MSX SCREEN 2 Mode: - 256x192px with 16 colors (fixed palette)
                     - Color clash: 2 colors each 8x1 pixels
                     - 64 sprites of 16x16px 1 color (or 256 of 8x8px 1 color)
                     - 32 planes for visible sprites at same time

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
    "  End of file  ",
    "  Invalid MSX SC2 file  ",
    "  Bad dimensions  ",
    "  Dimension overflow  ",
    "  MSX1 Palette not found  ",
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
  imgSpr = nil,       -- Image layer for Sprites
  sprRender = false,  -- Flag to know if Sprite Layer must be created
  sc2 = {             -- SC2 data
    maxWidth = 256,
    maxHeight = 192,
    sprSize = 32,       -- sprites size in bytes
    tilePatterns = nil,
    tileMap = nil,
    sprAttribs = nil,
    tileColors = nil,
    sprPatterns = nil,
  },
}
Reader.__index = Reader

-- ############################
function Reader:new(o)
  local rdr = {}
  setmetatable(rdr, Reader)
  rdr.filename = o.filename
  rdr.file = io.open(o.filename, "rb")
  rdr.sprRender = o.spr_render
  if o.spr16 then
    rdr.sc2.sprSize = 32
  else
    rdr.sc2.sprSize = 8
  end
  return rdr
end

-- ############################
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

  -- paint sprites
  if self.sc2.sprPatterns ~= nil then
    err = self:paintSpriteLayers()
    if err ~= nil then return err end
  end

  return err
end

-- ############################
function Reader:checkHeader()
  local buffer = self.file:read(3)
  if buffer == nil then return Error(E.EOF) end
  if Binary.compare(buffer, msxHeader) ~= true then
    return Error(E.NOT_MSX_FILE)
  end
  self.file:read(4)     -- skip rest of the header
  return nil
end

-- ############################
function Reader:createImage()
  self.spr = Sprite(self.sc2.maxWidth, self.sc2.maxHeight, ColorMode.INDEXED)
  self.spr.filename = self.filename .. ".png"

  -- MSX Palette
  local palette = Palette{ fromResource="MSX1" }
  if palette == nil then
    self.spr:close()
    return Error(E.PALETTE_NOT_FOUND)
  end
  self.spr:setPalette(palette)

  -- Background Layer
  app.useTool{
    tool='paint_bucket',
    color=1,
    points={ Point(0, 0) }
  }
  self.spr.layers[1].name = "Layer Bgrnd"

  -- Tiles Layer
  local layer = self.spr:newLayer()
  layer.name = "Layer Tiles"
  local cel = self.spr:newCel(layer, self.spr.frames[1])
  self.img = cel.image

  -- Sprite Layer
  if self.sprRender then
    layer = self.spr:newLayer()
    layer.name = "Layer Sprites"
    cel = self.spr:newCel(layer, self.spr.frames[1])
    self.imgSpr = cel.image
  end
end

-- ############################
function Reader:parseVRAM()
  -- Tile Patterns (1 byte = 8 horizontal pixels)
  self.sc2.tilePatterns = self.file:read(0x1800)
  if self.sc2.tilePatterns == nil then return Error(E.EOF) end
  -- Tile Map
  self.sc2.tileMap = self.file:read(0x300)
  if self.sc2.tileMap == nil then return Error(E.EOF) end
  -- Sprites Attributes
  self.sc2.sprAttribs = self.file:read(0x80)
  if self.sc2.sprAttribs == nil then return Error(E.EOF) end
  -- Unused VRAM
  self.file:read(0x480)
  -- Tile Colors (1 byte = 2 colors (2x4 bits) for each tile pattern byte)
  self.sc2.tileColors = self.file:read(0x1800)
  if self.sc2.tileColors == nil then return Error(E.EOF) end
  -- Sprites Patterns
  if self.sprRender then
    self.sc2.sprPatterns = self.file:read(0x800)
  end
end

-- ############################
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

-- ############################
function Reader:paintBitmapTile(x, y, offset)
  if offset >= self.sc2.tileColors:len() then
    return Error(E.TILESET_OVERFLOW);
  end

  for yt=0,7 do
    local pattern = self.sc2.tilePatterns:byte(offset + yt + 1)
    local color = self.sc2.tileColors:byte(offset + yt + 1)
    local fgcol = (color >> 4) & 0x0f
    local bgcol = (color & 0x0f)

    self:paintByte(self.img, x, y+yt, pattern, fgcol, bgcol)
  end

  return nil
end

-- ############################
function Reader:paintSpriteLayers()
  local attr = ""
  local sprData = ""
  for l=31,0,-1 do
    attr = self:getSpriteLayerAttribs(l)
    sprData = self:getSpritePattern(attr.patternNum)
    if attr.color & 0x80 == 0x80 then
      attr.x = attr.x - 32
    end
    if attr.y > self.sc2.maxHeight then
      attr.y = attr.y - 256
    end
    attr.y = attr.y + 1
    attr.color = attr.color & 0x7f
    self:paintSprite(attr.x, attr.y, attr.color, sprData)
  end
end

-- ############################
function Reader:paintSprite(x, y, color, data)
  local pos = 1
  for xp=x,x+8,8 do
    for yp=y,y+15 do
      if yp==y+8 and self.sc2.sprSize==8 then return end
      self:paintByte(self.imgSpr, xp, yp, data:byte(pos), color, 0)
      pos = pos + 1
    end
  end
end

-- ############################
function Reader:getSpritePattern(num)
  local pos = num * 8 + 1
  return self.sc2.sprPatterns:sub(pos, pos + self.sc2.sprSize - 1)
end

-- ############################
function Reader:getSpriteLayerAttribs(layer)
  layer = layer * 4 + 1
  local bin = self.sc2.sprAttribs:sub(layer, layer+3)
  return { y=bin:byte(1), x=bin:byte(2), patternNum=bin:byte(3), color=bin:byte(4) }
end

-- ############################
function Reader:paintByte(img, x, y, pattern, fgcol, bgcol)
  local colPixel = 0
  if pattern == nil then return end

  for xp=x+7,x,-1 do
    if (pattern & 1) == 1 then
      colPixel = fgcol
    else
      colPixel = bgcol
    end
    if colPixel > 0  and xp >= 0 and y >= 0 and xp < self.sc2.maxWidth and y < self.sc2.maxHeight then
      img:putPixel(xp, y, colPixel)
    end
    pattern = pattern // 2
  end
end


--! Script Body !--
if not app.isUIAvailable then
  return
end

local dlg = nil
local data = nil
local cancel = false
repeat
  dlg = Dialog("Import MSX image file")
  data = dlg
            :file{
              id="filename",
              label="MSX image file:",
              open=true,
              filetypes={ "SC2" } }
            :separator()
            :check{ id="spr_render",
              label="Render sprites",
              selected=true,
              onclick = function()
                dlg:modify{ id="spr8", enabled=dlg.data.spr_render }
                dlg:modify{ id="spr16", enabled=dlg.data.spr_render }
              end }
            :radio{ id="spr8",
              label="Sprite size",
              text="8x8 pixels",
              selected=false }
            :radio{ id="spr16",
              text="16x16 pixels",
              selected=true }
            :separator()
            :button{ id="ok", text="Ok" }
            :button{ id="cancel", text="Cancel" }
            :show().data

  if data.ok and data.filename == "" then 
    app.alert("  Select a file first  ")
  end
until data.filename ~= "" or data.cancel


if data.ok then
  if app.fs.isFile(data.filename) == false then
    app.alert("  File not found  ")
  else
    -- Load our SC2 image so we can get a base idea for setup.
    -- From here we can read sprite.filename into our SC2 reader.
    local rdr = Reader:new(data)
    local err = rdr:decode()
    if err ~= nil then
      app.alert(err:string())
    end
  end
end
