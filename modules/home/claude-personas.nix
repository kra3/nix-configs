{
  flake.homeManagerModules.home-claude-personas =
    { flakeLib, lib, ... }:
    {
      home.file = lib.listToAttrs (
        map (
          p:
          lib.nameValuePair ".claude/agents/${p.name}.md" {
            force = true;
            text = lib.concatStringsSep "\n" (
              [
                "---"
                "name: ${p.name}"
                "description: ${builtins.toJSON "Top-level persona: run as `claude --agent ${p.name}` or via tsk, not as a subagent. ${p.description}"}"
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
