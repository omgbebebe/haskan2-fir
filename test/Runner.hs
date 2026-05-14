{-# LANGUAGE OverloadedStrings #-}

module Runner
  ( getTypecheckOutput
  , runCompileTest
  , CompileResult(..)
  ) where

import Control.Arrow (second)
import Control.Monad (when, replicateM)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import FIR (CompilerFlag(..))
import System.Directory
  ( doesFileExist, removeFile, renameFile )
import System.FilePath
  ( (<.>), (</>), replaceExtension, splitFileName )
import System.IO (Handle, hClose, openBinaryTempFile)
import System.Process
  ( CreateProcess(std_in, std_out, std_err)
  , StdStream(CreatePipe, UseHandle)
  , createProcess, proc, waitForProcess
  )

data CompileResult
  = CompileOK
  | CompileTypecheckFailed
  | CompileError Text
  | CompileParseError
  | FIRNotAvailable
  | CompileUnknownError
  deriving (Eq, Show)

ghc :: FilePath
ghc = "ghc"

validator :: FilePath
validator = "spirv-val"

--------------------------------------------------------------------------------
-- Typecheck
--------------------------------------------------------------------------------

getTypecheckOutput
  :: FilePath -> FilePath -> FilePath -> IO (Maybe ByteString)
getTypecheckOutput baseDir folder name = do
  let src = baseDir </> folder </> name <.> "hs"
  exists <- doesFileExist src
  if not exists
    then pure (Just "Source file missing.\n")
    else do
      (tmp, tmpH) <- mkTemp src
      let p = (proc ghc [src, "-w", "-fno-code", "-package", "fir", "-threaded"])
                { std_err = UseHandle tmpH }
      (_, _, _, ph) <- createProcess p
      _ <- waitForProcess ph
      hClose tmpH
      contents <- BS8.readFile tmp
      removeFile tmp
      pure (parseTcOutput contents)

parseTcOutput :: ByteString -> Maybe ByteString
parseTcOutput contents =
  let ls = dropWhile ignoreLineBS (BS8.lines contents)
  in case ls of
       [] -> Just "No type-checking errors."
       (l:_)
         | BS8.take 43 l == "<command line>: cannot satisfy -package fir"
         -> Nothing
       _ -> Just (BS8.unlines ls)

ignoreLineBS :: ByteString -> Bool
ignoreLineBS s = BS8.null s
  || BS8.take 4 s == "GHCi"
  || BS8.take 26 s == "Loaded package environment"

--------------------------------------------------------------------------------
-- Compile + Validate
--------------------------------------------------------------------------------

runCompileTest
  :: [CompilerFlag]
  -> FilePath -> FilePath -> FilePath
  -> IO CompileResult
runCompileTest flags baseDir folder name = do
  let dir   = baseDir </> folder
      src   = dir </> name <.> "hs"
      spv   = dir </> name <.> "spv"
      failF = dir </> name <.> "fail"

  exists <- doesFileExist src
  if not exists
    then pure FIRNotAvailable
    else do
      [(out, outH), (err, errH)] <- replicateM 2 (mkTemp src)
      let p = (proc ghc
                  [ "--interactive", src, "-w"
                  , "-package", "fir", "-threaded"
                  ])
                { std_in  = CreatePipe
                , std_out = UseHandle outH
                , std_err = UseHandle errH
                }
      (Just inH, _, _, ph) <- createProcess p
      TIO.hPutStrLn inH $
           "compileTo "
        <> T.pack (show spv) <> " "
        <> T.pack (show flags)
        <> " program"
      TIO.hPutStrLn inH ":q"
      hClose inH
      _ <- waitForProcess ph

      outContent <- TIO.readFile out
      let res = parseCGOutput outContent

      result <- case res of
        CompileTypecheckFailed -> do
          renameFile err failF
          removeFile out
          pure CompileTypecheckFailed

        CompileError _ -> do
          renameFile out failF
          removeFile err
          pure res

        CompileOK -> do
          removeFile out
          removeFile err
          failExists <- doesFileExist failF
          when (NoCode `elem` flags && failExists) (removeFile failF)
          pure CompileOK

        _ -> do
          removeFile out
          errLines <- dropWhile ignoreLineText . T.lines
                       <$> TIO.readFile err
          case errLines of
            (l:_) | T.take 43 l
                     == "<command line>: cannot satisfy -package fir" -> do
              removeFile err
              pure FIRNotAvailable
            _ -> do
              renameFile err failF
              pure res

      case (result, NoCode `notElem` flags) of
        (CompileOK, True) -> do
          (val, valH) <- mkTemp src
          let vp = (proc validator [spv]) { std_err = UseHandle valH }
          (_, _, _, vph) <- createProcess vp
          _ <- waitForProcess vph
          valContent <- TIO.readFile val
          case valContent of
            "" -> do
              removeFile val
              removeFile spv
              failExists <- doesFileExist failF
              when failExists (removeFile failF)
              pure CompileOK
            _ -> do
              renameFile val failF
              renameFile spv (spv <.> "fail")
              pure (CompileError valContent)
        _ -> pure result

parseCGOutput :: Text -> CompileResult
parseCGOutput contents =
  let ls = dropWhile ignoreLineText (T.lines contents)
  in case ls of
       l1:l2:l3:_
         | T.take 8 l1 == "[1 of 1]" ->
           case l2 of
             "Ok, one module loaded." ->
               let l3' = T.drop 2 . T.dropWhile (/= '>') $ l3
               in case T.breakOn " " l3' of
                    ("Left", rest) ->
                      CompileError
                        ( T.dropAround (== '"')
                        . T.drop 1
                        $ rest
                        )
                    ("Right", _) -> CompileOK
                    _            -> CompileParseError
             "Failed, no modules loaded." -> CompileTypecheckFailed
             _                            -> CompileUnknownError
       _ -> CompileUnknownError

ignoreLineText :: Text -> Bool
ignoreLineText s = T.null s
  || T.take 4 s == "GHCi"
  || T.take 26 s == "Loaded package environment"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

mkTemp :: FilePath -> IO (FilePath, Handle)
mkTemp src =
  uncurry openBinaryTempFile
    . second (`replaceExtension` "tmp")
    $ splitFileName src
