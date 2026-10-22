local map = vim.keymap.set

local function trim_whitespace()
  local view = vim.fn.winsaveview()
  vim.cmd([[keeppatterns silent! %s/\s\+$//e]])
  vim.fn.winrestview(view)
end

vim.api.nvim_create_user_command("FixWhitespace", trim_whitespace, {})
map("n", "<leader>cw", trim_whitespace, { desc = "Trim Trailing Whitespace" })

map("n", "<leader>wt", function()
  if vim.fn.winnr("$") <= 1 then
    return
  end
  vim.cmd(vim.fn.winlayout()[1] == "col" and "windo wincmd H" or "windo wincmd K")
end, { desc = "Toggle Window Layout" })
