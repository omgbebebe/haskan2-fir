{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue6_TypeInferenceCascade where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: Single typo poisons entire shader
-- Expected: One error (using + instead of ^+^) cascades to 50+ errors
-- All downstream bindings get inferred as Code (V 3 a0) with ambiguous a0
-- Fix: Better error localization in shader combinator

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  a <- get @"in_a"
  b <- get @"in_b"

  -- Intentional bug: using scalar + on vectors
  let c = a + b

  -- Everything below here will cascade-fail
  -- because c :: Code (V 3 a0) with ambiguous a0
  let d = a ^*^ c
      e = minV a d
      f = maxV a d

  put @"out" f
