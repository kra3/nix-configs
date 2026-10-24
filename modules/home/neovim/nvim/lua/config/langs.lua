local ok, generated = pcall(require, "config.nix-langs")

return ok and generated
  or { langs = { nix = true, lua = true, python = true }, extras = { "lang.nix", "lang.python" }, tools = {} }
