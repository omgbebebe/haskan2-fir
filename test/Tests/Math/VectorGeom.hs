{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.VectorGeom where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs = '[ "in_i"    ':-> Input  '[Location 0] (V 3 Float)
             , "in_n"    ':-> Input  '[Location 1] (V 3 Float)
             , "in_nref" ':-> Input  '[Location 2] (V 3 Float)
             , "in_eta"  ':-> Input  '[Location 3] Float
             , "out"     ':-> Output '[Location 0] (V 3 Float)
             , "main"    ':-> EntryPoint '[] Vertex
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do
  i    <- get @"in_i"
  n    <- get @"in_n"
  nref <- get @"in_nref"
  eta  <- get @"in_eta"
  let r = reflectV i n
      f = faceForwardV n i nref
      t = refractV i n eta
  put @"out" (r ^+^ f ^+^ t)
