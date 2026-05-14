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

module Tests.Control.WhenLoop where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program: Tests when wrapping a loop
-- This is the pattern suspected to cause segfault

type Defs =
  '[ "in_uv"    ':-> Input      '[Location 0] (V 2 Float)
   , "out_colour" ':-> Output     '[Location 0] (V 4 Float)
   , "main"     ':-> EntryPoint '[OriginUpperLeft] Fragment
   ]

program :: Module Defs
program = Module $ entryPoint @"main" @Fragment do

  uv <- get @"in_uv"
  let (Vec2 _ uvY) = uv

  _ <- def @"acc" @RW @Float 0.0
  _ <- def @"step" @RW @Int32 0

  -- when wrapping loop (suspected problematic pattern)
  when (uvY >= 0.05) do
    loop do
      i <- get @"step"
      when (i >= 4) do
        break @1

      modify @"acc" (+ 0.1)
      modify @"step" (+1)

  final <- get @"acc"
  put @"out_colour" (Vec4 final final final 1.0)
