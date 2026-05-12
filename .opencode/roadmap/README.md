# FIR Project Roadmap

## Overview

FIR is a Haskell EDSL for SPIR-V shader generation. The project compiles but produces shaders with excessive binary size (11MB+ for complex fragment shaders) due to the absence of any optimization infrastructure. The type system, validation, and code generation are mature. Optimization is the critical gap.

## Roadmaps

| Area | Document | Status | Priority |
|------|----------|--------|----------|
| Shader binary optimization | [optimization/README.md](optimization/README.md) | Planning | Critical |
| Code quality & safety | *(not yet created)* | — | Medium |
| Testing & CI | *(not yet created)* | — | Medium |

## Current State Summary

- **Strengths**: Type-level validation pipeline, extensible GADT AST, structured CFG with phi nodes, proper type/constant deduplication in codegen
- **Weaknesses**: No optimization passes, full loop unrolling in several paths, no function inlining, no CSE/DCE, 93 `unsafeCoerce` calls (working but fragile)
- **Immediate pain point**: Shader binary size making Vulkan driver compilation slow or failing

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-12 | Phase 0: integrate `spirv-opt` before any code changes | Zero-effort 30-50% size reduction, available on system |
| 2026-05-12 | Phase 1 before Phase 2 | Targeted fixes in TODO-marked code give outsized returns for minimal risk |
| 2026-05-12 | Post-codegen passes over pre-codegen AST passes | Easier to implement within existing CGMonad, catches low-level redundancy |
