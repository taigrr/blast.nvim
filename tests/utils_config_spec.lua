local utils = require 'blast.utils'

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s\nexpected: %s\nactual: %s', message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local parsed = utils._parse_blast_config [[
# private = true
name = 'quoted-project'
private = false
]]

assert_eq(parsed.name, 'quoted-project', 'single-quoted project names should be supported')
assert_eq(parsed.private, false, 'commented private=true should not enable private mode')

parsed = utils._parse_blast_config [[
name = "double-quoted"
private = true # inline comments are ignored by the boolean parser
]]

assert_eq(parsed.name, 'double-quoted', 'double-quoted project names should still be supported')
assert_eq(parsed.private, true, 'private=true should enable private mode')

parsed = utils._parse_blast_config [[
name = ""
]]

assert_eq(parsed.name, nil, 'empty project names should be ignored so the directory fallback applies')
