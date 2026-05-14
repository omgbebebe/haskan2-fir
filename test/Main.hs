module Main (main) where

import Control.Monad (filterM, forM)
import Data.List (sort)
import Data.ByteString.Lazy (fromStrict)
import FIR (CompilerFlag(..))
import Runner
  ( CompileResult(..)
  , getTypecheckOutput
  , runCompileTest
  )
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((<.>), (</>), dropExtension, takeExtension)
import Test.Tasty (defaultMain, testGroup, TestTree)
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit (assertFailure, testCase)

main :: IO ()
main = discoverTests >>= defaultMain

testDir :: FilePath
testDir = "test/Tests"

discoverTests :: IO TestTree
discoverTests = do
  entries <- sort <$> listDirectory testDir
  folders <- filterM (isDir . (testDir </>)) entries
  groups <- forM folders $ \folder -> do
    let folderPath = testDir </> folder
    files <- sort <$> listDirectory folderPath
    let hsFiles = filter ((== ".hs") . takeExtension) files
    tests <- forM hsFiles $ \hsFile -> do
      let name = dropExtension hsFile
      mkTest folder name
    return $ testGroup folder tests
  return $ testGroup "fir" groups

mkTest :: FilePath -> FilePath -> IO TestTree
mkTest folder name = do
  let goldPath   = testDir </> folder </> name <.> "golden"
      nocodePath = testDir </> folder </> name <.> "nocode"
  hasGold   <- doesFileExist goldPath
  hasNocode <- doesFileExist nocodePath
  pure $ case (hasGold, hasNocode) of
    (True, _)     -> typecheckGolden folder name goldPath
    (_, True)     -> codegenCase folder name
    (False, False) -> validateCase folder name

typecheckGolden :: FilePath -> FilePath -> FilePath -> TestTree
typecheckGolden folder name goldPath =
  goldenVsString
    (name ++ " (typecheck)")
    goldPath
    (do mb <- getTypecheckOutput testDir folder name
        case mb of
          Nothing  -> fail "fir package not available"
          Just bs  -> pure (fromStrict bs))

codegenCase :: FilePath -> FilePath -> TestTree
codegenCase folder name =
  testCase (name ++ " (codegen)") $ do
    result <- runCompileTest [Debug, Assert, NoCode] testDir folder name
    case result of
      CompileOK -> pure ()
      err       -> assertFailure (show err)

validateCase :: FilePath -> FilePath -> TestTree
validateCase folder name =
  testCase (name ++ " (validate)") $ do
    result <- runCompileTest [Debug, Assert] testDir folder name
    case result of
      CompileOK -> pure ()
      err       -> assertFailure (show err)

isDir :: FilePath -> IO Bool
isDir = doesDirectoryExist
