export const meta = {
  name: 'service-implement',
  description: 'One upstream app → services/<name>: research, scaffold, author until verify passes, review, report',
  whenToUse: 'Implement one or more upstream community-scripts apps as services interactively. args: { app: "<id>" } or { apps: ["<id>", ...] }. CI uses tools/agent/run-service-agent.sh instead.',
  phases: [
    { title: 'Research', detail: 'service-researcher reads upstream + nixpkgs, writes research.json' },
    { title: 'Author', detail: 'scaffold, then service-author iterates until tools/verify-service.sh passes' },
    { title: 'Review', detail: 'service-reviewer checks what tests cannot; blocking issues go back to the author once' },
  ],
}

const RESEARCH = {
  type: 'object',
  properties: {
    feasible: { type: 'boolean' },
    infeasible_reason: { type: ['string', 'null'] },
    name: { type: 'string' },
    approach: { type: 'string', enum: ['extracted', 'modular'] },
    approach_reason: { type: 'string' },
  },
  required: ['feasible', 'name', 'approach', 'approach_reason'],
}

const VERIFY = {
  type: 'object',
  properties: {
    passed: { type: 'boolean' },
    failing_stage: { type: ['string', 'null'] },
    summary: { type: 'string' },
  },
  required: ['passed', 'summary'],
}

const REVIEW = {
  type: 'object',
  properties: {
    approved: { type: 'boolean' },
    blocking: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
  required: ['approved', 'blocking', 'summary'],
}

const apps = args && args.apps ? args.apps : [args && args.app].filter(Boolean)
if (!apps.length) throw new Error('pass { app: "<upstream id>" } or { apps: [...] }')

// One independent chain per app: research → scaffold+author → verify → review.
const results = await pipeline(
  apps,
  (app) => agent(
    `Research upstream app '${app}'. Upstream mirror: .upstream/ (run tools/upstream/checkout.sh first if it's missing). ` +
    `Write .agent/${app}/research.json as your role describes, then return its key fields.`,
    { agentType: 'service-researcher', phase: 'Research', label: `research:${app}`, schema: RESEARCH },
  ),
  async (research, app) => {
    if (!research || !research.feasible) return { app, research, skipped: true }
    const name = research.name
    const verify = await agent(
      `Run \`tools/new-service.sh ${name} ${app}\` if services/${name} doesn't exist yet. ` +
      `Then implement service '${name}' from .agent/${app}/research.json, iterating until ` +
      `\`tools/verify-service.sh ${name}\` passes (quick first, then full). Return whether the full verify passed.`,
      { agentType: 'service-author', phase: 'Author', label: `author:${name}`, schema: VERIFY },
    )
    return { app, name, research, verify }
  },
  async (r) => {
    if (!r || r.skipped || !r.verify || !r.verify.passed) return r
    let review = await agent(
      `Review service '${r.name}' (services/${r.name}/). Write .agent/${r.app}/review.json as your role describes and return its verdict.`,
      { agentType: 'service-reviewer', phase: 'Review', label: `review:${r.name}`, schema: REVIEW },
    )
    if (review && !review.approved && review.blocking.length) {
      const fixed = await agent(
        `The reviewer found blocking issues in services/${r.name}/:\n- ${review.blocking.join('\n- ')}\n` +
        `Fix them, then make \`tools/verify-service.sh ${r.name}\` pass again.`,
        { agentType: 'service-author', phase: 'Review', label: `fix:${r.name}`, schema: VERIFY },
      )
      if (fixed && fixed.passed) {
        review = await agent(
          `Re-review service '${r.name}' after fixes. Write .agent/${r.app}/review.json and return the verdict.`,
          { agentType: 'service-reviewer', phase: 'Review', label: `re-review:${r.name}`, schema: REVIEW },
        )
      }
      return { ...r, verify: fixed || r.verify, review }
    }
    return { ...r, review }
  },
)

const done = results.filter(Boolean)
for (const r of done) {
  if (r.skipped) log(`${r.app}: not feasible — ${r.research ? r.research.infeasible_reason : 'research failed'}`)
  else log(`${r.app} → ${r.name}: verify ${r.verify && r.verify.passed ? 'pass' : 'FAIL'}, review ${r.review && r.review.approved ? 'approved' : 'not approved'}`)
}
return done
