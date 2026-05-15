{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue5_MixVector where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: mix/lerp on vectors
-- Expected: Currently FAILS with overlapping instances for Choose
-- Same root cause as Issue 2 (if-then-else)
-- Workaround: Manual per-component lerp
-- Fix: Fix Choose instance resolution

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "in_t"  ':-> Input  '[Location 2] Float
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  a <- get @"in_a"
  b <- get @"in_b"
  t <- get @"in_t"

  -- This FAILS with overlapping instances:
  -- let result = mixV a b t

  -- Workaround: manual lerp
  let result = a ^* (1.0 - t) ^+^ b ^* t

  put @"out" result
