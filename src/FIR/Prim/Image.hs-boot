{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE ExplicitForAll       #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RoleAnnotations      #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module FIR.Prim.Image where

-- base
import Data.Int
  ( Int32 )
import Data.Kind
  ( Type )
import Data.Type.Bool
  ( If )
import Data.Type.Known
  ( Known )
import Data.Typeable
  ( Typeable )
import GHC.TypeNats
  ( Nat )

-- fir
import Data.Type.List
  ( Elem )
import FIR.Prim.Array
  ( Array )
import Math.Linear
  ( V )
import SPIRV.Image
  ( Arrayness(..)
  , Dimensionality(..)
  , HasDepth(..)
  , ImageUsage(..)
  , ImageFormat(..)
  , MultiSampling(..)
  , Operand
  )
import qualified SPIRV.Image as SPIRV
  ( Image )

--------------------------------------------------

data ImageCoordinateKind
  = IntegralCoordinates
  | FloatingPointCoordinates 

data ImageProperties where
  Properties
    :: ImageCoordinateKind
    -> Type
    -> Dimensionality
    -> Maybe HasDepth
    -> Arrayness
    -> MultiSampling
    -> ImageUsage
    -> Maybe (ImageFormat Nat)
    -> ImageProperties

data Image (props :: ImageProperties)
type role Image phantom

instance Show (Image props)
instance Eq (Image props)
instance Ord (Image props)

newtype ImageAndCoordinate
  = ImageAndCoordinate (SPIRV.Image, ImageCoordinateKind)

knownImage :: forall props. Known ImageProperties props => SPIRV.Image

data OperandName
  = DepthComparison
  | ProjectiveCoords
  | BaseOperand Operand

data ImageOperands
        ( props :: ImageProperties )
        ( ops   :: [OperandName]   )
      :: Type
type role ImageOperands phantom phantom

data Gather
  = ComponentGather
  | DrefGather

data GatherInfo val (gather :: Gather) where
 ComponentWithOffsets
   :: val -> Array 4 (V 2 Int32) -> GatherInfo val ComponentGather
 DepthWithOffsets
   ::        Array 4 (V 2 Int32) -> GatherInfo val DrefGather

type role GatherInfo representational nominal

type family WhichGather (ops :: [OperandName]) :: Gather where
  WhichGather ops
    = If
        ( DepthComparison `Elem` ops  )
        DrefGather
        ComponentGather
