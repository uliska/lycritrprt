local err, warn, info, log = luatexbase.provides_module({
    name               = "lycritrprt",
    version            = '0',
    date               = "2018/06/01",
    description        = "Module lycritrprt.",
    author             = "Urs Liska <ul@openlilylib.org>",
    copyright          = "2018 Urs Liska",
    license            = "GPL v3",
})

local lfs = require 'lfs'
local md5 = require 'md5'

local annotations = {}
local ANNOTATIONS = {}
local SCORES = {}
local source = {}
local util = {}

local lycritrprt = {}

local REPORTS = {}


---------------------------------
-- TEMPLATES
---------------------------------

local TEMPLATES = {}

--[[
  Templates for all supported annotation fields.
  Fields for which there are no templates are silently ignored
  (for example all the different fields about the rhythmic location).
  On the other hand this means that custom annotation fields can easily
  be supported by adding field templates.
  Each template is a table with one or two elements. If a second element
  is present this is used when the annotation field is not present. Otherwise
  the keyword in the template is simply removed.

  Items can be arbitrarily styled, and non-standard macros can be used
  when they are defined elsewhere.

  The top-level entries represent report styles. If a different style than
  'default' is requested then fields present in the given style will override
  the ones in the 'default' template.
  NOTE: This is not implemented yet.
--]]
TEMPLATES.ann_fields = {
  ['default'] = {
    ['measure-no'] = { [[<<<measure-no>>>)]] },
    ['beat-string'] =  { [[<<<beat-string>>> |]] },
    ['context-id'] = { [[<<<context-id>>>\\]] },
    ['message'] = { [[<<<message>>>]] },
    ['author'] = { [[\emph{(<<<author>>>, ]], [[\emph{(]]},
    ['type'] = { [[<<<type>>>)}]]},
    ['location'] = { [[\href{textedit://<<<location>>>}{Ursprung}]]}
  }
}


--[[
  Overall template for a single annotation entry.
  This defines the basic outline of a report entry, the order and selection
  of fields. The actual content of the fields (including behaviour for missing
  entries) is specified in the ann_fields template.

  The top-level entries represent report styles. If a different style than
  'default' is requested then fields present in the given style will override
  the ones in the 'default' template.
  NOTE: This is not implemented yet.
--]]
TEMPLATES.annotation = {
  ['default'] = [[
\begin{annotation}
<<<measure-no>>>
<<<beat-string>>>
<<<context-id>>>
<<<message>>>
<<<author>>><<<type>>>
<<<location>>>
\end{annotation}
]]
}

--[[
  Overall template for a single report.
--]]
TEMPLATES.report = {
  ['default'] = [[
<<<heading>>>
\small
\setlength{\parindent}{0pt}
<<<entries>>>
\normalsize
]]
}


--[[
  Parse an annotation (string), create a table from it, add it to the
  corresponding annotations sub-table.
--]]
function annotations.add_annotation(text)
  local ann, score = annotations.parse_annotation(text)
  if not SCORES[score] then
     ANNOTATIONS[score] = {}
     SCORES[score] = score
   end
  table.insert(ANNOTATIONS[score], ann)
end


--[[
  Read the annotations (configured by the options argument),
  generate and return TeX code to print a report.
  
  NOTE: options currently is simply expected to contain a string
  key for the ANNOTATIONS.score table. All the configuration remains
  to be implemented.
--]]
function annotations.make(options)
  local ann_list = ANNOTATIONS[options]
  result = ''
  for i, ann in ipairs(ann_list) do
    result = result..annotations.make_annotation(ann)
  end
  return result
end


--[[
  Interpolate a single entry within an annotation with the value
  from the annotation.
  If the entry is missing and an alternative field template is defined
  that is used, otherwise the empty value is interpolated with the
  regular template.
--]]
function annotations.interpolate(ann, element, tpl)
  local content = ann[element] or ''
  if ((content == '') and (#tpl == 2)) then
    return tpl[2]
  else
    return tpl[1]:gsub('<<<'..util.quote_hyphens(element)..'>>>', content)
  end
end


--[[
  Create and return a string of TeX code representing the given
  annotation.
--]]
function annotations.make_annotation(ann)
  local tpl = TEMPLATES.annotation['default']
  local field_tpl = TEMPLATES.ann_fields['default']
  for element in tpl:gmatch('<<<(.-)>>>') do
    tpl = tpl:gsub(
      '<<<'..util.quote_hyphens(element)..'>>>',
      annotations.interpolate(ann, element, field_tpl[element]))
  end
  return tpl
end

--[[
  Parse a blcok of LaTeX key=value assignments.
  Assignments spanning multiple lines are concatenated to a single string,
  Line comments are currently not supported
  (i.e. ignored and will probably cause errors).
  NOTE: The "values" are returned as strings, so any "Scheme-y" interpretation
  has to be done afterwards.
--]]
function annotations.parse_annotation(input)
  local result = {}
  local from, to = input:find('(%g-)%s-=')
  local key = input:sub(from, to-1)
  input = input:sub(to+1)
  for value, next_key in input:gmatch('%s-(.-)%s-\n-%s-(%g-)%s-=')
  do
    result[key] = util.unbracify(value)
    key = next_key
  end
  result[key] = util.unbracify(input:match('.*=(.*)'))
  return result, result['score-id']
end


--[[
  Split the original input file into annotations and parse them.
  After this function the annotations are available in the
  ANNOTATIONS[score-id] tables.
--]]
function source.parse()
  for _, ann, _ in string.gmatch(source.raw, '(\\.-%[%s-)(%g.-)(%]%s-\n)') do
    annotations.add_annotation(ann)
  end
end






-- Print (to TeX) the given string as a sequence of strings
function util.print_latex(content)
  local lines = content:explode('\n')
  for _, line in ipairs(lines) do
    tex.print(line)
  end
end


-- Take a string (for use as pattern) and quote any hyphens
function util.quote_hyphens(input)
  return input:gsub('%-', '%%-')
end


--[[
  Replaces fields in a template string with values from the tbl table.
  A field is wrapped in three angled brackets and must match a top-level entry
  in tpl. 
  Fields that are *not* found in the tables are ignored (i.e. kept in their
  template state) and should be handled specifically afterwards.
]]
function util.replace(template, tbl)
  local value
  for element in template:gmatch('<<<(.-)>>>') do
    value = tbl[element]
    if value then
      template = template:gsub('<<<'..util.quote_hyphens(element)..'>>>', value)
    end
  end
  return template
end


-- Remove leading and trailing curly braces from a string
function util.unbracify(input)
  return input:match('^{?(.-)}?,?$')
end




--[[
  Load a critical report from a file, parse and store its annotations.
  The given 'basename' argument may directly point to a file, to a file
  basename.inp, or basename.annotations.inp
--]]
function lycritrprt.load_critical_report(basename)
  local report_file = ''
  if lfs.isfile(basename) then report_file = basename
  elseif lfs.isfile(basename..'.inp') then
    report_file = basename..'.inp'
  elseif lfs.isfile(basename..'.annotations.inp') then
    report_file = basename..'.annotations.inp'
  else
    warn("No critical report file found for "..basename..
  "\nSkip generating reports.")
  end

  local f = io.open(report_file, 'r')
  source.raw = f:read('*a')
  f:close()

  source.parse()

end


--[[
  Generate code for a critical report and 'print' it to the TeX document.
  NOTE: The options are currently simply a string referencing the score-id.
  Proper configuration remains to be implemented.
--]]
function lycritrprt.print_critical_report(options)
  --TODO: Make this really configurable by parsing key=value items
  local heading = ''
  if options ~= '' then heading = [[\subsection*{]]..options..[[}]] end
  local output = TEMPLATES.report['default']:gsub('<<<heading>>>', heading)
  output = util.replace(output, {
    ['entries'] = annotations.make(options)
  })
  util.print_latex(output)
end

return lycritrprt
