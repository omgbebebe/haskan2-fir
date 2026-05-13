{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.VectorOps where

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
  let -- Component-wise arithmetic
      d = a ^*^ b
      -- Min/max
      e = minV a b
      f = maxV a b
      -- Clamp, mix, step, smoothstep
      g = clampV a (Vec3 0 0 0) (Vec3 1 1 1)
      h = mixV a b c
      i = stepV (Vec3 0.5 0.5 0.5) a
      j = smoothstepV (Vec3 0 0 0) (Vec3 1 1 1) a
      -- Fract
      k = fractV a
  put @"out" (d ^+^ e ^+^ f ^+^ g ^+^ h ^+^ i ^+^ j ^+^ k)
