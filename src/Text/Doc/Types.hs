{-# LANGUAGE OverloadedStrings #-}
----------------------------------------------------------------------
-- |
-- Module      :  Text.Doc.Types
-- Copyright   :  2015-2017 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mschenner.dev@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- The Doc type and utility functions.
----------------------------------------------------------------------

module Text.Doc.Types
  ( -- * Doc type
    Doc(..)
  , docTitle
  , docSubTitle
  , docAuthors
  , docDate
    -- * Meta
  , Meta(..)
  , defaultMeta
  , HasMeta(..)
    -- ** Sections
  , SectionInfo(..)
  , BookRegion(..)
  , SectionPosition(..)
  , SectionNumber
  , registerRegion
  , registerHeader
  , registerHeaderPhantom
  , getPhantomAnchor
  , isPhantomSection
    -- ** Citations
  , CiteKey
  , CiteMap
  , CiteDB
  , CiteEntry(..)
  , registerCiteKeys
  , extractCiteKeys
    -- ** Anchors
  , Label
  , Location
  , LinkTitle
  , LinkType
  , NotePart(..)
  , Anchor(..)
  , anchorTarget
  , anchorTitle
  , anchorType
  , anchorDescription
  , InternalAnchor(..)
  , internalAnchorID
  , internalAnchorTarget
  , internalAnchorDescription
  , internalAnchorDescriptionAsText
  , internalAnchorLocalNum
  , internalAnchorSwitch
  , registerAnchorLabel
  , extractAnchor
    -- ** Media
  , MediaID
  , MediaMap
  , registerMedia
  , lookupMedia
  , setCoverImage
    -- ** Multifile
  , FileID
  , AnchorFileMap
  , filenameFromID
    -- ** Writer options
  , HtmlVersion(..)
  , setHtmlVersion
    -- * Content types
    -- ** Blocks
  , Content
  , Block(..)
  , Level
  , ListType(..)
  , AnchorListType(..)
  , ListItem(..)
  , TableRow
  , TableCell(..)
    -- ** Inlines
  , Inline(..)
  , Style(..)
  , MathType(..)
  , MultiCite(..)
  , SingleCite(..)
  , CiteMode(..)
    -- * Content functions
    -- ** Blocks
  , isPara
  , isHeader
  , isList
    -- ** Inlines
  , plain
  , isStr
  , isSpace
    -- ** Normalization
  , normalizeInlines
  , stripInlines
    -- ** Generic formatting
  , mkExternalLink
  , mkInternalLink
  , fmtEmph
  , fmtSepByDot
  , fmtEndByDot
  , fmtSepBy
  , fmtSepEndBy
  , fmtEndBy
  , fmtWrap
  ) where

import Control.Applicative
import Data.List (dropWhileEnd, intersperse, intercalate)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Text.Printf (printf)

import Text.TeX.Parser.Types (MathType(..))


-------------------- Doc type

-- | A 'Doc' document consist of meta information and content.
data Doc = Doc Meta Content
  deriving (Eq, Show)


-------------------- Meta type

-- | Meta information of a 'Doc' document.
data Meta = Meta
  { metaTitle :: [Inline]
  , metaSubTitle :: [Inline]
  , metaAuthors :: [[Inline]]
  , metaDate :: [Inline]
  , metaCover :: Maybe FilePath
  , metaCiteDB :: CiteDB
  , metaCiteMap :: CiteMap
  , metaCiteCount :: Int
  , metaAnchorCurrent :: InternalAnchor
  , metaAnchorMap :: Map Label InternalAnchor
  , metaAnchorFileMap :: AnchorFileMap
  , metaNoteMap :: Map (Int, Int) [Block]
  , metaMediaCurrent :: Int
  , metaMediaMap :: MediaMap
  , metaPhantomSectionCount :: Int
  , metaBookRegion :: BookRegion
  , metaSectionCurrent :: SectionNumber
  , metaFigureCurrent :: (Int, Int)
  , metaTableCurrent :: (Int, Int)
  , metaNoteCurrent :: (Int, Int)
  , metaItemCurrent :: (Int, [Int])
  , metaWriterHtmlVersion :: HtmlVersion
  } deriving (Eq, Show)

-- | Default (empty) meta information of a document.
defaultMeta :: Meta
defaultMeta = Meta
  { metaTitle = []
  , metaSubTitle = []
  , metaAuthors = []
  , metaDate = []
  , metaCover = Nothing
  , metaCiteDB = M.empty
  , metaCiteMap = M.empty
  , metaCiteCount = 0
  , metaAnchorCurrent = DocumentAnchor
  , metaAnchorMap = M.empty
  , metaAnchorFileMap = M.empty
  , metaNoteMap = M.empty
  , metaMediaCurrent = 0
  , metaMediaMap = M.empty
  , metaPhantomSectionCount = 0
  , metaBookRegion = Frontmatter
  , metaSectionCurrent = sectionNumberReset
  , metaFigureCurrent = (0, 0)
  , metaTableCurrent = (0, 0)
  , metaNoteCurrent = (0, 0)
  , metaItemCurrent = (0, [0])
  , metaWriterHtmlVersion = XHTML5
  }

-- | A class for document types that hold meta information.
class HasMeta d where
  -- | Extract meta information.
  docMeta :: d -> Meta

instance HasMeta Doc where
  docMeta (Doc meta _) = meta

---------- Anchors: Cross-references and external links

-- | An anchor is a location in a document
-- that can be the target of a 'Pointer'.
data Anchor
  = InternalResourceAuto InternalAnchor
  | InternalResource [Inline] InternalAnchor LinkTitle LinkType
  | ExternalResource [Inline] Location LinkTitle LinkType
  deriving (Eq, Show)

-- | An internal anchor is a location within the current document.
--
-- Internal anchors and pointers are used to model cross-references.
data InternalAnchor
  = DocumentAnchor             -- initial anchor in a document
  | SectionAnchor SectionInfo  -- includes book region and section number
  | FigureAnchor (Int, Int)    -- chapter number and chapter-relative figure count
  | TableAnchor (Int, Int)     -- chapter number and chapter-relative table count
  | NoteAnchor (Int, Int, NotePart) -- chapter number and chapter-relative note count
  | ItemAnchor (Int, [Int])    -- chapter number and chapter-relative item numbers
                               --   in reverse order, e.g. [1,3,2] --> \"2.3.1\"
  | BibAnchor Int              -- global appearance order
  deriving (Eq, Ord, Show)

-- | Notes may be split into two parts: The note mark and the note text.
--
-- This flag can be used to distinguish between the two parts. If a note
-- is not separated into parts, this setting defaults to 'NoteMark'.
data NotePart = NoteMark | NoteText
  deriving (Eq, Ord, Show)

-- | Generate identifying string for an internal anchor.
--
-- This can be used for @xml:id@ attributes.
internalAnchorID :: InternalAnchor -> Text
internalAnchorID DocumentAnchor = ""
internalAnchorID (SectionAnchor secinfo) =
  let (reg, nums) = sectionInfoID secinfo
  in T.concat ["sec-", reg, hyphenSep nums]
internalAnchorID (FigureAnchor (ch, n)) =
  T.append "figure-" (hyphenSep [ch, n])
internalAnchorID (TableAnchor (ch, n)) =
  T.append "table-" (hyphenSep [ch, n])
internalAnchorID (NoteAnchor (ch, n, NoteMark)) =
  T.append "note-" (hyphenSep [ch, n])
internalAnchorID (NoteAnchor (ch, n, NoteText)) =
  T.append "notetext-" (hyphenSep [ch, n])
internalAnchorID (ItemAnchor (ch, ns)) =
  T.append "item-" (hyphenSep (ch:reverse ns))
internalAnchorID (BibAnchor n) =
  T.append "bib-" (T.pack (show n))

-- | Switch between the two parts of a 'NoteAnchor'.
--
-- (Identity function for all other anchors that do not have two parts.)
internalAnchorSwitch :: InternalAnchor -> InternalAnchor
internalAnchorSwitch (NoteAnchor (ch, n, NoteMark)) = NoteAnchor (ch, n, NoteText)
internalAnchorSwitch (NoteAnchor (ch, n, NoteText)) = NoteAnchor (ch, n, NoteMark)
internalAnchorSwitch otherAnchor = otherAnchor

-- | Generate target location string for an anchor.
--
-- This can be used for @href@ attributes in HTML hyperlinks.
anchorTarget :: AnchorFileMap -> Anchor -> Text
anchorTarget db (InternalResourceAuto res) = internalAnchorTarget db res
anchorTarget db (InternalResource _ res _ _) = internalAnchorTarget db res
anchorTarget _ (ExternalResource _ loc _ _) = loc

-- | Generate link title string for an anchor.
--
-- This can be used for @title@ attributes in HTML hyperlinks.
anchorTitle :: Anchor -> Text
anchorTitle (InternalResourceAuto _) = ""
anchorTitle (InternalResource _ _ t _) = t
anchorTitle (ExternalResource _ _ t _) = t

-- | Generate link type string for an anchor.
--
-- This can be used for @class@ attributes in HTML hyperlinks
-- or for @type@ attributes in XML cross-references.
anchorType :: Anchor -> Text
anchorType (InternalResourceAuto _) = ""
anchorType (InternalResource _ _ _ t) = t
anchorType (ExternalResource _ _ _ t) = t

-- | Generate target location string for an internal anchor.
--
-- This can be used for @href@ attributes in HTML hyperlinks.
internalAnchorTarget :: AnchorFileMap -> InternalAnchor -> Text
internalAnchorTarget db anchor =
  maybe id (T.append . T.pack . filenameFromID) (M.lookup anchor db)
  (T.cons '#' (internalAnchorID anchor))

-- | Generate description text for an anchor.
anchorDescription :: Anchor -> [Inline]
anchorDescription (InternalResourceAuto i) = internalAnchorDescription i
anchorDescription (InternalResource l _ _ _) = l
anchorDescription (ExternalResource l _ _ _) = l

-- | Generate description text for an internal anchor.
--
-- Intended to be used in running 'Inline' text.
internalAnchorDescription :: InternalAnchor -> [Inline]
internalAnchorDescription = (:[]) . Str . internalAnchorDescriptionAsText

-- | Generate raw description text for an internal anchor.
--
-- Intended to be used in XML attribute values.
internalAnchorDescriptionAsText :: InternalAnchor -> String
internalAnchorDescriptionAsText DocumentAnchor = "start"
internalAnchorDescriptionAsText (SectionAnchor secinfo) =
  (dotSep . snd . sectionInfoID) secinfo
internalAnchorDescriptionAsText (FigureAnchor (ch, n)) = dotSep [ch, n]
internalAnchorDescriptionAsText (TableAnchor (ch, n)) = dotSep [ch, n]
internalAnchorDescriptionAsText (NoteAnchor (ch, n, _)) = dotSep [ch, n]
internalAnchorDescriptionAsText (ItemAnchor (ch, ns)) = dotSep (ch:reverse ns)
internalAnchorDescriptionAsText (BibAnchor n) = show n

-- Note: For some anchor types, fallback values are returned --
-- consider throwing an exception in these cases instead.
-- Note: This function is mainly used for 'ItemAnchor' values.
-- | Extract value at the innermost level of an internal anchor.
internalAnchorLocalNum :: InternalAnchor -> Int
internalAnchorLocalNum DocumentAnchor = 0 -- fallback
internalAnchorLocalNum (SectionAnchor si) = (last . snd . sectionInfoID) si
internalAnchorLocalNum (FigureAnchor (_, n)) = n
internalAnchorLocalNum (TableAnchor (_, n)) = n
internalAnchorLocalNum (NoteAnchor (_, n, _)) = n
internalAnchorLocalNum (ItemAnchor (_, n:_)) = n
internalAnchorLocalNum (ItemAnchor (_, [])) = 0 -- fallback
internalAnchorLocalNum (BibAnchor n) = n

-- Given a list of numbers, format them as an inline string
-- with a separating period between numbers (e.g. \"2.3.1\").
dotSep :: [Int] -> String
dotSep = intercalate "." . map show

-- Given a list of numbers, format them as an inline string
-- with a separating hyphen between numbers (e.g. \"2-3-1\").
hyphenSep :: [Int] -> Text
hyphenSep = T.pack . intercalate "-" . map show

-- | A label is a name of an internal anchor.
--
-- In particular, it can be used by a 'Pointer' as
-- a way to refer to an 'InternalAnchor' in the document.
type Label = Text

-- | A description of the location of a resource, typically an URI.
--
-- This is used as the link target of an 'ExternalResource'.
type Location = Text

-- | An optional secondary description of an external resource.
--
-- This is used as the link title of an 'ExternalResource'.
type LinkTitle = Text

-- | An optional description of the type of an external resource.
--
-- This is used as the link type of an 'ExternalResource'.
type LinkType = Text

-- | Assign a label to the current anchor
-- in the document meta information.
registerAnchorLabel :: Label -> Meta -> Meta
registerAnchorLabel label meta =
  let anchor = metaAnchorCurrent meta
      newMap = M.insert label anchor (metaAnchorMap meta)
  in meta { metaAnchorMap = newMap }

-- | Extract the target anchor from 'Pointer' arguments.
extractAnchor :: Map Label InternalAnchor -> Label -> Maybe Anchor -> Anchor
extractAnchor db label protoAnchor =
  let undefinedAnchor = ExternalResource [Str "???"] "" "" ""
  in fromMaybe undefinedAnchor $ protoAnchor <|>
     (InternalResourceAuto <$> M.lookup label db)


---------- Media references

-- | A MediaID is a unique identifier of a referenced media file.
type MediaID = Int

-- | A mapping from identifiers to filepaths
-- of referenced media files.
type MediaMap = Map MediaID Location

-- | Register a new media file.
--
-- Assign and increment current media ID.
registerMedia :: Location -> Meta -> Meta
registerMedia filePath meta =
  let mediaID = metaMediaCurrent meta
      newMap = M.insert mediaID filePath (metaMediaMap meta)
  in meta { metaMediaCurrent = 1 + mediaID
          , metaMediaMap = newMap }

-- | Lookup the filepath of a media file by its ID.
--
-- Return empty filepath for non-existing IDs.
lookupMedia :: MediaID -> MediaMap -> Location
lookupMedia mediaID db = fromMaybe "" (M.lookup mediaID db)

-- | Set cover image for the document.
setCoverImage :: FilePath -> Doc -> Doc
setCoverImage path (Doc meta body) =
  let newMeta = meta { metaCover = Just path }
  in Doc newMeta body


---------- Multifile support

-- | A FileID identifies a physical file of a multifile document.
type FileID = Int

-- | A mapping from internal anchors to the physical file
-- in which they are contained.
--
-- This map is only used for multifile documents.
-- If the document is contained in a single file,
-- this map is empty.
type AnchorFileMap = Map InternalAnchor FileID

-- | Return the filename associated with a FileID.
--
-- Note: We assume an \"xhtml\" file extension.
-- Example filename: \"section-001.xhtml\".
filenameFromID :: FileID -> FilePath
filenameFromID = printf "section-%03d.xhtml"


---------- Writer options

-- | HTML version to be used by HTML Writer.
data HtmlVersion = XHTML5 | XHTML1
  deriving (Eq, Show)

-- | Configure HTML version.
setHtmlVersion :: HtmlVersion -> Doc -> Doc
setHtmlVersion version (Doc meta body) =
  let newMeta = meta { metaWriterHtmlVersion = version }
  in Doc newMeta body


---------- Citations

-- | Identifier key for bibliographic entries.
type CiteKey = Text

-- | A complete set of citekeys that are used in a document.
--
-- Each citekey is associated with some meta information: the number
-- of its first occurrence in the global citation occurrence order.
type CiteMap = Map CiteKey Int

-- | A collection of formatted citations.
type CiteDB = Map CiteKey CiteEntry

-- | Citation information for a single bibliographic entry.
--
-- This can be used to generate an author-year style citation
-- and a full bibliographic reference for a single entry.
data CiteEntry = CiteEntry
  { citeAnchor :: InternalAnchor
  , citeAgents :: [[Inline]]
  , citeYear   :: [Inline]
  , citeFull   :: [Inline]
  } deriving (Eq, Show)

-- Used for sorting the bibliography.
instance Ord CiteEntry where
  compare = comparing citeFull

-- | Add a list of citekeys to document meta information.
registerCiteKeys :: [CiteKey] -> Meta -> Meta
registerCiteKeys keys meta =
  let citeCount = metaCiteCount meta
      citeMap = metaCiteMap meta
      keysNum = zip keys [citeCount..]
      insertIfNew = uncurry (M.insertWith (flip const))
      newCount = citeCount + length keys
      newMap = foldr insertIfNew citeMap keysNum
  in meta { metaCiteMap = newMap
          , metaCiteCount = newCount
          }

---------- Sections

-- | Identifying information about a section.
data SectionInfo = SectionInfo BookRegion SectionPosition
  deriving (Eq, Ord, Show)

-- Return pieces for easily constructing an identifying string for a
-- SectionInfo. In particular, return a prefix string (for the book
-- region and to indicate phantom sections) and a trimmed section
-- hierarchy list, e.g. @[1,2]@ for @Chapter 1, Section 2@.
--
-- The returned list always contains at least one element (chapter).
-- However, the returned prefix string may be empty (in particular,
-- it is empty for all numbered mainmatter sections).
sectionInfoID :: SectionInfo -> (Text, [Int])
sectionInfoID (SectionInfo reg pos) =
  let regionPrefix = bookRegionID reg
      (phantomPrefix, nums) = sectionPositionID pos
  in (T.append regionPrefix phantomPrefix, nums)

-- | The broad region in which a section is located.
--
-- This structuring level is above @part@ and @chapter@.
-- It may be used to control chapter numbering style, for example.
data BookRegion
  = Frontmatter
  | Mainmatter
  | Backmatter
  deriving (Eq, Ord, Show)

-- Help generate an identifying string for 'sectionInfoID'.
bookRegionID :: BookRegion -> Text
bookRegionID r = case r of
  Frontmatter -> "front-"
  Mainmatter -> ""
  Backmatter -> "back-"

-- | Identifying information about the position of a section
-- (within a 'BookRegion').
data SectionPosition
    -- | Regular numbered section.
  = SectionRegular SectionNumber
    -- | Unnumbered section.
    -- An \"unnumbered\" section is still associated
    -- with an identifying count.
  | SectionPhantom Int
  deriving (Eq, Ord, Show)

-- | Representation of a numbered section (within a 'BookRegion')
-- as a tuple: @(part, chapter, section, subsection,
-- subsubsection, paragraph, subparagraph)@.
type SectionNumber = (Int,Int,Int,Int,Int,Int,Int)

-- Return trimmed section hierarchy list
-- (no part number and no trailing zeros),
-- e.g. @[1,2]@ for @Chapter 1, Section 2@,
-- together with a prefix string for phantom sections.
-- The returned list always contains at least one element (chapter).
sectionPositionID :: SectionPosition -> (Text, [Int])
sectionPositionID (SectionRegular sn) =
  let (chap:xs) = tail (sectionNumberToList sn)
  in ("", chap : dropWhileEnd (==0) xs)
sectionPositionID (SectionPhantom i) =
  ("unnumbered-", [i])

-- Convert section number to a list representation.
sectionNumberToList :: SectionNumber -> [Int]
sectionNumberToList (pt,ch,se,sb,ss,pa,sp) = [pt,ch,se,sb,ss,pa,sp]

-- Convert a list of integers to a section number.
--
-- Throws an error if the input list has an incorrect length.
sectionNumberFromList :: [Int] -> SectionNumber
sectionNumberFromList [pt,ch,se,sb,ss,pa,sp] = (pt,ch,se,sb,ss,pa,sp)
sectionNumberFromList _ = error "sectionNumberFromList: invalid section number list"

-- | Initial section number.
sectionNumberReset :: SectionNumber
sectionNumberReset = (0,0,0,0,0,0,0)

-- | Increment a section number at a given level.
sectionNumberIncrement :: Level -> SectionNumber -> SectionNumber
sectionNumberIncrement n c@(pt,ch,se,sb,ss,pa,sp)
  | n == 1 = (pt+1,ch,se,sb,ss,pa,sp) -- incrementing Part does not affect lower levels
  | otherwise = sectionNumberFromList $
      uncurry (++) $ incLevels `fmap` splitAt (n-1) (sectionNumberToList c)
  where
    incLevels [] = []
    incLevels (x:xs) = x+1 : replicate (length xs) 0

-- | Extract chapter number.
getChapter :: SectionNumber -> Int
getChapter (_,ch,_,_,_,_,_) = ch

-- | Register a new phantom section header
-- in the document meta information.
registerHeaderPhantom :: Meta -> Meta
registerHeaderPhantom meta = meta
  { metaPhantomSectionCount = 1 + metaPhantomSectionCount meta }

-- | Construct an internal anchor for the current phantom section.
getPhantomAnchor :: Meta -> InternalAnchor
getPhantomAnchor meta =
  let reg = metaBookRegion meta
      count = metaPhantomSectionCount meta
  in SectionAnchor (SectionInfo reg (SectionPhantom count))

-- | Test whether an internal anchor is a phantom section.
isPhantomSection :: InternalAnchor -> Bool
isPhantomSection (SectionAnchor (SectionInfo _ (SectionPhantom _))) = True
isPhantomSection _ = False

-- | Register a new section header
-- in the document meta information.
--
-- This will set the header as the current anchor
-- (e.g. for subsequent @label@ assignments).
-- If the header starts a new chapter, all chapter-dependent
-- counters are also reset (e.g. figures, tables, notes, items).
registerHeader :: Level -> Meta -> Meta
registerHeader level meta =
  let sectionCurrent = sectionNumberIncrement level (metaSectionCurrent meta)
      bookRegion = metaBookRegion meta
      anchorCurrent = SectionAnchor
        (SectionInfo bookRegion (SectionRegular sectionCurrent))
      figureCurrent = if level == 2
                      then (getChapter sectionCurrent, 0)
                      else metaFigureCurrent meta
      tableCurrent  = if level == 2
                      then (getChapter sectionCurrent, 0)
                      else metaTableCurrent meta
      noteCurrent   = if level == 2
                      then (getChapter sectionCurrent, 0)
                      else metaNoteCurrent meta
      itemCurrent   = if level == 2
                      then (getChapter sectionCurrent, [0])
                      else metaItemCurrent meta
  in meta { metaSectionCurrent = sectionCurrent
          , metaAnchorCurrent = anchorCurrent
          , metaFigureCurrent = figureCurrent
          , metaTableCurrent = tableCurrent
          , metaNoteCurrent = noteCurrent
          , metaItemCurrent = itemCurrent
          }

-- | Register the beginning of a new book region
-- in the document meta information.
--
-- This will reset the chapter counter.
registerRegion :: BookRegion -> Meta -> Meta
registerRegion newRegion meta =
  -- If we already are in the specified region,
  -- do not reset the section (chapter) counter.
  -- (In particular, since we map @\\appendix@ and @\\backmatter@
  -- both to 'Backmatter', the latter will have no effect.)
  let regionCurrent = metaBookRegion meta
      sectionCurrent = if newRegion == regionCurrent
                       then metaSectionCurrent meta
                       else sectionNumberReset
  in meta { metaBookRegion = newRegion
          , metaSectionCurrent = sectionCurrent
          }


-------------------- Content type

-- | Content of a 'Doc' document.
type Content = [Block]

-- | Level of a heading.
type Level = Int

-- | Type of list: unordered or ordered.
data ListType = UnorderedList | OrderedList
  deriving (Eq, Show)

-- | Type of an anchor list.
data AnchorListType
  -- | A list of items with the special property that
  -- they have a unique number based on a global counter.
  -- They can be used to model @gb4e@-style linguistic examples.
  = ItemList
  -- | A list of notes.
  | NoteList
  deriving (Eq, Show)

-- | A list item with an internal anchor.
data ListItem = ListItem InternalAnchor [Block]
  deriving (Eq, Show)

-- | A table row consist of a list of table cells.
type TableRow = [TableCell]

-- Note: Table cells can only contain 'Inline' elements at the moment,
-- but we might have to broaden this to (certain) 'Block' elements.
--
-- | A (logical) table cell can span one or more physical cells.
--
-- Note: 'MultiCell' elements model multi-column cells, not multi-row cells.
data TableCell
  = SingleCell [Inline]
  | MultiCell Int [Inline]
  deriving (Eq, Show)

-- | Block elements in a 'Doc' document.
data Block
  = Para [Inline]
  | Header Level InternalAnchor [Inline]
  | List ListType [[Block]]
  | AnchorList AnchorListType [ListItem]
  | BibList [CiteEntry]
  | QuotationBlock [Block]
  | Figure InternalAnchor MediaID [Inline]
  | Table InternalAnchor [Inline] [TableRow]
  | SimpleTable [TableRow]
  deriving (Eq, Show)

-- | Inline elements in a 'Doc' document.
data Inline
  = Str String
  | FontStyle Style [Inline]
  | Math MathType [Inline]
  | Space
  | Citation MultiCite
  | Pointer Label (Maybe Anchor)
  | Note InternalAnchor [Block]
  deriving (Eq, Show)

-- Preliminary instance. Should use text and text-icu.
instance Ord Inline where
  compare = comparing plain

-- | Font styles for textual elements.
data Style
  = Normal
  | Emph
  | Sub
  | Sup
  deriving (Eq, Show)

-- | A list of 'SingleCite' citations
-- with optional prenote and postnote.
--
-- This is modeled after biblatex's
-- multicite commands (e.g. @\\cites@).
data MultiCite = MultiCite
  { multiCiteMode :: CiteMode
  , multiCitePrenote :: [Inline]
  , multiCitePostnote :: [Inline]
  , multiCites :: [SingleCite]
  } deriving (Eq, Show)

-- | A single citation
-- comprised of a list of citekeys
-- and optional prenote and postnote.
--
-- This is modeled after biblatex's
-- basic cite commands (e.g. @\\cite@).
data SingleCite = SingleCite
  { singleCitePrenote :: [Inline]
  , singleCitePostnote :: [Inline]
  , singleCiteKeys :: [CiteKey]
  } deriving (Eq, Show)

-- | The type of a citation.
--
-- This may be used by document writers to adjust
-- the formatting of a citation.
data CiteMode
  = CiteBare    -- like biblatex's @\\cite@
  | CiteParen   -- like biblatex's @\\parencite@
  | CiteText    -- like biblatex's @\\textcite@
  | CiteAuthor  -- like biblatex's @\\citeauthor@
  | CiteYear    -- like biblatex's @\\citeyear@
  deriving (Eq, Show)

-- | Extract all citekeys from a citation.
extractCiteKeys :: MultiCite -> [CiteKey]
extractCiteKeys = concatMap singleCiteKeys . multiCites


-------------------- Block predicates

-- | Test whether a 'Block' is a 'Para'.
isPara :: Block -> Bool
isPara Para{} = True
isPara _ = False

-- | Test whether a 'Block' is a 'Header'.
isHeader :: Block -> Bool
isHeader Header{} = True
isHeader _ = False

-- | Test whether a 'Block' is a 'List'.
isList :: Block -> Bool
isList List{} = True
isList _ = False


-------------------- Inline predicates

-- | Test whether an 'Inline' is a 'Str'.
isStr :: Inline -> Bool
isStr Str{} = True
isStr _ = False

-- | Test whether an 'Inline' is a 'Space'.
isSpace :: Inline -> Bool
isSpace Space = True
isSpace _ = False


-------------------- Accessor functions

-- | Extract document title.
docTitle :: HasMeta d => d -> [Inline]
docTitle = metaTitle . docMeta

-- | Extract document subtitle.
docSubTitle :: HasMeta d => d -> [Inline]
docSubTitle = metaSubTitle . docMeta

-- | Extract document authors.
docAuthors :: HasMeta d => d -> [[Inline]]
docAuthors = metaAuthors . docMeta

-- | Extract document date.
docDate :: HasMeta d => d -> [Inline]
docDate = metaDate . docMeta

-- Warning: does not preserve full content.
-- - strips font styles
-- - drops footnotes
-- - drops prenotes and postnotes in citations
-- | Extract plain character data from an 'Inline' element.
plain :: Inline -> String
plain (Str xs) = xs
plain (FontStyle _ is) = concatMap plain is
plain (Math _ is) = concatMap plain is
plain Space = " "
plain (Citation (MultiCite _ _ _ xs)) = T.unpack (plainCites xs)
plain (Pointer label _) = T.unpack (T.concat ["<", label, ">"])
plain Note{} = ""

-- Helper for showing raw citations.
plainCites :: [SingleCite] -> Text
plainCites = T.intercalate ";" . map plainCite

-- Helper for showing raw citations.
plainCite :: SingleCite -> Text
plainCite (SingleCite _ _ sKeys) = T.concat (intersperse "," sKeys)


-------------------- Normalization

-- | Conflate adjacent strings.
normalizeInlines :: [Inline] -> [Inline]
normalizeInlines [] = []
normalizeInlines (Str xs : Str ys : zs) = normalizeInlines (Str (xs ++ ys) : zs)
normalizeInlines (xs : ys) = xs : normalizeInlines ys

-- | Strip leading and trailing whitespace.
stripInlines :: [Inline] -> [Inline]
stripInlines = dropWhile isSpace . dropWhileEnd isSpace


-------------------- Generic formatting helpers

-- | Create a 'Pointer' to an external resource.
mkExternalLink :: [Inline] -> Location -> LinkTitle -> LinkType -> [Inline]
mkExternalLink description target linkTitle linkType =
  [Pointer "" (Just (ExternalResource description target linkTitle linkType))]

-- | Create a 'Pointer' to an internal resource.
mkInternalLink :: [Inline] -> InternalAnchor -> LinkTitle -> LinkType -> [Inline]
mkInternalLink description anchor linkTitle linkType =
  [Pointer "" (Just (InternalResource description anchor linkTitle linkType))]

-- | Apply emphasis iff content is not null.
fmtEmph :: [Inline] -> [Inline]
fmtEmph [] = []
fmtEmph xs@(_:_) = [FontStyle Emph xs]

-- | Concatenate a list, interspersing two different separators:
-- one between inner list items, one between the last two items.
-- Works just like 'Data.List.intercalate' except that the last
-- two items are separated by a special separator.
--
-- Syntax: @fmtSepEndBy midSep endSep itemlist@.
-- This separates items by @midSep@, except for the last two items,
-- which are separated by @endSep@.
--
-- Example:
--
-- > fmtSepEndBy ", " " and " ["one", "two", "three"]  ==  "one, two and three"
--
fmtSepEndBy :: [a] -> [a] -> [[a]] -> [a]
fmtSepEndBy _ _ [] = []
fmtSepEndBy _ _ [i] = i
fmtSepEndBy _ endSep [i,j] = i ++ endSep ++ j
fmtSepEndBy midSep endSep (i:items@(_:_:_)) = i ++ midSep ++ fmtSepEndBy midSep endSep items

-- | Insert separator iff both parts are not null.
--
-- Syntax: @fmtSepBy left sep right@.
fmtSepBy :: [a] -> [a] -> [a] -> [a]
fmtSepBy [] _ right = right
fmtSepBy left _ [] = left
fmtSepBy left@(_:_) sep right@(_:_) = left ++ sep ++ right

-- | Separate two inlines by a period and a space.
--
-- If either part is null the other is returned.
-- If the left part ends with a period, only a space is inserted.
--
-- Syntax: @fmtSepByDot left right@.
fmtSepByDot :: [Inline] -> [Inline] -> [Inline]
fmtSepByDot left@(_:_) right
  | endsWithChar '.' (last left) = fmtSepBy left [Space] right
  | otherwise = fmtSepBy left [Str ".", Space] right
fmtSepByDot [] right = right

-- Test whether the inline ends with a certain character.
endsWithChar :: Char -> Inline -> Bool
endsWithChar c (Str (xs@(_:_))) = c == last xs
endsWithChar _ _ = False

-- | Add suffix iff content is not null.
--
-- Syntax: @fmtEndBy content suffix@.
fmtEndBy :: [a] -> [a] -> [a]
fmtEndBy = fmtWrap []

-- | Append a period if content is not null and
-- does not already end with a period.
fmtEndByDot :: [Inline] -> [Inline]
fmtEndByDot [] = []
fmtEndByDot xs@(_:_)
  | endsWithChar '.' (last xs) = xs
  | otherwise = xs ++ [Str "."]

-- | Add prefix and suffix iff content is not null.
--
-- Syntax: @fmtWrap prefix content suffix@.
fmtWrap :: [a] -> [a] -> [a] -> [a]
fmtWrap _ [] _ = []
fmtWrap pre is@(_:_) post = pre ++ is ++ post
