--[[
  ####### Aseprite - MSX SC2 image Color Clash detector #######
  Copyright by Natalia Pujol (2021)
  This file is released under the terms of the MIT license.
--]]

-- ============================
function isColorClash_8x1(img, x, y)
  local c1, c2
  c1 = -1
  c2 = -1
  for ix=0,7 do
    col = img:getPixel(x+ix, y)
    if c1==-1 or c1==col then
      c1 = col
    elseif c2==-1 or c2==col then
      c2 = col
    else
      return true
    end
  end
  return false
end

-- ############################################################
local spr = app.activeSprite
local newSel = Selection(0,0, 0,0)

if not spr then
  return app.alert("There is no active sprite")
end

local img = spr.cels[1].image

for x=0,img.width-1,8 do
  for y=0,img.height-1 do
    if isColorClash_8x1(img, x, y)==true then
      local addSel = Selection(x,y, 8,1)
      newSel:add(addSel)
    end
  end
end
spr.selection = newSel