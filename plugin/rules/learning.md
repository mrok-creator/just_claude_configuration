# Learning Capture Convention

Always-on. Full logic: `.claude/commands/learn-process.md`.

Append to `.cc_settings/.memory/buffer.md` (prefix `\n---\n`) when you: make a non-obvious **architecture** decision (not derivable from code/rules), hit a **pitfall** (compiles/lints, breaks at runtime/usage), or consciously **deviate** from a convention.

```
**type:** architecture | pitfall | deviation | correction | mistake (candidate)
**summary:** one-line, specific (dedup key)
**detail:** what happened   **root:** why / cause
**resolution:** fix or decision   **generalization:** "Going forward: X" | one-off, no generalization
**context:** service/module/ticket   **destination:** library | rule | hook | ephemeral
**captured:** ISO-8601 UTC timestamp
```
