{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TemplateHaskell #-}

{-|
Module: FIR.Prim.Array.Literal

Template Haskell helpers for constructing FIR array literals ergonomically.

Instead of the verbose:

> Lit $ MkArray (fromJust $ Vector.fromList [1.0, 2.0, 3.0])

Use:

> $(arrayLitE [[|1.0|], [|2.0|], [|3.0|]])

For literal values, 'arrayLit' is more convenient:

> $(arrayLit [1.0, 2.0, 3.0])

The size @n@ is inferred from the length of the list.
-}

module FIR.Prim.Array.Literal
  ( arrayLit
  , arrayLitE
  ) where

-- base
import Data.Maybe
  ( fromJust )
import Language.Haskell.TH
  ( Exp, Q, listE )
import Language.Haskell.TH.Syntax
  ( Lift, lift )

-- vector-sized
import qualified Data.Vector.Sized as Vector
  ( fromList )

-- fir
import FIR.Prim.Array
  ( Array(MkArray) )
import FIR.AST.Prim
  ( pattern Lit )

-- | Construct a FIR constant array literal from a list of literal values.
--
-- Usage:
--
-- > $(arrayLit [1.0, 2.0, 3.0]) :: AST s (Val (Array 3 Float))
--
-- The element type is inferred from the context. Requires a 'Lift' instance
-- for the element type.
arrayLit :: Lift a => [a] -> Q Exp
arrayLit elems = arrayLitE (map lift elems)

-- | Construct a FIR constant array literal from a list of Template Haskell
-- expressions.
--
-- Usage:
--
-- > $(arrayLitE [[|x + 1|], [|y * 2|], [|3.0|]])
--
-- The size @n@ and element type @a@ are inferred from context.
arrayLitE :: [Q Exp] -> Q Exp
arrayLitE elems = do
  list <- listE elems
  [e| Lit (MkArray (fromJust (Vector.fromList $(pure list)))) |]
