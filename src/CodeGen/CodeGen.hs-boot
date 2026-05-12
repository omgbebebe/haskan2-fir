{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}

module CodeGen.CodeGen where

-- base
import Data.Kind
  ( Type )

-- fir
import CodeGen.Application
  ( Application )
import CodeGen.Instruction
  ( ID )
import CodeGen.Monad
  ( CGMonad )
import FIR.AST.Type
  ( AugType, Nullary )
import FIR.AST
  ( AllOpsF )
import qualified SPIRV.PrimTy as SPIRV

----------------------------------------------------------------------------
-- export the 'CodeGen' type class and instance for the AST
-- this allows auxiliary code generation code to recursively call 'codeGen'

import Data.Variant.EGADT
  ( EGADT )

class CodeGenMemo (ast :: AugType -> Type) where
  tryMemoize :: Nullary v => ast v -> CGMonad (Maybe (ID, SPIRV.PrimTy))
  storeMemo  :: Nullary v => ast v -> (ID, SPIRV.PrimTy) -> CGMonad ()

instance {-# OVERLAPPABLE #-} CodeGenMemo ast

instance CodeGenMemo (EGADT AllOpsF)

class CodeGen (ast :: AugType -> Type) where
  codeGenArgs :: Nullary r => Application ast f r -> CGMonad (ID, SPIRV.PrimTy)

codeGen :: ( CodeGen f, Nullary a, CodeGenMemo f ) => f a -> CGMonad (ID, SPIRV.PrimTy)
