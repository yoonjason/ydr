#!/bin/bash
# 워크스페이스: ydr
# Claude Code 서브에이전트 워크스페이스 자동 세팅

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

osascript - "$PROJECT_DIR" <<'APPLESCRIPT'
on run argv
  set projectDir to item 1 of argv

  tell application "iTerm"
    activate

    set newWin to (create window with default profile)

    tell newWin
      set mainSession to current session of current tab of newWin

      set shellSession to (split horizontally with default profile of mainSession)
          set agentCol1 to (split vertically with default profile of mainSession)

          set col2 to (split vertically with default profile of agentCol1)
          set a3 to (split horizontally with default profile of agentCol1)
          set a4 to (split horizontally with default profile of col2)
          set a5 to (split horizontally with default profile of a3)
          set a6 to (split horizontally with default profile of a4)
          set a7 to (split horizontally with default profile of a5)
          set a8 to (split horizontally with default profile of a6)
          tell agentCol1
          set name to "ux-designer"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh ux-designer"
          end tell
          tell col2
          set name to "ios-engineer"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh ios-engineer"
          end tell
          tell a3
          set name to "backend-engineer"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh backend-engineer"
          end tell
          tell a4
          set name to "qa-engineer"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh qa-engineer"
          end tell
          tell a5
          set name to "code-reviewer"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh code-reviewer"
          end tell
          tell a6
          set name to "tech-writer"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh tech-writer"
          end tell
          tell a7
          set name to "analyst"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh analyst"
          end tell
          tell a8
          set name to "security-auditor"
          write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && ~/.claude/hooks/agent-interactive.sh security-auditor"
          end tell


      tell mainSession
        set name to "ydr"
        write text "export CLAUDE_PROJECT_DIR=" & (quoted form of projectDir) & " && cd " & (quoted form of projectDir) & " && printf '\\e]7;file://%s%s\\a' \"$HOSTNAME\" \"$PWD\" && mkdir -p .claude/log && claude --dangerously-skip-permissions"
      end tell
      tell shellSession
        set name to "shell"
        write text "cd " & (quoted form of projectDir)
      end tell
    end tell
  end tell
end run
APPLESCRIPT