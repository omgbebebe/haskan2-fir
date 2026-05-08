{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE PatternSynonyms     #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Tests.Images.Bindless where

-- fir
import FIR
import Math.Linear

------------------------------------------------
-- program

type Defs
  =  '[ "textures" ':-> BindlessTexture2D '[ Binding 0, DescriptorSet 0 ] (RGBA8 UNorm)
      , "in_pos"   ':-> Input      '[ Location 0 ] (V 3 Float)
      , "out_col"  ':-> Output     '[ Location 0 ] (V 4 Float)
      , "main"     ':-> EntryPoint '[ OriginLowerLeft ] Fragment
      ]

program :: Module Defs
program =
  Module $ entryPoint @"main" @Fragment do
    pos <- get @"in_pos"
    -- Access first texture in bindless array (index 0)
    -- For a real bindless shader, the index would come from a push constant or vertex attribute
    let idx = 0 :: Word32
    col <- use @(BindlessTexel "textures") idx NilOps pos
    put @"out_col" col
