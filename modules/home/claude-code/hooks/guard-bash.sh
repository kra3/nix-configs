#!/usr/bin/env bash
# PreToolUse guardrail for the Bash tool.
#
# Blocks a small, deliberately narrow list of clearly-accidental
# destructive patterns (root/home wipe, force-push to main/master,
# disk-format primitives, fork bombs). Everything else — including
# rm -rf on subdirectories, disko/nixos-rebuild/colmena, git reset
# --hard, nix builds, etc. — is left alone. This is a last-resort net,
# not a full security boundary: it matches on the literal command
# string, so it can be defeated by indirection (variables, eval, a
# script file). Exit 0 with no output means "allow".

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

verdict="$(GUARD_CWD="$cwd" GUARD_HOME="$HOME" perl -e '
  local $/;
  my $cmd = <STDIN>;
  my $cwd = $ENV{GUARD_CWD} // "";
  my $home = $ENV{GUARD_HOME} // "";
  my $reason;

  # Fork bomb: :(){ :|:& };:  (allow whitespace variance)
  if ($cmd =~ /:\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&?\s*\}\s*;\s*:/) {
    $reason = "fork bomb pattern";
  }

  # Split on shell separators to inspect individual commands, not the whole pipeline.
  my @segs = split /(?:&&|\|\||;|\|)/, $cmd;
  for my $seg (@segs) {
    next if $reason;
    my $s = $seg;
    $s =~ s/^\s+|\s+$//g;
    next if $s eq "";

    # mkfs.*
    if ($s =~ /(^|\s)mkfs(\.\S+)?(\s|$)/) {
      $reason = "mkfs formats a block device";
      last;
    }

    # dd ... of=/dev/*
    if ($s =~ /(^|\s)dd(\s|$)/ && $s =~ /\bof=\/dev\//) {
      $reason = "dd writing directly to /dev/* can wipe a disk";
      last;
    }

    # rm -rf (any flag order/spelling) targeting exactly / , ~ , $HOME, or a home dir root
    if ($s =~ /(^|\s)rm\s+(.*)/) {
      my $rest = $2;
      my @tokens = split /\s+/, $rest;
      my $has_r = 0;
      my $has_f = 0;
      my @targets;
      for my $t (@tokens) {
        if ($t =~ /^--recursive$/) { $has_r = 1; next; }
        if ($t =~ /^--force$/) { $has_f = 1; next; }
        if ($t =~ /^-[a-zA-Z]+$/) {
          $has_r = 1 if $t =~ /r/;
          $has_f = 1 if $t =~ /f/;
          next;
        }
        push @targets, $t;
      }
      if ($has_r && $has_f) {
        for my $t (@targets) {
          my $norm = $t;
          $norm =~ s{(.)/+$}{$1};
          if ($norm eq "/" || $norm eq "~" || $norm eq "\$HOME" || $norm =~ m{^/home/[^/]+$}) {
            $reason = "rm -rf targeting filesystem/home root ($t)";
            last;
          }
          if ($norm eq "." && $cwd ne "" && ($cwd eq "/" || $cwd eq $home)) {
            $reason = "rm -rf . while cwd is $cwd (filesystem/home root)";
            last;
          }
        }
      }
    }
    last if $reason;

    # git push --force / -f to main or master
    if ($s =~ /(^|\s)git\s+push\b/) {
      if ($s =~ /(^|\s)(--force|--force-with-lease|-f)(\s|$)/) {
        if ($s =~ /\b(main|master)\b/) {
          $reason = "git push --force/-f targeting main/master";
        }
      }
    }
  }

  print $reason ? "BLOCK:$reason" : "OK";
' <<<"$cmd")"

if [[ "$verdict" == BLOCK:* ]]; then
  reason="${verdict#BLOCK:}"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Blocked by guard-bash.sh: " + $reason + ". Re-run manually outside Claude Code if this is really intended.")
    }
  }'
fi

exit 0
