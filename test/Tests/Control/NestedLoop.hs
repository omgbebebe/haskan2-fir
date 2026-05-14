{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE NamedWildCards   #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE PolyKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Tests.Control.NestedLoop where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program: Nested loops with mutable variables
-- Tests: nested while loops with shared mutable state

type Defs =
  '[ "in_uv"    ':-> Input      '[Location 0] (V 2 Float)
   , "out_colour" ':-> Output     '[Location 0] (V 4 Float)
   , "main"     ':-> EntryPoint '[OriginUpperLeft] Fragment
   ]

program :: Module Defs
program = Module $ entryPoint @"main" @Fragment do

  uv <- get @"in_uv"
  let (Vec2 uvX uvY) = uv

  -- Mutable accumulators
  _ <- def @"step" @RW @Int32 0
  _ <- def @"total" @RW @Float 0.0
  _ <- def @"innerSum" @RW @Float 0.0

  let scaleFactor = uvX * 3.0 + 0.1

  -- Outer loop
  loop do
    s <- get @"step"
    when (s >= (4 :: Code Int32)) do
      break @1

    -- Reset inner sum for each outer iteration
    put @"innerSum" (0.0 :: Code Float)

    _ <- def @"lightStep" @RW @Int32 0

    -- Inner loop (nested)
    loop do
      ls <- get @"lightStep"
      when (ls >= (3 :: Code Int32)) do
        break @1

      -- Use outer variable inside inner loop
      modify @"innerSum" (+ scaleFactor)
      modify @"lightStep" (+1)

    -- Use inner result in outer loop body
    innerResult <- get @"innerSum"
    modify @"total" (+ innerResult)
    modify @"step" (+1)

  -- Use results after both loops
  finalTotal <- get @"total"
  put @"out_colour" (Vec4 finalTotal scaleFactor finalTotal 1.0)
