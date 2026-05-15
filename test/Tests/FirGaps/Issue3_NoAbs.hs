{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue3_NoAbs where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: abs function for Code types
-- Expected: Currently FAILS - no abs in GLSLMath/PrimOp
-- Workaround: step 0.0 x * x + step x 0.0 * (0.0 - x)
-- Fix: Add abs to GLSLMath type class

type Defs = '[ "in_x"  ':-> Input  '[Location 0] Float
             , "out"   ':-> Output '[Location 0] Float
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  x <- get @"in_x"

  -- This should work but doesn't:
  -- let absX = abs x

  -- Workaround: branchless abs via step
  let absX = step 0.0 x * x + step x 0.0 * (0.0 - x)

  put @"out" absX
