local E = {}

function E.frames(expression, capacity)
  expression = (expression or ''):gsub('%s+', '')
  assert(expression ~= '' and not expression:match('^,') and not expression:match(',$') and not expression:match(',,'),
    'Enter cells such as 5-8 or 5,5,6,7,8')
  local result = {}
  for token in expression:gmatch('[^,]+') do
    local first, last = token:match('^(%d+)%-(%d+)$')
    if not first then first = token:match('^(%d+)$'); last = first end
    first, last = tonumber(first), tonumber(last)
    assert(first and last and first >= 1 and last >= 1 and first <= capacity and last <= capacity,
      'Cell numbers must be between 1 and ' .. capacity)
    for slot = first, last, first <= last and 1 or -1 do
      assert(#result < math.max(400,capacity*10), 'Too many playback steps')
      result[#result + 1] = slot
    end
  end
  assert(#result > 0, 'Enter at least one cell')
  return result
end

function E.frameText(slots)
  local parts, i = {}, 1
  while i <= #slots do
    local last = i
    while last < #slots and slots[last+1] == slots[last]+1 do last=last+1 end
    parts[#parts+1] = last > i and (slots[i] .. '-' .. slots[last]) or tostring(slots[i])
    i=last+1
  end
  return table.concat(parts, ',')
end

function E.advance(index, count, loop)
  if index < count then return index + 1, true end
  return loop and 1 or count, loop == true
end

local function clamp(x, low, high) return math.max(low, math.min(high, x)) end

local function hsv(r, g, b)
  local high, low = math.max(r,g,b), math.min(r,g,b)
  local delta, h = high-low, 0
  if delta > 0 then
    if high == r then h=((g-b)/delta)%6
    elseif high == g then h=(b-r)/delta+2
    else h=(r-g)/delta+4 end
    h=h*60
  end
  return h, high == 0 and 0 or delta/high, high
end

local function rgb(h, s, v)
  local c = v*s
  local x = c*(1-math.abs((h/60)%2-1))
  local m = v-c
  if h < 60 then return c+m,x+m,m
  elseif h < 120 then return x+m,c+m,m
  elseif h < 180 then return m,c+m,x+m
  elseif h < 240 then return m,x+m,c+m
  elseif h < 300 then return x+m,m,c+m
  else return c+m,m,x+m end
end

function E.transform(image, settings)
  local hue, saturation = settings.hue or 0, settings.saturation or 0
  local brightness, contrast = settings.brightness or 0, settings.contrast or 0
  local tolerance = settings.tolerance or 0
  assert(hue >= -180 and hue <= 180 and saturation >= -100 and saturation <= 100 and
    brightness >= -100 and brightness <= 100 and contrast >= -100 and contrast <= 100 and
    tolerance >= 0 and tolerance <= 100, 'Adjustment values are outside their allowed range')
  local source, target = settings.source, settings.target
  assert(not settings.pickedOnly or source, 'Pick a source color first')
  assert(not settings.replace or target, 'Choose a replacement color')
  local threshold2 = 3 * 255 * 255 * (tolerance/100)^2
  local out, matched, cache = Image(image), 0, {}
  local pc = app.pixelColor
  for y=0,image.height-1 do
    for x=0,image.width-1 do
      local pixel = image:getPixel(x,y)
      local item = cache[pixel]
      if not item then
        local r,g,b,a = pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel),pc.rgbaA(pixel)
        local match = a > 0
        if match and settings.pickedOnly then
          match = (r-source.red)^2+(g-source.green)^2+(b-source.blue)^2 <= threshold2
        end
        local output = pixel
        if match then
          if settings.replace then r,g,b=target.red,target.green,target.blue end
          local h,s,v = hsv(r/255,g/255,b/255)
          r,g,b=rgb((h+hue)%360,clamp(s*(1+saturation/100),0,1),v)
          local factor = 1+contrast/100
          local function channel(value)
            return math.floor(clamp((value-0.5)*factor+0.5+brightness/100,0,1)*255+0.5)
          end
          output=pc.rgba(channel(r),channel(g),channel(b),a)
        end
        item={output=output,matched=match}; cache[pixel]=item
      end
      if item.matched then matched=matched+1 end
      if item.output ~= pixel then out:drawPixel(x,y,item.output) end
    end
  end
  return out, matched
end

function E.apply(state, selected, settings)
  local changes, count = {}, 0
  for slot=1,state.layout.capacity do
    local cel = selected[slot] and state.slots[slot]
    if cel then
      local image = E.transform(cel.image, settings)
      if not image:isEqual(cel.image) then changes[#changes+1]={cel=cel,image=image} end
      count=count+1
    end
  end
  assert(count > 0, 'Select at least one sprite to recolor')
  if #changes == 0 then return false end
  app.transaction('Recolor sprites', function()
    for _, change in ipairs(changes) do change.cel.image=change.image end
  end)
  return true
end

return E
