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

module Tests.Control.CloudRaymarch where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program: Simulates cloud ray marching with nested loops
-- Tests: dynamic loop, mutable vars, texture sampling in loop

type Defs =
  '[ "in_uv"    ':-> Input      '[Location 0] (V 2 Float)
   , "cloud_noise" ':-> Texture3D '[Binding 0, DescriptorSet 0] (RGBA8 UNorm)
   , "out_colour" ':-> Output     '[Location 0] (V 4 Float)
   , "main"     ':-> EntryPoint '[OriginUpperLeft] Fragment
   ]

program :: Module Defs
program = Module $ entryPoint @"main" @Fragment do

  uv <- get @"in_uv"
  let (Vec2 uvX uvY) = uv

  let dirY = uvY * 2.0 - 1.0
      absDirY = abs dirY

  -- Mutable accumulators (like cloud shader)
  _ <- def @"step" @RW @Int32 0
  _ <- def @"accR" @RW @Float 0.0
  _ <- def @"accG" @RW @Float 0.0

  let stepCount = if absDirY < 0.1
        then (16 :: Code Int32)
        else (if absDirY < 0.6 then (24 :: Code Int32) else (32 :: Code Int32))

  -- Dynamic loop with break
  loop do
    s <- get @"step"
    when (s >= stepCount) do
      break @1

    -- Sample texture inside loop (like cloud noise sampling)
    ~(Vec4 nr _ _ _) <- use @(ImageTexel "cloud_noise") NilOps (Vec3 uvX uvY 0.5)

    modify @"accR" (+ nr)
    modify @"accG" (+ 0.01)
    modify @"step" (+1)

  -- Nested light march loop
  _ <- def @"lightStep" @RW @Int32 0
  _ <- def @"lightAcc" @RW @Float 0.0

  loop do
    ls <- get @"lightStep"
    when (ls >= 4) do
      break @1

    modify @"lightAcc" (+ 0.1)
    modify @"lightStep" (+1)

  finalR <- get @"accR"
  finalG <- get @"accG"
  finalLight <- get @"lightAcc"

  put @"out_colour" (Vec4 finalR finalG finalLight 1.0)
