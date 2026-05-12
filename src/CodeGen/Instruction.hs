{-# LANGUAGE BlockArguments             #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE PatternSynonyms            #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}

{-|
Module: CodeGen.Instruction

This module defines an 'Instruction' data type which collects the information associated to a SPIR-V instruction:
  
  * which instruction it is (essentially: the instruction's OpCode),
  * the ID of the result returned by the instruction (if any),
  * the ID of the return type of the instruction (if any),
  * the arguments to the instruction (usually IDs, but can be other things such as string literals).
-}


module CodeGen.Instruction
  ( Args(..), foldrArgs, arity, toArgs, Pair(..)
  , ID(..), TyID(MkTyID, TyID, tyID)
  , Instruction(..)
  , mapInstructionIDs, extractInstructionIDs
  , prependArg, setArgs
  ) where

-- base
import Control.Category
  ( (>>>) )
import Data.Word
  ( Word32 )

-- fir
import Data.Binary.Class.Put
  ( Put(..) )
import qualified SPIRV.Operation as SPIRV

----------------------------------------------------------------------------
-- args

data Args where
  EndArgs :: Args
  Arg     :: ( Show a, Put a ) => a -> Args -> Args

deriving stock instance Show Args

-- mono-foldable business
foldrArgs :: (forall a. (Show a, Put a) => a -> b -> b) -> b -> Args -> b
foldrArgs _ b0 EndArgs    = b0
foldrArgs f b0 (Arg a as) = f a ( foldrArgs f b0 as )

instance Put Args where
  put = foldrArgs (put >>> (>>)) (pure ())
  wordCount = foldrArgs ( (+) . wordCount ) 0
  mapIDs _ EndArgs = EndArgs
  mapIDs f (Arg a as) = Arg (mapIDs f a) (mapIDs f as)
  extractIDs EndArgs = []
  extractIDs (Arg a as) = extractIDs a ++ extractIDs as

arity :: Num a => Args -> a
arity = foldrArgs (const (+1)) 0

toArgs :: ( Show a, Put a, Foldable t ) => t a -> Args
toArgs = foldr Arg EndArgs

newtype Pair a b = Pair (a,b)
  deriving stock Show
instance ( Put a, Put b ) => Put (Pair a b) where
  put (Pair (a,b)) = put a *> put b
  wordCount (Pair (a,b)) = wordCount a + wordCount b
  mapIDs f (Pair (a,b)) = Pair (mapIDs f a, mapIDs f b)
  extractIDs (Pair (a,b)) = extractIDs a ++ extractIDs b

----------------------------------------------------------------------------
-- instructions

newtype ID = ID { idNumber :: Word32 }
  deriving newtype ( Eq, Ord, Enum )

instance Put ID where
  put (ID n) = put n
  wordCount _ = 1
  mapIDs f (ID n) = ID (f n)
  extractIDs (ID n) = [n]

instance Show ID where
  show (ID n) = "%" ++ show n

newtype TyID = TyID { tyID :: ID }
  deriving newtype ( Eq, Ord, Enum, Show )

instance Put TyID where
  put (TyID i) = put i
  wordCount _ = 1
  mapIDs f (TyID i) = TyID (mapIDs f i)
  extractIDs (TyID i) = extractIDs i

pattern MkTyID :: Word32 -> TyID
pattern MkTyID i = TyID (ID i)

data Instruction
  = Instruction
    { operation :: SPIRV.Operation
    , resTy     :: Maybe TyID
    -- making 'resTy' and 'resID' of different types prevents accidentally mixing them up
    , resID     :: Maybe ID
    , args      :: Args
    }
    deriving stock Show

mapInstructionIDs :: (Word32 -> Word32) -> Instruction -> Instruction
mapInstructionIDs f inst = inst
  { resTy = fmap (mapIDs f) (resTy inst)
  , resID = fmap (mapIDs f) (resID inst)
  , args = mapIDs f (args inst)
  }

extractInstructionIDs :: Instruction -> [Word32]
extractInstructionIDs inst =
  maybe [] extractIDs (resTy inst) ++
  maybe [] extractIDs (resID inst) ++
  extractIDs (args inst)

prependArg :: ( Show a, Put a ) => a -> Instruction -> Instruction
prependArg arg instr@Instruction { args = oldArgs }
  = instr { args = Arg arg oldArgs }

setArgs :: Args -> Instruction -> Instruction
setArgs as instr = instr { args = as }
