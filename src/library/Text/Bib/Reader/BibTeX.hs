----------------------------------------------------------------------
-- |
-- Module      :  Text.Bib.Reader.BibTeX
-- Copyright   :  (c) Mathias Schenner 2015,
--                (c) Language Science Press 2015.
-- License     :  GPL-3
--
-- Maintainer  :  mathias.schenner@langsci-press.org
-- Stability   :  experimental
-- Portability :  portable
--
-- Main internal interface to BibTeX parser.
--
-- The BibTeX parser is organized in three layers:
--
-- * layer 1 (Structure): parse entry structure and interpret \@string macros,
-- * layer 2 (Reference): interpret reference entries as BibDB types,
-- * layer 3 (Inheritance): resolve crossreferences and inherited data.
----------------------------------------------------------------------

module Text.Bib.Reader.BibTeX
  ( -- * Parser
    fromBibTeX
  , fromBibTeXFile
  ) where

import Data.Text (Text)
import qualified Data.Text.IO as T

import Text.Bib.Types (BibDB)
import Text.Bib.Reader.BibTeX.Structure (parseBibTeX)
import Text.Bib.Reader.BibTeX.Reference (parseBib)
import Text.Bib.Reader.BibTeX.Inheritance (resolveCrossrefs)


-- | Parse bibliographic entries from BibTeX file.
fromBibTeXFile :: String -> FilePath -> IO (Either String BibDB)
fromBibTeXFile label filename = fromBibTeX label <$> T.readFile filename

-- | Parse bibliographic entries from BibTeX file content.
fromBibTeX :: String -> Text -> Either String BibDB
fromBibTeX label text = case parseBibTeX label text of
  Left err -> Left (show err)
  Right db -> return (resolveCrossrefs (parseBib db))