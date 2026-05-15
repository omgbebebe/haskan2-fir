{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue2_IfThenElse where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: if-then-else on Code Float
-- Expected: Currently FAILS with overlapping instances for Choose
-- Error: Overlapping instances for Choose (Code Bool) ...
-- Workaround: Use branchless step()
-- Fix: Fix Choose instance resolution or add Select primop

type Defs = '[ "in_x"  ':-> Input  '[Location 0] Float
             , "out"   ':-> Output '[Location 0] Float
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  x <- get @"in_x"

  -- This should work but fails:
  -- let absX = if x > 0 then x else 0 - x

  -- Workaround: branchless step
  let absX = step 0.0 x * x + step x 0.0 * (0.0 - x)

  put @"out" absX
