{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE NamedWildCards   #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE PolyKinds        #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Tests.Control.SimpleLoop where

-- fir
import FIR
import FIR.Syntax.Labels
import Math.Linear

------------------------------------------------
-- Minimal loop test

type Defs = '[ "main" ':-> EntryPoint '[] Vertex ]

program :: Module Defs
program = Module $ entryPoint @"main" @Vertex do

  #i @Int32 #= 0

  loop do
    i <- #i
    when (i >= 4) do
      break @1
    #i %= (+1)

  v <- #i
  #gl_Position .= Vec4 (fromIntegral v) 0 0 1
