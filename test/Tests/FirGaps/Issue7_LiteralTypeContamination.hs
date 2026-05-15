{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue7_LiteralTypeContamination where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: Vector literal type contamination
-- Problem: Top-level Vec3 literal can infer nested type V 3 (V 3 a0)
-- when nearby expressions have ambiguity
-- Fix: Explicit type signatures or vec3 smart constructor

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  a <- get @"in_a"
  b <- get @"in_b"

  -- This literal should be V 3 Float but can be contaminated
  -- if a nearby expression is ambiguous
  let cloudBase = Vec3 1.0 0.98 0.95

  -- If the above literal gets inferred as V 3 (V 3 a0),
  -- this will cascade-fail
      result = a ^+^ cloudBase

  put @"out" result
