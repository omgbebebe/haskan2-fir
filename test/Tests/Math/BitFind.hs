{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Math.BitFind where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs = '[ "in_i"  ':-> Input  '[Location 0] Int32
             , "in_u"  ':-> Input  '[Location 1] Word32
             , "out"   ':-> Output '[Location 0] (V 3 Int32)
             , "main"  ':-> EntryPoint '[OriginUpperLeft] Fragment
             ]

program :: Module Defs
program = Module $ entryPoint @"main" @Fragment do
  i <- get @"in_i"
  u <- get @"in_u"
  let lsb  = findILsb i
      smsb = findSMsb i
      umsb = findUMsb u
  put @"out" (Vec3 lsb smsb umsb)
