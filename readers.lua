-- ########################################################
--     Reader class
--  The Reader is the state machine that is responsible for
--  decoding a MSX file into the active Aseprite sprite.
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

  -- From ScreenMode classes
  address = {},
  screen = {},
}

-- ============================
function Reader:new(input)
  local o = {}
  setmetatable(o, self)
  self.__index = self

  -- config object internals
  local err
  if input ~= nil then
    err = o:config(input)
    if err ~= nil then return err end
  end

  return o
end

-- ============================
function Reader:getInstance(data)
  if data.scrMode == 1 then return ReaderSC1:new(data) end
  if data.scrMode == 2 then return ReaderSC2:new(data) end
  if data.scrMode == 3 then return ReaderSC3:new(data) end
  if data.scrMode == 4 then return ReaderSC4:new(data) end
  if data.scrMode == 5 then return ReaderSC5:new(data) end
  if data.scrMode == 6 then return ReaderSC6:new(data) end
  if data.scrMode == 7 then return ReaderSC7:new(data) end
  if data.scrMode == 8 then return ReaderSC8:new(data) end
  if data.scrMode == 10 then return ReaderSCA:new(data) end
  if data.scrMode == 12 then return ReaderSCC:new(data) end
  return nil
end

-- ============================
function Reader:config(input)
  -- initializing object attributes
  self.filename = input.filename
  self.file = io.open(input.filename, "rb")
  self.sprRender = input.chk_sprRender
  self.tilesLayer = input.chk_tilesLayer
  if input.spr16 then
    self.sprSize = 32
  else
    self.sprSize = 8
  end

  -- store info of MSX screen mode
  local scrMode = ScreenMode:getInstance(input.scrMode)
  if scrMode == nil then
    return Error(E.NOT_MSX_FILE)
  end
  self.screen = scrMode.screen
  self.address = scrMode.address
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
    cel = self.spr:newCel(layer, self.spr.frames[1])
    self.imgSpr = cel.image
    self.imgSpr:clear()
  end

  -- Raw Tiles Layer
  if self.tilesLayer then
    layer = self.spr:newLayer()
    layer.name = "Layer Raw Tiles"
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
  if self.screen.palette ~= nil then
    local palette = self.spr.palettes[1]
    local r, g, b

    -- return if the in file palette is empty
    local empty = 0
    for i=1,self.screen.palette:len() do
      if self.screen.palette:byte(i)==0 then
        empty = empty + 1
      end
    end
    if empty==self.screen.palette:len() then
      return
    end

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

function ReaderTiled:new(input)
  o = Reader:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

function ReaderSC1:new(input)
  o = ReaderTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

function ReaderSC2:new(input)
  o = ReaderTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     ReaderSC3
-- ########################################################

ReaderSC3 = ReaderTiled:new()

function ReaderSC3:new(input)
  o = ReaderTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

function ReaderSC4:new(input)
  o = ReaderTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end

-- ============================
function ReaderSC4:getSpriteLayerAttribs(layer)
  return self:_getSpriteLayerAttribsMode2(layer)
end



-- ########################################################
--     ReaderBitmapRGB (abstract)
-- ########################################################

ReaderBitmapRGB = Reader:new()

function ReaderBitmapRGB:new(input)
  o = Reader:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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
function ReaderBitmapRGB:getSpriteLayerAttribs(layer)
  return self:_getSpriteLayerAttribsMode2(layer)
end



-- ########################################################
--     ReaderSC5
-- ########################################################

ReaderSC5 = ReaderBitmapRGB:new()

function ReaderSC5:new(input)
  o = ReaderBitmapRGB:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

function ReaderSC6:new(input)
  o = ReaderBitmapRGB:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

function ReaderSC7:new(input)
  o = ReaderSC5:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     ReaderSC8
-- ########################################################

ReaderSC8 = ReaderBitmapRGB:new()

function ReaderSC8:new(input)
  o = ReaderBitmapRGB:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

function ReaderBitmapYJK:new(input)
  o = Reader:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
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

  return ColorYJK:toRGB(y1, j, k), 
         ColorYJK:toRGB(y2, j, k), 
         ColorYJK:toRGB(y3, j, k), 
         ColorYJK:toRGB(y4, j, k)
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



-- ########################################################
--     ReaderSCA
-- ########################################################

ReaderSCA = ReaderBitmapYJK:new()

function ReaderSCA:new(input)
  o = ReaderBitmapYJK:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end

-- ============================
function ReaderSCA:getColorRGB(colorBytes)
  local y1, y2, y3, y4, j, k
  local c1, c2, c3, c4

  y1,y2,y3,y4,j,k = self:decodeYJK(colorBytes)

  if y1 & 1 == 1 then c1 = Color(self.spr.palettes[1]:getColor(y1>>1))
  else c1 = ColorYJK:toRGB(y1, j, k) end

  if y2 & 1 == 1 then c2 = Color(self.spr.palettes[1]:getColor(y2>>1))
  else c2 = ColorYJK:toRGB(y2, j, k) end

  if y3 & 1 == 1 then c3 = Color(self.spr.palettes[1]:getColor(y3>>1))
  else c3 = ColorYJK:toRGB(y3, j, k) end

  if y4 & 1 == 1 then c4 = Color(self.spr.palettes[1]:getColor(y4>>1))
  else c4 = ColorYJK:toRGB(y4, j, k) end

  return c1, c2, c3, c4
end



-- ########################################################
--     ReaderSCC
-- ########################################################

ReaderSCC = ReaderBitmapYJK:new()

function ReaderSCC:new(input)
  o = ReaderBitmapYJK:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end
