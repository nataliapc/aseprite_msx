-- ########################################################
--     Writers class
--  The Writer is the state machine that is responsible
--  for encoding a MSX file into a new file from the 
--  active Aseprite sprite.
-- ########################################################

Writer = {
  msxHeader = "\xFE\x00\x00",
  filename = nil,       -- filename of the MSX output file
  file = nil,           -- file writer from io
  fileSize = 0,         -- full file size
  spr = nil,            -- Sprite object
  img = nil,            -- Image object

  -- From ScreenMode classes
  address = {},
  screen = {},
}

-- ============================
function Writer:new(input)
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
function Writer:getInstance(data)
  if data.scrMode == 1 then return WriterSC1:new(data) end
  if data.scrMode == 2 then return WriterSC2:new(data) end
  if data.scrMode == 3 then return WriterSC3:new(data) end
  if data.scrMode == 4 then return WriterSC4:new(data) end
  if data.scrMode == 5 then return WriterSC5:new(data) end
  if data.scrMode == 6 then return WriterSC6:new(data) end
  if data.scrMode == 7 then return WriterSC7:new(data) end
  if data.scrMode == 8 then return WriterSC8:new(data) end
  if data.scrMode == 10 then return WriterSCA:new(data) end
  if data.scrMode == 12 then return WriterSCC:new(data) end
  return nil
end

-- ============================
function Writer:config(input)
  -- store info of MSX screen mode
  local scrMode = ScreenMode:getInstance(input.scrMode)
  if scrMode == nil then
    return Error(E.NOT_MSX_FILE)
  end
  self.screen = scrMode.screen
  self.address = scrMode.address
  self.fileSize = scrMode.fileSize

  self.spr = app.activeSprite
  self.img = self.spr.cels[1].image

  -- initializing object attributes
  self.filename = input.filename

  return nil
end

-- ============================
function Writer:encode()
  local err = nil
  self.file = io.open(self.filename, "w+b")

  -- write full file
  self.file:write(self.msxHeader)                       -- magic number and start 0x0000
  self.file:write(Binary.int16ToBytes(self.fileSize-1)) -- size of the VRAM dump in bytes
  self.file:write(string.char(0,0))                     -- empty 0x0000 (execution address)
  self.file:write(string.rep("\0", self.fileSize))      -- fullfill the file with 0x00

  -- dump image
  self:dumpImageToFile()

  -- fill sprite colors
  self:fillSpriteColors()

  -- fill sprite attributes
  self:fillSpriteAttribs()

  -- dump palette
  self:dumpImagePalette()

  self.file:flush()
  self.file:close()
  return err
end

-- ============================
function Writer:fillSpriteColors()
  if self.address.sprCol == nil then return end
  self:seekPos(self.address.sprCol.pos)
  self.file:write(string.rep("\x0f", self.address.sprCol.size))
end

-- ============================
function Writer:fillSpriteAttribs()
  local planes = self.address.sprAttr.size // 4
  self:seekPos(self.address.sprAttr.pos)

  for sprNum=0,planes-1 do
    self.file:write(string.char(0xd9, 0x00, sprNum*4, 0x0f))
  end
end

-- ============================
function Writer:dumpImagePalette()
  local palette = self.spr.palettes[1]
  local color = 0
  self:seekPos(self.address.palette.pos)

  for i=0,self.screen.maxColors-1 do
    color = palette:getColor(i)
    color.red = color.red >> 5
    color.green = color.green >> 5
    color.blue = color.blue >> 5
    self.file:write(string.char((color.red<<4) | color.blue, color.green))
  end
end

-- ########################################################
--     Aux functions

-- ============================
function Writer:seekPos(pos)
  self.file:seek("set", 7 + pos)
end



-- ########################################################
--     WriterTiled (abstract)
-- ########################################################

WriterTiled = Writer:new()

function WriterTiled:new(input)
  o = Writer:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end

-- ============================
function WriterTiled:dumpImageToFile()
end



-- ########################################################
--     WriterSC1
-- ########################################################

WriterSC1 = WriterTiled:new()

function WriterSC1:new(input)
  o = WriterTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSC2
-- ########################################################

WriterSC2 = WriterTiled:new()

function WriterSC2:new(input)
  o = WriterTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSC3
-- ########################################################

WriterSC3 = WriterTiled:new()

function WriterSC3:new(input)
  o = WriterTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSC4
-- ########################################################

WriterSC4 = WriterTiled:new()

function WriterSC4:new(input)
  o = WriterTiled:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterBitmapRGB (abstract)
-- ########################################################

WriterBitmapRGB = Writer:new()

function WriterBitmapRGB:new(input)
  o = Writer:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end

-- ============================
function WriterBitmapRGB:getBitsPerPixel()
  local ret = 0
  local colors = self.screen.maxColors
  
  repeat
    ret = ret + 1
    colors = colors // 2
  until colors==1

  return ret
end

-- ============================
function WriterBitmapRGB:dumpImageToFile()
  self:seekPos(self.address.tilePat.pos)

  self.bitsPerPixel = self:getBitsPerPixel()
  self.pixelsPerByte = 8 // self.bitsPerPixel

  for y=0,self.img.height-1 do
    for x=0,self.img.width-1,self.pixelsPerByte do
      self:dumpPixels(x, y)
    end
  end
end

-- ============================
function WriterBitmapRGB:dumpPixels(x, y)
  local byte1 = self.img:getPixel(x, y)
  local byte2 = self.img:getPixel(x+1, y)
  local bout = ((byte1 & 0x0f) << 4) | (byte2 & 0x0f)
  self.file:write(string.char(bout)) 
end



-- ########################################################
--     WriterSC5
-- ########################################################

WriterSC5 = WriterBitmapRGB:new()

function WriterSC5:new(input)
  o = WriterBitmapRGB:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSC6
-- ########################################################

WriterSC6 = WriterBitmapRGB:new()

function WriterSC6:new(input)
  o = WriterBitmapRGB:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSC7
-- ########################################################

WriterSC7 = WriterSC5:new()

function WriterSC7:new(input)
  o = WriterSC5:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSC8
-- ########################################################

WriterSC8 = WriterBitmapRGB:new()

function WriterSC8:new(input)
  o = WriterBitmapRGB:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterBitmapYJK (abstract)
-- ########################################################

WriterBitmapYJK = Writer:new()

function WriterBitmapYJK:new(input)
  o = Writer:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end

-- ============================
function WriterBitmapYJK:dumpImageToFile()
end



-- ########################################################
--     WriterSCA
-- ########################################################

WriterSCA = WriterBitmapYJK:new()

function WriterSCA:new(input)
  o = WriterBitmapYJK:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end



-- ########################################################
--     WriterSCC
-- ########################################################

WriterSCC = WriterBitmapYJK:new()

function WriterSCC:new(input)
  o = WriterBitmapYJK:new(input)
  setmetatable(o, self)
  self.__index = self
  return o
end
