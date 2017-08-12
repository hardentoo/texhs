{-# LANGUAGE CPP #-}
----------------------------------------------------------------------
-- |
-- Module      :  Text.TeX.Filter
-- Copyright   :  2015-2017 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mschenner.dev@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- Filters for normalizing whitespace and for resolving syntactic
-- TeX commands (symbols, diacritics) and ligatures.
----------------------------------------------------------------------

module Text.TeX.Filter
  ( -- * Normalization
    normalize
    -- * Syntax Expansion
  , resolveSyntacticTeX
    -- ** Control sequences
    -- *** Types
  , CmdMap
  , SymbolMap
    -- *** Data
  , syntactic
  , symbols
  , diacritics
  , dbldiacritics
    -- *** Argument specifications
  , argspecsSyntactic
    -- ** Ligatures
    -- *** Types
  , LigatureMap
    -- *** Data
  , texLigatures
    -- *** Functions
  , replaceLigatures
  ) where

#if MIN_VERSION_base(4,8,0)
import Data.Monoid (First(..))
#else
import Data.Monoid (Monoid(..), First(..))
#endif
import Data.Char (isMark)
import Data.List (sortBy, stripPrefix)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Ord (comparing)

import qualified Text.TeX.Filter.Plain as Plain
import qualified Text.TeX.Filter.Primitive as Primitive
import Text.TeX.Parser.Types


---------- Types

-- | Data map from TeX command names
-- to (argspec, expansion function) pairs.
type CmdMap = Map String (ArgSpecSimple, Args -> TeX)

-- | Data map from TeX command names to Unicode symbols.
type SymbolMap = Map String String

-- | Data map for TeX ligatures.
type LigatureMap = Map String String


---------- Data

-- | A map that contains all registered syntactic commands
-- that are not 'symbols', 'diacritics' or 'dbldiacritics'.
syntactic :: CmdMap
syntactic = M.unions
  [ Primitive.syntactic
  ]

-- | A map that contains all registered symbols.
--
-- Symbols are syntactic commands that take no argument.
symbols :: SymbolMap
symbols = M.unions
  [ Primitive.symbols
  , Plain.symbols
  ]

-- | A map that contains all registered diacritics.
--
-- Diacritics are syntactic commands that take a single argument.
diacritics :: SymbolMap
diacritics = M.unions
  [ Plain.diacritics
  ]

-- | A map that contains all registered double diacritics.
--
-- Double diacritics are syntactic commands that take two arguments.
dbldiacritics :: SymbolMap
dbldiacritics = M.unions
  [ Plain.dbldiacritics
  ]


---------- ArgSpec DB

-- | Lookup table for the ArgSpecs of registered syntactic commands.
--
-- This table may be used by the TeX parser in "Text.TeX.Parser"
-- to determine the number of arguments a given command takes.
argspecsSyntactic :: Map String ArgSpecSimple
argspecsSyntactic = M.unions
  [ M.map (const (0,0)) symbols
  , M.map (const (0,1)) diacritics
  , M.map (const (0,2)) dbldiacritics
  , M.map fst syntactic]


---------- Resolve symbols

-- | Resolve syntactic control sequences (symbols, diacritics)
-- and TeX ligatures.
resolveSyntacticTeX :: TeX -> TeX
resolveSyntacticTeX = map (resolve (symbols, diacritics, syntactic, texLigatures))

resolve :: (SymbolMap, SymbolMap, CmdMap, LigatureMap) -> TeXAtom -> TeXAtom
resolve (_, _, _, ligdb) (Plain str) = Plain (replaceLigatures ligdb str)
resolve db@(symdb, accdb, syndb, _) (Command name args) =
  case M.lookup name symdb of
    Just str -> Plain str
    Nothing -> case M.lookup name accdb of
      Just str ->
        -- Nested diacritics need to be processed bottom-up.
        let target = map (resolve db) (getOblArg 0 args)
        in wrapAsAtom (insertAccent str target)
      Nothing -> case M.lookup name syndb of
        Just (_, f) -> wrapAsAtom (f args)
        Nothing -> Command name (fmapArgs (map (resolve db)) args)
resolve db atom = fmapAtom (map (resolve db)) atom

-- Insert combining accent after the first character and any following
-- Unicode mark characters (determined by 'isMark').
insertAccent :: String -> TeX -> TeX
insertAccent acc [] = [Plain (' ':acc)]
insertAccent acc (x:xs) = insertAccentInAtom acc x : xs

insertAccentInAtom :: String -> TeXAtom -> TeXAtom
insertAccentInAtom acc (Plain []) = Plain (' ':acc)
insertAccentInAtom acc (Plain (x:xs)) =
  let (marks, trailer) = span isMark xs
  in Plain (x: marks ++ acc ++ trailer)
insertAccentInAtom _ cmd@Command{} = cmd
insertAccentInAtom acc (Group name args body) = Group name args (insertAccent acc body)
insertAccentInAtom acc (MathGroup mtype body) = MathGroup mtype (insertAccent acc body)
insertAccentInAtom acc (SupScript body) = SupScript (insertAccent acc body)
insertAccentInAtom acc (SubScript body) = SubScript (insertAccent acc body)
insertAccentInAtom _ AlignMark = AlignMark
insertAccentInAtom acc White = Plain (' ':acc)
insertAccentInAtom _ Newline = Newline
insertAccentInAtom _ Par = Par

-- Package 'TeX' as 'TeXAtom'.
wrapAsAtom :: TeX -> TeXAtom
wrapAsAtom [] = Group "" [] []
wrapAsAtom [x] = x
wrapAsAtom xs@(_:_) = Group "" [] xs


---------- Ligatures

-- Note: Needles (keys) are overlapping,
-- start replacements with longest needles.
-- | Default TeX ligatures.
texLigatures :: LigatureMap
texLigatures = M.fromList
  [ -- quotation marks
    ("``", "\x201C")  -- LEFT DOUBLE QUOTATION MARK
  , ("''", "\x201D")  -- RIGHT DOUBLE QUOTATION MARK
  , ("`", "\x2018")   -- LEFT SINGLE QUOTATION MARK
  , ("'", "\x2019")   -- RIGHT SINGLE QUOTATION MARK
    -- dashes
  , ("--", "\x2013")  -- EN DASH
  , ("---", "\x2014") -- EM DASH
    -- Spanish ligatures
  , ("?`", "\x00BF")  -- INVERTED QUESTION MARK
  , ("!`", "\x00A1")  -- INVERTED EXCLAMATION MARK
  ]

-- | Replace ligatures in a string.
replaceLigatures :: LigatureMap -> String -> String
replaceLigatures _ [] = []
replaceLigatures ligdb haystack@(hh:ht) =
  case getFirst (mconcat (map (First . (`replaceLigature` haystack)) ligatures)) of
    Just (xs, ys) -> xs ++ replaceLigatures ligdb ys
    Nothing -> hh : replaceLigatures ligdb ht
  where
    -- Sort ligatures by length of key (needle) in descending order.
    -- (This is necessary because ligature keys are overlapping. See 'texLigatures'.)
    ligatures :: [(String, String)]
    ligatures = sortBy (flip (comparing (length . fst))) (M.assocs ligdb)
    -- Search for a ligature at the left end (prefix) of a string.
    replaceLigature :: (String, String) -> String -> Maybe (String, String)
    replaceLigature (from, to) = fmap ((,) to) . stripPrefix from


---------- Normalization

-- | Conflate intra-level adjacent whitespace.
--
-- This will not remove redundant whitespace completely. In
-- particular, it will not strip leading or trailing whitespace and it
-- will not collapse inter-level adjacent whitespace. For example,
-- both spaces in \"@a { }b@\" and in \"@a{ }{ }b@\" will be kept.
normalize :: TeX -> TeX
normalize [] = []
normalize (White:xs) = case dropWhile isWhite xs of
  (Newline:ys) -> Newline : normalize (dropWhile isWhite ys)
  ys@(Par:_) -> normalize ys
  ys -> White : normalize ys
normalize (Par:xs) = Par : normalize (dropWhile (\x -> isWhite x || isPar x) xs)
normalize (x:xs) = fmapAtom normalize x : normalize xs


---------- Helpers for mapping over 'TeX' structures

-- Apply a 'TeX' function to a 'TeXAtom'.
fmapAtom :: (TeX -> TeX) -> TeXAtom -> TeXAtom
fmapAtom _ (Plain content) = Plain content
fmapAtom f (Command name args) = Command name (fmapArgs f args)
fmapAtom f (Group name args body) = Group name (fmapArgs f args) (f body)
fmapAtom f (MathGroup mtype body) = MathGroup mtype (f body)
fmapAtom f (SupScript body) = SupScript (f body)
fmapAtom f (SubScript body) = SubScript (f body)
fmapAtom _ AlignMark = AlignMark
fmapAtom _ White = White
fmapAtom _ Newline = Newline
fmapAtom _ Par = Par

-- Lift a 'TeX' function to an 'Args' function.
fmapArgs :: (TeX -> TeX) -> Args -> Args
fmapArgs f = map (fmapArg f)

-- Lift a 'TeX' function to an 'Arg' function.
fmapArg :: (TeX -> TeX) -> Arg -> Arg
fmapArg f (OblArg xs) = OblArg (f xs)
fmapArg f (OptArg xs) = OptArg (f xs)
fmapArg _ StarArg = StarArg
