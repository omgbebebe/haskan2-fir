{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.PackUnpack where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs = '[ "in_v"  ':-> Input  '[Location 0] (V 4 Float)
             , "in_w"  ':-> Input  '[Location 1] Word32
             , "out"   ':-> Output '[Location 0] (V 4 Float)
             , "main"  ':-> EntryPoint '[OriginUpperLeft] Fragment
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Fragment do
  v <- get @"in_v"
  w <- get @"in_w"
  let p = packUnorm4x8 v
      u = unpackUnorm4x8 w
      -- Force both operations to appear by combining results
      dummy = Vec4 (fromIntegral p) 0.0 0.0 0.0 ^+^ u
  put @"out" dummy
