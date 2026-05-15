# FIR EDSL Gap Test Suite

This directory contains regression tests for known gaps in the FIR EDSL.
Each test demonstrates a specific issue encountered during real-world shader development.

## Running Tests

```bash
cd 3rdparty/fir
cabal test
```

## Issue Index

| File | Issue | Severity | Status |
|------|-------|----------|--------|
| `Issue1_NoLerp.hs` | No `lerp` synonym for `mix` | Low | Has workaround |
| `Issue2_IfThenElse.hs` | `if-then-else` fails on `Code Float` | **High** | Requires branchless `step()` |
| `Issue3_NoAbs.hs` | No `abs` for `Code` types | Medium | Requires manual `step()` |
| `Issue4_VectorScalarOps.hs` | `+`/`*` scalar-only, no unified operators | Medium | Use `^+^`/`^*^` |
| `Issue5_MixVector.hs` | `mixV` on vectors fails (same as Issue 2) | **High** | Manual lerp |
| `Issue6_TypeInferenceCascade.hs` | Single typo poisons 50+ lines | Medium | Careful typing |
| `Issue7_LiteralTypeContamination.hs` | Literals infer nested types | Low | Keep literals close |

## Test Categories

### Typecheck-only tests (`.nocode` files)
These tests verify that FIR can typecheck the workaround code.

### Validation tests (no extension)
These tests compile to SPIR-V and validate.

### Golden tests (`.golden` files)
These tests compare typecheck output against expected errors.

## Workaround Patterns

### Issue 2 & 5: Branchless conditionals
```haskell
-- Instead of: if x > 0 then x else 0
-- Use:        step 0.0 x * x + step x 0.0 * (0.0 - x)
```

### Issue 3: Manual abs
```haskell
-- Instead of: abs x
-- Use:        step 0.0 x * x + step x 0.0 * (0.0 - x)
```

### Issue 1 & 5: Manual lerp
```haskell
-- Instead of: lerp a b t  or  mixV a b t
-- Use:        a ^* (1.0 - t) ^+^ b ^* t
```

## Fix Milestone

See `.opencode/MILESTONE_FIR_GAPS.md` in the haskan2 repo for upstream fix plan.
