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

TEMPLATES.annotation = [[
\begin{annotation}
<<<measure-no>>>) <<<beat-string>>> | <<<context-id>>>\\
<<<message>>> \emph{(<<<author>>>, <<<type>>>)
\href{textedit://<<<location>>>}{Ursprung}}
\end{annotation}
]]

TEMPLATES.report = [[
\subsection*{<<<score-id>>>}
\small
\setlength{\parindent}{0pt}
<<<entries>>>
\normalsize
]]

function annotations.add_annotation(text)
  local ann, score = annotations.parse_annotation(text)
  if not SCORES[score] then
     ANNOTATIONS[score] = {}
     SCORES[score] = score
   end
  table.insert(ANNOTATIONS[score], ann)
end


function annotations.make(options)
  print()
  print("Options?")
  print(options)
  local ann_list = ANNOTATIONS[options]
  result = ''
  for i, ann in ipairs(ann_list) do
    result = result..util.replace(TEMPLATES.annotation, ann)
  end
  return result
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
  Replaces fields in a template string with values from the META, CONFIG.options,
  or CONFIG.engrave_options tables -- or a custom table given as argument.
  A field is wrapped in three angled brackets and must match a top-level entry
  in either of the tables. This also implies that field names must be unique
  across these three tables.
  Fields that are *not* found in the tables are ignored and should be handled
  specifically afterwards.
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

function util.unbracify(input)
  return input:match('^{?(.-)}?,?$')
end





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

function lycritrprt.print_critical_report(options)
  --TODO: Make this really configurable by parsing key=value items
  local output = TEMPLATES.report:gsub('<<<score%-id>>>', options)
  output = util.replace(output, {
    ['entries'] = annotations.make(options)
  })
  print(output)
  util.print_latex(output)
end

return lycritrprt
