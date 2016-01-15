{-# LANGUAGE OverloadedStrings #-}
----------------------------------------------------------------------
--
-- Module      :  Text.Doc.Writer.HtmlSpec
-- Copyright   :  2015-2016 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
-- Maintainer  :  mathias.schenner@langsci-press.org
--
-- Tests for the "Text.Doc.Writer.Html" module.
----------------------------------------------------------------------

module Text.Doc.Writer.HtmlSpec
  ( tests
  ) where

import Test.Framework (Test, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.HUnit ((@?=))
import Data.Text.Lazy (Text)
import qualified Data.Text.Lazy as LT

import Text.Doc.Types
import Text.Doc.Writer.Html


-------------------- tests

tests :: Test
tests = testGroup "Text.Doc.Writer.HtmlSpec"
  [ testsDoc
  , testsBlocks
  , testsInlines
  ]

testsDoc :: Test
testsDoc = testGroup "documents"
  [ testCase "empty document" $
    doc2html (Doc defaultMeta [])
    @?=
    LT.concat [ "<!DOCTYPE HTML>\n<html><head>"
              , metaCharset
              , "<title></title>"
              , metaViewport
              , metaGenerator
              , "</head><body>"
              , "<h1></h1><h2></h2>"
              , "</body></html>"]
  , testCase "simple document" $
    doc2html (Doc
      defaultMeta { metaTitle = [Str "No title"]
                  , metaAuthors = [[Str "Nobody"]]
                  , metaDate = [Str "2015-12-31"] }
      [Para [Str "hello", Space, Emph [Str "world"]]])
    @?=
    LT.concat [ "<!DOCTYPE HTML>\n<html><head>"
              , metaCharset
              , "<title>No title</title>"
              , metaViewport
              , metaGenerator
              , "</head><body>"
              , "<h1>No title</h1><h2>Nobody</h2>"
              , "<p>hello <em>world</em></p>"
              , "</body></html>"]
  ]

testsBlocks :: Test
testsBlocks = testGroup "blocks"
  [ testCase "single paragraph" $
    blocks2html [Para [Str "hello", Space, Emph [Str "world"]]]
    @?=
    "<p>hello <em>world</em></p>"
  , testCase "simple unordered list" $
    blocks2html [List UnorderedList
      [ [Para [Str "one",Space,Str "one"]]
      , [Para [Str "two",Space]]
      , [Para [Str "three"]]]]
    @?=
    LT.append "<ul><li><p>one one</p></li><li><p>two </p></li>"
              "<li><p>three</p></li></ul>"
  , testCase "simple ordered list" $
    blocks2html [List OrderedList
      [ [Para [Str "one"]]
      , [Para [Str "two"]]]]
    @?=
    LT.append "<ol><li><p>one</p></li>"
              "<li><p>two</p></li></ol>"
  , testCase "simple block quote" $
    blocks2html [QuotationBlock [Para [Str "one"]]]
    @?=
    "<blockquote><p>one</p></blockquote>"
  , testCase "simple figure" $
    blocks2html [Figure (FigureAnchor (2,1)) "image.png" [Str "description"]]
    @?=
    LT.append "<figure id=\"figure1chap2\"><img src=\"image.png\">"
              "<figcaption>description</figcaption></figure>"
  , testCase "empty table" $
    blocks2html [Table (TableAnchor (2,1)) [Str "description"] []]
    @?=
    LT.append "<table id=\"table1chap2\"><caption>description</caption>"
              "<tbody></tbody></table>"
  , testCase "simple table" $
    blocks2html [Table (TableAnchor (2,1)) [Str "description"]
      [[SingleCell [Str "top-left"], SingleCell [Str "top-right"]]
      ,[SingleCell [Str "bottom-left"], SingleCell [Str "bottom-right"]]]]
    @?=
    LT.concat [ "<table id=\"table1chap2\">"
              , "<caption>description</caption>"
              , "<tbody>"
              , "<tr><td>top-left</td><td>top-right</td></tr>"
              , "<tr><td>bottom-left</td><td>bottom-right</td></tr>"
              , "</tbody></table>"]
  , testCase "table with multi-column cells" $
    blocks2html [Table (TableAnchor (3,4)) [Str "description"]
      [[SingleCell [Str "single", Space, Str "column"], MultiCell 2 [Str "two"]]
      ,[MultiCell 3 [Str "three", Space, Str "columns"]]
      ,[SingleCell [Str "1"], SingleCell [Str "2"], SingleCell [Str "3"]]]]
    @?=
    LT.concat [ "<table id=\"table4chap3\">"
              , "<caption>description</caption>"
              , "<tbody>"
              , "<tr><td>single column</td><td colspan=\"2\">two</td></tr>"
              , "<tr><td colspan=\"3\">three columns</td></tr>"
              , "<tr><td>1</td><td>2</td><td>3</td></tr>"
              , "</tbody></table>"]
  ]

testsInlines :: Test
testsInlines = testGroup "inlines"
  [ testCase "basic text" $
    inlines2html [Str "hello", Space, Str "world"]
    @?=
    "hello world"
  , testCase "emphasis" $
    inlines2html [Str "hello", Space, Emph [Str "world"]]
    @?=
    "hello <em>world</em>"
  , testCase "link to external resource" $
    inlines2html [Pointer "external" (Just (ExternalResource
      [Str "some", Space, Str "description"] "http://example.com/"))]
    @?=
    "<a href=\"http://example.com/\">some description</a>"
  , testCase "link to internal figure" $
    inlines2html [Str "Figure", Space, Pointer "internallabel"
      (Just (InternalResource (FigureAnchor (2,1))))]
    @?=
    "Figure <a href=\"#figure1chap2\">2.1</a>"
  , testCase "empty footnote (only mark)" $
    inlines2html [Note (NoteAnchor (2,8)) []]
    @?=
    "<a id=\"fn8chap2ref\" class=\"fnRef\" href=\"#fn8chap2\"><sup>2.8</sup></a>"
  , testCase "simple footnote (only mark)" $
    inlines2html [Note (NoteAnchor (1,2)) [Para [Str "hello"]]]
    @?=
    "<a id=\"fn2chap1ref\" class=\"fnRef\" href=\"#fn2chap1\"><sup>1.2</sup></a>"
  ]


-------------------- boilerplate constants

metaCharset :: Text
metaCharset = "<meta charset=\"utf-8\">"

metaViewport :: Text
metaViewport = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"

metaGenerator :: Text
metaGenerator = "<meta name=\"generator\" content=\"texhs\">"
