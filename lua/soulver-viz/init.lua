local M = {
  soulver_path = nil,
  live = true,
}

function M.setup(opts)
  opts = opts or {}
  if opts.path == nil then error("soulver path provided") end
  M.set_soulver_path(opts.path)
  M.live = opts.live or true
end

function M.set_soulver_path(path, callback)
  if path ~= nil then
    path = vim.fs.normalize(path)
    vim.uv.fs_stat(path, function(err, fstat)
      if err == nil then
        M.soulver_path = path
      end
    end)
  end
end

local strings_join = function(strings, sep)
  local ret = ''

  for i, v in ipairs(strings) do
    if i ~= 1 then
      ret = ret .. '\n'
    end
    ret = ret .. v
  end

  return ret
end

-- https://stackoverflow.com/a/51893646
local string_split = function(str, delimiter)
  local result = {}
  local from = 1
  local delim_from, delim_to = string.find(str, delimiter, from)
  while delim_from do
    table.insert(result, string.sub(str, from, delim_from - 1))
    from = delim_to + 1
    delim_from, delim_to = string.find(str, delimiter, from)
  end
  table.insert(result, string.sub(str, from))
  return result
end

local run_soulver = function(lines, callback)
  local co
  co = coroutine.create(function()
    local stdin = vim.uv.new_pipe()
    local stdout = vim.uv.new_pipe()
    local stderr = vim.uv.new_pipe()

    local handle, pid = vim.uv.spawn(M.soulver_path, {
      args = {},
      stdio = {
        stdin,
        stdout,
        stderr,
      },
    }, function(code, signal)
      if code == 0 then
      end
    end)

    if handle == nil then
      error('spawn failed')
    end

    vim.uv.write(stdin, strings_join(lines, '\n'), function(err)
      local out_data = ''
      local err_data = ''
      local out_read_complete = false
      local err_read_complete = false

      local on_read_complete = function()
        if out_read_complete and err_read_complete then
          if err_data ~= '' then
            vim.notify('error in soulver: ' .. err_data, vim.log.levels.ERROR)
          end
          vim.uv.shutdown(stdin, function()
            vim.uv.close(handle, function()
              stdin:close()
              stdout:close()
              stderr:close()
              coroutine.resume(co, out_data, err_data)
            end)
          end)
        end
      end

      vim.uv.read_start(stdout, function(read_err, data)
        if data == nil then
          out_read_complete = true
          on_read_complete()
          return
        end
        if read_err == nil then
          out_data = out_data .. data
        end
      end)
      vim.uv.read_start(stderr, function(read_err, data)
        if data == nil then
          err_read_complete = true
          on_read_complete()
          return
        end
        if read_err == nil then
          err_data = err_data .. data
        end
      end)
    end)

    local out_data, err_data = coroutine.yield()
    vim.schedule(function()
      callback(out_data, err_data)
    end)
  end)
  coroutine.resume(co)
end

local nspace = vim.api.nvim_create_namespace('soulver_viz')
local hlgrp_name = 'SoulverVizResult'
vim.api.nvim_set_hl(0, hlgrp_name, { italic = true, bold = true })

local refresh_extmarks = function(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  run_soulver(lines, function(stdout, stderr)
    vim.api.nvim_buf_clear_namespace(bufnr, nspace, 0, -1)
    local out = string_split(stdout, '\n')
    local maxlen = 0
    for _, output in ipairs(lines) do
      if #output > maxlen then
        maxlen = #output
      end
    end

    local col = maxlen + 10
    for i, output in ipairs(out) do
      local status, ret = pcall(
        vim.api.nvim_buf_set_extmark,
        bufnr,
        nspace,
        i - 1,
        0,
        { virt_text = { { output, hlgrp_name } }, virt_text_win_col = col, strict = false }
      )
      if status == false then print(ret) end
    end
  end)
end

vim.api.nvim_create_user_command('SoulverViz', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ftype = vim.bo[bufnr].filetype
  if ftype == 'soulver' then
    refresh_extmarks(bufnr)
  end
end, {})

vim.api.nvim_create_user_command('SoulverVizOn', function()
  M.live = true
end, {})
vim.api.nvim_create_user_command('SoulverVizOff', function()
  M.live = false
end, {})
vim.api.nvim_create_user_command('SoulverVizStatus', function()
  print(M.live)
  print(M.soulver_path)
end, {})

vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
  pattern = { '*.soulver' },
  callback = function(arg)
    local bufnr = arg.buf
    if M.live then
      refresh_extmarks(bufnr)
    end
  end,
})

return M
