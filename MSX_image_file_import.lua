--[[
	####### Aseprite - MSX image files importer script #######
  Copyright by Natalia Pujol (2021)
  This file is released under the terms of the MIT license.

  Info:
    - MSX Graphics Screen modes:
        https://www.msx.org/wiki/Yamaha_V9958
        http://map.grauw.nl/resources/video/yamaha_v9958.pdf
    - YJK modes:
        http://map.grauw.nl/articles/yjk/
    - MAG MAX file format:
        https://mooncore.eu/bunny/txt/makichan.htm


	Code inspired by
    https://github.com/kettek/aseprite-scripts/blob/master/import-apng.lua
 --]]
local version = "v1.0"
local plugin

function init(globalPlugin)
  print("MSX image file import plugin initialized...")

  plugin = globalPlugin

  if plugin.preferences.sprRender == nil then
    plugin.preferences.sprRender = true
  end
  if plugin.preferences.sprSize == nil then
    plugin.preferences.spr16 = true
  end
  if plugin.preferences.tilesLayer == nil then
    plugin.preferences.tilesLayer = true
  end

  plugin:newCommand{
    id="msx_image_import",
    title="Import MSX image file",
    group="file_import",
    onclick=function()
      startDialog()
    end
  }

end

function exit(plugin)
  print("MSX image file import plugin closing...")
end



-- ########################################################

--[[ Array
Array provides a few helper function for array management.
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



-- ########################################################
--     Reader class
--  The Reader is the state machine that is responsible for decoding a 
--  MSX file into the active Aseprite sprite.
-- ########################################################

Reader = {
  msxHeader = "\xFE\x00\x00",
  filename = nil,       -- filename of the MSX file
  file = nil,           -- file reader from io
  spr = nil,            -- Sprite object
  img = nil,            -- Image object
  imgSpr = nil,         -- Image layer for Sprites
  imgTiles = nil,       -- Image layer for Raw Tiles
  sprRender = false,    -- Flag to know if Sprite Layer must be created
  tilesLayer = false,   -- Flag to create a Raw Tiles Layer or not
  sprSize = 32,         -- sprites size in bytes

  address = {
    tileMap = nil,
    tilePat = nil,
    tileCol = nil,
    sprAttr = nil,
    sprPat  = nil,
    sprCol  = nil,      -- only MSX2 or above
    palette = nil,      -- only MSX2 or above
  },

  screen = {            -- MSX screen mode info/data
    -- info variables
    mode = -1,          -- screen mode: 1, 2, 3, 4, 5, 6, 7, 8, 10 or 12
    maxWidth = 256,
    maxHeight = 192,
    maxColors = 16,
    paletteRes = "MSX1_DEFAULT",
    -- data containers
    tileMap = nil,      -- used by Screen 1..12
    tilePatterns = nil, -- used by Screen 1..4
    tileColors = nil,   -- used by Screen 1..4
    sprAttribs = nil,   -- used by Screen 1..12
    sprPatterns = nil,  -- used by Screen 1..12
    sprColors = nil,    -- used by Screen 4..12
    palette = nil,      -- used by Screen 4..7 and 10
  },
}

-- ============================
function Reader:new(o)
  local rdr = {}
  setmetatable(rdr, self)
  self.__index = self

  if o ~= nil then
    rdr:config(o)
  end

  return rdr
end

-- ============================
function Reader:config(o)
  self.filename = o.filename
  self.file = io.open(o.filename, "rb")
  self.sprRender = o.chk_sprRender
  self.tilesLayer = o.chk_tilesLayer

  self.screen.mode = o.scrMode

  self.screen.maxWidth  = 256
  self.screen.maxHeight = 192
  self.screen.maxColors = 16

  self.address.tilePat = nil
  self.address.sprCol  = nil
  self.address.sprAttr = nil
  self.address.palette = nil
  self.address.sprPat  = nil
  self.address.tileMap = nil
  self.address.tileCol = nil

  if o.spr16 then self.sprSize = 32 else self.sprSize = 8 end
end

-- ============================
function Reader:decode()
  -- check header
  local err = self:checkHeader()
  if err ~= nil then return err end

  -- create the new image
  self:createImage()

  -- parse the MSX file
  err = self:parseVRAM()
  if err ~= nil then return err end

  -- set de custom palette if any
  err = self:setPalette()
  if err ~= nil then return err end

  -- paint image
  err = self:paintBitmapScreen()
  if err ~= nil then return err end

  -- paint sprites
  if self.sprRender and self.screen.sprPatterns ~= nil then
    err = self:paintSpriteLayers()
    if err ~= nil then return err end
  end

  -- paint raw tiles
  if self.tilesLayer then
    err = self:paintTilesLayer()
    if err ~= nil then return err end
  end

  return err
end

-- ============================
function Reader:checkHeader()
  local buffer = self.file:read(3)
  if buffer == nil then return Error(E.EOF) end
  if Binary.compare(buffer, self.msxHeader) ~= true then
    return Error(E.NOT_MSX_FILE)
  end
  return nil
end

-- ============================
function Reader:createImage()
  self.spr = Sprite(self.screen.maxWidth, self.screen.maxHeight, ColorMode.INDEXED)
  self.spr.filename = self.filename .. ".png"

  -- MSX Default Palettes
  local palette = Palette{ fromResource=self.screen.paletteRes }
  if palette == nil then
    self.spr:close()
    return Error(E.PALETTE_NOT_FOUND)
  end
  if self.screen.maxColors<256 then
    palette:resize(self.screen.maxColors+1)
  end
  self.spr:setPalette(palette)
  self.spr.transparentColor = self.screen.maxColors

  -- Bitmap Layer
  self.spr.layers[1].name = "Layer Bitmap"
  self.img = self.spr.cels[1].image
  self.img:clear()

  -- Sprite Layer
  if self.sprRender then
    layer = self.spr:newLayer()
    layer.name = "Layer Sprites"
--    layer.isTransparent = true
    cel = self.spr:newCel(layer, self.spr.frames[1])
    self.imgSpr = cel.image
    self.imgSpr:clear()
  end

  -- Raw Tiles Layer
  if self.tilesLayer then
    layer = self.spr:newLayer()
    layer.name = "Layer Raw Tiles"
--    layer.isTransparent = false
    layer.isVisible = false
    cel = self.spr:newCel(layer, self.spr.frames[1])
    self.imgTiles = cel.image
    self.imgTiles:clear(0)
  end
end

-- ============================
function Reader:parseVRAM()
  -- Tile Map
  self.screen.tileMap = self:readChunk(self.address.tileMap)
  -- Tile Patterns
  self.screen.tilePatterns = self:readChunk(self.address.tilePat)
  -- Tile Colors
  self.screen.tileColors = self:readChunk(self.address.tileCol)
  -- Sprites Attributes
  self.screen.sprAttribs = self:readChunk(self.address.sprAttr)
  -- Sprites Patterns
  self.screen.sprPatterns = self:readChunk(self.address.sprPat)
  -- Sprites Colors
  self.screen.sprColors = self:readChunk(self.address.sprCol)
  -- Palette
  self.screen.palette = self:readChunk(self.address.palette)
end

-- ########################################################
--     Bitmap functions

-- ============================
function Reader:paintBitmapScreen()
  local tile
  local offset
  local x = 0
  local y = 0
  local err = nil

  for t=1,self.screen.tileMap:len() do
    tile = self.screen.tileMap:byte(t)
    offset = 0x800 * math.floor(y/64) -- banks offset
    offset = offset + tile * 8        -- adding tile offset

    err = self:paintBitmapTile(self.img, x, y, offset)
    if err ~= nil then return err end

    x = x + 8
    if x == self.screen.maxWidth then
      x = 0
      y = y + 8
    end
  end
end

-- ============================
function Reader:paintByte(img, x, y, pattern, fgcol, bgcol, isOrEnabled)
  local colPixel = 0
  if pattern == nil then return end

  for xp=x+7,x,-1 do
    -- Pixel value
    if (pattern & 1) == 1 then
      colPixel = fgcol
      -- OR colors
      if isOrEnabled then
        local oldColor = img:getPixel(xp, y)
        if oldColor >= self.screen.maxColors then oldColor = 0 end
        colPixel = colPixel | oldColor
      end
    else
      colPixel = bgcol
    end
    if colPixel ~= self.screen.maxColors and xp >= 0 and y >= 0 and xp < self.screen.maxWidth and y < self.screen.maxHeight then
      img:putPixel(xp, y, colPixel)
    end
    pattern = pattern // 2
  end
end

-- ########################################################
--     Sprite functions

-- ============================
function Reader:paintSpriteLayers()
  local attr = ""
  local sprPat = ""
  for layer=31,0,-1 do
    attr = self:getSpriteLayerAttribs(layer)
    sprPat = self:getSpritePattern(attr.patternNum)
    if attr.y > self.screen.maxHeight then
      attr.y = attr.y - 256
    end
    attr.y = attr.y + 1
    self:paintSprite(attr, sprPat)
  end
end

-- ============================
function Reader:paintSprite(attr, data)
  local pos = 1
  local offset
  for xp=attr.x,attr.x+8,8 do
    for line=0,15 do
      if line==8 and self.sprSize==8 then return end
      if attr.ec[line+1]>0 then offset=-32 else offset=0 end
      if self.screen.mode > 3 or attr.color[line+1] ~= 0 then
        self:paintByte(self.imgSpr, xp+offset, attr.y+line, data:byte(pos), attr.color[line+1], self.screen.maxColors, attr.orColor[line+1])
      end
      pos = pos + 1
    end
  end
end

-- ============================
function Reader:getSpritePattern(num)
  local pos = num * 8 + 1
  return self.screen.sprPatterns:sub(pos, pos + self.sprSize - 1)
end

-- ============================
function Reader:getSpriteLayerAttribs(layer)
  return self:_getSpriteLayerAttribsMode1(layer)
end

-- ============================
function Reader:_getSpriteLayerAttribsMode1(layer)
  layer = layer * 4 + 1
  local bin = self.screen.sprAttribs:sub(layer, layer+3)
  local colorByte = bin:byte(4) or 0
  return { 
    y = bin:byte(1) or 209,
    x = bin:byte(2) or 0,
    patternNum = bin:byte(3) or 0,
    ec = Array:fill(16, colorByte >> 7),
    color = Array:fill(16, colorByte & 0x0f),
    orColor = Array:fill(16, false),
  }
end

-- ============================
function Reader:_getSpriteLayerAttribsMode2(layer)
  local attr = self:_getSpriteLayerAttribsMode1(layer)
  -- añadimos atributos modo2 de la tabla sprColors
  layer = layer * 16 + 1
  local colors = self.screen.sprColors:sub(layer, layer+15)
  local aux
  for line=1,16 do
    aux = colors:byte(line) or 0
    attr.color[line] = aux & 0x0f
    attr.ec[line] = aux >> 7
    attr.orColor[line] = (aux >> 6) & 1
  end
  return attr
end


-- ########################################################
--     Aux functions

-- ============================
function Reader:seekPos(pos)
  self.file:seek("set", 7 + pos)
end

-- ============================
function Reader:readChunk(addrStruct)
  if addrStruct ~= nil then
    self:seekPos(addrStruct.pos)
    return self.file:read(addrStruct.size)
  end
  return nil
end

-- ============================
function Reader:setPalette()
  -- function overrided for MSX2 or above classes
end

-- ============================
function Reader:_parsePaletteMSX2()
  if self.screen.palette ~= nil then
    local palette = self.spr.palettes[1]
    local r, g, b

    -- the file palette is RGB444 but the MSX hardware is RGB333
    for i=0,self.screen.maxColors-1 do
      -- read palette from file & create RGB444
      r = self.screen.palette:byte(i*2+1) or 0
      g = self.screen.palette:byte(i*2+2) or 0
      b = r & 0x0f
      r = r >> 4
      -- RGB444 -> RGB888
      r = r * 255 // 7
      g = g * 255 // 7
      b = b * 255 // 7
      palette:setColor(i, Color(r, g, b))
    end
  end
end



-- ########################################################
--     ReaderTiled (abstract)
-- ########################################################

ReaderTiled = Reader:new()

function ReaderTiled:new(o)
  rdr = Reader:new(o)
  setmetatable(rdr, self)
  self.__index = self

  return rdr
end

-- ============================
function Reader:paintTilesLayer()
  local tile
  local offset
  local x = 0
  local y = 0
  local err = nil
  local numTiles = self.address.tilePat.size / 0x800 * 0x100

  for t=0,numTiles-1 do
    tile = t % 256
    offset = 0x800 * math.floor(y/64) -- banks offset
    offset = offset + tile * 8        -- adding tile offset

    err = self:paintBitmapTile(self.imgTiles, x, y, offset)
    if err ~= nil then return err end

    x = x + 8
    if x == self.screen.maxWidth then
      x = 0
      y = y + 8
    end
  end
end

-- ============================
function ReaderTiled:paintBitmapTile(img, x, y, offset)
  if offset >= self.screen.tileColors:len() then
    return Error(E.TILESET_OVERFLOW);
  end

  for yt=0,7 do
    local pattern = self.screen.tilePatterns:byte(offset + yt + 1)
    local color = self.screen.tileColors:byte(offset + yt + 1)
    local fgcol = (color >> 4) & 0x0f
    local bgcol = (color & 0x0f)

    self:paintByte(img, x, y+yt, pattern, fgcol, bgcol, false)
  end

  return nil
end



-- ########################################################
--     ReaderSC1
-- ########################################################

ReaderSC1 = ReaderTiled:new()

function ReaderSC1:new(o)
  rdr = ReaderTiled:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 192
  rdr.screen.maxColors = 16
  rdr.screen.paletteRes = "MSX1_DEFAULT"

  rdr.address.tilePat = { pos=0x0000, size=0x0800 }
  rdr.address.tileMap = { pos=0x1800, size=0x300 }
  rdr.address.sprAttr = { pos=0x1b00, size=0x80 }
  rdr.address.tileCol = { pos=0x2000, size=0x20 }
  rdr.address.sprPat  = { pos=0x3800, size=0x800 }

  return rdr
end

-- ============================
function ReaderSC1:paintBitmapTile(img, x, y, offset)
  offset = offset % 0x800
  local color = self.screen.tileColors:byte(offset//64 + 1)
  for yt=0,7 do
    local pattern = self.screen.tilePatterns:byte(offset + yt + 1)
    local fgcol = (color >> 4) & 0x0f
    local bgcol = (color & 0x0f)

    self:paintByte(img, x, y+yt, pattern, fgcol, bgcol, false)
  end

  return nil
end



-- ########################################################
--     ReaderSC2
-- ########################################################

ReaderSC2 = ReaderTiled:new()

function ReaderSC2:new(o)
  rdr = ReaderTiled:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 192
  rdr.screen.maxColors = 16
  rdr.screen.paletteRes = "MSX1_DEFAULT"

  rdr.address.tilePat = { pos=0x0000, size=0x1800 }
  rdr.address.tileMap = { pos=0x1800, size=0x300 }
  rdr.address.sprAttr = { pos=0x1b00, size=0x80 }
  rdr.address.tileCol = { pos=0x2000, size=0x1800 }
  rdr.address.sprPat  = { pos=0x3800, size=0x800 }

  return rdr
end



-- ########################################################
--     ReaderSC3
-- ########################################################

ReaderSC3 = ReaderTiled:new()

function ReaderSC3:new(o)
  rdr = ReaderTiled:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 192
  rdr.screen.maxColors = 16
  rdr.screen.paletteRes = "MSX1_DEFAULT"

  rdr.address.tileCol = { pos=0x0000, size=0x0600 } -- Block colors
  rdr.address.tileMap = { pos=0x0800, size=0x300 }
  rdr.address.sprAttr = { pos=0x1b00, size=0x80 }
  rdr.address.sprPat  = { pos=0x3800, size=0x800 }

  return rdr
end

-- ============================
function ReaderSC3:paintBitmapScreen()
  local offset = 0
  local x = 0
  local y = 0

  for t=1,0x600 do
    offset = (y//8)*256+(y & 7)+(x*4 & 0xf8)
    self:paintBitmapTile(self.img, x, y, offset)

    x = x + 2
    if x >= 64 then
      x = 0
      y = y + 1
    end
  end
end

-- ============================
function ReaderSC3:paintBitmapTile(img, x, y, offset)
  local col = self.screen.tileColors:byte(offset+1) or 0

  for px=0,15 do 
    img:putPixel(x*4+px%4, y*4+px//4, col >> 4)
    img:putPixel((x+1)*4+px%4, y*4+px//4, col & 0x0f)
  end
end



-- ########################################################
--     ReaderSC4
-- ########################################################

ReaderSC4 = ReaderTiled:new()

function ReaderSC4:new(o)
  rdr = ReaderTiled:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 192
  rdr.screen.maxColors = 16
  rdr.screen.paletteRes = "MSX2_DEFAULT"

  rdr.address.tilePat = { pos=0x0000, size=0x1800 }
  rdr.address.tileMap = { pos=0x1800, size=0x300 }
  rdr.address.palette = { pos=0x1b80, size=0x20 }
  rdr.address.sprCol  = { pos=0x1c00, size=0x200 }
  rdr.address.sprAttr = { pos=0x1e00, size=0x80 }
  rdr.address.tileCol = { pos=0x2000, size=0x1800 }
  rdr.address.sprPat  = { pos=0x3800, size=0x800 }

  return rdr
end

-- ============================
function ReaderSC4:setPalette()
  self:_parsePaletteMSX2()
end

-- ============================
function ReaderSC4:getSpriteLayerAttribs(layer)
  return self:_getSpriteLayerAttribsMode2(layer)
end



-- ########################################################
--     ReaderBitmapRGB (abstract)
-- ########################################################

ReaderBitmapRGB = Reader:new()

function ReaderBitmapRGB:new(o)
  rdr = Reader:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.paletteRes = "MSX2_DEFAULT"

  return rdr
end

-- ============================
function ReaderBitmapRGB:paintBitmapScreen()
  local x = 0
  local y = 0
  local pos = 1

  repeat
    colorByte = self.screen.tilePatterns:byte(pos) or nil
    pos = pos + 1

    if colorByte ~= nil then
      x, y = self:paintBitmapByte(x, y, colorByte)
    end
  until colorByte == nil
end

-- ============================
function ReaderBitmapRGB:paintBitmapByte(x, y, colorByte)
  self.img:putPixel(x, y, colorByte >> 4)
  self.img:putPixel(x+1, y, colorByte & 0x0f)
  x = x + 2
  if (x >= self.screen.maxWidth) then
    x = 0
    y = y + 1
  end
  return x, y
end

-- ============================
function ReaderBitmapRGB:setPalette()
  self:_parsePaletteMSX2()
end

-- ============================
function ReaderBitmapRGB:getSpriteLayerAttribs(layer)
  return self:_getSpriteLayerAttribsMode2(layer)
end



-- ########################################################
--     ReaderSC5
-- ########################################################

ReaderSC5 = ReaderBitmapRGB:new()

function ReaderSC5:new(o)
  rdr = ReaderBitmapRGB:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 212
  rdr.screen.maxColors = 16

  rdr.address.tilePat = { pos=0x0000, size=0x6a00 }
  rdr.address.sprCol  = { pos=0x7400, size=0x200 }
  rdr.address.sprAttr = { pos=0x7600, size=0x80 }
  rdr.address.palette = { pos=0x7680, size=0x20 }
  rdr.address.sprPat  = { pos=0x7800, size=0x800 }

  return rdr
end

-- ============================
function ReaderSC5:paintBitmapByte(x, y, colorByte)
  self.img:putPixel(x, y, colorByte >> 4)
  self.img:putPixel(x+1, y, colorByte & 0x0f)
  x = x + 2
  if (x >= self.screen.maxWidth) then
    x = 0
    y = y + 1
  end
  return x, y
end



-- ########################################################
--     ReaderSC6
-- ########################################################

ReaderSC6 = ReaderBitmapRGB:new()

function ReaderSC6:new(o)
  rdr = ReaderBitmapRGB:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 512
  rdr.screen.maxHeight = 212
  rdr.screen.maxColors = 4

  rdr.address.tilePat = { pos=0x0000, size=0x6a00 }
  rdr.address.sprCol  = { pos=0x7400, size=0x200 }
  rdr.address.sprAttr = { pos=0x7600, size=0x80 }
  rdr.address.palette = { pos=0x7680, size=0x20 }
  rdr.address.sprPat  = { pos=0x7800, size=0x800 }

  return rdr
end

-- ============================
function ReaderSC6:paintBitmapByte(x, y, colorByte)
  self.img:putPixel(x, y, colorByte >> 6)
  self.img:putPixel(x+1, y, (colorByte >> 4) & 0x03)
  self.img:putPixel(x+2, y, (colorByte >> 2) & 0x03)
  self.img:putPixel(x+3, y, colorByte & 0x03)
  x = x + 4
  if (x >= self.screen.maxWidth) then
    x = 0
    y = y + 1
  end
  return x, y
end



-- ########################################################
--     ReaderSC7
-- ########################################################

ReaderSC7 = ReaderSC5:new()

function ReaderSC7:new(o)
  rdr = ReaderSC5:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 512
  rdr.screen.maxHeight = 212
  rdr.screen.maxColors = 16

  rdr.address.tilePat = { pos=0x0000, size=0xd400 }
  rdr.address.sprPat  = { pos=0xf000, size=0x800 }
  rdr.address.sprCol  = { pos=0xf800, size=0x200 }
  rdr.address.sprAttr = { pos=0xfa00, size=0x80 }
  rdr.address.palette = { pos=0xfa80, size=0x20 }

  return rdr
end



-- ########################################################
--     ReaderSC8
-- ########################################################

ReaderSC8 = ReaderBitmapRGB:new()

function ReaderSC8:new(o)
  rdr = ReaderBitmapRGB:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 212
  rdr.screen.maxColors = 256
  rdr.screen.paletteRes = "MSX2_SC8"

  rdr.address.tilePat = { pos=0x0000, size=0xd400 }
  rdr.address.sprPat  = { pos=0xf000, size=0x800 }
  rdr.address.sprCol  = { pos=0xf800, size=0x200 }
  rdr.address.sprAttr = { pos=0xfa00, size=0x80 }
  rdr.address.palette = { pos=0xfa80, size=0x20 }

  return rdr
end

-- ============================
function ReaderSC8:paintBitmapByte(x, y, colorByte)
  self.img:putPixel(x, y, colorByte)
  x = x + 1
  if (x >= self.screen.maxWidth) then
    x = 0
    y = y + 1
  end
  return x, y
end



-- ########################################################
--     ReaderBitmapYJK (abstract)
-- ########################################################

ReaderBitmapYJK = Reader:new()

function ReaderBitmapYJK:new(o)
  rdr = Reader:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.paletteRes = "MSX2_DEFAULT"
  rdr.screen.colorMode = ColorMode.RGB

  return rdr
end

-- ============================
function ReaderBitmapYJK:createImage()
  self.spr = Sprite(self.screen.maxWidth, self.screen.maxHeight, ColorMode.RGB)
  self.spr.filename = self.filename .. ".png"

  -- MSX Default Palettes
  local palette = Palette{ fromResource=self.screen.paletteRes }
  if palette == nil then
    self.spr:close()
    return Error(E.PALETTE_NOT_FOUND)
  end
  self.spr:setPalette(palette)
  -- self.spr.transparentColor = self.screen.maxColors

  -- Bitmap Layer
  self.spr.layers[1].name = "Layer Bitmap"
  self.img = self.spr.cels[1].image
end

-- ============================
function ReaderBitmapYJK:setPalette()
  self:_parsePaletteMSX2()
end

-- ============================
function ReaderBitmapYJK:getSpriteLayerAttribs(layer)
  return self:_getSpriteLayerAttribsMode2(layer)
end

-- ============================
function ReaderBitmapYJK:paintBitmapScreen()
  local x = 0
  local y = 0
  local pos = 1

  repeat
    colorByte = self.screen.tilePatterns:sub(pos, pos+3) or nil
    pos = pos + 4

    if colorByte ~= nil then
      x, y = self:paintBitmapByte(x, y, colorByte)
    end
  until self.screen.tilePatterns:byte(pos) == nil
end

-- ============================
function ReaderBitmapYJK:paintBitmapByte(x, y, colorBytes)
  local c1, c2, c3, c4

  c1,c2,c3,c4 = self:getColorRGB(colorBytes)

  self.img:putPixel(x+0, y, c1)
  self.img:putPixel(x+1, y, c2)
  self.img:putPixel(x+2, y, c3)
  self.img:putPixel(x+3, y, c4)

  x = x + 4
  if (x >= self.screen.maxWidth) then
    x = 0
    y = y + 1
  end

  return x, y
end

-- ============================
function ReaderBitmapYJK:getColorRGB(colorBytes)
  local y1, y2, y3, y4, j, k

  y1,y2,y3,y4,j,k = self:decodeYJK(colorBytes)

  return self:yjk2rgb(y1, j, k), self:yjk2rgb(y2, j, k), self:yjk2rgb(y3, j, k), self:yjk2rgb(y4, j, k)
end

-- ============================
function ReaderBitmapYJK:decodeYJK(colorBytes)
  local y1, y2, y3, y4, j, k
  local aux
  
  aux = colorBytes:byte(1) or 0
  y1 = aux >> 3
  k = aux & 0x07

  aux = colorBytes:byte(2) or 0
  y2 = aux >> 3
  k = k | ((aux & 0x07) << 3)
  k = decodeTwocomplement6bits(k)

  aux = colorBytes:byte(3) or 0
  y3 = aux >> 3
  j = aux & 0x07

  aux = colorBytes:byte(4) or 0
  y4 = aux >> 3
  j = j | ((aux & 0x07) << 3)
  j = decodeTwocomplement6bits(j)

  return y1, y2, y3, y4, j, k
end

-- ============================
function ReaderBitmapYJK:yjk2rgb(y, j, k)
  local r, g, b

  r = y + j
  g = y + k
  b = math.ceil(5*y/4.0 - j/2.0 - k/2.0)

  r = r * 255 // 31
  g = g * 255 // 31
  b = b * 255 // 31

  r = math.max(math.min(r, 255), 0)
  g = math.max(math.min(g, 255), 0)
  b = math.max(math.min(b, 255), 0)

  return Color(r, g, b)
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
--     ReaderSCA
-- ########################################################

ReaderSCA = ReaderBitmapYJK:new()

function ReaderSCA:new(o)
  rdr = ReaderBitmapYJK:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 212
  rdr.screen.maxColors = 16

  rdr.address.tilePat = { pos=0x0000, size=0xd400 }
  rdr.address.sprPat  = { pos=0xf000, size=0x800 }
  rdr.address.sprCol  = { pos=0xf800, size=0x200 }
  rdr.address.sprAttr = { pos=0xfa00, size=0x80 }
  rdr.address.palette = { pos=0xfa80, size=0x20 }

  return rdr
end

-- ============================
function ReaderSCA:getColorRGB(colorBytes)
  local y1, y2, y3, y4, j, k
  local c1, c2, c3, c4

  y1,y2,y3,y4,j,k = self:decodeYJK(colorBytes)

  if y1 & 1 == 1 then c1 = Color(self.spr.palettes[1]:getColor(y1>>1))
  else c1 = self:yjk2rgb(y1, j, k) end

  if y2 & 1 == 1 then c2 = Color(self.spr.palettes[1]:getColor(y2>>1))
  else c2 = self:yjk2rgb(y2, j, k) end

  if y3 & 1 == 1 then c3 = Color(self.spr.palettes[1]:getColor(y3>>1))
  else c3 = self:yjk2rgb(y3, j, k) end

  if y4 & 1 == 1 then c4 = Color(self.spr.palettes[1]:getColor(y4>>1))
  else c4 = self:yjk2rgb(y4, j, k) end

  return c1, c2, c3, c4
end



-- ########################################################
--     ReaderSCC
-- ########################################################

ReaderSCC = ReaderBitmapYJK:new()

function ReaderSCC:new(o)
  rdr = ReaderBitmapYJK:new(o)
  setmetatable(rdr, self)
  self.__index = self

  rdr.screen.maxWidth = 256
  rdr.screen.maxHeight = 212
  rdr.screen.maxColors = 16

  rdr.address.tilePat = { pos=0x0000, size=0xd400 }
  rdr.address.sprPat  = { pos=0xf000, size=0x800 }
  rdr.address.sprCol  = { pos=0xf800, size=0x200 }
  rdr.address.sprAttr = { pos=0xfa00, size=0x80 }
  rdr.address.palette = { pos=0xfa80, size=0x20 }

  return rdr
end



-- ########################################################
--     Dialog management
-- ########################################################

function showFileInfo(dlg)
  local ret = nil
  local newType = "<unknown file format>"
  local newInfo = ""
  local newTilesLayer = false
  local newBtnOkEnabled = true
  local newInfoVisible = false
  local newRenderSprites = true

  if dlg.data.filename == nil then
    newType = "<none>"
    newBtnOkEnabled = false
  else
    local ext = dlg.data.filename:upper():sub(-4)
    if ext:sub(1,3) == ".SC" then
      ext = ext:sub(-1)
      ret = tonumber("0x"..ext)
      newInfo = "<not implemented yet>"
      -- SC1
      if ext == "1" then
        newType = "MSX Screen 1 tiled file"
        newInfo = "256x192 16 fixed colors"
        newTilesLayer = true
      -- SC2
      elseif ext == "2" then
        newType = "MSX Screen 2 tiled file"
        newInfo = "256x192 16 fixed colors"
        newTilesLayer = true
      -- SC3
      elseif ext == "3" then
        newType = "MSX Screen 3 file"
        newInfo = "64x48 16 fixed colors"
      -- SC4
      elseif ext == "4" then
        newType = "MSX2 Screen 4 tiled file"
        newInfo = "256x192 16col from 512"
        newTilesLayer = true
      -- SC5
      elseif ext == "5" then
        newType = "MSX2 Screen 5 file"
        newInfo = "256x212 16col from 512"
      -- SC6
      elseif ext == "6" then
        newType = "MSX2 Screen 6 file"
        newInfo = "512x212 4col from 512"
      -- SC7
      elseif ext == "7" then
        newType = "MSX2 Screen 7 file"
        newInfo = "512x212 16col from 512"
      -- SC8
      elseif ext == "8" then
        newType = "MSX2 Screen 8 file"
        newInfo = "256x212 256 fixed col"
        newRenderSprites = false
      -- SCA
      elseif ext == "A" then
        newType = "MSX2+ Screen 10 file"
        newInfo = "256x212 12k YJK + 16 RGB"
        newRenderSprites = false
      -- SCC
      elseif ext == "C" then
        newType = "MSX2+ Screen 12 file"
        newInfo = "256x212 19k YJK Colors"
        newRenderSprites = false
      else
        newBtnOkEnabled = false
      end
    end
  end

  if newInfo ~= "" then
    newInfoVisible = true
  else
    newBtnOkEnabled = false
    ret = nil
  end

  -- filetype
  dlg:modify{ id="file_type", text=newType }
  dlg:modify{ id="file_info", text=newInfo, visible=newInfoVisible }
  -- render sprites
  dlg:modify{ id="chk_sprRender",
    selected=newRenderSprites and plugin.preferences.sprRender, 
    enabled=newRenderSprites
  }
  dlg:modify{ id="spr8", enabled=plugin.preferences.sprRender }
  dlg:modify{ id="spr16", enabled=plugin.preferences.sprRender }
  -- raw tiles layer
  dlg:modify{ id="chk_tilesLayer", 
    visible=newTilesLayer, 
    enabled=newTilesLayer , 
    selected=newTilesLayer and plugin.preferences.tilesLayer
  }
  -- buttons
  dlg:modify{ id="ok", enabled=newBtnOkEnabled }

  return ret
end

function typeof(var)
    local _type = type(var);
    if(_type ~= "table" and _type ~= "userdata") then
        return _type;
    end
    local _meta = getmetatable(var);
    if(_meta ~= nil and _meta._NAME ~= nil) then
        return _meta._NAME;
    else
        return _type;
    end
end

--! Script Body !--
function startDialog()
  if not app.isUIAvailable then
    return
  end

  local scrMode = 0
  local dlg = nil
  local data = nil
  local cancel = false
  repeat
    dlg = Dialog("Import MSX image file "..version)
    data = dlg
              :file{
                id="filename",
                label="MSX image file:",
                open=true,
                filetypes={ "SC1", "SC2", "SC3", "SC4", "SC5", "SC6", "SC7", "SC8", "SCA", "SCC" },
                onchange=function() scrMode = showFileInfo(dlg) end }
              :label{ id="file_type", label="Selected image:", text="<none>" }
              :newrow()
              :label{ id="file_info", text="", visible=false }
              :separator()
              :check{ id="chk_sprRender",
                label="Render sprites:",
                text="Sprite size:",
                selected=plugin.preferences.sprRender,
                onclick = function()
                  plugin.preferences.sprRender = dlg.data.chk_sprRender
                  dlg:modify{ id="spr8", enabled=dlg.data.chk_sprRender }
                  dlg:modify{ id="spr16", enabled=dlg.data.chk_sprRender }
                end }
              :radio{ id="spr8",
                text="8x8 pixels",
                selected=false }
              :radio{ id="spr16",
                text="16x16 pixels",
                selected=true }
              :check{ id="chk_tilesLayer",
                label="Add layer w/ raw tiles:", 
                selected=false,
                visible=false,
                onclick = function()
                  plugin.preferences.tilesLayer = dlg.data.chk_tilesLayer
                end }
              :separator()
              :button{ id="ok", text="Ok", enabled=false }
              :button{ id="cancel", text="Cancel" }
              :label{ label="by NataliaPC'2021" }
              :show().data

    data.scrMode = scrMode
    if data.ok and data.filename == "" then 
      app.alert("  Select a file first  ")
    end
  until data.filename ~= "" or data.cancel or (data.cancel or data.ok)==false


  if data.ok then
    if app.fs.isFile(data.filename) == false then
      app.alert("  File not found  ")
    else
      -- From here we can read sprite.filename into our MSX reader.
      local rdr = nil
      
      if data.scrMode == 1 then
        rdr = ReaderSC1:new(data)
      elseif data.scrMode == 2 then
        rdr = ReaderSC2:new(data)
      elseif data.scrMode == 3 then
        rdr = ReaderSC3:new(data)
      elseif data.scrMode == 4 then
        rdr = ReaderSC4:new(data)
      elseif data.scrMode == 5 then
        rdr = ReaderSC5:new(data)
      elseif data.scrMode == 6 then
        rdr = ReaderSC6:new(data)
      elseif data.scrMode == 7 then
        rdr = ReaderSC7:new(data)
      elseif data.scrMode == 8 then
        rdr = ReaderSC8:new(data)
      elseif data.scrMode == 10 then
        rdr = ReaderSCA:new(data)
      elseif data.scrMode == 12 then
        rdr = ReaderSCC:new(data)
      end

      if rdr ~= nil then
        local err = rdr:decode()
        if err ~= nil then
          app.alert(err:string())
        else
          if data.scrMode==6 or data.scrMode==7 then
            app.alert("You need to change manually the Pixel Aspect Ratio to (1:2). Press [Ctrl+P]")
          end
        end
      end
    end
  end

end
