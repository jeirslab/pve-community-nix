# CLAUDE.md

Read [AGENTS.md](./AGENTS.md) first — its iron rules apply to every agent.

Claude-specific:

- The service pipeline's roles are in `.claude/agents/`
  (`service-researcher`, `service-author`, `service-reviewer`).
  `tools/agent/run-service-agent.sh` runs them in order for one upstream
  app; `.github/workflows/service-agent.yml` runs that script in CI, once
  per app.
- `.claude/workflows/service-implement.js` is the same pipeline as a
  Claude workflow, for interactive use: run it with `{ app: "<id>" }`.
- `.claude/settings.json` scopes agent permissions; don't widen them.
