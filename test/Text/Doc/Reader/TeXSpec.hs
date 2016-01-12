{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
----------------------------------------------------------------------
--
-- Module      :  Text.Doc.Reader.TeXSpec
-- Copyright   :  2015-2016 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
-- Maintainer  :  mathias.schenner@langsci-press.org
--
-- Tests for the "Text.Doc.Reader.TeX" module.
----------------------------------------------------------------------

module Text.Doc.Reader.TeXSpec
  ( tests
  ) where

#if MIN_VERSION_base(4,8,0)
-- Prelude exports all required operators from Control.Applicative
#else
import Control.Applicative ((<$>), (<*>), (<*), (*>))
#endif
import qualified Data.Map.Strict as M
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.HUnit ((@?=))

import Text.TeX.Context.Types
import Text.TeX.Context.Walk
import Text.TeX.Parser.Types
import Text.Doc.Types
import Text.Doc.Reader.TeX


-------------------- tests

tests :: Test
tests = testGroup "Text.Doc.Reader.TeXSpec"
  [ testsBasic
  , testsBlocks
  , testsInlines
  , testsLists
  , testsCrossrefs
  , testsWhitespace
  ]

testsBasic :: Test
testsBasic = testGroup "basic traversals"
  [ testCase "item" $
    runParser item example1
    @?=
    Right (Plain "hello")
  , testCase "chained item" $
    runParser (item >> item >> item) example1
    @?=
    Right (Plain "world!")
  , testCase "failing chained item" $
    runParser (item >> item >> item >> item) example1
    @?=
    Left [EndOfGroup]
  , testCase "satisfy" $
    runParser (satisfy isPlain) example1
    @?=
    Right (Plain "hello")
  , testCase "failing satisfy" $
    runParser (item >> satisfy isPlain) example1
    @?=
    Left [Unexpected White]
  , testCase "walk into group" $
    runParser (goDown >> item) example2
    @?=
    Right (Plain "hello")
  , testCase "failing item inside of group" $
    runParser (goDown >> item >> item) example2
    @?=
    Left [EndOfGroup]
  , testCase "enter and leave group" $
    runParser (goDown >> item >> goUp >> item) example2
    @?=
    Right White
  , testCase "flatten groups" $
    runParser inlines example3
    @?=
    Right [Emph [Str "hello"], Space, Str "world", Str "!"]
  ]

testsBlocks :: Test
testsBlocks = testGroup "block elements"
  [ testCase "single section header" $
    runParser block
      [Command "section" [OblArg [Plain "one"]]]
    @?=
    Right (Header 3 (SectionAnchor [0,0,1,0,0,0]) [Str "one"])
  , testCase "single paragraph" $
    runParser block [Plain "hello"]
    @?=
    Right (Para [Str "hello"])
  ]

testsInlines :: Test
testsInlines = testGroup "inline elements"
  [ testCase "simple emph" $
    runParser emph example4
    @?=
    Right (Emph [Str "hello"])
  , testCase "emph with inner space" $
    runParser emph example5
    @?=
    Right (Emph [Str "one",Space,Str "two"])
  , testCase "return to parent after emph" $
    runParser (emph *> space *> item) example4
    @?=
    Right (Plain "world")
  , testCase "em with inner space" $
    runParser em example6
    @?=
    Right (Emph [Str "one",Space,Str "two"])
  , testCase "failing em" $
    runParser em example7
    @?=
    Left [Unexpected (Group "" []
      [Command "em" [], Plain "one", White, Plain "two"])]
  , testCase "nested em" $
    runParser (optNested em) example7
    @?=
    Right (Emph [Str "one",Space,Str "two"])
  , testCase "combining nested em with parent inlines" $
    runParser ((:) <$> optNested em <*> inlines) example7
    @?=
    Right [Emph [Str "one",Space,Str "two"],Space,Str "three"]
  , testCase "rm between em font switches" $
    runParser inlines example8
    @?=
    Right [Emph [Str "one",Normal [Str "two",Emph [Str "three"]]]]
  ]

testsLists :: Test
testsLists = testGroup "list blocks"
  [ testCase "simple list" $
    runParser (inlines *> itemize) exampleList1
    @?=
    Right (List [ [Para [Str "one",Space,Str "one"]]
                , [Para [Str "two",Space]]
                , [Para [Str "three"]]])
  , testCase "nested list" $
    runParser (inlines *> itemize) exampleList2
    @?=
    Right (List [ [ Para [ Str "up-one"]]
                , [ Para [ Str "up-two",Space]
                  , List [ [Para [Str "down-one",Space]]
                         , [Para [Str "down-two",Space]]]]
                , [ Para [ Str "up-three"]]])
  ]

testsCrossrefs :: Test
testsCrossrefs = testGroup "cross-references"
  [ testCase "labels are dropped" $
    runParser (inlines <* eof)
      [Command "label" [OblArg [Plain "mylabel"]]]
    @?=
    Right []
  , testCase "labels between spaces do not prevent whitespace conflation" $
    runParser (inlines <* eof)
      [White, Command "label" [OblArg [Plain "mylabel"]], White]
    @?=
    Right [Space]
  , testCase "spaces after labels are not dropped" $
    runParser (inlines <* eof)
      [Plain "a", Command "label" [OblArg [Plain "mylabel"]], White]
    @?=
    Right [Str "a", Space]
  , testCase "spaces after labels are conflated" $
    runParser (inlines <* eof)
      [Plain "a", Command "label" [OblArg [Plain "mylabel"]], White, White]
    @?=
    Right [Str "a", Space]
  , testCase "labels between plain strings are dropped by inlines parser" $
    runParser (inlines <* eof)
      [ Plain "a"
      , Command "label" [OblArg [Plain "mylabel"]]
      , Plain "b"]
    @?=
    Right [Str "a", Str "b"]
  , testCase "labels between plain strings are dropped by blocks parser" $
    runParser (blocks <* eof)
      [ Plain "a"
      , Command "label" [OblArg [Plain "mylabel"]]
      , Plain "b"]
    @?=
    Right [Para [Str "a", Str "b"]]
  , testCase "simple pointer with undefined target" $
    runParser block
      [Command "ref" [OblArg [Plain "nosuchtarget"]]]
    @?=
    Right (Para [Pointer "nosuchtarget" Nothing])
  , testCase "section label and reference" $
    runParser (blocks <* eof)
      [ Command "section" [OblArg [Plain "one"]]
      , Command "label" [OblArg [Plain "mylabel"]]
      , Command "ref" [OblArg [Plain "mylabel"]]
      ]
    @?=
    Right
      [ Header 3 (SectionAnchor [0,0,1,0,0,0]) [Str "one"]
      , Para [Pointer "mylabel" Nothing]]
  , testCase "retrieve section number" $
    either (error . show) (M.lookup "mylabel" . metaAnchorMap . snd)
      (runParserWithState (blocks <* eof)
        [ Command "section" [OblArg [Plain "one"]]
        , Command "section" [OblArg [Plain "two"]]
        , Command "subsection" [OblArg [Plain "two-one"]]
        , Command "label" [OblArg [Plain "mylabel"]]
        , Command "section" [OblArg [Plain "three"]]
        , Command "section" [OblArg [Plain "four"]]
        , Command "ref" [OblArg [Plain "mylabel"]]
        ])
    @?=
    Just (SectionAnchor [0,0,2,1,0,0])
  ]

testsWhitespace :: Test
testsWhitespace = testGroup "whitespace"
  [ testCase "inline whitespace is conflated" $
    runParser (inlines <* eof)
      [White, White]
    @?=
    Right [Space]
  , testCase "inline whitespace within paragraphs is conflated" $
    runParser (blocks <* eof)
      [Plain "a", White, White, Plain "b"]
    @?=
    Right [Para [Str "a", Space, Str "b"]]
  , testCase "whitespace after paragraphs is dropped" $
    runParser (blocks <* eof)
      [Plain "a", Par, White, Plain "b"]
    @?=
    Right [Para [Str "a"], Para [Str "b"]]
  ]

-------------------- examples

-- >> hello world!
example1 :: TeX
example1 = [ Plain "hello"
           , White
           , Plain "world!"
           ]

-- >> {hello} world{!}
example2 :: TeX
example2 = [ Group "" [] [Plain "hello"]
           , White
           , Plain "world"
           , Group "" [] [Plain "!"]
           ]

-- >> \emph{hello} world{!}
example3 :: TeX
example3 = [ Command "emph" [OblArg [Plain "hello"]]
           , White
           , Plain "world"
           , Group "" [] [Plain "!"]
           ]

-- simple "emph" command
-- >> \emph{hello} world
example4 :: TeX
example4 = [ Command "emph" [OblArg [Plain "hello"]]
           , White
           , Plain "world"
           ]

-- multiple TeXAtoms in mandarg of "emph" cmd
-- >> \emph{one two} three
example5 :: TeX
example5 = [ Command "emph" [OblArg [Plain "one", White, Plain "two"]]
           , White
           , Plain "three"
           ]

-- font switch "em" (without enclosing group)
-- >> \em one two
example6 :: TeX
example6 = [ Command "em" []
           , Plain "one"
           , White
           , Plain "two"
           ]

-- font switch "em" (with enclosing group)
-- >> {\em one two} three
example7 :: TeX
example7 = [ Group "" []
             [ Command "em" []
             , Plain "one"
             , White
             , Plain "two"
             ]
           , White
           , Plain "three"
           ]

-- font switches "em" and "rm"
-- >> \em one\rm two\em three
example8 :: TeX
example8 = [ Command "em" []
           , Plain "one"
           , Command "rm" []
           , Plain "two"
           , Command "em" []
           , Plain "three"
           ]

-- itemize list
-- >>:
{-
  pre-list
  \begin{itemize}
  \item one one
  \par
  \item two
  \item three
  \end{itemize}
  after list
-}
exampleList1 :: TeX
exampleList1 = [ Plain "pre-list"
               , White
               , Group "itemize" []
                 [ Command "item" []
                 , Plain "one"
                 , White
                 , Plain "one"
                 , Par
                 , Command "item" []
                 , Plain "two"
                 , White
                 , Command "item" []
                 , Plain "three"
                 ]
               , Plain "after"
               , White
               , Plain "list"
               ]

-- nested list
-- >>:
{-
  pre-list
  \begin{itemize}
    \item up-one\par
    \item up-two
    \begin{itemize}
      \item down-one
      \item down-two
    \end{itemize}
    \item up-three
  \end{itemize}
  after list
-}
exampleList2 :: TeX
exampleList2 = [ Plain "pre-list"
               , White
               , Group "itemize" []
                 [ Command "item" []
                 , Plain "up-one"
                 , Par
                 , Command "item" []
                 , Plain "up-two"
                 , White
                 , Group "itemize" []
                   [ Command "item" []
                   , Plain "down-one"
                   , White
                   , Command "item" []
                   , Plain "down-two"
                   , White
                   ]
                 , Command "item" []
                 , Plain "up-three"
                 ]
               , Plain "after"
               , White
               , Plain "list"
               ]