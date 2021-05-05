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

-- Utils classes
dofile("./utils.lua")
-- MSX Screen modes definitions
dofile("./screen_modes.lua")
-- MSX images readers classes
dofile("./readers.lua")
-- MSX images writers classes
dofile("./writers.lua")



function init(globalPlugin)
  print("MSX image files plugin initialized...")

  plugin = globalPlugin

  -- initialize extension preferences
  if plugin.preferences.sprRender == nil then
    plugin.preferences.sprRender = true
  end
  if plugin.preferences.spr16 == nil then
    plugin.preferences.spr16 = true
  end
  if plugin.preferences.tilesLayer == nil then
    plugin.preferences.tilesLayer = true
  end
  if plugin.preferences.alert_pixelratio == nil then
    plugin.preferences.alert_pixelratio = true
  end

  -- add new option at "File" menu
  plugin:newCommand{
    id="msx_image_import",
    title="Import MSX image file",
    group="file_import",
    onclick=function()
      startLoadDialog()
    end
  }

  -- add new option at "File" menu
  plugin:newCommand{
    id="msx_image_export",
    title="Export MSX image file",
    group="file_export",
    onclick=function()
      --startSaveDialog()
      app.alert("Export MSX")
    end
  }

end

function exit(plugin)
  print("MSX image files plugin closing...")
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
      if ext == "1" then      -- ******************* SC1
        newType = "MSX Screen 1 tiled file"
        newInfo = "256x192 16 fixed colors"
        newTilesLayer = true
      elseif ext == "2" then  -- ******************* SC2
        newType = "MSX Screen 2 tiled file"
        newInfo = "256x192 16 fixed colors"
        newTilesLayer = true
      elseif ext == "3" then  -- ******************* SC3
        newType = "MSX Screen 3 file"
        newInfo = "64x48 16 fixed colors"
      elseif ext == "4" then  -- ******************* SC4
        newType = "MSX2 Screen 4 tiled file"
        newInfo = "256x192 16col from 512"
        newTilesLayer = true
      elseif ext == "5" then  -- ******************* SC5
        newType = "MSX2 Screen 5 file"
        newInfo = "256x212 16col from 512"
      elseif ext == "6" then  -- ******************* SC6
        newType = "MSX2 Screen 6 file"
        newInfo = "512x212 4col from 512"
      elseif ext == "7" then  -- ******************* SC7
        newType = "MSX2 Screen 7 file"
        newInfo = "512x212 16col from 512"
      elseif ext == "8" then  -- ******************* SC8
        newType = "MSX2 Screen 8 file"
        newInfo = "256x212 256 fixed col"
        newRenderSprites = false
      elseif ext == "A" then  -- ******************* SCA
        newType = "MSX2+ Screen 10 file"
        newInfo = "256x212 12k YJK + 16 RGB"
        newRenderSprites = false
      elseif ext == "C" then  -- ******************* SCC
        newType = "MSX2+ Screen 12 file"
        newInfo = "256x212 19k YJK Colors"
        newRenderSprites = false
      else  -- ******************* unknown
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

  local spritesEnabled = newRenderSprites and plugin.preferences.sprRender
  -- filetype
  dlg:modify{ id="file_type", text=newType }
  dlg:modify{ id="file_info", text=newInfo, visible=newInfoVisible }
  -- render sprites
  dlg:modify{ id="chk_sprRender",
    selected = spritesEnabled, 
    enabled = newRenderSprites
  }
  dlg:modify{ id="spr8", enabled = spritesEnabled }
  dlg:modify{ id="spr16", enabled = spritesEnabled }
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
function startLoadDialog()
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
                focus=true,
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
                selected=plugin.preferences.spr16==false,
                onclick = function()
                  plugin.preferences.spr16 = false
                end }
              :radio{ id="spr16",
                text="16x16 pixels",
                selected=plugin.preferences.spr16==true,
                onclick = function()
                  plugin.preferences.spr16 = true
                end }
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
            if app.version >= Version("1.2.27") then
              rdr.spr.pixelRatio = Size(1,2)
            elseif plugin.preferences.alert_pixelratio then
              local dlg = Dialog("ADVICE: Pixel aspect ratio")
              dlg
                :label{ text="You need to change manually the Pixel Aspect Ratio to (1:2)" }
                :newrow()
                :label{ text="Press [Ctrl+P] after closing this message." }
                :check{ id="chk_showAgain",
                  text="Always show this alert", 
                  selected=true,
                  onclick = function()
                    plugin.preferences.alert_pixelratio = dlg.data.chk_showAgain
                  end }
                :button{ id="ok", text="Close", focus=true }
                :show()
            end
          end
        end
      end
    end
  end

end
