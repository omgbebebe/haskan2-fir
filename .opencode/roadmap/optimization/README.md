# Shader Binary Optimization Roadmap

## Problem Statement

FIR-generated SPIR-V binaries are orders of magnitude larger than equivalent hand-written or GLSL-compiled shaders. A light fragment shader (path tracer) produces ~11MB of SPIR-V. This causes:
- Slow Vulkan pipeline compilation (driver JIT)
- Potential driver rejection of large modules
- Increased GPU memory for shader modules
- Unacceptable production deployment characteristics

Root cause: the code generation pipeline is `AST → CodeGen → SPIR-V Binary` with no optimization layer.

---

## Phases

| Phase | Name | Goal | Timeline | Expected Size Reduction |
|-------|------|------|----------|------------------------|
| 0 | External optimizer integration | Pipe through `spirv-opt` | 1 hour | 30-50% |
| 1 | Targeted codegen fixes | Fix known unrolling/decomposition bugs | 1-2 weeks | 50-70% cumulative |
| 2 | Instruction-level optimization | CSE, DCE, peephole passes | 1-2 months | 70-85% cumulative |

---

## Phase 0 — External Optimizer Integration

**Timeline**: 1 hour
**Risk**: None — purely additive, no existing code modified
**Expected result**: 11MB → 5-8MB

### Task

Modify `compileTo` (or add `compileToOptimized`) to run `spirv-opt` on the generated `.spv` file.

**File to modify**: `src/FIR.hs` (the `compileTo` function)

**Implementation**:

```
compileTo opts path module_ = do
  -- existing: write raw .spv
  writeSPV path (compile opts module_)
  -- new: optimize in-place
  callProcess "spirv-opt"
    [ "-O"
    , path
    , "-o", path
    ]
```

**Recommended `spirv-opt` passes** (in order):
```
--eliminate-dead-functions
--inline-entry-points-exhaustive
--eliminate-dead-code-aggressive
--scalar-replacement=100
--ccp                          (conditional constant propagation)
--simplify-instructions
--if-conversion
--eliminate-dead-branches
--merge-blocks
--eliminate-dead-code-aggressive
--private-to-local
--eliminate-local-single-block
--eliminate-local-single-store
--eliminate-dead-code-aggressive
```

Or just `-O` which selects a reasonable preset.

**Acceptance criteria**:
- [ ] `compileToOptimized` produces valid SPIR-V (passes `spirv-val`)
- [ ] Binary size reduction measured and recorded for path tracer example
- [ ] Option to disable (fallback to unoptimized)
- [ ] Works when `spirv-opt` is not available (graceful degradation)

---

## Phase 1 — Targeted Codegen Fixes

**Timeline**: 1-2 weeks
**Risk**: Low — changes are localized to specific functions with existing TODO comments
**Expected result**: 5-8MB → 3-5MB (cumulative with Phase 0)

### 1.1 `storeAtTypeThroughAccessChain` — Loop Instead of Unrolling

**File**: `src/CodeGen/Optics.hs:758-828`
**Current behavior**: Element-wise `OpAccessChain` + `OpStore` for every element of a matrix/array/vector/struct
**Existing comment**: `-- TODO: should be a loop as opposed to being fully unrolled, but creating loops is unfortunately quite cumbersome`

**Impact per call site**:
| Type | Current instructions | With loop | Savings |
|------|---------------------|-----------|---------|
| `V 4 Float` scalar-assign | 12 | 4 | 67% |
| `M 4 4 Float` scalar-assign | 48 | 6 | 87% |
| `Array 64 Float` scalar-assign | 192 | 6 | 97% |

**Implementation plan**:
1. Write a helper `storeThroughLoop` that uses `CodeGen.CFG.while` infrastructure
2. For `Array n`, emit: loop i from 0 to n-1, `OpAccessChain` with [i], `OpStore`
3. For `Matrix m n`, emit: loop i from 0 to n-1, inner loop j from 0 to m-1, or use vector store per column
4. For `Vector n`, emit: loop i from 0 to n-1
5. For `Struct`, keep element-wise (field counts are small and variable)

**Edge cases**:
- Nested `OfType` optics (already recursive, the loop body calls back into `storeAtTypeThroughAccessChain`)
- The existing `while` in CFG requires phi-node dry-run; this is compile-time cost but acceptable

**Acceptance criteria**:
- [ ] `M 4 4 Float` scalar-assign emits ≤10 instructions
- [ ] `Array N` scalar-assign emits O(1) instructions regardless of N
- [ ] All existing optics tests pass
- [ ] `spirv-val` passes on generated modules

---

### 1.2 `GradedMappendF` — Loop for Array Concatenation

**File**: `src/CodeGen/Composite.hs:185-205`
**Current behavior**: `traverse [0..n-1]` generating `n` `OpCompositeExtract` per array, then 1 `OpCompositeConstruct`
**Existing comment**: `-- should probably use a loop instead of this, but nevermind`

**Implementation plan**:
1. For `Array lg` ⊕ `Array lg'`, allocate a result `Array (lg+lg')` as a local variable
2. Emit loop: copy lg elements from first array, then lg' from second
3. Each copy is: `OpAccessChain` + `OpLoad` (source) + `OpAccessChain` + `OpStore` (dest)
4. Single `OpLoad` on the result variable at the end

**Alternative (simpler)**: Use the existing `createArray` from `CodeGen.Array` which already generates a `while` loop.

**Acceptance criteria**:
- [ ] `Array 64` ⊕ `Array 64` emits O(1) instructions instead of 129
- [ ] All struct concatenation tests pass
- [ ] `spirv-val` passes

---

### 1.3 Expand Vectorization Whitelist

**File**: `src/CodeGen/Applicative.hs:366-388`
**Current behavior**: `SanitiseVectorisation` only recognizes `MkVectorF`, `UnsafeCoerceF`, `LitF`, and `PrimOpF` (when native vectorized op exists). Everything else falls back to n independent codegen passes.
**Fallback cost**: For `V 4`, any unrecognized expression is codegen'd 4 times.

**New instances to add**:

#### `SelectionF` / `IfF` — Vector Conditionals
```
Vector condition: if V 4 Bool then V 4 a else V 4 a
→ OpSelect (vector result)
```
SPIR-V has `OpSelect` that works on vectors. This is the single biggest win for lighting code (`fmap (\x -> if x > 0 then x else 0) vec`).

**Implementation**: Add `SanitiseVectorisation n (SelectionF AST)` instance that:
1. Vectorize condition and both branches via recursive `sanitiseVectorisation`
2. If all three succeed, emit `OpSelect`
3. Otherwise return `Nothing`

#### `LetF` — Let-bindings in Vector Context
```
let y = f x in V 4 (g y)
→ vectorize the body, y is shared
```
Passthrough — vectorize the body, the let-binding is compile-time only.

#### `BindF` — Monadic Bind
Similar to `LetF` — passthrough, vectorize the continuation.

**Acceptance criteria**:
- [ ] `fmap (\x -> if c then a else b) vec` emits 1 `OpSelect` instead of 4 `OpSelect` + 4 codegen'd conditions
- [ ] `let'` inside vector applicative doesn't cause element-wise fallback
- [ ] Vector test suite passes
- [ ] New test cases for vectorized conditionals

---

### 1.4 Measure and Record Baseline

After each change, measure:
```
Path tracer fragment shader size (raw):
Path tracer fragment shader size (spirv-opt -O):
Instruction count (spirv-dis | wc -l):
Compile time:
```

Record in `.opencode/roadmap/optimization/measurements.md`.

---

## Phase 2 — Instruction-Level Optimization Passes

**Timeline**: 1-2 months
**Risk**: Medium — requires understanding of full codegen pipeline, changes to `CGMonad` or addition of post-processing
**Expected result**: 3-5MB → 0.5-2MB (cumulative)

### Architecture

Add an intermediate step between instruction emission and binary serialization:

```
Current:  CGMonad (accumulates Instructions) → putModule → ByteString
Target:   CGMonad (accumulates Instructions) → optimizeModule → putModule → ByteString
```

The `CGState` already accumulates instructions in `Binary.PutM`. The optimization pass operates on the accumulated state before `putModule` serializes it.

**Key file to modify**: `src/CodeGen/Binary.hs` — add `optimizeModule :: CGState -> CGState` before `putModule`.

### 2.1 Common Subexpression Elimination (CSE)

**Priority**: P0
**Effort**: 1 week

**Algorithm**:
1. Walk all instructions in order
2. For each pure instruction (no side effects), compute a key: `(operation, resTy, args)`
3. Maintain a `Map (Op, Maybe TyID, Args) ID`
4. On hit: replace result ID with cached ID, mark instruction as dead
5. On miss: cache the result ID

**Pure instructions** (eligible for CSE):
- `OpCompositeExtract`, `OpCompositeConstruct`
- All arithmetic: `OpFAdd`, `OpFMul`, `OpIAdd`, `OpIMul`, etc.
- `OpVectorShuffle`, `OpSWizzle`
- `OpConvert*` (type conversions)
- `OpAccessChain` on non-mutable pointers with same indices

**Impure instructions** (NOT eligible):
- `OpLoad`, `OpStore` (memory effects)
- `OpFunctionCall` (arbitrary side effects)
- `OpImageWrite`, `OpImageRead`
- Any instruction with barrier semantics

**Implementation**:
- Add `_cseCache :: Map CSEKey ID` to `CGState` or as a local variable in `optimizeModule`
- Walk instructions in reverse dependency order? No — forward order is correct for SSA
- After CSE, run DCE to remove dead instructions

**Acceptance criteria**:
- [ ] Duplicate `OpCompositeExtract` with same source and indices → single instruction
- [ ] Duplicate arithmetic with same operands → single instruction
- [ ] `spirv-val` passes
- [ ] Measurable size reduction on path tracer

---

### 2.2 Dead Code Elimination (DCE)

**Priority**: P0
**Effort**: 1 week

**Algorithm**:
1. Start from entry point instructions
2. Follow all referenced IDs transitively (operands of reachable instructions)
3. Mark all reachable instructions
4. Remove unreachable instructions from state maps

**What to eliminate**:
- Unused types (referenced by no reachable instruction)
- Unused constants
- Unused decorations on dead variables
- Dead local variables (allocated but never loaded)
- Dead functions (never called from reachable entry points)

**Implementation**:
- Extract the instruction graph from `CGState`
- Compute reachability set
- Filter `knownTypes`, `knownConstants`, decorations, function bodies

**Acceptance criteria**:
- [ ] Types/constants used only by dead code are removed
- [ ] All reachable functionality preserved
- [ ] `spirv-val` passes

---

### 2.3 Function Inlining

**Priority**: P1
**Effort**: 1-2 weeks

Two approaches:

**Approach A — Post-codegen inlining** (harder, more general):
- Detect `OpFunctionCall` to single-call-site functions
- Inline body at call site, renaming IDs
- Requires SSA renovation at the call site

**Approach B — Pre-codegen AST inlining** (easier, recommended first):
- Before codegen, analyze `FunDefF` / `FunCallF` pairs
- For functions called exactly once, substitute the body AST at the call site
- For functions marked `Inline` in `FunctionControl`, substitute unconditionally
- Let the existing codegen handle the expanded AST

**Implementation** (Approach B):
1. Walk the AST, count `FunCallF` occurrences per function name
2. For single-call-site functions, perform AST substitution: replace `FunCallF name args` with the function body with `Lam`/`App` reductions
3. Run beta-reduction pass to clean up
4. Then run normal codegen

**Risks**: Large functions inlined at multiple sites could increase size. Start with single-call-site only.

**Acceptance criteria**:
- [ ] Single-call-site functions are inlined
- [ ] `Inline`-annotated functions are inlined
- [ ] No size increase from inlining (measured)
- [ ] `spirv-val` passes

---

### 2.4 Peephole Optimizations

**Priority**: P2
**Effort**: 1 week

Small pattern-based rewrites:

| Pattern | Replacement |
|---------|-------------|
| `OpCompositeExtract i (OpCompositeConstruct [a0,..,aN])` | `ai` (direct) |
| `OpLoad + OpStore` same pointer, no intervening writes | Remove `OpLoad` |
| `OpFMul x (OpFMul 1.0 y)` | `OpFMul x y` |
| `OpFAdd x (OpFAdd 0.0 y)` | `OpFAdd x y` |
| `OpVectorShuffle` that is identity | Remove |
| `OpConvert*` to same type | Remove |

**Implementation**: Walk instructions, match patterns, substitute. Simple but tedious.

**Acceptance criteria**:
- [ ] Identity shuffles eliminated
- [ ] Extract-immediately-after-construct eliminated
- [ ] Neutral element arithmetic simplified
- [ ] `spirv-val` passes

---

### 2.5 Loop Dry-Run Optimization (Compile-Time)

**Priority**: P3
**Effort**: 1 week

**File**: `src/CodeGen/CFG.hs:472-536`
**Problem**: Each `while` loop runs codegen twice (dry run + real run). N-deep nesting = 2^N compile-time.

**Implementation**: Add a `dryRunMode :: Bool` flag to `CGState`. In dry-run mode:
- Suppress all `instruction` calls (don't emit binary)
- Suppress all `typeID`/`constID` calls (don't create types/constants)
- Only track `_localBindings` changes
- The dry run becomes a lightweight binding simulation

**Acceptance criteria**:
- [ ] Compile time for N-deep loop nesting is linear, not exponential
- [ ] Generated binary is identical to current output
- [ ] Path tracer compile time reduced measurably

---

## Measurements Template

File: `.opencode/roadmap/optimization/measurements.md`

| Date | Phase | Change | Raw Size | After spirv-opt | Instruction Count | Compile Time |
|------|-------|--------|----------|-----------------|-------------------|--------------|
| (baseline) | — | Unoptimized FIR | 11 MB | — | — | — |

*(Fill in after each phase)*

---

## Dependency Graph

```
Phase 0 (spirv-opt)
    │
    ▼
Phase 1.1 (storeAtTypeThroughAccessChain → loop)
Phase 1.2 (GradedMappendF → loop)        ─── independent, can parallelize
Phase 1.3 (vectorization whitelist)
    │
    ▼
Phase 1.4 (measure)
    │
    ▼
Phase 2.1 (CSE)  ─── depends on Phase 1 being done to measure impact
Phase 2.2 (DCE)  ─── should follow CSE (removes CSE-dead instructions)
    │
Phase 2.3 (inlining)  ─── can start after 2.1, benefits from 2.2
Phase 2.4 (peephole)  ─── independent, can start anytime
Phase 2.5 (dry-run)   ─── independent, compile-time only
```

---

## What NOT to Optimize

| Area | Reason |
|------|--------|
| `unsafeCoerce` in `Applicative.hs` (28 occurrences) | Works correctly at SPIR-V level. Rewriting would require fundamental type-system changes. Not worth the risk. |
| `CGMonad` transformer stack | Complex but correct. Restructuring has no user benefit. |
| Type/constant deduplication | Already working perfectly via `Map`-based caching in `CGState`. |
| Optic access chain emission | Already optimal at 2 instructions (`OpAccessChain` + `OpLoad`/`OpStore`). |
| Custom SPIR-V optimizer | `spirv-opt` exists and is production-quality. Don't reinvent. |

---

## References

- SPIR-V spec: https://www.khronos.org/registry/SPIR-V/
- spirv-opt documentation: https://github.com/KhronosGroup/SPIRV-Tools/blob/main/source/opt/README.md
- FIR code bloat analysis: `.opencode/shader-bloat-analysis.md`
- SPIR-V optimization recipes: https://www.khronos.org/opengl/wiki/SPIR-V_optimizations
