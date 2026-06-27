import Std

/-!
# AuthVerify.lean

Companion code for **"The Way of Building Software That Proves Itself Correctness"**.

Link: https://anirudhg07.github.io/src/blog.html?post=the-way-of-building-software-that-proves-itself-correctness

A tiny, fully-verified authorization engine. The whole story is that we
model "no opinion" as a *first-class value* (`notApplicable`) rather than
sneaking it in as a `false` or an `Option`. Once that value exists, the
algebra falls out, the proofs get short, and the machine does the work.

The file is laid out in four parts:

1. **Definitions** — the data model and the functions over it.
2. **Helper theorems** — the reusable theory; we tag everything so the
   automation absorbs it.
3. **Macros & DSL** — keywords that let policies read like prose, plus the
   `auth_prove` tactic that bottles the whole theory.
4. **AI agent workflows** — concrete agent requests whose decisions we
   *prove*, discharged with `auth_prove` alone.

The file is self-contained: `lean auth.lean` (Lean 4, only `Std`).
-/

/-!
## Part 1 — Definitions
-/

/-! ### 1.1 The Core Type

Three values, not two. The third state — `notApplicable` — is the important
extra. It is the difference between "this rule says *no*" and "this rule has
*nothing to say*". Most access-control bugs live in that gap. -/

-- #show
inductive Decision
  | permit
  | deny
  | notApplicable
  deriving DecidableEq, Repr
-- #endshow

/-! ### 1.2 Domain Types

A `Request` is what gets checked. A `Rule` is what checks it: a predicate
saying *which* requests it speaks to, plus the `Decision` it hands down when
it does. A `Policy` is just a list of rules. -/

-- #show
structure Request where
  user     : String
  action   : String
  resource : String
  deriving DecidableEq, Repr

structure Rule where
  equivalent : Request → Bool
  outcome    : Decision

abbrev Policy := List Rule
-- #endshow

/-! ### 1.3 The Combinator (deny-overrides)

How do several rules' opinions combine into one? With the classic
*deny-overrides* rule: any `deny` wins, otherwise any `permit` wins, and
`notApplicable` is silence.

The point worth internalising: `combine` is a **commutative monoid**. It is
the join (`max`) of the order `notApplicable < permit < deny`. `notApplicable`
is the identity, `deny` is the absorbing top. That single algebraic fact is
what makes every proof below cheap — `denyOverrides` is then "fold a monoid
over a list", and order/duplication/silence stop mattering. -/

-- #show
@[simp, grind =] def combine : Decision → Decision → Decision
  | .deny,          _       => .deny
  | _,              .deny   => .deny
  | .permit,        _       => .permit
  | _,              .permit => .permit
  | .notApplicable, d       => d

@[simp, grind] def denyOverrides : List Decision → Decision :=
  List.foldr combine .notApplicable

-- #endshow

/-! ### 1.4 Evaluation

Run a policy against a request: collect the outcomes of every *matching*
rule, then resolve them with `denyOverrides`. Non-matching rules contribute
nothing — which, because `notApplicable` is the identity, is the same as
contributing `notApplicable`. -/

-- #show
@[simp, grind] def evaluate (policy : Policy) (req : Request) : Decision :=
  denyOverrides (policy.filterMap fun rule =>
    if rule.equivalent req then some rule.outcome else none)
-- #endshow

/-! ### 1.5 Optimization

Strip rules whose outcome is `notApplicable`: silence doesn't vote, so
removing silent rules can never change a result. -/

def optimize (policy : Policy) : Policy :=
  policy.filter fun rule => rule.outcome != .notApplicable

/-! ### 1.6 Closing the World

In production a gateway must ultimately answer yes or no; `notApplicable`
cannot be served over the wire. The honest place to make that choice is *one*
explicit, auditable function — a fail-closed default — not scattered through
the rules. `enforce` collapses silence into `deny`. Keeping silence as its
own value until this final step is exactly what let us reason cleanly. -/

@[simp, grind =]
def resolve (default : Decision) : Decision → Decision
  | .notApplicable => default
  | d              => d

@[simp, grind =]
def enforce (policy : Policy) (req : Request) : Decision :=
  resolve .deny (evaluate policy req)

/-!
## Part 2 — Helper Theorems

Each lemma is tagged (`@[simp]` / `@[grind]`) so it becomes a reflex for the
automation. We are not just proving facts; we are teaching the machine to
think in this domain, so that Part 4 can discharge real requests in one line.
First the monoid laws, then the fold-level shortcuts, then the structural
properties of `optimize`/`enforce`.
-/

/-! ### 2.1 The Monoid Laws of `combine` -/

-- #show
-- `deny` is the absorbing top: it wins on either side.
@[simp, grind =] theorem combine_deny_left  (d : Decision) : combine .deny d = .deny := by grind
@[simp, grind =] theorem combine_deny_right (d : Decision) : combine d .deny = .deny := by grind

-- `notApplicable` is the identity: silence on either side changes nothing.
@[simp, grind =] theorem combine_na_left  (d : Decision) : combine .notApplicable d = d := by
  cases d <;> rfl
@[simp, grind =] theorem combine_na_right (d : Decision) : combine d .notApplicable = d := by
  cases d <;> rfl

@[simp, grind =] theorem denyOverrides_nil : denyOverrides [] = .notApplicable := rfl

@[simp, grind =] theorem denyOverrides_cons (d : Decision) (rest : List Decision) :
    denyOverrides (d :: rest) = combine d (denyOverrides rest) := rfl

@[simp, grind =] theorem denyOverrides_deny (rest : List Decision) :
    denyOverrides (.deny :: rest) = .deny := by grind

-- The headline behaviour of `notApplicable`: a silent vote at the head just
-- disappears. This is *why* `optimize` is sound.
@[simp, grind =] theorem denyOverrides_na (rest : List Decision) :
    denyOverrides (.notApplicable :: rest) = denyOverrides rest := by grind

-- #endshow

-- The remaining monoid laws: idempotent, commutative, associative — i.e. a join.
@[grind =] theorem combine_idem (d : Decision) : combine d d = d := by
  grind [= combine.eq_def]

@[grind =] theorem combine_comm (a b : Decision) : combine a b = combine b a := by
  grind [= combine.eq_def]

@[grind =] theorem combine_assoc (a b c : Decision) :
    combine (combine a b) c = combine a (combine b c) := by
  grind [= combine.eq_def]

/-! ### 2.2 Fold-level Shortcuts for `denyOverrides` -/



/-! ### 2.3 What "deny-overrides" Actually Means

The two structural theorems that capture the policy's intent. They are also
what stops `notApplicable` from ever being mistaken for a soft `permit`. -/

-- A single `deny` anywhere in the list forces the whole result to `deny`.
theorem deny_wins (ds : List Decision) (h : Decision.deny ∈ ds) :
    denyOverrides ds = .deny := by
  induction ds with
  | nil => simp at h
  | cons d rest ih =>
    grind

-- With no `deny` present, the result is never `deny` — silence and permits
-- cannot manufacture a denial.
theorem not_deny_of_no_deny (ds : List Decision) (h : Decision.deny ∉ ds) :
    denyOverrides ds ≠ .deny := by
  induction ds with
  | nil => simp
  | cons d rest ih =>
    have hr : Decision.deny ∉ rest := fun hm => h (List.mem_cons_of_mem _ hm)
    have := ih hr
    cases d <;> grind

/-! ### 2.4 Optimization is Sound

An optimized policy (silent rules stripped) decides *every* request exactly
as the original. The proof is one induction and a `grind` per step, because
§2.2 already taught the machine that `notApplicable` is the fold's identity. -/

-- #show
@[simp, grind .]
theorem optimize_equiv (p : Policy) (req : Request) :
    evaluate (optimize p) req = evaluate p req := by
  simp only [evaluate, optimize]
  induction p with
  | nil => rfl
  | cons rule rest ih =>
    grind

-- #endshow

-- #show

/- The safety corollary that matters: optimization must never *widen* access.
If the original denied a request, no optimized version may permit it. -/
theorem optimize_no_escalation (p : Policy) (req : Request) :
    evaluate p req = .deny → evaluate (optimize p) req ≠ .permit := by
  grind only [optimize_equiv]

-- #endshow

/-! ### 2.5 The Fail-closed Gate is Honest -/

-- The gateway permits a request only when the policy genuinely permitted it —
-- silence becomes `deny`, never `permit`.
theorem enforce_permit_iff (policy : Policy) (req : Request) :
    enforce policy req = .permit ↔ evaluate policy req = .permit := by
  cases h : evaluate policy req <;> grind

-- Optimization is still safe under enforcement: same answer at the gate.
theorem enforce_optimize_equiv (p : Policy) (req : Request) :
    enforce (optimize p) req = enforce p req := by
  grind

/-!
## Part 3 — Macros & DSL

Two ergonomic layers built on Parts 1–2:

* a rule DSL (`allow` / `forbid` / `abstain`) so policies read like a document,
* the `auth_prove` tactic, which packs the entire tagged theory into one word.

### 3.1 The Rule DSL

Three keywords:

* `allow  u to a on r` — a `permit` rule,
* `forbid u to a on r` — a `deny`  rule,
* `abstain u on r`      — a rule that matches but deliberately says
  `notApplicable`. This is the keyword that puts our third value to work:
  it carves out an explicit "no opinion here" hole in the policy. -/

-- #show
macro "allow" u:str "to" a:str "on" r:str : term =>
  `(Rule.mk (fun req => req.user == $u && req.action == $a && req.resource == $r) .permit)

macro "forbid" u:str "to" a:str "on" r:str : term =>
  `(Rule.mk (fun req => req.user == $u && req.action == $a && req.resource == $r) .deny)

-- `abstain` matches on *any* action for a (user, resource) pair and yields
macro "abstain" u:str "on" r:str : term =>
  `(Rule.mk (fun req => req.user == $u && req.resource == $r) .notApplicable)
-- #endshow

/-! ### 3.2 `auth_prove` — A Custom Domain Tactic

Rather than reaching for `simp`/`grind` by hand on every goal, we bottle the
recipe. Because every lemma in Part 2 is tagged, this one tactic carries the
entire theory with it. It is not magic — hard goals still need new lemmas —
but for concrete requests it just finishes the job. Part 4 uses *only* this. -/

-- #show
macro "auth_prove" : tactic =>
  `(tactic|
    first
      -- A concrete request reduces to a value, so let the kernel just compute it.
      | decide
      -- A request with symbolic fields needs the tagged theory + case-splitting.
      | (intros <;>
         simp [evaluate, optimize, enforce, List.filterMap, List.filter] <;>
         grind +locals))

-- #endshow

/-!
## Part 4 — Verifying AI Agent Workflows

This is where the model earns its keep. An autonomous agent — or a fleet of
them — issues requests against a policy. Before any agent acts, we don't
*hope* the policy allows it; we *prove* the decision the policy returns. Each
theorem below is a machine-checked capability (or restriction) of an agent,
discharged entirely by `auth_prove`.

Crucially the proofs cover all three outcomes: an explicit `permit`, an
explicit `deny`, and — the case a Boolean model could not even state —
`notApplicable`, an agent the policy has no opinion about. Pair that with the
fail-closed `enforce` from §1.6 and you get the headline safety property: any
capability not *positively* granted is denied at the gate.
-/

/-! ### 4.1 The Agent Policy (written in the DSL)

A fleet of three agents. `summarizer` reads but may not write; `deployer`
ships to prod but may never delete it; `auditor` is explicitly left undecided
on the logs — a hole we have chosen not to fill with a rule. -/

-- #show

def agentPolicy : Policy := [
  allow   "summarizer" to "read"   on "/code",
  allow   "summarizer" to "read"   on "/logs",
  forbid  "summarizer" to "write"  on "/code",
  allow   "deployer"   to "deploy" on "/prod",
  forbid  "deployer"   to "delete" on "/prod",
  abstain "auditor"                on "/logs",
]
-- #endshow

/-! ### 4.2 Proven Decisions — `auth_prove` only
-/

-- #show

-- The summarizer agent may read the codebase.
theorem summarizer_may_read_code :
    evaluate agentPolicy ⟨"summarizer", "read", "/code"⟩ = .permit := by
  auth_prove

-- ...but is explicitly forbidden from writing to it.
theorem summarizer_cannot_write_code :
    evaluate agentPolicy ⟨"summarizer", "write", "/code"⟩ = .deny := by
  auth_prove

-- The deployer agent may ship to production.
theorem deployer_may_deploy :
    evaluate agentPolicy ⟨"deployer", "deploy", "/prod"⟩ = .permit := by
  auth_prove

-- An unprovisioned agent matches no rule: the policy has *no opinion* on it.
theorem rogue_agent_unspecified :
    evaluate agentPolicy ⟨"rogue", "read", "/prod"⟩ = .notApplicable := by
  auth_prove

-- The auditor is matched *only* by an `abstain` rule: the policy speaks about
-- it and still deliberately says nothing — a state a Bool could never capture.
theorem auditor_explicitly_undecided :
    evaluate agentPolicy ⟨"auditor", "read", "/logs"⟩ = .notApplicable := by
  auth_prove

-- #endshow

-- ...but can never delete it — deny overrides.
theorem deployer_cannot_delete_prod :
    evaluate agentPolicy ⟨"deployer", "delete", "/prod"⟩ = .deny := by
  auth_prove


-- Optimisation never changes an agent's decision: dropping the auditor's
-- silent rule leaves the deployer's denial exactly where it was.
theorem optimize_keeps_deployer_deny :
    evaluate (optimize agentPolicy) ⟨"deployer", "delete", "/prod"⟩ = .deny := by
  auth_prove

-- The fail-closed gate, end to end: an unspecified capability is denied —
-- never permitted by accident. This is the property you actually ship.
theorem rogue_agent_denied_at_gate :
    enforce agentPolicy ⟨"rogue", "read", "/prod"⟩ = .deny := by
  auth_prove

-- And the limiting case: a policy of nothing but silence decides nothing, for
-- any agent and any request whatsoever.
theorem all_abstain_is_silent (req : Request) :
    evaluate [abstain "x" on "/a", abstain "y" on "/b"] req = .notApplicable := by
  auth_prove

/-! ### 4.3 DSL-direct — Interpreting the Keywords *in* the Statement

The same facts again, but with no intermediate `def`: the policy is written
out with `allow` / `forbid` / `abstain` right inside the theorem, so each
statement reads as an English sentence and is *interpreted* — expanded to a
`Rule`, evaluated, decided — on the spot. Same one-word proof, `auth_prove`.

First, the keywords examined one rule at a time. "`allow` him to read `/help`"
really is a `permit` rule, and its predicate fires on exactly that request: -/

theorem allow_builds_a_permit_rule :
    (allow "him" to "read" on "/help").outcome = .permit := by
  auth_prove

theorem allow_fires_on_its_request :
    (allow "him" to "read" on "/help").equivalent ⟨"him", "read", "/help"⟩ = true := by
  auth_prove

theorem forbid_builds_a_deny_rule :
    (forbid "him" to "delete" on "/prod").outcome = .deny := by
  auth_prove

/-! Now whole policies, spelled out inline and evaluated against a request. -/

-- "allow him to read /help" → he may read /help.
theorem inline_allow_permits :
    evaluate [allow "him" to "read" on "/help"] ⟨"him", "read", "/help"⟩ = .permit := by
  auth_prove

-- "forbid him to delete /prod" → he may not.
theorem inline_forbid_denies :
    evaluate [forbid "him" to "delete" on "/prod"] ⟨"him", "delete", "/prod"⟩ = .deny := by
  auth_prove

-- #show

theorem abstain_builds_a_silent_rule :
    (abstain "him" on "/logs").outcome = .notApplicable := by
  auth_prove

-- "abstain him on /logs" → the policy stays silent about him.
theorem inline_abstain_is_silent :
    evaluate [abstain "him" on "/logs"] ⟨"him", "read", "/logs"⟩ = .notApplicable := by
  auth_prove

-- #endshow

-- Allow *and* forbid the same request inline: deny overrides, in one statement.
theorem inline_deny_overrides_allow :
    evaluate
      [ allow  "him" to "read" on "/help",
        forbid "him" to "read" on "/help" ]
      ⟨"him", "read", "/help"⟩ = .deny := by
  auth_prove

-- A multi-rule policy written entirely inline, then enforced at the gate:
-- "him" is granted nothing for "/secrets", so the fail-closed gate denies.
theorem inline_policy_fails_closed :
    enforce
      [ allow  "him" to "read"  on "/help",
        forbid "him" to "write" on "/help" ]
      ⟨"him", "read", "/secrets"⟩ = .deny := by
  auth_prove

