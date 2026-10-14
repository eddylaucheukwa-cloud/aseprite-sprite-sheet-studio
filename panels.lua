local P = {}
local previewDialog, recolorDialog
local previewRefresh, recolorRefresh

local function report(action)
  local ok, result = pcall(action)
  if not ok then app.alert{title='Sprite Sheet Studio',text=tostring(result)} end
  return ok, result
end

local function checker(gc, width, height)
  for y=0,height-1,8 do
    for x=0,width-1,8 do
      local v=(x/8+y/8)%2 == 0 and 54 or 69
      gc.color=Color{r=v,g=v,b=v}
      gc:fillRect(Rectangle(x,y,8,8))
    end
  end
end

local function fit(width,height,boxWidth,boxHeight,offset)
  local scale=math.min(boxWidth/width,boxHeight/height)
  local w,h=math.max(1,math.floor(width*scale)),math.max(1,math.floor(height*scale))
  return Rectangle((offset or 0)+math.floor((boxWidth-w)/2),math.floor((boxHeight-h)/2),w,h)
end

local function sampleAt(image,box,x,y)
  if x<box.x or y<box.y or x>=box.x+box.width or y>=box.y+box.height then return end
  return math.floor((x-box.x)*image.width/box.width),math.floor((y-box.y)*image.height/box.height)
end

function P.closeAll()
  if previewDialog then previewDialog:close(); previewDialog=nil end
  if recolorDialog then recolorDialog:close(); recolorDialog=nil end
end

function P.refreshAll()
  if previewRefresh then report(previewRefresh) end
  if recolorRefresh then recolorRefresh() end
end

function P.preview(M,E,getState,getSelected)
  local layout=getState().layout
  if previewDialog then previewDialog:close() end
  local timer, frames, index, image, appliedRange = nil, {}, 1, nil, nil
  local dlg=Dialog{title='Animate',onclose=function()
    if timer then timer:stop() end
    previewRefresh=nil
  end}
  previewDialog=dlg
  local function occupied()
    local result={}
    local state=getState()
    for slot=1,layout.capacity do if state.slots[slot] then result[#result+1]=slot end end
    return result
  end
  local initialSlots={}
  for _,slot in ipairs(occupied()) do if getSelected()[slot] then initialSlots[#initialSlots+1]=slot end end
  if #initialSlots==0 then initialSlots=occupied() end
  local initial=E.frameText(initialSlots)
  if initial=='' then initial='1' end
  local function refresh()
    if #frames==0 then return end
    image=M.cellImage(getState(),frames[index])
    dlg:modify{id='frame',min=1,max=#frames,value=index}
    dlg:modify{id='position',text='Cell '..frames[index]..' | '..index..' / '..#frames}
    dlg:modify{id='play',text=timer and timer.isRunning and 'Pause' or 'Play'}
    dlg:repaint()
  end
  previewRefresh=refresh
  local function setRange()
    local nextFrames=E.frames(dlg.data.frames,layout.capacity)
    if timer then timer:stop() end
    frames=nextFrames; index=1
    appliedRange=dlg.data.frames
    refresh()
  end
  timer=Timer{interval=1/8,ontick=function()
    local ok=report(function()
      local keepPlaying
      index,keepPlaying=E.advance(index,#frames,dlg.data.loop)
      if not keepPlaying then timer:stop() end
      refresh()
    end)
    if not ok then timer:stop() end
  end}
  dlg:entry{id='frames',label='Frames:',text=initial}
  dlg:button{text='Set',onclick=function() report(setRange) end}
  dlg:newrow()
  dlg:button{text='Selected',onclick=function()
    report(function()
      local slots={}
      for slot=1,layout.capacity do if getSelected()[slot] then slots[#slots+1]=slot end end
      assert(#slots>0,'Select cells in the sheet first')
      dlg:modify{id='frames',text=E.frameText(slots)}; setRange()
    end)
  end}
  dlg:button{text='All',onclick=function()
    report(function()
      local slots=occupied(); assert(#slots>0,'The sheet is empty')
      dlg:modify{id='frames',text=E.frameText(slots)}; setRange()
    end)
  end}
  dlg:newrow()
  dlg:canvas{id='animation',width=192,height=192,autoscaling=false,onpaint=function(ev)
    checker(ev.context,192,192)
    if image then ev.context:drawImage(image,image.bounds,fit(image.width,image.height,192,192)) end
  end}
  dlg:newrow()
  dlg:label{id='position',text=''}
  dlg:newrow()
  dlg:slider{id='frame',label='Frame:',min=1,max=layout.capacity,value=1,onchange=function()
    timer:stop(); index=dlg.data.frame; report(refresh)
  end}
  dlg:newrow()
  dlg:button{text='Previous',onclick=function()
    timer:stop(); index=(index-2)%#frames+1; report(refresh)
  end}
  dlg:button{id='play',text='Play',onclick=function()
    report(function()
      if timer.isRunning then timer:stop(); refresh()
      else
        if dlg.data.frames~=appliedRange or (index==#frames and not dlg.data.loop) then setRange() end
        timer.interval=1/dlg.data.fps; timer:start(); refresh()
      end
    end)
  end}
  dlg:button{text='Next',onclick=function()
    timer:stop(); index=index%#frames+1; report(refresh)
  end}
  dlg:newrow()
  dlg:slider{id='fps',label='FPS:',min=1,max=60,value=8,onchange=function()
    local running=timer.isRunning; timer:stop(); timer.interval=1/dlg.data.fps
    if running then timer:start() end
  end}
  dlg:check{id='loop',text='Loop',selected=true}
  dlg:newrow()
  dlg:button{text='Close',onclick=function() dlg:close() end}
  setRange()
  dlg:show{wait=false,autoscrollbars=true}
  dlg:repaint()
  return dlg
end

function P.recolor(M,E,getState,getSelected,getFocused,commit)
  local layout=getState().layout
  local originalBox=fit(layout.cellWidth,layout.cellHeight,128,128)
  local adjustedBox=fit(layout.cellWidth,layout.cellHeight,128,128,128)
  if recolorDialog then recolorDialog:close() end
  local fullDialog, colorDialog, colorRefresh
  local dlg=Dialog{title='Recolor',onclose=function()
    recolorRefresh=nil
    if fullDialog then fullDialog:close() end
    if colorDialog then colorDialog:close() end
  end}
  recolorDialog=dlg
  local before, after, sampleSlot, busy, previewSlots, fullBefore, fullAfter
  local previewIndex, pickMode = 1, false
  local scopeCells={}
  local function settings()
    local d=dlg.data
    return {hue=d.hue,saturation=d.saturation,brightness=d.brightness,contrast=d.contrast,
      pickedOnly=d.match=='Picked color',source=d.source,tolerance=d.tolerance,
      replace=d.replace,target=d.target}
  end
  local function selected()
    if dlg.data.scope=='Selection' then return getSelected() end
    local all={}; for slot=1,layout.capacity do all[slot]=true end; return all
  end
  local function refresh()
    if busy then return end
    report(function()
      local state=getState()
      scopeCells=selected()
      previewSlots={}
      for slot=1,layout.capacity do
        if scopeCells[slot] and state.slots[slot] then previewSlots[#previewSlots+1]=slot end
      end
      local found
      for i,slot in ipairs(previewSlots) do if slot==sampleSlot then found=i end end
      if not found then
        for i,slot in ipairs(previewSlots) do if slot==getFocused() then found=i end end
      end
      previewIndex=found or 1
      sampleSlot=previewSlots[previewIndex] or getFocused() or 1
      before=M.cellImage(state,sampleSlot)
      local matched=0
      local adjustment=settings()
      if scopeCells[sampleSlot] then after,matched=E.transform(before,adjustment)
      else after=Image(before) end
      dlg:modify{id='sampleFrame',min=1,max=math.max(1,#previewSlots),value=previewIndex,enabled=#previewSlots>0}
      dlg:modify{id='frameLabel',text=#previewSlots>0 and
        ('Cell '..sampleSlot..' | '..previewIndex..' / '..#previewSlots) or 'Select sprites in Arrange.'}
      dlg:modify{id='matchCount',text=matched..' matching pixels'}
      local matching=dlg.data.match=='Picked color'
      dlg:modify{id='source',enabled=matching}
      dlg:modify{id='sourcePicker',enabled=matching}
      dlg:modify{id='tolerance',enabled=matching}
      dlg:modify{id='target',enabled=dlg.data.replace}
      dlg:modify{id='targetPicker',enabled=dlg.data.replace}
      dlg:modify{id='apply',enabled=#previewSlots>0}
      if fullDialog then
        fullBefore=Image(layout.width,layout.height,ColorMode.RGB)
        fullAfter=Image(layout.width,layout.height,ColorMode.RGB)
        for slot=1,layout.capacity do
          local cell=M.cellImage(state,slot)
          fullBefore:drawImage(cell,M.position(slot,layout))
          if scopeCells[slot] then cell=E.transform(cell,adjustment) end
          fullAfter:drawImage(cell,M.position(slot,layout))
        end
        fullDialog:repaint()
      end
      dlg:repaint()
      if colorRefresh then colorRefresh() end
    end)
  end
  local function reset()
    busy=true
    for _,id in ipairs({'hue','saturation','brightness','contrast'}) do dlg:modify{id=id,value=0} end
    dlg:modify{id='replace',selected=false}
    busy=false; refresh()
  end
  local function pick(image,x,y)
    if not image or x<0 or y<0 or x>=image.width or y>=image.height then return end
    local pixel=image:getPixel(x,y)
    local pc=app.pixelColor
    if pc.rgbaA(pixel)==0 then return end
    busy=true
    dlg:modify{id='source',color=Color{r=pc.rgbaR(pixel),g=pc.rgbaG(pixel),b=pc.rgbaB(pixel)}}
    dlg:modify{id='match',option='Picked color'}
    busy=false; refresh()
  end
  local function picking(enabled)
    pickMode=enabled
    dlg:modify{id='pickColor',text=enabled and 'Picking (Esc)' or 'Pick (I)'}
  end
  local function key(ev)
    if ev.ctrlKey or ev.altKey or ev.metaKey then return end
    local code=ev.code or ('Key'..(ev.key or ''):upper())
    if code=='KeyI' or (code=='Escape' and pickMode) then
      if ev.stopPropagation then ev:stopPropagation() end
      if (ev.repeatCount or 0)==0 then picking(code=='KeyI') end
    end
  end
  local function fullPreview()
    if fullDialog then fullDialog:close() end
    local box=fit(layout.width,layout.height,160,400)
    local sheetWidth,sheetHeight=box.width,box.height
    local scaleX,scaleY=sheetWidth/layout.width,sheetHeight/layout.height
    fullDialog=Dialog{title='Sheet preview',onclose=function() fullDialog=nil end}
    fullDialog:label{text='Original                               Preview'}
    fullDialog:newrow()
    fullDialog:label{text='Outline: selected | Click: inspect | I: pick'}
    fullDialog:newrow()
    fullDialog:canvas{id='fullSheet',width=sheetWidth*2,height=sheetHeight,autoscaling=false,
      onpaint=function(ev)
        local gc=ev.context
        checker(gc,sheetWidth*2,sheetHeight)
        if fullBefore then gc:drawImage(fullBefore,fullBefore.bounds,Rectangle(0,0,sheetWidth,sheetHeight)) end
        if fullAfter then gc:drawImage(fullAfter,fullAfter.bounds,Rectangle(sheetWidth,0,sheetWidth,sheetHeight)) end
        for slot=1,layout.capacity do
          local p=M.position(slot,layout)
          if scopeCells[slot] then
            gc.color=Color{r=255,g=200,b=60}
            local x,y=math.floor(p.x*scaleX),math.floor(p.y*scaleY)
            local w,h=math.max(1,math.floor((p.x+layout.cellWidth)*scaleX)-x),math.max(1,math.floor((p.y+layout.cellHeight)*scaleY)-y)
            gc:strokeRect(Rectangle(x,y,w,h))
            gc:strokeRect(Rectangle(x+sheetWidth,y,w,h))
          end
        end
      end,
      onmousedown=function(ev)
        if ev.button~=MouseButton.LEFT or ev.x<0 or ev.x>=sheetWidth*2 or ev.y<0 or ev.y>=sheetHeight then return end
        local x=math.floor((ev.x%sheetWidth)/scaleX)
        local y=math.floor(ev.y/scaleY)
        local slot=math.floor(y/layout.cellHeight)*layout.columns+math.floor(x/layout.cellWidth)+1
        if scopeCells[slot] then sampleSlot=slot; refresh() end
        if pickMode then pick(fullBefore,x,y) end
      end,onkeydown=key}
    fullDialog:newrow()
    fullDialog:button{text='Close',onclick=function() fullDialog:close() end}
    refresh()
    fullDialog:show{wait=false,autoscrollbars=true}
    fullDialog:repaint()
    fullDialog:modify{id='fullSheet',focus=true}
  end
  local function colorPicker(id)
    if colorDialog then
      colorDialog:modify{id='editing',option=id=='source' and 'Match color' or 'Replacement color'}
      colorRefresh()
      return
    end
    local h,s,v,gradient,gradientHue,dragging
    local width,height=240,240
    local picker=Dialog{title='Color',onclose=function()
      colorDialog=nil; colorRefresh=nil
    end}
    colorDialog=picker
    local function editing() return picker.data.editing=='Match color' and 'source' or 'target' end
    local function colorHex(c) return string.format('#%02X%02X%02X',c.red,c.green,c.blue) end
    colorRefresh=function()
      local color=dlg.data[editing()]
      h,s,v=color.hsvHue,color.hsvSaturation,color.hsvValue
      if gradientHue~=h then
        gradient=Image(width,height,ColorMode.RGB)
        for y=0,height-1 do for x=0,width-1 do
          gradient:drawPixel(x,y,Color{hue=h,saturation=x/(width-1),value=1-y/(height-1)}.rgbaPixel)
        end end
        gradientHue=h
      end
      picker:modify{id='hex',text=colorHex(color)}
      picker:modify{id='hsv',text=string.format('H %.0f | S %.0f%% | V %.0f%%',h,s*100,v*100)}
      picker:repaint()
    end
    local function choose(color)
      local field=editing()
      busy=true
      dlg:modify{id=field,color=color}
      if field=='source' then dlg:modify{id='match',option='Picked color'}
      else dlg:modify{id='replace',selected=true} end
      busy=false; refresh()
    end
    local function move(ev)
      if not dragging then return end
      local x=math.max(0,math.min(width-1,ev.x))
      if dragging=='hue' then h=x/(width-1)*359
      else
        s=x/(width-1)
        v=1-math.max(0,math.min(height-1,ev.y))/(height-1)
      end
      choose(Color{hue=h,saturation=s,value=v})
    end
    picker:combobox{id='editing',label='Choose:',options={'Match color','Replacement color'},
      option=id=='source' and 'Match color' or 'Replacement color',onchange=function() colorRefresh() end}
    picker:newrow()
    picker:canvas{id='picker',width=width,height=296,autoscaling=false,
      onpaint=function(ev)
        local gc=ev.context
        if gradient then gc:drawImage(gradient,gradient.bounds,Rectangle(0,0,width,height)) end
        for x=0,width-1 do
          gc.color=Color{hue=x/(width-1)*359,saturation=1,value=1}
          gc:fillRect(Rectangle(x,248,1,16))
        end
        local x=math.floor(s*(width-1)+0.5)
        local y=math.floor((1-v)*(height-1)+0.5)
        gc.color=Color{r=0,g=0,b=0}; gc:strokeRect(Rectangle(x-3,y-3,7,7))
        gc.color=Color{r=255,g=255,b=255}; gc:strokeRect(Rectangle(x-2,y-2,5,5))
        local hueX=math.floor(h/359*(width-1)+0.5)
        gc.color=Color{r=0,g=0,b=0}; gc:strokeRect(Rectangle(hueX-2,247,5,18))
        gc.color=Color{r=255,g=255,b=255}; gc:strokeRect(Rectangle(hueX-1,248,3,16))
        gc.color=dlg.data[editing()]; gc:fillRect(Rectangle(0,272,width,24))
      end,
      onmousedown=function(ev)
        if ev.button~=MouseButton.LEFT or ev.x<0 or ev.x>=width then return end
        if ev.y>=0 and ev.y<height then dragging='square'
        elseif ev.y>=248 and ev.y<264 then dragging='hue'
        else return end
        move(ev)
      end,
      onmousemove=move,
      onmouseup=function(ev)
        if ev.button==MouseButton.LEFT then move(ev); dragging=nil end
      end}
    picker:newrow()
    picker:entry{id='hex',label='Hex:',text=''}
    picker:button{text='Set',onclick=function()
      report(function()
        local hex=(picker.data.hex or ''):gsub('^%s*#?',''):gsub('%s*$','')
        assert(#hex==6 and hex:match('^%x+$'),'Enter six hex digits, for example #FFFFDC')
        choose(Color{r=tonumber(hex:sub(1,2),16),g=tonumber(hex:sub(3,4),16),b=tonumber(hex:sub(5,6),16)})
      end)
    end}
    picker:newrow()
    picker:label{id='hsv',text=''}
    picker:newrow()
    picker:button{text='Done',onclick=function() picker:close() end}
    colorRefresh()
    picker:show{wait=false,autoscrollbars=true}
    picker:repaint()
  end
  recolorRefresh=refresh
  dlg:combobox{id='scope',label='Sprites:',options={'Selection','Whole sheet'},option='Selection',onchange=refresh}
  dlg:button{text='Sheet preview',onclick=function() report(fullPreview) end}
  dlg:newrow()
  dlg:label{text='Original                    Preview'}
  dlg:button{id='pickColor',text='Pick (I)',onclick=function()
    picking(true); dlg:modify{id='colors',focus=true}
  end}
  dlg:newrow()
  dlg:canvas{id='colors',width=256,height=128,autoscaling=false,onpaint=function(ev)
    checker(ev.context,256,128)
    if before then ev.context:drawImage(before,before.bounds,originalBox) end
    if after then ev.context:drawImage(after,after.bounds,adjustedBox) end
  end,onmousedown=function(ev)
    if ev.button~=MouseButton.LEFT or not before then return end
    local x,y=sampleAt(before,originalBox,ev.x,ev.y)
    if x then pick(before,x,y) end
  end,onkeydown=key}
  dlg:newrow()
  dlg:slider{id='sampleFrame',label='Frame:',min=1,max=layout.capacity,value=1,onchange=function()
    sampleSlot=previewSlots[dlg.data.sampleFrame]; refresh()
  end}
  dlg:newrow()
  dlg:label{id='frameLabel',text=''}
  dlg:newrow()
  dlg:tab{id='adjust',text='Adjust'}
  dlg:slider{id='hue',label='Hue:',min=-180,max=180,value=0,onchange=refresh}
  dlg:newrow()
  dlg:slider{id='saturation',label='Saturation:',min=-100,max=100,value=0,onchange=refresh}
  dlg:newrow()
  dlg:slider{id='brightness',label='Brightness:',min=-100,max=100,value=0,onchange=refresh}
  dlg:newrow()
  dlg:slider{id='contrast',label='Contrast:',min=-100,max=100,value=0,onchange=refresh}
  dlg:tab{id='colorMatch',text='Color match'}
  dlg:combobox{id='match',label='Colors:',options={'All colors','Picked color'},option='All colors',onchange=refresh}
  dlg:newrow()
  dlg:color{id='source',label='Match:',color=Color{r=255,g=0,b=0},onchange=refresh}
  dlg:button{id='sourcePicker',text='Choose...',onclick=function() report(function() colorPicker('source') end) end}
  dlg:newrow()
  dlg:slider{id='tolerance',label='Similarity %:',min=0,max=100,value=0,onchange=refresh}
  dlg:newrow()
  dlg:check{id='replace',text='Replace',selected=false,onclick=refresh}
  dlg:color{id='target',label='New color:',color=Color{r=0,g=100,b=255},onchange=refresh}
  dlg:button{id='targetPicker',text='Choose...',onclick=function() report(function() colorPicker('target') end) end}
  dlg:newrow()
  dlg:label{id='matchCount',text=''}
  dlg:endtabs{selected='adjust'}
  dlg:newrow()
  dlg:button{id='apply',text='Apply',onclick=function()
    local ok,changed=report(function() return commit(selected(),settings()) end)
    if ok and changed then reset() else refresh() end
  end}
  dlg:button{text='Reset',onclick=reset}
  dlg:button{text='Close',onclick=function() dlg:close() end}
  refresh()
  dlg:show{wait=false,autoscrollbars=true}
  dlg:repaint()
  dlg:modify{id='colors',focus=true}
  return dlg
end

return P
