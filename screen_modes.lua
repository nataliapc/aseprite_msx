--[[
  ####### Aseprite - MSX image files importer script #######
  Copyright by Natalia Pujol (2021)
  This file is released under the terms of the MIT license.
--]]


-- ########################################################
--     ScreenMode class
--  Definition of the MSX Screen modes.
-- ########################################################
ScreenMode = {

  descName = "",        -- general name of the screen mode
  descFormat = "",      -- description of the screen format
  renderSprites = true, -- aseprite can render his sprites

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
    maxWidth  = 256,
    maxHeight = 192,
    maxColors = 16,
    paletteRes = "MSX1_DEFAULT",
    defaultPalette16 = false,

    -- data containers
    tileMap      = nil,   -- used by Screen 1..12
    tilePatterns = nil,   -- used by Screen 1..4
    tileColors   = nil,   -- used by Screen 1..4
    sprAttribs   = nil,   -- used by Screen 1..12
    sprPatterns  = nil,   -- used by Screen 1..12
    sprColors    = nil,   -- used by Screen 4..12
    palette      = nil,   -- used by Screen 4..7 and 10
  }

}

-- ============================
function ScreenMode:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

-- ============================
function ScreenMode:getInstance(mode)

  if mode == 1 then return ScreenMode1:new() end
  if mode == 2 then return ScreenMode2:new() end
  if mode == 3 then return ScreenMode3:new() end
  if mode == 4 then return ScreenMode4:new() end
  if mode == 5 then return ScreenMode5:new() end
  if mode == 6 then return ScreenMode6:new() end
  if mode == 7 then return ScreenMode7:new() end
  if mode == 8 then return ScreenMode8:new() end
  if mode == 10 then return ScreenMode10:new() end
  if mode == 12 then return ScreenMode12:new() end

  return nil
end



-- ########################################################
--     ScreenMode1
-- ########################################################
ScreenMode1 = ScreenMode:new()

-- ============================
function ScreenMode1:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX Screen 1 tiled file"
  o.descFormat = "256x192 16 fixed colors"
  o.fileSize = 0x4000

  o.screen.mode = 1
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 192
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX1_DEFAULT"

  o.address.tilePat = { pos=0x0000, size=0x0800 }
  o.address.tileMap = { pos=0x1800, size=0x300 }
  o.address.sprAttr = { pos=0x1b00, size=0x80 }
  o.address.tileCol = { pos=0x2000, size=0x20 }
  o.address.palette = { pos=0x2020, size=0x20 }
  o.address.sprPat  = { pos=0x3800, size=0x800 }

  return o
end



-- ########################################################
--     ScreenMode2
-- ########################################################
ScreenMode2 = ScreenMode:new()

-- ============================
function ScreenMode2:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX Screen 2 tiled file"
  o.descFormat = "256x192 16 fixed colors"
  o.fileSize = 0x4000

  o.screen.mode = 2
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 192
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX1_DEFAULT"

  o.address.tilePat = { pos=0x0000, size=0x1800 }
  o.address.tileMap = { pos=0x1800, size=0x300 }
  o.address.sprAttr = { pos=0x1b00, size=0x80 }
  o.address.palette = { pos=0x1b80, size=0x20 }
  o.address.tileCol = { pos=0x2000, size=0x1800 }
  o.address.sprPat  = { pos=0x3800, size=0x800 }

  return o
end



-- ########################################################
--     ScreenMode3
-- ########################################################
ScreenMode3 = ScreenMode:new()

-- ============================
function ScreenMode3:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX Screen 3 file"
  o.descFormat = "64x48 16 fixed colors"
  o.fileSize = 0x4000

  o.screen.mode = 3
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 192
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX1_DEFAULT"

  o.address.tileCol = { pos=0x0000, size=0x0600 } -- Block colors
  o.address.tileMap = { pos=0x0800, size=0x300 }
  o.address.palette = { pos=0x0f00, size=0x20 }
  o.address.sprAttr = { pos=0x1b00, size=0x80 }
  o.address.sprPat  = { pos=0x3800, size=0x800 }

  return o
end



-- ########################################################
--     ScreenMode4
-- ########################################################
ScreenMode4 = ScreenMode:new()

-- ============================
function ScreenMode4:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2 Screen 4 tiled file"
  o.descFormat = "256x192 16col from 512"
  o.fileSize = 0x4000

  o.screen.mode = 4
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 192
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX2_DEFAULT"

  o.address.tilePat = { pos=0x0000, size=0x1800 }
  o.address.tileMap = { pos=0x1800, size=0x300 }
  o.address.palette = { pos=0x1b80, size=0x20 }
  o.address.sprCol  = { pos=0x1c00, size=0x200 }
  o.address.sprAttr = { pos=0x1e00, size=0x80 }
  o.address.tileCol = { pos=0x2000, size=0x1800 }
  o.address.sprPat  = { pos=0x3800, size=0x800 }

  return o
end



-- ########################################################
--     ScreenMode5
-- ########################################################
ScreenMode5 = ScreenMode:new()

-- ============================
function ScreenMode5:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2 Screen 5 bitmap file"
  o.descFormat = "256x212 16col from 512"
  o.fileSize = 0x8000

  o.screen.mode = 5
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 212
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX2_DEFAULT"

  o.address.tilePat = { pos=0x0000, size=0x6a00 }
  o.address.sprCol  = { pos=0x7400, size=0x200 }
  o.address.sprAttr = { pos=0x7600, size=0x80 }
  o.address.palette = { pos=0x7680, size=0x20 }
  o.address.sprPat  = { pos=0x7800, size=0x800 }

  return o
end



-- ########################################################
--     ScreenMode6
-- ########################################################
ScreenMode6 = ScreenMode:new()

-- ============================
function ScreenMode6:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2 Screen 6 bitmap file"
  o.descFormat = "512x212 4col from 512"
  o.fileSize = 0x8000

  o.screen.mode = 6
  o.screen.maxWidth  = 512
  o.screen.maxHeight = 212
  o.screen.maxColors = 4
  o.screen.paletteRes = "MSX2_DEFAULT"

  o.address.tilePat = { pos=0x0000, size=0x6a00 }
  o.address.sprCol  = { pos=0x7400, size=0x200 }
  o.address.sprAttr = { pos=0x7600, size=0x80 }
  o.address.palette = { pos=0x7680, size=0x20 }
  o.address.sprPat  = { pos=0x7800, size=0x800 }

  return o
end



-- ########################################################
--     ScreenMode7
-- ########################################################
ScreenMode7 = ScreenMode:new()

-- ============================
function ScreenMode7:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2 Screen 7 bitmap file"
  o.descFormat = "512x212 16col from 512"
  o.fileSize = 0xfaa0

  o.screen.mode = 7
  o.screen.maxWidth  = 512
  o.screen.maxHeight = 212
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX2_DEFAULT"

  o.address.tilePat = { pos=0x0000, size=0xd400 }
  o.address.sprPat  = { pos=0xf000, size=0x800 }
  o.address.sprCol  = { pos=0xf800, size=0x200 }
  o.address.sprAttr = { pos=0xfa00, size=0x80 }
  o.address.palette = { pos=0xfa80, size=0x20 }

  return o
end



-- ########################################################
--     ScreenMode8
-- ########################################################
ScreenMode8 = ScreenMode:new()

-- ============================
function ScreenMode8:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2 Screen 8 bitmap file"
  o.descFormat = "256x212 256 fixed col"
  o.fileSize = 0xfaa0
  o.renderSprites = false

  o.screen.mode = 8
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 212
  o.screen.maxColors = 256
  o.screen.paletteRes = "MSX2_SC8"
  o.screen.defaultPalette16 = true

  o.address.tilePat = { pos=0x0000, size=0xd400 }
  o.address.sprPat  = { pos=0xf000, size=0x800 }
  o.address.sprCol  = { pos=0xf800, size=0x200 }
  o.address.sprAttr = { pos=0xfa00, size=0x80 }
  o.address.palette = { pos=0xfa80, size=0x20 }

  return o
end



-- ########################################################
--     ScreenMode10
-- ########################################################
ScreenMode10 = ScreenMode:new()

-- ============================
function ScreenMode10:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2+ Screen 10 bitmap file"
  o.descFormat = "256x212 12k YJK + 16 RGB"
  o.fileSize = 0xfaa0
  o.renderSprites = false

  o.screen.mode = 10
  o.screen.maxWidth  = 256
  o.screen.maxHeight = 212
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX2_DEFAULT"
  o.screen.defaultPalette16 = true

  o.address.tilePat = { pos=0x0000, size=0xd400 }
  o.address.sprPat  = { pos=0xf000, size=0x800 }
  o.address.sprCol  = { pos=0xf800, size=0x200 }
  o.address.sprAttr = { pos=0xfa00, size=0x80 }
  o.address.palette = { pos=0xfa80, size=0x20 }

  return o
end



-- ########################################################
--     ScreenMode12
-- ########################################################
ScreenMode12 = ScreenMode:new()

-- ============================
function ScreenMode12:new()
  o = ScreenMode:new()
  setmetatable(o, self)
  self.__index = self

  o.descName = "MSX2+ Screen 12 bitmap file"
  o.descFormat = "256x212 19k YJK colors"
  o.fileSize = 0xfaa0
  o.renderSprites = false

  o.screen.mode = 12
  o.screen.maxWidth = 256
  o.screen.maxHeight = 212
  o.screen.maxColors = 16
  o.screen.paletteRes = "MSX2_DEFAULT"
  o.screen.defaultPalette16 = true

  o.address.tilePat = { pos=0x0000, size=0xd400 }
  o.address.sprPat  = { pos=0xf000, size=0x800 }
  o.address.sprCol  = { pos=0xf800, size=0x200 }
  o.address.sprAttr = { pos=0xfa00, size=0x80 }
  o.address.palette = { pos=0xfa80, size=0x20 }

  return o
end
