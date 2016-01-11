{-# LANGUAGE OverloadedStrings #-}
----------------------------------------------------------------------
-- |
-- Module      :  Text.Doc.Writer.Html
-- Copyright   :  2015-2016 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mathias.schenner@langsci-press.org
-- Stability   :  experimental
-- Portability :  GHC
--
-- HTML writer: Convert Doc to HTML.
----------------------------------------------------------------------

module Text.Doc.Writer.Html
 ( -- * Doc to HTML Conversion
   doc2html
 , blocks2html
 , inlines2html
 ) where


import Data.Monoid
import Data.Text.Lazy (Text)
import qualified Data.Text as T
import Text.Blaze.Html5
  ( (!), Html, toHtml, textValue, docTypeHtml, title
  , h1, h2, ul, li, p, em, a)
import Text.Blaze.Html5.Attributes
  (name, charset, content, style, href)
import Text.Blaze.Html.Renderer.Text (renderHtml)
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

import Text.Doc.Types


---------- main: Doc to HTML conversion

-- | Convert a 'Doc' document to HTML.
doc2html :: Doc -> Text
doc2html = renderHtml . convertDoc

-- Convert 'Doc' to 'Html' type.
convertDoc :: Doc -> Html
convertDoc doc = docTypeHtml $ mkHead doc <> mkBody doc

-- | Convert 'Block' elements to an HTML fragment.
blocks2html :: [Block] -> Text
blocks2html = renderHtml . blocks

-- | Convert 'Inline' elements to an HTML fragment.
inlines2html :: [Inline] -> Text
inlines2html = renderHtml . inlines


---------- meta

-- Create @<head>@ element.
mkHead :: Doc -> Html
mkHead doc = H.head $ do
  H.meta ! charset "utf-8"
  title $ inlines (docTitle doc)
  H.meta ! name "viewport" ! content "width=device-width, initial-scale=1.0"
  H.meta ! name "generator" ! content "texhs"


---------- content

-- Create @<body>@ element.
mkBody :: Doc -> Html
mkBody doc@(Doc _ docbody) = H.body $ do
  h1 $ inlines (docTitle doc)
  h2 $ mapM_ inlines (docAuthors doc)
  blocks docbody

-- Convert 'Block' elements to HTML.
blocks :: [Block] -> Html
blocks = mapM_ block

-- Convert 'Inline' elements to HTML.
inlines :: [Inline] -> Html
inlines = mapM_ inline

-- Convert a single 'Block' element to HTML.
block :: Block -> Html
block (Para xs) = p $ inlines xs
block (Header level anchor xs) =
  heading level ! A.id (textValue (anchorURI anchor)) $
  inlines xs
block (List xss) = ul $ mapM_ (li . blocks) xss

-- Convert a single 'Inline' element to HTML.
inline :: Inline -> Html
inline (Str xs) = toHtml xs
inline (Normal xs) =
  H.span ! style "font-style: normal;" $
  inlines xs
inline (Emph xs) = em $ inlines xs
inline Space = toHtml ' '
inline (Citation _ Nothing) =
  error "HTML Writer does not support unprocessed citations."
inline (Citation _ (Just xs)) =
  H.span ! A.class_ "citation" $
  inlines xs
inline (Pointer _ Nothing) =
  error "HTML Writer does not support unprocessed or undefined pointers."
inline (Pointer _ (Just anchor)) =
  a ! href (textValue (T.cons '#' (anchorURI anchor))) $
  toHtml (anchorDescription anchor)

-- Map header level to 'Html' combinator.
heading :: Level -> Html -> Html
heading n
  | n <= 1 = H.h1
  | n == 2 = H.h2
  | n == 3 = H.h3
  | n == 4 = H.h4
  | n == 5 = H.h5
  | otherwise = H.h6
