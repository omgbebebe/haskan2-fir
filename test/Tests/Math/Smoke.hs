{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.Smoke where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs = '[ "in_a"  ':-> Input  '[Location 0] (V 3 Float)
             , "in_b"  ':-> Input  '[Location 1] (V 3 Float)
             , "out"   ':-> Output '[Location 0] (V 3 Float)
             , "main"  ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  a <- get @"in_a"
  b <- get @"in_b"
  -- Basic vector operations that already exist in FIR
  let c = a ^+^ b
      d = a ^-^ b
      e = 2.0 *^ a
      f = a ^* 3.0
      g = dot a b
      h = cross a b
      i = normalise a
      j = norm a
  put @"out" (c ^+^ d ^+^ e ^+^ f ^+^ Vec3 g j 0 ^+^ h ^+^ i)
