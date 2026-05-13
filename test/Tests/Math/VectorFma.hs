{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.VectorFma where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "in_c"  ':-> Input  '[Location 2] (V 3 Float)
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  a <- get @"in_a"
  b <- get @"in_b"
  c <- get @"in_c"
  let v = fmaV a b c
      s = fma (view @(Index 0) a) (view @(Index 0) b) (view @(Index 0) c)
  put @"out" (v ^+^ Vec3 s s s)
