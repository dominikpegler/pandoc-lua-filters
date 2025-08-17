local utils = require 'pandoc.utils'

local function strip_trailing_period_and_space(inls)
  local res = pandoc.List(inls):clone()
  while #res > 0 and res[#res].t == 'Space' do res:remove(#res) end
  if #res == 0 then return nil end
  local last = res[#res]
  if last.t == 'Str' then
    local t = last.text
    if t:sub(-1) == '.' then
      if #t == 1 then
        res:remove(#res)
      else
        last.text = t:sub(1, -2)
        res[#res] = last
      end
      return res
    end
  end
  return nil
end

function Para(el)
  local inls = el.content
  if #inls == 0 then return nil end
  local first = inls[1]
  local bold, italic = false, false
  local head_inls, rest_idx

  if first.t == 'Strong' then
    bold = true
    if #first.content == 1 and first.content[1].t == 'Emph' then
      italic = true
      head_inls = first.content[1].content
    else
      head_inls = first.content
    end
    rest_idx = 2
  elseif first.t == 'Emph' then
    italic = true
    if #first.content == 1 and first.content[1].t == 'Strong' then
      bold = true
      head_inls = first.content[1].content
    else
      -- italic-only isn't an APA run-in heading
      return nil
    end
    rest_idx = 2
  else
    return nil
  end
  if not bold then return nil end

  local stripped = strip_trailing_period_and_space(head_inls)
  if not stripped then return nil end

  local lvl = italic and 5 or 4
  local title = utils.stringify(stripped)
  if title == '' then return nil end

  local header = pandoc.Header(lvl, { pandoc.Str(title) }, pandoc.Attr('', {'runin','apa'}, {}))
  local rest = pandoc.List()
  for i = rest_idx, #inls do rest:insert(inls[i]) end
  if #rest == 0 then
    return header
  else
    return { header, pandoc.Para(rest) }
  end
end

