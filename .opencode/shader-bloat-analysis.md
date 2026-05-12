# FIR Shader Code Bloat Analysis

## Executive Summary

The FIR DSL generates SPIR-V binaries with no optimization passes. For complex shaders (e.g., the path tracer light fragment shader at ~11MB), instruction explosion comes from **full loop unrolling**, **no function inlining**, **no CSE**, and **element-wise decomposition** of composite operations. No single issue causes all bloat — it's the compounding effect of all of them.

---

## Critical Issues (High Impact)

### 1. `storeAtTypeThroughAccessChain` — Full Unrolling of `OfType` Stores

**File:** `src/CodeGen/Optics.hs:758-828`

When `assign` is used with an `OfType` optic (writing a scalar into every element of a matrix/array/vector/struct), the code **fully unrolls** element-wise stores.

The code itself acknowledges this (`Optics.hs:801`):
```haskell
-- TODO: should be a loop as opposed to being fully unrolled,
-- but creating loops is unfortunately quite cumbersome
```

**Cost:** A 4×4 matrix scalar-assign generates **48 instructions** (16 × `OpAccessChain` + 16 × `OpStore` + 16 × `constID`). A loop would need ~6. For large arrays, this is catastrophic.

**Fix:** Emit a SPIR-V `while` loop (the `CodeGen.CFG.while` infrastructure exists). Even for 4×4 matrices, a loop saves ~40 instructions per such store.

---

### 2. `GradedMappendF` — Fully Unrolled Array/Struct Concatenation

**File:** `src/CodeGen/Composite.hs:185-205`

Array concatenation via `Semigroup`/`Monoid` instances extracts every element individually, then reconstructs.

The code literally says (`Composite.hs:200`):
```haskell
-- should probably use a loop instead of this, but nevermind
```

**Cost:** Concatenating `Array 64 a` ⊕ `Array 64 a` emits **129 instructions** (128 × `OpCompositeExtract` + 1 × `OpCompositeConstruct`). Same for structs with many fields.

**Fix:** For arrays, emit a loop that copies elements. For structs, this is harder to avoid but struct field counts are typically small.

---

### 3. No Function Inlining

**File:** `src/CodeGen/Functions.hs:145-162`

Every `def` that creates a function (via `FunDefF`) generates a separate SPIR-V function, and every call site emits `OpFunctionCall`. There is no inlining — not even for single-call-site functions or trivial bodies.

The `FunctionControl` hint (`Inline`/`DontInline`) is stored in the definition but never acted upon by the call site.

**Cost:** Each function call has SPIR-V calling convention overhead. More importantly, the function boundary prevents any cross-call optimization (CSE, constant folding, dead code elimination).

**Fix:** Implement a simple inlining pass: for functions called once, or marked `Inline`, substitute the body at the call site during AST→AST optimization before code generation.

---

### 4. No Common Subexpression Elimination (CSE)

The code generator emits instructions linearly with no analysis of previously emitted instructions. The same computation under different `def` names produces duplicate instruction sequences.

The only "sharing" is SSA name reuse when referencing the same `def` binding. But structurally identical expressions under different names are fully duplicated.

**Cost:** In a complex shader like the path tracer, many lighting calculations (dot products, normalizations, Fresnel terms) are repeated across code paths. Each repetition emits full instruction sequences.

**Fix:** Add a CSE pass at the `CGMonad` level — before emitting an instruction, check if an equivalent one was already emitted (hash-cons on operation + argument IDs). This is straightforward for pure operations.

---

## Moderate Issues (Medium Impact)

### 5. Vector Applicative Fallback — Element-wise CodeGen

**File:** `src/CodeGen/Applicative.hs:253-266`

When vectorization via `applyIdiomV` fails (returns `Nothing`), the code generates **n independent codegen passes** for a `V n` vector, then one `CompositeConstruct`.

`applyIdiomV` only succeeds for:
- `MkVectorF`, `UnsafeCoerceF`, `LitF` — trivial
- `PrimOpF` — only when SPIR-V has a native vectorized form
- `SMul` (scalar-vector multiply)

**Everything else** hits the `OVERLAPPABLE` instance (`Applicative.hs:387-388`) which returns `Nothing`.

This means lambdas, conditionals, let-bindings, function calls, image operations inside a vector applicative context all expand element-by-element. For `V 4`, that's **4× instruction multiplier**.

**Cost:** Any `fmap`/`<*>` over a vector with a non-`PrimOp` function expands fully. Common in lighting calculations (e.g., `fmap (\x -> if x > 0 then x else 0) vec`).

**Fix:** Expand the vectorization whitelist. At minimum, handle `IfF`/`SelectionF` (vector comparisons), `LetF`, and single-argument `AppF` (beta-reduced lambdas).

---

### 6. Matrix Operations — Per-Column Without Cross-Column Optimization

**File:** `src/CodeGen/Applicative.hs:267-280`

Matrix applicative operations are decomposed into per-column vector operations via `distributeMatrixIdiom`. No attempt to use native SPIR-V matrix ops (`OpMatrixTimesMatrix`, `OpMatrixTimesVector`, `OpVectorTimesMatrix`).

**Fix:** Add a `MatPrimOp` recognition path similar to `VecPrimOp` for common matrix operations.

---

### 7. No Dead Code Elimination (DCE)

SPIR-V modules include all declared types, constants, decorations, and variables — even if unused. The code generator accumulates everything into `CGState` maps and serializes all of it in `Binary.putModule`.

**Fix:** A dead code elimination pass on the generated module: trace from entry points, mark reachable instructions, remove the rest. SPIR-V tools like `spirv-opt` do this, but it would be better to not emit dead code.

---

## Low Impact / Compile-Time Issues

### 8. Loop Two-Pass Code Generation (Compile-time only)

**File:** `src/CodeGen/CFG.hs:472-536`

Each `while` loop runs the body code generation **twice**:
1. **Dry run** — to learn which variables change during iteration (for phi-node construction)
2. **Real run** — with phi-aware bindings, emitting actual instructions

For nested loops, this is multiplicative: N-deep nesting generates the innermost body **2^N** times in compile time.

**Cost:** Exponential compile-time, but **zero runtime cost** — only the real run's bytes end up in the binary.

**Fix:** Replace the dry run with a lightweight binding-simulation pass that tracks mutations without emitting instructions. Add a "dry-run mode" flag to `CGMonad` that suppresses `instruction` calls.

---

### 9. `reverseConstantLookup` — Linear Scan

**File:** `src/CodeGen/Pointers.hs:190-207`

Each runtime index in an access chain triggers a full scan of all known constants to reverse-lookup the constant ID.

**Cost:** O(n) per index per access chain, where n = total number of constants. Not code bloat, but slows compilation.

**Fix:** Maintain a reverse map `Map ID AConstant` alongside `knownConstants`.

---

## What IS Working Well

| Feature | Status |
|---------|--------|
| Type deduplication | Full — `Map SPIRV.PrimTy Instruction`, one decl per unique type |
| Constant deduplication | Full — `Map AConstant Instruction`, one decl per unique value |
| `let'` / monadic bind | Zero overhead — compile-time only |
| `def` for scalars | Zero overhead — compile-time name binding |
| Optic access chains | Optimal — `OpAccessChain` + `OpLoad`/`OpStore` = 2 instructions |
| Phi nodes | Minimal — one per actually-changing variable |
| Array applicative (via loop) | Good — genuine `while` loop, O(k) instructions regardless of size |

---

## Recommended Optimization Priority

| Priority | Optimization | Estimated Size Reduction | Effort |
|----------|-------------|-------------------------|--------|
| **P0** | CSE pass (hash-cons on operation+args) | 20-40% | Medium |
| **P0** | Function inlining (single-call-site) | 15-30% | Medium |
| **P1** | `OfType` store → loop | 5-15% per use site | Low |
| **P1** | Expand vectorization whitelist | 10-25% for lighting math | Medium |
| **P2** | `GradedMappendF` → loop for arrays | 5-10% if used | Low |
| **P2** | Dead code elimination pass | Variable | High |
| **P3** | Matrix native ops | 5-10% for matrix-heavy shaders | Medium |
| **P3** | Dry-run → binding simulation | Compile-time only | Medium |

---

## Architectural Note

The fundamental issue is that FIR has **no IR optimization layer**. The pipeline is:

```
Haskell AST → CodeGen → SPIR-V Binary
```

It needs to be:

```
Haskell AST → AST Optimization → CodeGen → SPIR-V Binary Optimization → SPIR-V Binary
```

The most impactful changes would be:
1. **Pre-codegen AST passes**: inlining, beta-reduction, constant folding, dead binding elimination
2. **Post-codegen instruction passes**: CSE, DCE, peephole optimization

Alternatively, running `spirv-opt` (from the SPIR-V tools suite) as a post-processing step with flags like `-O` or `--eliminate-dead-code --eliminate-dead-functions --inline-entry-points-exhaustive --scalar-replacement=100 --ccp --simplify-instructions` could provide significant size reductions with zero implementation effort.

---

*Generated: 2026-05-12*
