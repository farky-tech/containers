# PostToolUse Hook Spec

Purpose: notice tool results that should trigger verification, fallback, or learning.

Trigger examples:
- file edit succeeded,
- test/build failed,
- tool unavailable,
- command blocked,
- search returned no result,
- write path was unavailable,
- risky external action attempted.

Action:
- for normal successful tool use, stay silent.
- for failed/weakened/replaced tool use, trigger fallback report.
- after meaningful implementation, remind verification if not already planned.
- after repeated manual workaround, trigger capability gap prompt.
