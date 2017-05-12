function dump(o, level)
  if not level then
    level = 5
  end
  if level == 0 then
    return "...to deep..."
  end
  if type(o) == 'table' then
    local s = '{\n'
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v, level - 1) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end