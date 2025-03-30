local ls = require 'luasnip'
-- some shorthands...
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local l = require('luasnip.extras').lambda
local rep = require('luasnip.extras').rep
local p = require('luasnip.extras').partial
local m = require('luasnip.extras').match
local n = require('luasnip.extras').nonempty
local dl = require('luasnip.extras').dynamic_lambda
local fmt = require('luasnip.extras.fmt').fmt
local fmta = require('luasnip.extras.fmt').fmta
local types = require 'luasnip.util.types'
local conds = require 'luasnip.extras.conditions'
local conds_expand = require 'luasnip.extras.conditions.expand'

-- If you're reading this file for the first time, best skip to around line 190
-- where the actual snippet-definitions start.

-- Every unspecified option will be set to the default.
ls.setup {
  keep_roots = true,
  link_roots = true,
  link_children = true,

  -- Update more often, :h events for more info.
  update_events = 'TextChanged,TextChangedI',
  -- Snippets aren't automatically removed if their text is deleted.
  -- `delete_check_events` determines on which events (:h events) a check for
  -- deleted snippets is performed.
  -- This can be especially useful when `history` is enabled.
  delete_check_events = 'TextChanged',
  ext_opts = {
    [types.choiceNode] = {
      active = {
        virt_text = { { 'choiceNode', 'Comment' } },
      },
    },
  },
  -- treesitter-hl has 100, use something higher (default is 200).
  ext_base_prio = 300,
  -- minimal increase in priority.
  ext_prio_increase = 1,
  enable_autosnippets = true,
  -- mapping for cutting selected text so it's usable as SELECT_DEDENT,
  -- SELECT_RAW or TM_SELECTED_TEXT (mapped via xmap).
  store_selection_keys = '<Tab>',
  -- luasnip uses this function to get the currently active filetype. This
  -- is the (rather uninteresting) default, but it's possible to use
  -- eg. treesitter for getting the current filetype by setting ft_func to
  -- require("luasnip.extras.filetype_functions").from_cursor (requires
  -- `nvim-treesitter/nvim-treesitter`). This allows correctly resolving
  -- the current filetype in eg. a markdown-code block or `vim.cmd()`.
  ft_func = function()
    return vim.split(vim.bo.filetype, '.', true)
  end,
}

-- args is a table, where 1 is the text in Placeholder 1, 2 the text in
-- placeholder 2,...
local function copy(args)
  return args[1]
end

-- 'recursive' dynamic snippet. Expands to some text followed by itself.
local rec_ls
rec_ls = function()
  return sn(
    nil,
    c(1, {
      -- Order is important, sn(...) first would cause infinite loop of expansion.
      t '',
      sn(nil, { t { '', '\t\\item ' }, i(1), d(2, rec_ls, {}) }),
    })
  )
end

-- complicated function for dynamicNode.
local function jdocsnip(args, _, old_state)
  -- !!! old_state is used to preserve user-input here. DON'T DO IT THAT WAY!
  -- Using a restoreNode instead is much easier.
  -- View this only as an example on how old_state functions.
  local nodes = {
    t { '/**', ' * ' },
    i(1, 'A short Description'),
    t { '', '' },
  }

  -- These will be merged with the snippet; that way, should the snippet be updated,
  -- some user input eg. text can be referred to in the new snippet.
  local param_nodes = {}

  if old_state then
    nodes[2] = i(1, old_state.descr:get_text())
  end
  param_nodes.descr = nodes[2]

  -- At least one param.
  if string.find(args[2][1], ', ') then
    vim.list_extend(nodes, { t { ' * ', '' } })
  end

  local insert = 2
  for indx, arg in ipairs(vim.split(args[2][1], ', ', true)) do
    -- Get actual name parameter.
    arg = vim.split(arg, ' ', true)[2]
    if arg then
      local inode
      -- if there was some text in this parameter, use it as static_text for this new snippet.
      if old_state and old_state[arg] then
        inode = i(insert, old_state['arg' .. arg]:get_text())
      else
        inode = i(insert)
      end
      vim.list_extend(nodes, { t { ' * @param ' .. arg .. ' ' }, inode, t { '', '' } })
      param_nodes['arg' .. arg] = inode

      insert = insert + 1
    end
  end

  if args[1][1] ~= 'void' then
    local inode
    if old_state and old_state.ret then
      inode = i(insert, old_state.ret:get_text())
    else
      inode = i(insert)
    end

    vim.list_extend(nodes, { t { ' * ', ' * @return ' }, inode, t { '', '' } })
    param_nodes.ret = inode
    insert = insert + 1
  end

  if vim.tbl_count(args[3]) ~= 1 then
    local exc = string.gsub(args[3][2], ' throws ', '')
    local ins
    if old_state and old_state.ex then
      ins = i(insert, old_state.ex:get_text())
    else
      ins = i(insert)
    end
    vim.list_extend(nodes, { t { ' * ', ' * @throws ' .. exc .. ' ' }, ins, t { '', '' } })
    param_nodes.ex = ins
    insert = insert + 1
  end

  vim.list_extend(nodes, { t { ' */' } })

  local snip = sn(nil, nodes)
  -- Error on attempting overwrite.
  snip.old_state = param_nodes
  return snip
end

-- Make sure to not pass an invalid command, as io.popen() may write over nvim-text.
local function bash(_, _, command)
  local file = io.popen(command, 'r')
  local res = {}
  for line in file:lines() do
    table.insert(res, line)
  end
  return res
end

-- Returns a snippet_node wrapped around an insertNode whose initial
-- text value is set to the current date in the desired format.
local date_input = function(args, snip, old_state, fmt)
  local fmt = fmt or '%Y-%m-%d'
  return sn(nil, i(1, os.date(fmt)))
end

-- snippets are added via ls.add_snippets(filetype, snippets[, opts]), where
-- opts may specify the `type` of the snippets ("snippets" or "autosnippets",
-- for snippets that should expand directly after the trigger is typed).
--
-- opts can also specify a key. By passing an unique key to each add_snippets, it's possible to reload snippets by
-- re-`:luafile`ing the file in which they are defined (eg. this one).
ls.add_snippets('c', {
  -- function head
  s('fn', {
    i(3, 'void'),
    t ' ',
    i(1, 'fun'),
    t '(',
    i(2, 'void'),
    t { ') {', '\t' },
    i(0),
    t { '', '}' },
  }),
  -- first order IIR filter.
  s(
    'iir',
    fmta(
      [[
        static float alpha = <alpha>; // settling time: ~= -5*Ts/ln(<alpha>) = <Tset>*Ts
        <x> = <new_x> * (1.0f - alpha) + <x> * alpha;
      ]],
      {
        alpha = i(1, 'alpha'),
        x = i(2, 'x'),
        new_x = i(3, 'new_x'),
        Tset = f(function(alpha_str)
          local alpha = tonumber(alpha_str[1][1])
          if alpha == nil then
            return alpha_str[1][1]
          end
          local Tsettle = -5 / math.log(alpha)
          return string.format('%.1f', Tsettle)
        end, { 1 }),
      },
      {
        repeat_duplicates = true,
      }
    )
  ),
}, {
  key = 'c',
})

ls.add_snippets('tex', {
  -- rec_ls is self-referencing. That makes this snippet 'infinite' eg. have as many
  -- \item as necessary by utilizing a choiceNode.
  s('ls', {
    t { '\\begin{itemize}', '\t\\item ' },
    i(1),
    d(2, rec_ls, {}),
    t { '', '\\end{itemize}' },
  }),
}, {
  key = 'tex',
})

-- set type to "autosnippets" for adding autotriggered snippets.
ls.add_snippets('all', {
  s('autotrigger', {
    t 'autosnippet',
  }),
}, {
  type = 'autosnippets',
  key = 'all_auto',
})

-- in a lua file: search lua-, then c-, then all-snippets.
ls.filetype_extend('lua', { 'c' })
-- in a cpp file: search c-snippets, then all-snippets only (no cpp-snippets!!).
ls.filetype_set('cpp', { 'c' })

-- see DOC.md/LUA SNIPPETS LOADER for some details.
require('luasnip.loaders.from_lua').load { include = { 'c' } }
require('luasnip.loaders.from_lua').lazy_load { include = { 'all', 'cpp' } }
