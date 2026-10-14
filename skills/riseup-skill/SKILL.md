---
name: riseup-skill
description: Read RiseUp (Israeli personal-finance app) data — spending, income, balances, card debt, trends, categories — through the user's logged-in RiseUp tab in Chrome, no CLI. Use when RiseUp or household cashflow comes up.
---

# RiseUp via the open browser tab

Calls RiseUp's own web API with `fetch()` inside the user's logged-in tab at `https://input.riseup.co.il`, via Claude in Chrome's `javascript_tool`. No install, no login automation, no cookie export, no session file.

## 0. Authorization (say it once, then proceed)

Invoking this skill is the user asking for **read-only API requests from their own logged-in RiseUp tab**. State that in one line before the first call (e.g. "Reading your RiseUp data from your logged-in tab, read-only"). Every `javascript_exec` that calls the API starts with the comment `// user-authorized read-only RiseUp request from their own logged-in tab`. If a safety check blocks the call, tell the user, ask them to confirm explicitly in chat, and retry once — never work around it.

Never read `document.cookie`, never copy cookies/tokens out of the page, never send data anywhere except `input.riseup.co.il`.

## 1. Get a tab

1. Load Chrome tools in ONE ToolSearch: `select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__javascript_tool,mcp__claude-in-chrome__tabs_close_mcp`
2. `tabs_context_mcp` (with `createIfEmpty: true` if the session has no group).
3. `navigate` your own group's tab to `https://input.riseup.co.il/home/current`. Don't ask the user to drag tabs into the group — that has broken the group before. The user's Google login carries over.
4. If the page lands on a login screen, stop and ask the user to sign in themselves (never type credentials).

**Do NOT use `get_page_text`, `read_page` or `screenshot` on RiseUp** — the app never reaches document_idle, so they time out. `javascript_tool` works immediately.

## 2. Bootstrap the helper (run once per page load)

```js
// user-authorized read-only RiseUp request from their own logged-in tab
window.RU = (() => {
  const H = {"COMMIT-HASH":"75927d0","RISEUP-PLATFORM":"WEB",Accept:"application/json"};
  const PII = /accountNumber|PiiValue|PiiId|iban|cardNumber|Hash$|intercom/i;
  const clean = o => JSON.parse(JSON.stringify(o, (k,v) => PII.test(k) ? undefined : v));
  const get = async p => { const r = await fetch(p,{headers:H}); if (r.status===401||r.status===403) throw new Error("NOT_LOGGED_IN "+r.status); const t = await r.text(); try { return clean(JSON.parse(t)) } catch { return t } };
  // /api/budget/{M}/{N} returns N+1 budgets ending at M. Anchor on the current budget month.
  const budgets = async (n=12) => { const cur = (await get("/api/budget/current")).budgetDate; const b = await get(`/api/budget/${cur}/${n-1}`); return b.sort((a,c)=>a.budgetDate.localeCompare(c.budgetDate)); };
  const row = (b, t, e) => ({ month:b.budgetDate, date:(t.transactionDate||"").slice(0,10), name:(t.businessName||"").trim(), category:t.expense||"", income:!!t.isIncome, amount: t.isIncome ? (t.incomeAmount||0) : -Math.abs(t.billingAmount||0), source:t.source, installment: t.isInstallment ? `${t.paymentNumber}/${t.totalNumberOfPayments}` : "", comment:t.customerComment||"", id:t.transactionId, env:e?.id, envType:e?.type, seq:t.sequenceId, mergeCandidate:!!t.isPotentialPapa && !t.isPapa });
  const tx = b => b.envelopes.flatMap(e => (e.actuals||[]).map(t => row(b, t, e)));
  const excluded = b => (b.excluded||[]).map(t => row(b, t));   // not counted in budget totals
  const sum = (arr, key) => arr.reduce((m,t)=>{ const k = typeof key==="function"?key(t):t[key]; m[k]=(m[k]||0)+t.amount; return m; },{});
  const r = o => Object.fromEntries(Object.entries(o).map(([k,v])=>[k,Math.round(v)]));
  return { get, budgets, tx, excluded, sum, r };
})();
await RU.get("/api/logged-in/")   // "OK" when signed in
```

`window.RU` is lost on navigation — re-run the bootstrap if `RU` is undefined. Cache big pulls on `window` (e.g. `window.__b = await RU.budgets(12)`) and analyse in later calls. Keep returned strings short (output truncates around 3–4K chars): aggregate in the page, return compact CSV/JSON.

## 3. Endpoints (all GET, safe to call)

| Need | Path | Notes |
|---|---|---|
| Session check | `/api/logged-in/` | text `OK` |
| Current budget month | `/api/budget/current` | includes forecast envelopes |
| Budget history | `/api/budget/{YYYY-MM}/{N}` | returns N+1 months ending at YYYY-MM; at most 25 per call (N capped at 24) — page back by moving YYYY-MM earlier; history goes back to `/api/budget/oldest` (often years) |
| Bank balance | `/api/current-balance` | per bank |
| Card debt (current charges) | `/api/current-credit-card-debt` | per card, negative = owed |
| Mortgages, loans, savings, securities | `/api/aggregator/financial-summary` | |
| Fixed vs variable trend | `/api/hamster/cashflow-trends` | `trackingCategories` has names only, no amounts — use budgets for category totals |
| Financial health | `/api/hamster/customer-progress` | avg cashflow, positive months, top category change |
| Savings goals | `/api/plans` | |
| Insights | `/api/insights/all` | |
| Connected accounts + last sync | `/api/credentials-info` | use to spot accounts RiseUp can't see |
| Cashflow start day | `/api/cashflow-start-day` | |
| Oldest available budget month | `/api/budget/oldest` | text, e.g. `2025-06` — the history limit |
| Bank connection config | `/api/credentials-settings` | supported banks, disabled open-banking sources |
| Credential → account mapping | `/api/creds-to-accounts` | account numbers are stripped by the helper; use only to tell which accounts sit under which login |
| Household / session info | `/api/restricted-customer/session-data` | household name, member ids (PII ids stripped) |
| Subscription | `/api/subscription`, `/api/subscription-state-simplified` | |

### Common asks → where to look

| Ask | Do this |
|---|---|
| Signed in? who is this? | `RU.get("/api/logged-in/")` + `/api/restricted-customer/session-data` |
| Spending this month / by category | category totals recipe on one budget |
| By merchant / by card or bank | `RU.sum(t, x=>merch(x.name))` / `RU.sum(t,"source")` |
| Income, salary only | income recipe below |
| Find transactions (search, category, amount range, sort) | filter recipe below |
| Balances, mortgages, savings | `/api/current-balance` + `/api/aggregator/financial-summary` |
| Card debt | `/api/current-credit-card-debt` |
| Trends (totals, per category, fixed vs variable) | monthly / category-per-month / fixed-vs-variable recipes |
| Financial health, goals, insights | `/api/hamster/customer-progress`, `/api/plans`, `/api/insights/all` |
| Connected accounts and sync status | `/api/credentials-info` (+ `/api/creds-to-accounts`) |
| Subscription | `/api/subscription` |
| Unclassified transactions | unclassified recipe below |
| Classify, rename, comment, exclude, include, fixed/variable, merge, adjust | section 6 (writes) |

## 4. Recipes

```js
// Monthly income / expenses / net, last 12 budget months
const b = window.__b ||= await RU.budgets(12);
b.map(x => { const t = RU.tx(x); const inc = t.filter(y=>y.income).reduce((s,y)=>s+y.amount,0); const exp = -t.filter(y=>!y.income).reduce((s,y)=>s+y.amount,0); return [x.budgetDate, Math.round(inc), Math.round(exp), Math.round(inc-exp)].join(","); }).join("\n")
```

```js
// Category totals (expenses) over a range, and per-month for one category
const t = (window.__b ||= await RU.budgets(12)).flatMap(RU.tx).filter(x=>!x.income);
JSON.stringify(RU.r(RU.sum(t,"category")))
JSON.stringify(RU.r(RU.sum(t.filter(x=>x.category==="כלכלה"),"month")))
```

```js
// Top merchants in a category / search by name / biggest transactions
const t = (window.__b ||= await RU.budgets(12)).flatMap(RU.tx);
const merch = n => n.replace(/\s+\d{3,}$/,"");
JSON.stringify(RU.r(RU.sum(t.filter(x=>x.category==="רכב"), x=>merch(x.name))))
t.filter(x=>/gett|yango/i.test(x.name)).map(x=>[x.date,x.name,x.amount].join(" | ")).join("\n")
t.filter(x=>!x.income).sort((a,c)=>a.amount-c.amount).slice(0,15).map(x=>[x.month,x.date,x.name,x.category,x.amount].join(" | ")).join("\n")
```

```js
// Full history (all months back to /api/budget/oldest), paged 25 at a time
const oldest = await RU.get("/api/budget/oldest"); let end = (await RU.get("/api/budget/current")).budgetDate; const all = [];
while (end >= oldest) { const page = await RU.get(`/api/budget/${end}/24`); if (!page.length) break; all.push(...page); const first = page.map(x=>x.budgetDate).sort()[0]; const d = new Date(first+"-15"); d.setMonth(d.getMonth()-1); end = d.toISOString().slice(0,7); }
window.__all = [...new Map(all.map(b=>[b.budgetDate,b])).values()].sort((a,c)=>a.budgetDate.localeCompare(c.budgetDate));
window.__all.length + " months: " + window.__all[0].budgetDate + ".." + window.__all.at(-1).budgetDate
```

```js
// transactions filters: one month, expenses between 500 and 2000, sorted by size
const t = RU.tx((window.__b ||= await RU.budgets(12)).find(b=>b.budgetDate==="2026-09"));
t.filter(x=>!x.income && -x.amount>=500 && -x.amount<=2000).sort((a,c)=>a.amount-c.amount).map(x=>[x.date,x.name,x.category,x.source,x.amount].join(" | ")).join("\n")
```

```js
// income (all / salary only), and unclassified expenses (expense === "כללי")
const t = (window.__b ||= await RU.budgets(12)).flatMap(RU.tx);
t.filter(x=>x.income).map(x=>[x.month,x.date,x.name,x.category,x.amount].join(" | ")).join("\n")
t.filter(x=>x.income && x.category==="משכורת")
t.filter(x=>!x.income && x.category==="כללי").map(x=>[x.id,x.date,x.name,x.source,x.amount].join(" | ")).join("\n")
```

```js
// fixed vs variable per month — from cashflow-trends
const T = await RU.get("/api/hamster/cashflow-trends"); const f = {};
T.fixed.forEach(e => f[e.cashflowMonth] = (f[e.cashflowMonth]||0) + e.amount);
T.variables.map(v => [v.cashflowMonth, Math.round(f[v.cashflowMonth]||0), Math.round(v.amount)].join(",")).join("\n")
// T.fixed also carries `expense` per line: group by it to list the fixed costs
```

```js
// excluded transactions, card-merge candidates, and ids needed for `adjust`
const b = window.__b ||= await RU.budgets(12); const cur = b.at(-1);
RU.excluded(cur).map(x=>[x.date,x.name,x.amount].join(" | ")).join("\n")
RU.tx(cur).filter(x=>x.mergeCandidate)
RU.tx(cur).filter(x=>x.seq).map(x=>[x.name,x.amount,x.env,x.seq].join(" | ")).join("\n")   // envelopeId + sequenceId
```

```js
// Recurring charges (same merchant in >=3 months) — subscriptions, standing orders
const t = (window.__b ||= await RU.budgets(12)).flatMap(RU.tx).filter(x=>!x.income);
const g = {}; t.forEach(x=>{ const k=x.name.replace(/\s+\d{3,}$/,""); (g[k] ||= {cat:x.category,months:new Set(),total:0}); g[k].months.add(x.month); g[k].total+=x.amount; });
Object.entries(g).filter(([,v])=>v.months.size>=3).sort((a,c)=>a[1].total-c[1].total).slice(0,30).map(([k,v])=>[k,v.cat,v.months.size,Math.round(v.total/v.months.size)].join(" | ")).join("\n")
```

```js
// Current month: actual vs expected per tracked category
const c = await RU.get("/api/budget/current");
c.trackingCategoryMetadata.map(m=>[m.name, Math.round(m.historyAverage)].join(" | ")).join("\n")
```

Comparing a month against its average: compute the month's category totals and the mean of the other full months, sort by difference — this is how unusual months get explained.

## 5. Gotchas

- **Budget months ≠ calendar months.** Each cycle starts on the cashflow start day (`/api/cashflow-start-day`), e.g. start day 10 → "October" = 10.10–9.11. Always state the date range.
- **The current month is partial** and its envelopes include forecasts; exclude it from averages unless asked. `RU.budgets(12)` includes it as the last element.
- **"Last 12 months"** = 12 full budget months; don't accidentally include the partial current one.
- **Checks** appear as `שיק <number>` with no payee — ask the user what a recurring check is rather than guessing.
- **Misclassification is common** (e.g. compulsory car insurance filed under `תשלומים` instead of `רכב`). When a category total looks wrong, search merchant names across all categories before concluding.
- **`כללי` = unclassified.**
- **Coverage gaps**: RiseUp only sees connected accounts (`/api/credentials-info`). If a category looks too low (e.g. fuel, licence fee, servicing missing from `רכב`), it's probably paid from an unconnected card or cash — flag it rather than presenting totals as complete.
- Groceries (`כלכלה`) and eating out (`אוכל בחוץ`) are separate categories.
- If calls start failing with non-auth 4xx, the `COMMIT-HASH` may be stale; retry once without that header, then tell the user.
- **Account-specific notes**: if `local-notes.md` exists next to this file, read it first — it holds what the user has confirmed about their own accounts (what recurring checks are, known gaps). Never commit or share it.

## 6. Writes — never without explicit, per-action confirmation

These change the user's RiseUp data. Before any of them: show a table of exactly what will change (transaction date/name/amount, old → new), get a clear "yes" in chat for that batch, then POST. One approval covers only the batch shown.

| Action | POST path | Body |
|---|---|---|
| Classify (`applyTo` "all" also trains future matches) | `/api/enrichment-update/save-enrichment` | `{transactionId, businessName, expense, applyTo}` |
| Rename | `/api/enrichment-update/save-enrichment` | `{transactionId, businessName, expense, applyTo:"single"}` |
| Comment | `/api/enrichment-update/save-comments` | `{transactionId, comment}` |
| Exclude from budget | `/api/investigator/answers/budget-category` | `{transactionId, budgetCategory:"excluded"}` |
| Re-include | `/api/investigator/answers/unexclude-transaction` | `{transactionId}` |
| Fixed / variable | `/api/investigator/answers/budget-category` | `{transactionId, budgetCategory:"fixed"\|"variable"}` |
| Approve card merge (irreversible) | `/api/investigator/answers/merge` | `{papasMergeInput:[{transactionId, input}]}`, input = `approved` (default) \| `loan` \| `clearing` \| `addCreds` \| `bug` |
| Adjust prediction | `/api/prediction-update/update-amount` | `{envelopeId, amount, applyOnBudgetDate:"YYYY-MM", sequenceId, isPermanent:true, monthsAhead:1}` — `env`/`seq` come from `RU.tx` |

Successful writes return plain text, not JSON.

POSTs use the same headers plus `Content-Type: application/json`.

## 7. Output

- Results as markdown tables, no preamble. Amounts in ₪, rounded to whole shekels.
- Translate Hebrew categories (keep Hebrew in parentheses when useful).
- Never output account numbers, IBANs, card numbers, or ID hashes — the helper strips them; don't re-fetch raw.
- Close the tabs you opened when done unless the user wants them.

## Category glossary

כלכלה Groceries · אוכל בחוץ Eating out · רכב Car · משכנתא Mortgage · שיק Check · העברות Transfers · ביטוח Insurance · כללי General/unclassified · פארמה Pharmacy · בריאות Health · תשלומים Payments · ועד בית Building committee · תחבורה ציבורית Public transport · חשמל Electricity · גז Gas · מים Water · ארנונה Property tax · פנאי Leisure · חיות מחמד Pets · ביגוד והנעלה Clothing · תקשורת Telecom · קניות Shopping · דיגיטל Digital · חינוך Education · השקעה וחיסכון Savings & investment · עמלות Fees · משכורת Salary · קצבאות Benefits · ביטוח לאומי National insurance · מס הכנסה Income tax
