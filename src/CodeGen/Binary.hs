{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE PatternSynonyms     #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

{-|
Module: CodeGen.Binary

Emitting SPIR-V binary data.
-}

module CodeGen.Binary
  ( putModule
  , instruction
  , whenEmitting
  , putInstruction
  , compactIDs
  )
  where

-- base
import Control.Monad
  ( when )
import Control.Monad.State
  ( State, execState, modify )
import Data.Coerce
  ( coerce )
import Data.List
  ( sortOn)
import Data.Foldable
  ( traverse_, for_, toList )
import Data.Maybe
  ( fromJust )
import Data.Typeable
  ( Typeable, cast )
import Data.Word
  ( Word32 )
import qualified Data.Bits as Bits

-- binary
import qualified Data.Binary as Binary
import qualified Data.Binary.Put as Binary

-- containers
import Data.Map.Strict
  ( Map )
import qualified Data.Map.Strict as Map
import Data.Sequence
  ( Seq, (|>) )
import qualified Data.Sequence as Seq
import Data.Set
  ( Set )
import qualified Data.Set as Set

-- lens
import Control.Lens
  ( use, view, modifying )

-- mtl
import Control.Monad.Except
  ( ExceptT )
import Control.Monad.Reader
  ( MonadReader )
import Control.Monad.State
  ( MonadState )

-- text-short
import Data.Text.Short
  ( ShortText )
import qualified Data.Text.Short as ShortText
  ( pack )

-- transformers
import Control.Monad.Trans.Class
  ( lift )

-- fir
import CodeGen.IDs
  ( extInstID )
import CodeGen.Instruction
  ( Args(..), toArgs
  , ID(..), TyID(..), pattern MkTyID
  , Instruction(..)
  , mapInstructionIDs
  )
import CodeGen.Monad
  ( CGMonad, note, liftPut )
import CodeGen.State
  ( CGContext(..), CGState(..)
  , _emittingCode, _earlyExit
  , LoopBlockIDs(..), ContinueOrMergeID(..)
  , _emittedInstructions
  )
import Data.Binary.Class.Put
  ( Put(put, wordCount, mapIDs, extractIDs) )
import Debug.Trace
  ( trace )
import Data.Containers.Traversals
  ( traverseWithKey_, traverseSet_ )
import Control.Arrow
  ( (***) )
import qualified SPIRV.Capability    as SPIRV
import qualified SPIRV.Decoration    as SPIRV
import qualified SPIRV.ExecutionMode as SPIRV
import qualified SPIRV.Extension     as SPIRV
  ( Extension, ExtInst, extInstName )
import qualified SPIRV.Operation     as SPIRV.Op
import qualified SPIRV.PrimTy        as SPIRV
import qualified SPIRV.Stage         as SPIRV
import qualified SPIRV.Version       as SPIRV

----------------------------------------------------------------------------
-- emitting a SPIR-V module
-- some instruction need to be floated to the top

putModule :: CGContext -> CGState -> ExceptT ShortText Binary.PutM ()
putModule
  CGContext { .. }
  CGState   { .. }
  | emittingCode = do
    lift $ do putHeader spirvVersion ( idNumber currentID )
              putCapabilities         neededCapabilities
              putExtensions           neededExtensions
              putExtendedInstructions knownExtInsts
              putMemoryModel          backend
    let knownBindingIDs = fmap fst knownBindings
        usedGlobalIDs   = fmap fst usedGlobals
    putEntryPoints    entryPoints interfaces
    putExecutionModes entryPoints userEntryPoints
    lift $ do
              putKnownStringLits      knownStringLits
              putBindingAnnotations   knownBindingIDs
              putBindingAnnotations   usedGlobalIDs
              putNames                names
              putDecorations          decorations
              putMemberDecorations    memberDecorations

              -- Type and constant declarations need to be interleaved.
              -- For instance, an array type needs to have
              -- its length (a constant) defined earlier.
              putTypesAndConstants    knownTypes knownConstants

              putUndefineds           knownUndefineds

    putGlobals knownTypes usedGlobals
  | otherwise = pure ()

----------------------------------------------------------------------------
-- individual binary instructions

whenEmitting :: ( MonadReader CGContext m, MonadState CGState m ) => m () -> m ()
whenEmitting action = do
  emitting  <- view _emittingCode
  earlyExit <- use  _earlyExit
  when ( emitting && null earlyExit )
    action

-- | Emit code for an instruction (wrapper).
-- Instructions are buffered in CGState for ID compaction, then serialized after.
instruction :: Instruction -> CGMonad ()
instruction inst = whenEmitting do
  case operation inst of
    SPIRV.Op.ExtCode ext _ -> do
      extID <- extInstID ext
      let inst' = case inst of
            Instruction { operation = SPIRV.Op.ExtCode _ extOpCode, .. } ->
              Instruction { operation = SPIRV.Op.ExtInst
                          , args = Arg extID $ Arg extOpCode args
                          , ..
                          }
      modifying _emittedInstructions (|> inst')
    _ -> modifying _emittedInstructions (|> inst)

putInstruction :: Instruction -> Binary.Put
putInstruction Instruction { operation = op, resTy = opResTy, resID = opResID, args = opArgs }
    = case op of

      SPIRV.Op.Code opCode ->
        let n :: Word32
            n = 1                          -- OpCode and word count (first byte)
              + maybe 0 (const 1) opResTy  -- result type (if present)
              + maybe 0 (const 1) opResID  -- ID (if present)
              + wordCount opArgs
        in do put @Word32 ( Bits.shift n 16 + fromIntegral opCode)
              traverse_ put opResTy
              traverse_ put opResID
              put opArgs

      _ -> error "putInstruction: unexpected extended instruction"

putExtendedInstruction :: ID -> Instruction -> Binary.Put
putExtendedInstruction extID Instruction { operation = op, resTy = opResTy, resID = opResID, args = opArgs }
  = case op of

      SPIRV.Op.ExtCode _ extOpCode ->
        putInstruction
          Instruction
            { operation = SPIRV.Op.ExtInst
            , resTy     = opResTy
            , resID     = opResID
            , args      = Arg extID
                        $ Arg extOpCode
                        opArgs
            }

      _ -> error "putExtendedInstruction: unexpected non-extended instruction"

putHeader :: SPIRV.Version -> Word32 -> Binary.Put
putHeader ver bound
  = do
      put SPIRV.magicNo
      put ver
      put libraryMagicNo
      put bound
      put ( 0 :: Word32 )
  where
    libraryMagicNo :: Word32
    libraryMagicNo = 0x21524946 -- FIR!

putCapabilities :: Set SPIRV.Capability -> Binary.Put
putCapabilities = traverseSet_ putCap
  where
    putCap :: SPIRV.Capability -> Binary.Put
    putCap cap 
      = putInstruction
          Instruction
            { operation = SPIRV.Op.Capability
            , resTy     = Nothing
            , resID     = Nothing
            , args      = Arg cap
                          EndArgs
            }

putExtensions :: Set SPIRV.Extension -> Binary.Put
putExtensions = traverseSet_ putExt
  where
    putExt :: SPIRV.Extension -> Binary.Put
    putExt ext
      = putInstruction
          Instruction
            { operation = SPIRV.Op.Extension
            , resTy     = Nothing
            , resID     = Nothing
            , args      = Arg ext
                          EndArgs
            }

putExtendedInstructions :: Map SPIRV.ExtInst ID -> Binary.Put
putExtendedInstructions
  = traverseWithKey_ \ extInst extID ->
      putInstruction
        Instruction
          { operation = SPIRV.Op.ExtInstImport
          , resTy     = Nothing
          , resID     = Just extID
          , args      = Arg ( SPIRV.extInstName extInst ) EndArgs
          }
      
putMemoryModel :: SPIRV.Backend -> Binary.Put
putMemoryModel bk
  = putInstruction
      Instruction
        { operation = SPIRV.Op.MemoryModel
        , resTy     = Nothing
        , resID     = Nothing
        , args      = Arg @Word32 0 -- logical addressing
                    $ Arg memoryModel
                    EndArgs
        }
    where
      memoryModel :: Word32
      memoryModel = case bk of
        SPIRV.Vulkan -> 1 -- GLSL450 memory model
        SPIRV.OpenCL -> 2 -- OpenCL memory model

putEntryPoint :: SPIRV.ExecutionModel -> ShortText -> ID -> Map ShortText ID -> Binary.Put
putEntryPoint model modelName entryPointID interface
  = putInstruction
      Instruction
        { operation = SPIRV.Op.EntryPoint
        -- slight kludge to account for unusual parameters for OpEntryPoint
        -- instead of result type, resTy field holds the ExecutionModel value
        , resTy     = Just . MkTyID $ SPIRV.executionModelID model
        , resID     = Just entryPointID
        , args      = Arg modelName
                    $ toArgs interface -- 'Map ShortText ID' has the appropriate traversable instance
        }

putEntryPoints
  :: Map (ShortText, SPIRV.ExecutionModel) ID
  -> Map (ShortText, SPIRV.ExecutionModel) (Map ShortText ID)
  -> ExceptT ShortText Binary.PutM ()
putEntryPoints entryPointIDs
  = traverseWithKey_
      ( \(modelName, model) interface -> do
        entryPointID
          <- note
              (  "putEntryPoints: " <> ShortText.pack (show model)
              <> " entry point named \"" <> modelName
              <> "\" not bound to any ID."
              )
              ( Map.lookup (modelName, model) entryPointIDs )
        lift ( putEntryPoint model modelName entryPointID interface )
      )

putModelExecutionModes :: ID -> SPIRV.ExecutionModes -> Binary.Put
putModelExecutionModes modelID
  = traverse_
      ( \case
          SPIRV.MaxPatchVertices {} -> pure () -- custom execution mode that doesn't exist in SPIR-V
          mode -> putInstruction
            Instruction
              { operation = SPIRV.Op.ExecutionMode
              , resTy     = Nothing
              , resID     = Nothing
              , args      = Arg modelID
                          $ Arg mode EndArgs
              }
      )

putExecutionModes
  :: Map (ShortText, SPIRV.ExecutionModel) ID
  -> Map (ShortText, SPIRV.ExecutionModel) SPIRV.ExecutionModes
  -> ExceptT ShortText Binary.PutM ()
putExecutionModes entryPointIDs
  = traverseWithKey_
      ( \(modelName, model) executionModes -> do
        entryPointID
          <- note
              (  "putExecutionModes: " <> ShortText.pack (show model)
              <> " entry point named \"" <> modelName
              <> "\" not bound to any ID."
              )
              ( Map.lookup (modelName, model) entryPointIDs )
        lift ( putModelExecutionModes entryPointID executionModes )
      )

putKnownStringLits :: Map ShortText ID -> Binary.Put
putKnownStringLits
  = traverseWithKey_
      ( \ lit ident -> putInstruction
        Instruction
          { operation = SPIRV.Op.String
          , resTy     = Nothing
          , resID     = Just ident
          , args      = Arg lit EndArgs
          }
      )

putBindingAnnotations :: Map ShortText ID -> Binary.Put
putBindingAnnotations
  = traverseWithKey_
      ( \ name ident -> putInstruction
        Instruction
          { operation = SPIRV.Op.Name
          , resTy     = Nothing
          , resID     = Nothing
          , args      = Arg ident
                      $ Arg name EndArgs
          }
      )

putNames :: Set ( ID, Either ShortText (Word32, ShortText) ) -> Binary.Put
putNames = traverse_
  ( \case
      ( ident, Left name )
        -> putInstruction
              Instruction
                { operation = SPIRV.Op.Name
                , resTy     = Nothing
                , resID     = Nothing
                , args      = Arg ident
                            $ Arg name EndArgs
                }

      ( ident, Right (index,name) )
        -> putInstruction
             Instruction
               { operation = SPIRV.Op.MemberName
               , resTy     = Nothing
               , resID     = Nothing
               , args      = Arg ident
                           $ Arg index
                           $ Arg name EndArgs
               }
  )

putDecorations :: Map ID SPIRV.Decorations -> Binary.Put
putDecorations
  = traverseWithKey_
      ( \ decoratee ->
          traverse_
            ( \ dec ->
                putInstruction
                  Instruction
                    { operation = SPIRV.Op.Decorate
                    , resTy     = Nothing
                    , resID     = Nothing
                    , args      = Arg decoratee
                                $ Arg dec EndArgs
                    }
            )
      )

putMemberDecorations :: Map (TyID, Word32) SPIRV.Decorations -> Binary.Put
putMemberDecorations
  = traverseWithKey_
      ( \ (structTyID, index) ->
           traverse_
             ( \dec ->
                 putInstruction
                   Instruction
                     { operation = SPIRV.Op.MemberDecorate
                     , resTy     = Nothing
                     , resID     = Nothing
                     , args      = Arg structTyID
                                 $ Arg index
                                 $ Arg dec EndArgs
                     }
             )
      )

putTypesAndConstants
  :: Map types     Instruction
  -> Map constants Instruction
  -> Binary.Put
putTypesAndConstants ts cs
  = traverse_ putInstruction
      ( sortOn resID $ Map.elems ts ++ Map.elems cs )

putUndefineds :: Map SPIRV.PrimTy (ID, TyID) -> Binary.Put
putUndefineds = traverse_
  ( \ ( undefID, undefTyID ) ->
      putInstruction
        Instruction
          { operation = SPIRV.Op.Undef
          , resTy     = Just undefTyID
          , resID     = Just undefID
          , args      = EndArgs
          }
  )

putGlobals :: Map SPIRV.PrimTy Instruction
           -> Map ShortText (ID, SPIRV.PointerTy)
           -> ExceptT ShortText Binary.PutM ()
putGlobals typeIDs
  = traverse_
      ( \(globalID, ptrTy@(SPIRV.PointerTy storage _)) ->
        do  ptrTyID :: TyID
              <- note
                   ( "putGlobals: pointer type " <> ShortText.pack (show ptrTy) <> " not bound to any ID." )
                   ( coerce . resID =<< Map.lookup (SPIRV.pointerTy ptrTy) typeIDs )
            lift $ putInstruction
                  Instruction
                    { operation = SPIRV.Op.Variable
                    , resTy = Just ptrTyID
                    , resID = Just globalID
                    , args  = Arg storage EndArgs
                    }
      )

----------------------------------------------------------------------------
-- ID compaction

-- | Compact SPIR-V IDs by renumbering all used IDs contiguously starting from 1.
-- Updates the 'currentID' (bound) and rewrites all ID references in 'CGState'.
compactIDs :: CGState -> CGState
compactIDs state =
  let allUsedIDs = collectAllIDs state
      sortedIDs  = Set.toAscList allUsedIDs
      idMap      = Map.fromList (zip sortedIDs [1..])
      remap n    = Map.findWithDefault n n idMap
      newBound   = fromIntegral (Map.size idMap) + 1
      oldBound   = idNumber (currentID state)
      nEmitted   = length (emittedInstructions state)
      nTypes     = Map.size (knownTypes state)
      nConsts    = Map.size (knownConstants state)
      -- Count instruction types for debugging
      instCounts = Map.fromListWith (+) [ (show (operation inst), 1) | inst <- toList (emittedInstructions state) ]
      topInsts   = take 20 (sortOn (negate . snd) (Map.toList instCounts))
      instSummary = unlines [ "  " ++ op ++ ": " ++ show n | (op, n) <- topInsts ]
  in trace ("compactIDs: oldBound=" ++ show oldBound ++ " newBound=" ++ show newBound ++ " usedIDs=" ++ show (Set.size allUsedIDs) ++ " emitted=" ++ show nEmitted ++ " types=" ++ show nTypes ++ " consts=" ++ show nConsts ++ "\nTop instructions:\n" ++ instSummary)
     (rewriteCGState remap (state { currentID = ID newBound }))

collectAllIDs :: CGState -> Set Word32
collectAllIDs state = execState (collectCGStateIDs state) Set.empty

collectCGStateIDs :: CGState -> State (Set Word32) ()
collectCGStateIDs s = do
  -- Module-level declarations emitted by putModule
  for_ (Map.elems $ knownExtInsts s) addID
  for_ (Map.elems $ knownStringLits s) addID
  for_ (Set.toList $ names s) $ \(i, _) -> addID i
  for_ (Map.elems $ entryPoints s) addID
  for_ (Map.elems $ interfaces s) $ \m -> for_ (Map.elems m) addID
  for_ (Map.keys $ decorations s) addID
  for_ (Map.keys $ memberDecorations s) $ \(t, _) -> addID (tyID t)
  for_ (Map.elems $ knownTypes s) addInstructionIDs
  for_ (Map.elems $ knownConstants s) addInstructionIDs
  for_ (Map.elems $ knownUndefineds s) $ \(i, t) -> addID i >> addID (tyID t)
  for_ (Map.elems $ usedGlobals s) $ \(i, _) -> addID i
  for_ (Map.elems $ knownBindings s) $ \(i, _) -> addID i
  -- Function body instructions
  for_ (emittedInstructions s) addInstructionIDs
  where
    addID (ID n) = modify (Set.insert n)
    addInstructionIDs inst = do
      traverse_ (addID . tyID) (resTy inst)
      traverse_ addID (resID inst)
      addArgsIDs (args inst)
    addArgsIDs EndArgs = pure ()
    addArgsIDs (Arg a as) = do
      for_ (extractIDs a) (modify . Set.insert)
      addArgsIDs as

mapContinueOrMergeID :: (Word32 -> Word32) -> ContinueOrMergeID -> ContinueOrMergeID
mapContinueOrMergeID f (ContinueBlockID i) = ContinueBlockID (mapIDs f i)
mapContinueOrMergeID f (MergeBlockID i) = MergeBlockID (mapIDs f i)

rewriteCGState :: (Word32 -> Word32) -> CGState -> CGState
rewriteCGState f s = s
  { currentID           = mapIDs f (currentID s)
  , currentBlock        = fmap (mapIDs f) (currentBlock s)
  , loopBlockIDs        = fmap (\(LoopBlockIDs c m) -> LoopBlockIDs (mapIDs f c) (mapIDs f m)) (loopBlockIDs s)
  , earlyExits          = Map.mapKeys (mapIDs f) $ Map.map (\(v, bindings) -> (mapContinueOrMergeID f v, Map.map (mapIDs f *** id) bindings)) (earlyExits s)
  , knownExtInsts       = Map.map (mapIDs f) (knownExtInsts s)
  , knownStringLits     = Map.map (mapIDs f) (knownStringLits s)
  , names               = Set.map (\(i, name) -> (mapIDs f i, name)) (names s)
  , entryPoints         = Map.map (mapIDs f) (entryPoints s)
  , interfaces          = Map.map (Map.map (mapIDs f)) (interfaces s)
  , decorations         = Map.mapKeys (mapIDs f) (decorations s)
  , memberDecorations   = Map.mapKeys (\(t, i) -> (mapIDs f t, i)) (memberDecorations s)
  , knownTypes          = Map.map (mapInstructionIDs f) (knownTypes s)
  , knownConstants      = Map.map (mapInstructionIDs f) (knownConstants s)
  , knownUndefineds     = Map.map (\(i, t) -> (mapIDs f i, mapIDs f t)) (knownUndefineds s)
  , usedGlobals         = Map.map (\(i, p) -> (mapIDs f i, p)) (usedGlobals s)
  , knownBindings       = Map.map (\(i, t) -> (mapIDs f i, t)) (knownBindings s)
  , localBindings       = Map.map (\(i, t) -> (mapIDs f i, t)) (localBindings s)
  , localVariables      = Map.mapKeys (mapIDs f) (localVariables s)
  , rayQueries          = Map.map (mapIDs f) (rayQueries s)
  , temporaryPointers   = Map.map (\(i, p) -> (mapIDs f i, p)) (temporaryPointers s)
  , emittedInstructions = fmap (mapInstructionIDs f) (emittedInstructions s)
  }
