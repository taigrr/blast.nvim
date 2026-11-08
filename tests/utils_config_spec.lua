local utils = require 'blast.utils'

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s\nexpected: %s\nactual: %s', message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local parsed = utils._parse_blast_config [=[
# private = true
name = 'quoted-project'
private = false
]=]

assert_eq(parsed.name, 'quoted-project', 'single-quoted project names should be supported')
assert_eq(parsed.private, false, 'commented private=true should not enable private mode')

parsed = utils._parse_blast_config [=[
name = "double-quoted"
private = true # inline comments are ignored by the boolean parser
]=]

assert_eq(parsed.name, 'double-quoted', 'double-quoted project names should still be supported')
assert_eq(parsed.private, true, 'private=true should enable private mode')

parsed = utils._parse_blast_config [=[
name = ""
]=]

assert_eq(parsed.name, nil, 'empty project names should be ignored so the directory fallback applies')

parsed = utils._parse_blast_config [=[
name = "root-project"
private = false
[tool]
name = "nested-project"
private = true
]=]

assert_eq(parsed.name, 'root-project', 'table names must not override the root project')
assert_eq(parsed.private, false, 'table privacy must not override root privacy')

parsed = utils._parse_blast_config [=[
# [commented-table]
name = "private-project"
private = true
[[tools]]
name = "array-project"
private = false
]=]

assert_eq(parsed.name, 'private-project', 'array table names must not override the root project')
assert_eq(parsed.private, true, 'root privacy must survive array table settings')

parsed = utils._parse_blast_config [=[
  ["quoted.table"] # nested settings only
name = "nested-only"
private = true
]=]

assert_eq(parsed.name, nil, 'table-only names must leave the directory fallback intact')
assert_eq(parsed.private, false, 'table-only privacy must leave the root default intact')
