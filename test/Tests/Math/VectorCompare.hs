{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.VectorCompare where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[OriginUpperLeft] Fragment
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Fragment do
  a <- get @"in_a"
  b <- get @"in_b"
  let lt = lessThanV a b
      gt = greaterThanV a b
      eq = equalV a b
      ne = notEqualV a b
      le = lessThanEqualV a b
      ge = greaterThanEqualV a b
      x = if view @(Index 0) lt then 1.0 else 0.0
        + if view @(Index 0) gt then 1.0 else 0.0
        + if view @(Index 0) eq then 1.0 else 0.0
      y = if view @(Index 1) ne then 1.0 else 0.0
        + if view @(Index 1) le then 1.0 else 0.0
        + if view @(Index 1) ge then 1.0 else 0.0
      z = if view @(Index 2) lt then 1.0 else 0.0
  put @"out" (Vec3 x y z)
