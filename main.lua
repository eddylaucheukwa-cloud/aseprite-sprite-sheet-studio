local M
local E, P
local dialog
local clipboard = {}

local function report(action)
  local ok, message = pcall(action)
  if not ok then app.alert{ title='Sprite Sheet Studio', text=tostring(message) } end
  return ok, message
end

local function filePrompt(title, extension, filename, actionText, action, hint)
  local dlg=Dialog{title=title}
  if hint then dlg:label{text=hint}; dlg:newrow() end
  dlg:file{id='path',label='File:',filename=filename or '',filetypes={extension},
    open=extension=='png' and filename==nil,save=filename~=nil,title=title}
  dlg:newrow()
  dlg:button{text=actionText,onclick=function()
    local ok,done=report(function()
      assert(dlg.data.path and dlg.data.path~='', 'Choose a file first')
      return action(dlg.data.path)
    end)
    if ok and done~=false then dlg:close() end
  end}
  dlg:button{text='Cancel',onclick=function() dlg:close() end}
  dlg:show{autoscrollbars=true}
end

local function editor(state)
  if dialog then dialog:close() end
  local selected = { [1] = true }
  local focused, dragging = 1, nil
  local undoDepth, redoDepth = 0, 0
  local layout=state.layout
  local scale=math.min(32/math.max(layout.cellWidth,layout.cellHeight),320/layout.width,320/layout.height)
  local baseWidth=math.max(1,math.floor(layout.cellWidth*scale))
  local baseHeight=math.max(1,math.floor(layout.cellHeight*scale))
  local viewWidth,viewHeight=baseWidth*layout.columns,baseHeight*layout.rows
  local scrollX,scrollY=0,0
  local dlg = Dialog{ title='Arrange - '..layout.width..' x '..layout.height, onclose=function() P.closeAll() end }
  dialog = dlg

  local function geometry()
    local zoom=tonumber((dlg.data.zoom or ''):match('%d+')) or 100
    local width=math.max(1,math.floor(baseWidth*zoom/100))
    local height=math.max(1,math.floor(baseHeight*zoom/100))
    local gridWidth,gridHeight=width*layout.columns,height*layout.rows
    scrollX=math.max(0,math.min(scrollX,gridWidth-viewWidth))
    scrollY=math.max(0,math.min(scrollY,gridHeight-viewHeight))
    local x=gridWidth<=viewWidth and math.floor((viewWidth-gridWidth)/2) or -scrollX
    local y=gridHeight<=viewHeight and math.floor((viewHeight-gridHeight)/2) or -scrollY
    return width,height,x,y
  end

  local function refresh()
    local count = 0
    local occupied = 0
    for slot = 1, layout.capacity do if state.slots[slot] then occupied = occupied + 1 end end
    dlg:modify{ id='capacity', text=occupied .. ' / '..layout.capacity..' sprites' }
    for slot in pairs(selected) do
      count = count + 1
    end
    dlg:modify{ id='selected', text=count == 1 and ('Cell ' .. focused) or (count .. ' selected') }
    dlg:modify{ id='undo', enabled=undoDepth > 0 }
    dlg:modify{ id='redo', enabled=redoDepth > 0 }
    dlg:repaint()
    app.refresh()
    P.refreshAll()
  end

  local function mutate(action, recordsEdit)
    local changed
    report(function()
      app.activeSprite = state.sprite
      state = M.fromSprite(state.sprite)
      changed = action()
      if recordsEdit and changed ~= false then undoDepth=undoDepth+1; redoDepth=0 end
      refresh()
    end)
    return changed
  end

  local function cellAt(ev)
    if ev.x<0 or ev.y<0 or ev.x>=viewWidth or ev.y>=viewHeight then return nil end
    local width,height,x,y=geometry()
    local cx,cy=ev.x-x,ev.y-y
    if cx<0 or cy<0 or cx>=width*layout.columns or cy>=height*layout.rows then return nil end
    return math.floor(cy/height)*layout.columns+math.floor(cx/width)+1
  end

  local function saveTo(path, png)
    return mutate(function()
      assert(path and path ~= '', 'Choose an output filename first')
      assert(not state.sourcePaths[path:lower()], 'Original input PNGs are protected. Choose a different output file.')
      if app.fs.isFile(path) then
        if app.alert{ title='Replace output?', text='Replace ' .. app.fs.fileName(path) .. '?', buttons={'Replace', 'Cancel'} } ~= 1 then return false end
      end
      if png then M.exportPNG(state, path)
      else
        assert(path:lower():match('%.aseprite$'), 'Choose an .aseprite filename for the editable project')
        state.sprite:saveAs(path)
      end
      dlg:modify{ id='status', text='Saved.' }
      return true
    end)
  end

  local function undo()
    if undoDepth > 0 then mutate(function()
      app.command.Undo(); state=M.fromSprite(state.sprite)
      undoDepth=undoDepth-1; redoDepth=redoDepth+1
    end) end
  end

  local function redo()
    if redoDepth > 0 then mutate(function()
      app.command.Redo(); state=M.fromSprite(state.sprite)
      redoDepth=redoDepth-1; undoDepth=undoDepth+1
    end) end
  end

  local function copy()
    mutate(function()
      local entries = M.copy(state, selected)
      assert(#entries > 0, 'Select a sprite to copy first')
      clipboard = entries
      dlg:modify{ id='status', text='Copied '..#entries..'. Choose a cell and paste.' }
    end)
  end

  local function paste()
    mutate(function()
      local targets = M.paste(state, clipboard, focused)
      selected = {}
      for _, slot in ipairs(targets) do selected[slot] = true end
      focused = targets[1]
      dlg:modify{ id='status', text='Pasted '..#targets..'.' }
      return true
    end, true)
  end

  local function remove()
    mutate(function()
      local changed = M.remove(state, selected)
      dlg:modify{ id='status', text='Deleted. Ctrl+Z to restore.' }
      return changed
    end, true)
  end

  dlg:button{ text='Add folder...', onclick=function()
    filePrompt('Add folder','png',nil,'Add',function(path)
      return mutate(function()
        state=M.addFolder(state,app.fs.filePath(path))
        dlg:modify{id='status',text='Folder added.'}
        return true
      end,true)==true
    end,'Choose one PNG; all PNGs in its folder will be added.')
  end}
  dlg:button{ text='Animate', onclick=function()
    report(function() P.preview(M,E,function() return M.fromSprite(state.sprite) end,function() return selected end) end)
  end }
  dlg:button{ text='Recolor', onclick=function()
    report(function()
      P.recolor(M,E,function() return M.fromSprite(state.sprite) end,function() return selected end,
        function() return focused end,function(cells,settings)
          return mutate(function() return E.apply(state,cells,settings) end,true)
        end)
    end)
  end }
  dlg:newrow()
  dlg:button{ id='undo', text='Undo', onclick=undo }
  dlg:button{ id='redo', text='Redo', onclick=redo }
  dlg:button{ text='Flip H', onclick=function() mutate(function() return M.flip(state, selected, false) end, true) end }
  dlg:button{ text='Flip V', onclick=function() mutate(function() return M.flip(state, selected, true) end, true) end }
  dlg:newrow()
  dlg:label{ id='capacity', text='' }
  dlg:label{ id='selected', text='' }
  dlg:label{text='Zoom:'}
  dlg:combobox{id='zoom',options={'Fit','150%','200%','300%'},option='Fit',onchange=function()
    dragging=nil
    local width,height=geometry()
    scrollX=(((focused-1)%layout.columns)+0.5)*width-viewWidth/2
    scrollY=(math.floor((focused-1)/layout.columns)+0.5)*height-viewHeight/2
    dlg:repaint()
  end}
  dlg:newrow()
  dlg:canvas{
    id='grid', width=viewWidth, height=viewHeight, autoscaling=false,
    onpaint=function(ev)
      local gc = ev.context
      viewWidth,viewHeight=gc.width,gc.height
      local previewWidth,previewHeight,originX,originY=geometry()
      for slot = 1, layout.capacity do
        local x = originX+((slot-1) % layout.columns) * previewWidth
        local y = originY+math.floor((slot-1) / layout.columns) * previewHeight
        if x<viewWidth and y<viewHeight and x+previewWidth>0 and y+previewHeight>0 then
        for cy=0,previewHeight-1,8 do
          for cx=0,previewWidth-1,8 do
            local v = ((cx/8 + cy/8) % 2 == 0) and 54 or 69
            gc.color = Color{ r=v, g=v, b=v }
            gc:fillRect(Rectangle(x+cx,y+cy,math.min(8,previewWidth-cx),math.min(8,previewHeight-cy)))
          end
        end
        local cel = state.slots[slot]
        if cel then
          local image=M.cellImage(state,slot)
          gc:drawImage(image, image.bounds, Rectangle(x,y,previewWidth,previewHeight))
        end
        gc.color = selected[slot] and Color{r=255,g=200,b=60} or Color{r=105,g=105,b=105}
        gc:strokeRect(Rectangle(x,y,previewWidth,previewHeight))
        if selected[slot] and previewWidth>2 and previewHeight>2 then gc:strokeRect(Rectangle(x+1,y+1,previewWidth-2,previewHeight-2)) end
        gc.color = Color{r=230,g=230,b=230}
        if previewWidth>=24 and previewHeight>=16 then gc:fillText(tostring(slot), x+3, y+2) end
        end
      end
    end,
    onmousedown=function(ev)
      if ev.button ~= MouseButton.LEFT then return end
      local slot = cellAt(ev)
      if not slot then return end
      focused = slot
      if ev.shiftKey then
        selected[slot] = not selected[slot] or nil
        dragging = nil
      else selected = {[slot]=true}; dragging=slot end
      refresh()
    end,
    onmouseup=function(ev)
      local target, origin = cellAt(ev), dragging
      dragging = nil
      if target and origin and target ~= origin then
        mutate(function()
          local changed = M.swap(state, origin, target)
          focused = target; selected = {[target]=true}
          return changed
        end, true)
      end
    end,
    onwheel=function(ev)
      dragging=nil
      local width,height=geometry()
      if ev.shiftKey then scrollX=scrollX+((ev.deltaY or 0)+(ev.deltaX or 0))*width
      else
        scrollY=scrollY+(ev.deltaY or 0)*height
        scrollX=scrollX+(ev.deltaX or 0)*width
      end
      dlg:repaint()
    end,
    onkeydown=function(ev)
      local code = ev.code or ('Key' .. (ev.key or ''):upper())
      local action
      if ev.ctrlKey and not ev.altKey then
        if code == 'KeyZ' then action = ev.shiftKey and redo or undo
        elseif code == 'KeyY' then action = redo
        elseif code == 'KeyC' then action = copy
        elseif code == 'KeyV' then action = paste end
      elseif not ev.ctrlKey and not ev.altKey and not ev.metaKey then
        if code == 'Delete' then action = remove
        elseif code == 'KeyH' then action = function() mutate(function() return M.flip(state, selected, false) end, true) end
        elseif code == 'KeyV' then action = function() mutate(function() return M.flip(state, selected, true) end, true) end end
      end
      if action then
        if ev.stopPropagation then ev:stopPropagation() end
        if (ev.repeatCount or 0) == 0 then action() end
      end
    end
  }
  dlg:newrow()
  dlg:button{ text='All', onclick=function()
    selected = {}
    for slot = 1, layout.capacity do if state.slots[slot] then selected[slot] = true end end
    refresh()
  end }
  dlg:button{ text='None', onclick=function() selected = {}; refresh() end }
  dlg:button{ text='Copy', onclick=copy }
  dlg:button{ text='Paste', onclick=paste }
  dlg:button{ text='Delete', onclick=remove }
  dlg:newrow()
  dlg:label{text='Shift: multi-select | Drag: swap'}
  dlg:newrow()
  dlg:button{text='Save project...',onclick=function()
    filePrompt('Save project','aseprite','sprite-sheet.aseprite','Save',function(path) return saveTo(path,false)==true end)
  end}
  dlg:button{text='Export PNG...',onclick=function()
    filePrompt('Export PNG','png','sprite-sheet.png','Export',function(path) return saveTo(path,true)==true end)
  end}
  dlg:button{text='Shortcuts',onclick=function()
    app.alert{title='Shortcuts',text={'Shift + click: select several sprites','Drag: swap cells','Ctrl+Z / Ctrl+Y: undo / redo',
      'Ctrl+C / Ctrl+V: copy / paste','Delete: remove sprites','H / V: flip','Zoom: larger thumbnails; Fit: entire sheet',
      'Wheel: scroll; Shift + wheel: scroll sideways','I: pick a color in Recolor'}}
  end}
  dlg:newrow()
  dlg:label{ id='status', text='' }
  dlg:newrow()
  dlg:button{ text='Close', onclick=function() dlg:close() end }
  refresh()
  dlg:show{ wait=false, autoscrollbars=true }
  -- Aseprite cannot call canvas paint handlers until the dialog is shown.
  dlg:repaint()
end

local function start()
  local layout=M.layout(app.activeSprite and app.activeSprite.properties.sheetBuilderLayout)
  local picker = Dialog{ title='Sprite Sheet Studio' }
  local function summary()
    picker:modify{id='layout',text=layout.cellWidth..'x'..layout.cellHeight..' sprites | '..layout.columns..'x'..layout.rows..' grid | '..layout.width..'x'..layout.height..' px'}
  end
  picker:label{id='layout',text=''}
  picker:newrow()
  picker:button{text='Sheet size...',onclick=function()
    local size=Dialog{title='Sheet size'}
    local function read()
      return M.layout{cellWidth=size.data.cellWidth,cellHeight=size.data.cellHeight,columns=size.data.columns,rows=size.data.rows}
    end
    local function update()
      local ok,nextLayout=pcall(read)
      size:modify{id='result',text=ok and (nextLayout.width..'x'..nextLayout.height..' px | '..nextLayout.capacity..' cells') or 'Enter a valid size'}
      size:modify{id='use',enabled=ok}
    end
    for _,field in ipairs({{'cellWidth','Sprite width:'},{'cellHeight','Sprite height:'},{'columns','Columns:'},{'rows','Rows:'}}) do
      size:number{id=field[1],label=field[2],text=tostring(layout[field[1]]),decimals=0,onchange=update}
      size:newrow()
    end
    size:label{id='result',text=''}
    size:newrow()
    size:button{id='use',text='Use size',onclick=function()
      report(function() layout=read(); summary(); size:close() end)
    end}
    size:button{text='Cancel',onclick=function() size:close() end}
    update(); size:show{autoscrollbars=true}
  end}
  picker:button{ text='Import folder...', onclick=function()
    picker:close()
    filePrompt('Import folder','png',nil,'Import',function(path)
      local state=M.importFolder(app.fs.filePath(path),layout)
      editor(state); return true
    end,'Choose one PNG; all PNGs in its folder will be imported.')
  end}
  picker:button{ text='Edit open sheet',enabled=app.activeSprite~=nil,onclick=function()
    report(function()
      local sprite = app.activeSprite
      assert(sprite, 'Open your PNG or saved .aseprite sheet first')
      local state = M.editSheet(sprite,layout)
      picker:close(); editor(state)
    end)
  end }
  picker:button{ text='Close',onclick=function() picker:close() end }
  summary()
  picker:show{ autoscrollbars=true }
end

function init(plugin)
  M = dofile(app.fs.joinPath(plugin.path, 'core.lua'))
  E = dofile(app.fs.joinPath(plugin.path, 'effects.lua'))
  P = dofile(app.fs.joinPath(plugin.path, 'panels.lua'))
  plugin:newCommand{
    id='SpriteSheetStudio', title='Sprite Sheet Studio...', group='file_import_1',
    onclick=function() report(start) end
  }
end

function exit(plugin)
  if P then P.closeAll() end
  if dialog then dialog:close(); dialog=nil end
end

return {
  show=function(path)
    M=dofile(app.fs.joinPath(path, 'core.lua'))
    E=dofile(app.fs.joinPath(path, 'effects.lua'))
    P=dofile(app.fs.joinPath(path, 'panels.lua'))
    report(start)
  end
}
