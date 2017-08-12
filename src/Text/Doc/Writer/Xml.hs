{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
----------------------------------------------------------------------
-- |
-- Module      :  Text.Doc.Writer.Xml
-- Copyright   :  2015-2017 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mschenner.dev@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- XML writer: Convert Doc to a TEI-based XML format.
----------------------------------------------------------------------

module Text.Doc.Writer.Xml
 ( -- * Doc to XML Conversion
   doc2xml
 , sections2xml
 , blocks2xml
 , inlines2xml
 ) where

#if MIN_VERSION_base(4,8,0)
#else
import Control.Applicative
#endif
import Control.Monad.Trans.Reader (Reader, runReader, asks)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import Text.Blaze (Markup, string, text, (!), (!?), textValue, stringValue)
import Text.Blaze.Renderer.Text (renderMarkup)

import Text.Bib.Writer
import Text.Doc.Filter.DeriveSection
import Text.Doc.Section
import Text.Doc.Types
import Text.Doc.Writer.Core


---------- main: Doc to XML conversion

-- | Convert a 'Doc' document to a TEI-based XML format.
doc2xml :: Doc -> LT.Text
doc2xml = renderMarkup . convertDoc . doc2secdoc

-- Convert 'SectionDoc' to XML 'Markup'.
convertDoc :: SectionDoc -> Markup
convertDoc rawDoc =
  let doc = addBibliography rawDoc
  in withXmlDeclaration $
     el "TEI" ! attr "xmlns" "http://www.tei-c.org/ns/1.0" $
     runReader (header <+> content doc) (docMeta doc)

-- | Convert 'Section' elements to an XML fragment.
sections2xml :: Meta -> [Section] -> LT.Text
sections2xml = convert2xml sections

-- | Convert 'Block' elements to an XML fragment.
--
-- Note: This function does not convert blocks to sections
-- and thus will not create section elements for headers.
-- For a proper rendering of headers, use 'blocks2sections'
-- and 'sections2xml' instead.
blocks2xml :: Meta -> [Block] -> LT.Text
blocks2xml = convert2xml blocks

-- | Convert 'Inline' elements to an XML fragment.
inlines2xml :: Meta -> [Inline] -> LT.Text
inlines2xml = convert2xml inlines

-- Apply renderer to document content.
convert2xml :: (a -> Reader Meta Markup) -> Meta -> a -> LT.Text
convert2xml render meta docdata =
  renderMarkup (runReader (render docdata) meta)


---------- meta

-- Create TEI header.
header :: Reader Meta Markup
header = el "teiHeader" <$> fileDesc

-- Create @<fileDesc>@ element for TEI header.
fileDesc :: Reader Meta Markup
fileDesc = do
  title <- asks metaTitle
  subtitle <- asks metaSubTitle
  authors <- asks metaAuthors
  el "fileDesc" <$>
    ((el "titleStmt" <$>
       (el "title" ! attr "type" "full" <$>
         ((el "title" ! attr "type" "main" <$> inlines title) <+>
          unlessR (null subtitle)
            (el "title" ! attr "type" "sub" <$> inlines subtitle))) <+>
       foldMapR (fmap (el "author") . inlines) authors) <>$
     el "publicationStmt" (el "p" (text "Unknown")) <>$
     el "sourceDesc" (el "p" (text "Born digital.")))


---------- content

-- Create main content as TEI @<text>@ element.
content :: SectionDoc -> Reader Meta Markup
content (SectionDoc _ secs) =
  let (frontSecs, mainSecs, backSecs) = splitRegions secs
  in el "text" <$> front frontSecs <+> body mainSecs <+> back backSecs


---------- front matter

-- Create front matter as TEI @<front>@ element.
front :: [Section] -> Reader Meta Markup
front secs = el "front" <$> titlePage <+> sections secs

-- Create title page for TEI front matter.
titlePage :: Reader Meta Markup
titlePage = do
  title <- asks metaTitle
  subtitle <- asks metaSubTitle
  authors <- asks metaAuthors
  el "titlePage" <$>
    (el "docTitle" <$>
      (el "titlePart" ! attr "type" "main" <$> inlines title) <+>
      unlessR (null subtitle)
        (el "titlePart" ! attr "type" "sub" <$> inlines subtitle)) <+>
    (el "byline" <$> foldMapR (fmap (el "docAuthor") . inlines) authors)


---------- back matter

-- Create back matter as TEI @<back>@ element.
back :: [Section] -> Reader Meta Markup
back secs = el "back" <$> sections secs


---------- main matter

-- Create main matter as TEI @<body>@ element.
body :: [Section] -> Reader Meta Markup
body secs = el "body" <$> sections secs

-- Convert 'Section' elements to XML.
sections :: [Section] -> Reader Meta Markup
sections = foldMapR section

-- Convert 'Block' elements to XML.
blocks :: [Block] -> Reader Meta Markup
blocks = foldMapR block

-- Convert 'Inline' elements to XML.
inlines :: [Inline] -> Reader Meta Markup
inlines = foldMapR inline

-- Convert a single 'Section' element to XML.
section :: Section -> Reader Meta Markup
section (Section hlevel hanchor htitle secbody subsecs) =
  el "div" !
  attr "xml:id" (textValue (internalAnchorID hanchor)) !
  attr "type" (textValue (levelname hlevel)) <$>
    (el "head" <$> inlines htitle) <+>
    blocks secbody <+>
    sections subsecs

-- Convert a numeric header level to a textual description.
levelname :: Level -> Text
levelname i = fromMaybe "unknown" (lookup i (zip [1..] levels))
  where
    levels = [ "part", "chapter", "section"
             , "subsection", "subsubsection" ]

-- Convert a list type to a textual description.
showListType :: ListType -> Text
showListType UnorderedList = "unordered"
showListType OrderedList = "ordered"

-- Convert a single 'Block' element to XML.
--
-- Note: SectionDoc documents should not contain Header elements,
-- all header information is collected in Section elements.
block :: Block -> Reader Meta Markup
block (Para xs) = el "p" <$> inlines xs
block (Header _ _ xs) = el "head" <$> inlines xs
block (List ltype xss) =
  el "list" ! attr "type" (textValue (showListType ltype)) <$>
  foldMapR (fmap (el "item") . blocks) xss
block (AnchorList ItemList xs) =
  el "list" ! attr "type" "numbered-item-list" <$>
  foldMapR itemlistitem xs
block (AnchorList NoteList xs) =
  el "list" ! attr "type" "notes" <$>
  foldMapR notelistitem xs
block (BibList citeEntries) =
  el "listBibl" <$>
  foldMapR biblistitem citeEntries
block (QuotationBlock xs) =
  el "quote" <$> blocks xs
block (Figure anchor mediaid imgdesc) = do
  imgloc <- asks (lookupMedia mediaid . metaMediaMap)
  el "figure" ! attr "xml:id" (textValue (internalAnchorID anchor)) <$>
    leaf "graphic" ! attr "url" (textValue imgloc) $<>
    (el "head" <$> inlines imgdesc)
block (Table anchor tdesc tdata) =
  el "table" ! attr "xml:id" (textValue (internalAnchorID anchor)) <$>
  (el "head" <$> inlines tdesc) <+>
  foldMapR (fmap (el "row") . foldMapR tableCell) tdata
block (SimpleTable tdata) =
  el "table" <$>
  foldMapR (fmap (el "row") . foldMapR tableCell) tdata

-- Convert a single 'TableCell' element to XML.
tableCell :: TableCell -> Reader Meta Markup
tableCell (SingleCell xs) =
  el "cell" <$> inlines xs
tableCell (MultiCell i xs) =
  el "cell" ! attr "cols" (stringValue (show i)) <$> inlines xs

-- Convert a single 'ItemList' item to XML.
itemlistitem :: ListItem -> Reader Meta Markup
itemlistitem (ListItem anchor xs) =
  el "item" !
    attr "xml:id" (textValue (internalAnchorID anchor)) !
    attr "type" "numbered-item" !
    attr "n" (stringValue (show (internalAnchorLocalNum anchor))) <$>
  blocks xs

-- Convert a single 'NoteList' item to XML.
--
-- Note: This should only be used (if at all) for secondary lists
-- of notes. The items do not get an @xml:id@ attribute from the
-- anchor; these identifiers are reserved for 'Note' inlines.
notelistitem :: ListItem -> Reader Meta Markup
notelistitem (ListItem anchor xs) =
  el "item" !
    attr "n" (stringValue (internalAnchorDescriptionAsText anchor)) <$>
  blocks xs

-- Create a single entry in the bibliography.
biblistitem :: CiteEntry -> Reader Meta Markup
biblistitem (CiteEntry anchor _ _ formatted) =
  el "bibl" ! attr "xml:id" (textValue (internalAnchorID anchor)) <$>
  inlines formatted

-- Convert a single 'Inline' element to XML.
inline :: Inline -> Reader Meta Markup
inline (Str xs) = return $ string xs
inline (FontStyle s xs) = style s <$> inlines xs
inline (Math _ xs) = el "formula" <$> inlines xs
inline Space = return $ text " "
inline (Citation cit) = do
  db <- asks metaCiteDB
  el "seg" ! attr "type" "citation-group" <$>
    inlines (fmtMultiCite db cit)
inline (Pointer label protoAnchor) = do
  anchorDB <- asks metaAnchorMap
  fileDB <- asks metaAnchorFileMap
  let anchor = extractAnchor anchorDB label protoAnchor
  el "ref" !
    attr "target" (textValue (anchorTarget fileDB anchor)) !?
    ( not (T.null (anchorType anchor))
    , attr "type" (textValue (anchorType anchor))) <$>
    inlines (anchorDescription anchor)
inline (Note anchor notetext) =
  el "note" !
    attr "xml:id" (textValue (internalAnchorID anchor)) !
    attr "type" "footnote" !
    attr "place" "bottom" !
    attr "n" (stringValue (internalAnchorDescriptionAsText anchor)) <$>
  blocks notetext

-- Apply a font style.
style :: Style -> Markup -> Markup
style Normal = el "hi" ! attr "style" "font-style: normal;"
style Emph = el "emph"
style Sub = el "hi" ! attr "style" "vertical-align: sub; font-size: smaller;"
style Sup = el "hi" ! attr "style" "vertical-align: super; font-size: smaller;"
