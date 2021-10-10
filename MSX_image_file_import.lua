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
local version = "v1.2"
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
      startSaveDialog()
    end
  }

end

function exit(plugin)
  print("MSX image files plugin closing...")
end



-- ########################################################
--     Dialog management
-- ########################################################

function showLoadFileInfo(dlg)
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
    local scrMode = getFileInfo(dlg.data.filename)
    if scrMode ~= nil then
      newType = scrMode.descName
      newInfo = scrMode.descFormat
      ret = scrMode.screen.mode
      newTilesLayer = ret==1 or ret==2 or ret==4
      newRenderSprites = ret < 8
    end
  end

  if newInfo ~= "" then
    newInfoVisible = true
  else
    newInfo = "<unknown file format>"
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

function showSaveFileInfo(dlg)
  local ret = nil
  local newType = "<unknown file format>"
  local newInfo = ""
  local newBtnOkEnabled = true

  if dlg.data.filename == nil then
    newType = "<none>"
    newBtnOkEnabled = false
  else
    local scrMode = getFileInfo(dlg.data.filename)
    if scrMode ~= nil then
      newType = scrMode.descName
      newInfo = scrMode.descFormat
      ret = scrMode.screen.mode
    end
  end

  if newInfo ~= "" then
    newInfoVisible = true
  else
    newInfo = "<unknown file format>"
    newBtnOkEnabled = false
    ret = nil
  end

  -- filetype
  dlg:modify{ id="file_type", text=newType }
  dlg:modify{ id="file_info", text=newInfo, visible=newInfoVisible }
  -- buttons
  dlg:modify{ id="ok", enabled=newBtnOkEnabled }

  return ret
end

function getFileInfo(filename)
  local ret = nil
  local ext = filename:upper():sub(-4)

  if ext:sub(1,3) == ".SC" then
    ext = ext:sub(-1)
    ret = tonumber("0x"..ext)
    return ScreenMode:getInstance(ret)
  end
  return nil
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
                onchange=function() scrMode = showLoadFileInfo(dlg) end }
              :separator()
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
              :label{ label="-----------------", text="----------------------------------" }
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
      local rdr = Reader:getInstance(data)

      if rdr ~= nil then
        local err = nil
        if rdr.className ~= nil and rdr.className ~= Err.className then
          err = rdr:decode()
        else 
          err = rdr
        end
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

function startSaveDialog()
  if not app.isUIAvailable then
    return
  end

  if app.activeSprite==nil then
    app.alert("  No active image found!  ")
    return
  end

  local w = app.activeSprite.width
  local h = app.activeSprite.height
  local ext = nil;
  if w==512 and h==212 then
    ext = { "SC6", "SC7" }
  elseif (w==256) then
    if h==212 then
      ext = { "SC5", "SC8", "SCA", "SCC" }
    elseif h==192 then
      ext = { "SC1", "SC2", "SC3", "SC4" }
    end
  end
  if ext==nil then
    app.alert("  Current valid image sizes are: 256x192, 256x212 and 512x212  ")
    return
  end

  local layers = {}
  for i=1,#app.activeSprite.layers do
    layers[i] = app.activeSprite.layers[i].name
  end

  local scrMode = 0
  local dlg = nil
  local data = nil
  local cancel = false
  local info1 = app.activeSprite.width.."x"..app.activeSprite.height
  local info2 = ""
  if app.activeSprite.colorMode == ColorMode.INDEXED then
    info1 = info1.." Indexed image"
    info2 = countColors(app.activeSprite).." solid colors"
  else
    info1 = info1.." Bitmap image"
  end
  repeat
    dlg = Dialog("Export MSX image file "..version)
    data = dlg
              :label{ label="Current image:", text=info1 }
              :newrow()
              :label{ text=info2, visible=info2~="" }
              :separator()
              :file{
                id="filename",
                label="MSX image file:",
                open=false,
                save=true,
                focus=true,
                filetypes=ext,
                onchange=function() scrMode = showSaveFileInfo(dlg) end }
              :combobox{ id="layer", label="Layer to save:",
                option=layers[1],
                options=layers }
              :separator()
              :label{ id="file_type", label="Selected format:", text="<none>" }
              :newrow()
              :label{ id="file_info", text="", visible=false }
              :label{ label="-----------------", text="----------------------------------" }
              :button{ id="ok", text="Ok", enabled=false }
              :button{ id="cancel", text="Cancel" }
              :label{ label="by NataliaPC'2021" }
              :show().data

    data.scrMode = scrMode
    if data.ok and data.filename == "" then 
      app.alert("  Select an output file first  ")
    end
  until data.filename ~= "" or data.cancel or (data.cancel or data.ok)==false

  if data.ok then
    -- From here we can write sprite.filename with our MSX writer.
    local wrt = Writer:getInstance(data)

    if wrt ~= nil then
      local err = nil
      if wrt.className ~= nil and wrt.className ~= Err.className then
        err = wrt:encode()
      else 
        err = wrt
      end
      if err ~= nil then
        app.alert(err:string())
      end
    end
  end
end
