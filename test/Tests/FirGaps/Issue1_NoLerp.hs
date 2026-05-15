{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.FirGaps.Issue1_NoLerp where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- Test: lerp synonym for mix
-- Expected: Currently FAILS because FIR only has GLSL 'mix', no 'lerp'
-- Workaround: (a ^* (1-t) ^+^ b ^* t)
-- Fix: Add 'lerp = mix' to FIR math library

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

  -- This should work but doesn't:
  -- result = lerp a b t

  -- Workaround: manual lerp
  let result = a ^* (1.0 - t) ^+^ b ^* t

  put @"out" result
