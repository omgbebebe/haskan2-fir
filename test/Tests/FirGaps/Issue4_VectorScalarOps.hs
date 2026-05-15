{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue4_VectorScalarOps where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: Vector vs scalar operator confusion
-- Expected: Using + on vectors FAILS with No instance for ScalarTy (V 3 Float)
-- Workaround: Use ^+^ for vectors
-- Fix: Better error messages OR unified operators

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  a <- get @"in_a"
  b <- get @"in_b"

  -- This FAILS: + is scalar-only
  -- let bad = a + b

  -- OK: ^+^ is vector addition
  let good = a ^+^ b

  put @"out" good
