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


function init(plugin)
  print("MSX image file import plugin initialized...")

--  if plugin.preferences.sprRender == nil then
--    plugin.preferences.sprRender = true
--  end
--  if plugin.preferences.sprSize == nil then
--    plugin.preferences.spr16 = true
--  end

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

--[[ Binary
Binary provides a few helper function for decoding and comparing bytes.
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
  sprRender = false,    -- Flag to know if Sprite Layer must be created
  sprSize = 32,         -- sprites size in bytes
  transpColor = 16,     -- Transparent color

  address = {
    tileMap = nil,
    tilePat = nil,
    tileCol = nil,
    sprAttr = nil,
    sprPat  = nil,
    sprCol  = nil,      -- only MSX2 or above
    palette = nil,      -- only MSX2 or above
  },

  screen = {            -- MSX data
    mode = -1,          -- screen mode: 1, 2, 3, 4, 5, 6, 7, 8, 10 or 12
    maxWidth = 256,
    maxHeight = 192,
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
  --  Screen:         1    2    3    4    5    6    7    8   10   12
  local widths  = { 256, 256, 256, 256, 256, 512, 512, 256, 256, 256 }
  local heights = { 192, 192, 192, 192, 212, 212, 212, 212, 212, 212 }

  self.filename = o.filename
  self.file = io.open(o.filename, "rb")
  self.sprRender = o.spr_render

  if o.spr16 then self.sprSize = 32 else self.sprSize = 8 end

  self.screen.mode = o.scrMode
  self.screen.maxWidth = widths[o.scrMode]
  self.screen.maxHeight = heights[o.scrMode]
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
  if self.screen.sprPatterns ~= nil then
    err = self:paintSpriteLayers()
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

  -- MSX Palette
  local palette = Palette{ fromResource="MSX1" }
  if palette == nil then
    self.spr:close()
    return Error(E.PALETTE_NOT_FOUND)
  end
  palette:resize(17)
  palette:setColor(0, Color{ r=0, g=0, b=0, a=255 } )
  palette:setColor(self.transpColor, Color{ r=0, g=0, b=0, a=0 } )
  self.spr:setPalette(palette)
  self.spr.transparentColor = self.transpColor

  -- Bitmap Layer
  self.spr.layers[1].name = "Layer Bitmap"
  self.img = self.spr.cels[1].image
  self.img:clear(self.transpColor)

  -- Sprite Layer
  if self.sprRender then
    layer = self.spr:newLayer()
    layer.name = "Layer Sprites"
    cel = self.spr:newCel(layer, self.spr.frames[1])
    self.imgSpr = cel.image
    self.imgSpr:clear(self.transpColor)
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

-- ============================
function Reader:paintBitmapScreen()
  local tile = 0
  local offset = 0
  local x = 0
  local y = 0
  local err = nil

  for t=1,0x300 do
    tile = self.screen.tileMap:byte(t)
    offset = 0x800 * math.floor(y/64) -- banks offset
    offset = offset + tile * 8        -- adding tile offset

    err = self:paintBitmapTile(x, y, offset)
    if err ~= nil then return err end

    x = x + 8
    if x == self.screen.maxWidth then
      x = 0
      y = y + 8
    end
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
    -- if attr.color & 0x80 == 0x80 then
    --   attr.x = attr.x - 32
    -- end
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
      self:paintByte(self.imgSpr, xp, attr.y+line, data:byte(pos), attr.color[line+1], self.transpColor, attr.orColor[line+1])
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
    ec = Array:fill(16, (colorByte & 0x80) and true or false),
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
    attr.ec[line] = (aux & 0x80) and true or false
    attr.orColor[line] = (aux & 0x40) and true or false
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
    local palette = Palette(17)
    local r, g, b

    -- the file palette is RGB444 but the MSX hardware is RGB333
    for i=0,15 do
      -- read palette from file & create RGB444
      r = self.screen.palette:byte(i*2+1)
      g = self.screen.palette:byte(i*2+2)
      b = r & 0x0f
      r = r >> 4
      -- RGB444 -> RGB888
      r = r * 255 // 7
      g = g * 255 // 7
      b = b * 255 // 7
      palette:setColor(i, Color{ r=r, g=g, b=b })
    end
    -- set palette to the aseprite image
    self.spr:setPalette(palette)
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
function ReaderTiled:paintBitmapTile(x, y, offset)
  if offset >= self.screen.tileColors:len() then
    return Error(E.TILESET_OVERFLOW);
  end

  for yt=0,7 do
    local pattern = self.screen.tilePatterns:byte(offset + yt + 1)
    local color = self.screen.tileColors:byte(offset + yt + 1)
    local fgcol = (color >> 4) & 0x0f
    local bgcol = (color & 0x0f)

    self:paintByte(self.img, x, y+yt, pattern, fgcol, bgcol, false)
  end

  return nil
end

-- ============================
function ReaderTiled:paintByte(img, x, y, pattern, fgcol, bgcol, isOrEnabled)
  local colPixel = 0
  if pattern == nil then return end

  for xp=x+7,x,-1 do
    -- Pixel value
    if (pattern & 1) == 1 then
      colPixel = fgcol
      -- OR colors
      if isOrEnabled then
        local oldColor = img:getPixel(xp, y)
        if oldColor >= self.transpColor then oldColor = 0 end
        colPixel = colPixel | oldColor
      end
    else
      colPixel = bgcol
    end
    if colPixel ~= self.transpColor and xp >= 0 and y >= 0 and xp < self.screen.maxWidth and y < self.screen.maxHeight then
      img:putPixel(xp, y, colPixel)
    end
    pattern = pattern // 2
  end
end



-- ########################################################
--     ReaderSC2
-- ########################################################

ReaderSC2 = ReaderTiled:new()

function ReaderSC2:new(o)
  rdr = ReaderTiled:new(o)
  setmetatable(rdr, self)
  self.__index = self

  self.address.tilePat = { pos=0x0000, size=0x1800 }
  self.address.tileMap = { pos=0x1800, size=0x300 }
  self.address.sprAttr = { pos=0x1b00, size=0x80 }
  self.address.tileCol = { pos=0x2000, size=0x1800 }
  self.address.sprPat  = { pos=0x3800, size=0x800 }

  return rdr
end



-- ########################################################
--     ReaderSC4
-- ########################################################

ReaderSC4 = ReaderTiled:new()

function ReaderSC4:new(o)
  rdr = ReaderTiled:new(o)
  setmetatable(rdr, self)
  self.__index = self

  self.address.tilePat = { pos=0x0000, size=0x1800 }
  self.address.tileMap = { pos=0x1800, size=0x300 }
  self.address.palette = { pos=0x1b80, size=0x20 }
  self.address.sprCol  = { pos=0x1c00, size=0x200 }
  self.address.sprAttr = { pos=0x1e00, size=0x80 }
  self.address.tileCol = { pos=0x2000, size=0x1800 }
  self.address.sprPat  = { pos=0x3800, size=0x800 }

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
--     Dialog management
-- ########################################################

function showFileInfo(dlg)
  local ret = nil
  local newType = "<unknown file format>"
  local newInfo = ""
  local newOkEnabled = false
  local newInfoVisible = false

  if dlg.data.filename == nil then
    newType = "<none>"
  else
    local ext = dlg.data.filename:upper():sub(-4)
    if ext:sub(1,3) == ".SC" then
      ext = ext:sub(-1)
      ret = tonumber("0x"..ext)
      newInfo = "<not implemented yet>"
      -- SC2
      if ext == "2" then
        newType = "MSX Screen 2 file"
        newInfo = "256x192 16 fixed colors"
        newOkEnabled = true
      -- SC3
      elseif ext == "3" then
        newType = "MSX Screen 3 file"
        -- newInfo = "64x48 16 fixed colors"
      -- SC4
      elseif ext == "4" then
        newType = "MSX2 Screen 4 file"
        newInfo = "256x192 16col from 512"
        newOkEnabled = true
      -- SC5
      elseif ext == "5" then
        newType = "MSX2 Screen 5 file"
        -- newInfo = "256x212 16col from 512"
      -- SC6
      elseif ext == "6" then
        newType = "MSX2 Screen 6 file"
        -- newInfo = "512x212 4col from 512"
      -- SC7
      elseif ext == "7" then
        newType = "MSX2 Screen 7 file"
        -- newInfo = "512x212 16col from 512"
      -- SC8
      elseif ext == "8" then
        newType = "MSX2 Screen 8 file"
        -- newInfo = "256x212 256col"
      -- SCA
      elseif ext == "A" then
        newType = "MSX2+ Screen 10 file"
        -- newInfo = "256x212 12k YJK + 16 RGB"
      -- SCC
      elseif ext == "C" then
        newType = "MSX2+ Screen 12 file"
        -- newInfo = "256x212 19k YJK Colors"
      end
    end
  end

  if newInfo ~= "" then
    newInfoVisible = true
  else
    ret = nil
  end

  dlg:modify{ id="file_type", text=newType }
  dlg:modify{ id="file_info", text=newInfo, visible=newInfoVisible }
  dlg:modify{ id="ok", enabled=newOkEnabled }

  return ret
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
    dlg = Dialog("Import MSX image file")
    data = dlg
              :file{
                id="filename",
                label="MSX image file:",
                open=true,
                filetypes={ "SC2", "SC3", "SC4", "SC5", "SC6", "SC7", "SC8", "SCA", "SCC" },
                onchange=function() scrMode = showFileInfo(dlg) end }
              :label{ id="file_type", label="Selected", text="<none>" }
              :newrow()
              :label{ id="file_info", text="", visible=false }
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
      
      if data.scrMode == 2 then
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
        end
      end
    end
  end

end
