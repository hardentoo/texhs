{-# LANGUAGE CPP #-}
----------------------------------------------------------------------
-- |
-- Module      :  Main
-- Copyright   :  2015-2016 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mathias.schenner@langsci-press.org
-- Stability   :  experimental
-- Portability :  GHC
--
-- Executable driver for texhs.
----------------------------------------------------------------------

module Main where

#if MIN_VERSION_base(4,8,0)
-- Prelude exports all required operators from Control.Applicative
#else
import Control.Applicative ((<$>))
#endif
import Data.Char (toLower)
import Data.Text.Lazy (Text)
import qualified Data.Text.Lazy.IO as T
import System.Console.GetOpt
import System.Environment (getArgs, getProgName)
import System.IO

import Text.Bib (BibDB, fromBibTeXFile)
import Text.TeX (readTeXIO)
import Text.Doc (Doc, tex2docWithBib, doc2xml, doc2html)


---------- options

data OutputFormat
  = XML
  | HTML
  | InvalidFormat String
  deriving (Eq, Show)

data Options = Options
  { optShowUsage    :: Bool
  , optShowVersion  :: Bool
  , optVerbose      :: Bool
  , optOutputFormat :: OutputFormat
  , optOutputFile   :: Maybe FilePath
  , optBibFile      :: Maybe FilePath
  } deriving Show

defaultOptions :: Options
defaultOptions = Options
  { optShowUsage    = False
  , optShowVersion  = False
  , optVerbose      = False
  , optOutputFormat = HTML
  , optOutputFile   = Nothing
  , optBibFile      = Nothing
  }

options :: [OptDescr (Options -> Options)]
options =
  [ Option ['h'] ["help"]
    (NoArg (\ opts -> opts { optShowUsage = True }))
    "show usage information"
  , Option ['V'] ["version"]
    (NoArg (\ opts -> opts { optShowVersion = True }))
    "show version number"
  , Option ['v'] ["verbose"]
    (NoArg (\ opts -> opts { optVerbose = True }))
    "verbose output on stderr"
  , Option ['t'] ["target"]
    (ReqArg ((\ f opts -> opts { optOutputFormat = parseOutputFormat f })) "FMT")
    "output format (xml, html)"
  , Option ['b'] ["bibfile"]
    (ReqArg (\ f opts -> opts { optBibFile = Just f }) "FILE")
    "bib file"
  , Option ['o'] ["output"]
    (ReqArg (\ f opts -> opts { optOutputFile = Just f }) "FILE")
    "output file"
  ]

parseOutputFormat :: String -> OutputFormat
parseOutputFormat xs =
  case map toLower xs of
    "xml" -> XML
    "html" -> HTML
    _ -> InvalidFormat xs

parseOptions :: String -> [String] -> IO (Options, [String])
parseOptions name argv =
  case getOpt Permute options argv of
    (opts, args, []) -> return (foldl (flip id) defaultOptions opts, args)
    (_, _, errs) -> error $ concat errs ++ usageInfo (usageHeader name) options

usageHeader :: String -> String
usageHeader name = "Usage: " ++ name ++ " [options] texfile"


---------- conversion

runConversion :: Options -> String -> IO ()
runConversion opts filename = do
  bib <- maybe (return Nothing) parseBib (optBibFile opts)
  doc <- parseDoc filename bib
  case optOutputFormat opts of
    HTML -> output opts (doc2html doc)
    XML -> output opts (doc2xml doc)
    InvalidFormat fmt -> error $ "invalid or unsupported format: " ++ fmt

parseBib :: FilePath -> IO (Maybe BibDB)
parseBib bibfile = do
  bibinfo <- fromBibTeXFile bibfile bibfile
  case bibinfo of
    Left errmsg ->
      warn "Warning: cannot read bib file." *>
      warn errmsg *>
      return Nothing
    Right db -> return (Just db)

parseDoc :: FilePath -> Maybe BibDB -> IO Doc
parseDoc filename bib =
  tex2docWithBib bib filename <$>
  (readTeXIO filename =<< readFile filename)

output :: Options -> Text -> IO ()
output opts = maybe T.putStrLn T.writeFile (optOutputFile opts)


---------- helper

warn :: String -> IO ()
warn = hPutStrLn stderr


---------- main

showVersion :: String -> IO ()
showVersion name = putStrLn $ name ++ ": pre-release version"

showUsage :: String -> IO ()
showUsage name = error $ usageInfo (usageHeader name) options

run :: String -> Options -> [String] -> IO ()
run name opts args
  | optShowUsage opts = showUsage name
  | optShowVersion opts = showVersion name
  | otherwise = case args of
    [filename] -> runConversion opts filename
    _ -> error "usage error: expecting texfile as single argument"

main :: IO ()
main = do
  name <- getProgName
  argv <- getArgs
  (opts, args) <- parseOptions name argv
  run name opts args