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

The file is self-contained: `lean AuthVerify.lean` (Lean 4, only `Std`).
-/

import Std

/-! ## Part 1 — Definitions -/

/-! ### 1.1 The Core Type

Three values, not two. The third state — `notApplicable` — is the important
extra. It is the difference between "this rule says *no*" and "this rule has
*nothing to say*". Most access-control bugs live in that gap. -/

inductive Decision
  | permit
  | deny
  | notApplicable
  deriving DecidableEq, Repr

/-! ### 1.2 Domain Types -/

structure Request where
  user     : String
  action   : String
  resource : String
  deriving DecidableEq, Repr

structure Rule where
  equivalent : Request → Bool
  outcome    : Decision

abbrev Policy := List Rule

/-! ### 1.3 The Combinator (deny-overrides) -/

@[simp, grind =] def combine : Decision → Decision → Decision
  | .deny,          _       => .deny
  | _,              .deny   => .deny
  | .permit,        _       => .permit
  | _,              .permit => .permit
  | .notApplicable, d       => d

@[simp, grind] def denyOverrides : List Decision → Decision :=
  List.foldr combine .notApplicable

/-! ### 1.4 Evaluation -/

@[simp, grind] def evaluate (policy : Policy) (req : Request) : Decision :=
  denyOverrides (policy.filterMap fun rule =>
    if rule.equivalent req then some rule.outcome else none)

/-! ### 1.5 Optimization -/

def optimize (policy : Policy) : Policy :=
  policy.filter fun rule => rule.outcome != .notApplicable

/-! ### 1.6 Closing the World -/

@[simp, grind =]
def resolve (default : Decision) : Decision → Decision
  | .notApplicable => default
  | d              => d

@[simp, grind =]
def enforce (policy : Policy) (req : Request) : Decision :=
  resolve .deny (evaluate policy req)

/-! ## Part 2 — Helper Theorems -/

/-! ### 2.1 The Monoid Laws of `combine` -/

@[simp, grind =] theorem combine_deny_left  (d : Decision) : combine .deny d = .deny := by grind
@[simp, grind =] theorem combine_deny_right (d : Decision) : combine d .deny = .deny := by grind

@[simp, grind =] theorem combine_na_left  (d : Decision) : combine .notApplicable d = d := by
  cases d <;> rfl
@[simp, grind =] theorem combine_na_right (d : Decision) : combine d .notApplicable = d := by
  cases d <;> rfl

@[simp, grind =] theorem denyOverrides_nil : denyOverrides [] = .notApplicable := rfl

@[simp, grind =] theorem denyOverrides_cons (d : Decision) (rest : List Decision) :
    denyOverrides (d :: rest) = combine d (denyOverrides rest) := rfl

@[simp, grind =] theorem denyOverrides_deny (rest : List Decision) :
    denyOverrides (.deny :: rest) = .deny := by grind

@[simp, grind =] theorem denyOverrides_na (rest : List Decision) :
    denyOverrides (.notApplicable :: rest) = denyOverrides rest := by grind

@[grind =] theorem combine_idem (d : Decision) : combine d d = d := by
  grind [= combine.eq_def]

@[grind =] theorem combine_comm (a b : Decision) : combine a b = combine b a := by
  grind [= combine.eq_def]

@[grind =] theorem combine_assoc (a b c : Decision) :
    combine (combine a b) c = combine a (combine b c) := by
  grind [= combine.eq_def]

/-! ### 2.3 What "deny-overrides" Actually Means -/

theorem deny_wins (ds : List Decision) (h : Decision.deny ∈ ds) :
    denyOverrides ds = .deny := by
  induction ds with
  | nil => simp at h
  | cons d rest ih => grind

theorem not_deny_of_no_deny (ds : List Decision) (h : Decision.deny ∉ ds) :
    denyOverrides ds ≠ .deny := by
  induction ds with
  | nil => simp
  | cons d rest ih =>
    have hr : Decision.deny ∉ rest := fun hm => h (List.mem_cons_of_mem _ hm)
    have := ih hr
    cases d <;> grind

/-! ### 2.4 Optimization is Sound -/

@[simp, grind .]
theorem optimize_equiv (p : Policy) (req : Request) :
    evaluate (optimize p) req = evaluate p req := by
  simp only [evaluate, optimize]
  induction p with
  | nil => rfl
  | cons rule rest ih => grind

theorem optimize_no_escalation (p : Policy) (req : Request) :
    evaluate p req = .deny → evaluate (optimize p) req ≠ .permit := by
  grind only [optimize_equiv]

/-! ### 2.5 The Fail-closed Gate is Honest -/

theorem enforce_permit_iff (policy : Policy) (req : Request) :
    enforce policy req = .permit ↔ evaluate policy req = .permit := by
  cases h : evaluate policy req <;> grind

theorem enforce_optimize_equiv (p : Policy) (req : Request) :
    enforce (optimize p) req = enforce p req := by
  grind

/-! ## Part 3 — Macros & DSL -/

macro "allow" u:str "to" a:str "on" r:str : term =>
  `(Rule.mk (fun req => req.user == $u && req.action == $a && req.resource == $r) .permit)

macro "forbid" u:str "to" a:str "on" r:str : term =>
  `(Rule.mk (fun req => req.user == $u && req.action == $a && req.resource == $r) .deny)

macro "abstain" u:str "on" r:str : term =>
  `(Rule.mk (fun req => req.user == $u && req.resource == $r) .notApplicable)

macro "auth_prove" : tactic =>
  `(tactic|
    first
      | decide
      | (intros <;>
         simp [evaluate, optimize, enforce, List.filterMap, List.filter] <;>
         grind +locals))

/-! ## Part 4 — Verifying AI Agent Workflows -/

/-! ### 4.1 The Agent Policy -/

def agentPolicy : Policy := [
  allow   "summarizer" to "read"   on "/code",
  allow   "summarizer" to "read"   on "/logs",
  forbid  "summarizer" to "write"  on "/code",
  allow   "deployer"   to "deploy" on "/prod",
  forbid  "deployer"   to "delete" on "/prod",
  abstain "auditor"                on "/logs",
]

/-! ### 4.2 Proven Decisions -/

theorem summarizer_may_read_code :
    evaluate agentPolicy ⟨"summarizer", "read", "/code"⟩ = .permit := by auth_prove

theorem summarizer_cannot_write_code :
    evaluate agentPolicy ⟨"summarizer", "write", "/code"⟩ = .deny := by auth_prove

theorem deployer_may_deploy :
    evaluate agentPolicy ⟨"deployer", "deploy", "/prod"⟩ = .permit := by auth_prove

theorem rogue_agent_unspecified :
    evaluate agentPolicy ⟨"rogue", "read", "/prod"⟩ = .notApplicable := by auth_prove

theorem auditor_explicitly_undecided :
    evaluate agentPolicy ⟨"auditor", "read", "/logs"⟩ = .notApplicable := by auth_prove

theorem deployer_cannot_delete_prod :
    evaluate agentPolicy ⟨"deployer", "delete", "/prod"⟩ = .deny := by auth_prove

theorem optimize_keeps_deployer_deny :
    evaluate (optimize agentPolicy) ⟨"deployer", "delete", "/prod"⟩ = .deny := by auth_prove

theorem rogue_agent_denied_at_gate :
    enforce agentPolicy ⟨"rogue", "read", "/prod"⟩ = .deny := by auth_prove

theorem all_abstain_is_silent (req : Request) :
    evaluate [abstain "x" on "/a", abstain "y" on "/b"] req = .notApplicable := by auth_prove

/-! ### 4.3 DSL-direct -/

theorem allow_builds_a_permit_rule :
    (allow "him" to "read" on "/help").outcome = .permit := by auth_prove

theorem allow_fires_on_its_request :
    (allow "him" to "read" on "/help").equivalent ⟨"him", "read", "/help"⟩ = true := by auth_prove

theorem forbid_builds_a_deny_rule :
    (forbid "him" to "delete" on "/prod").outcome = .deny := by auth_prove

theorem inline_allow_permits :
    evaluate [allow "him" to "read" on "/help"] ⟨"him", "read", "/help"⟩ = .permit := by auth_prove

theorem inline_forbid_denies :
    evaluate [forbid "him" to "delete" on "/prod"] ⟨"him", "delete", "/prod"⟩ = .deny := by auth_prove

theorem abstain_builds_a_silent_rule :
    (abstain "him" on "/logs").outcome = .notApplicable := by auth_prove

theorem inline_abstain_is_silent :
    evaluate [abstain "him" on "/logs"] ⟨"him", "read", "/logs"⟩ = .notApplicable := by auth_prove

theorem inline_deny_overrides_allow :
    evaluate
      [ allow  "him" to "read" on "/help",
        forbid "him" to "read" on "/help" ]
      ⟨"him", "read", "/help"⟩ = .deny := by auth_prove

theorem inline_policy_fails_closed :
    enforce
      [ allow  "him" to "read"  on "/help",
        forbid "him" to "write" on "/help" ]
      ⟨"him", "read", "/secrets"⟩ = .deny := by auth_prove
