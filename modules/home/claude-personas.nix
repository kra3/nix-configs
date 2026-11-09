{
  flake.homeManagerModules.home-claude-personas =
    { flakeLib, lib, ... }:
    {
      home.file = lib.listToAttrs (
        map (
          p:
          lib.nameValuePair ".claude/agents/${p.name}.md" {
            text = lib.concatStringsSep "\n" (
              [
                "---"
                "name: ${p.name}"
                "description: ${builtins.toJSON p.description}"
                "model: ${p.model}"
              ]
              ++ lib.optional (p ? tools) "tools: ${p.tools}"
              ++ [
                "---"
                p.prompt
              ]
            );
          }
        ) flakeLib.claude-personas
      );
    };
}
