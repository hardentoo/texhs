{-# LANGUAGE GeneralizedNewtypeDeriving #-}
----------------------------------------------------------------------
-- |
-- Module      :  Text.TeX.Context.Walk
-- Copyright   :  2015-2017 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mschenner.dev@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- Parser type for walking TeX contexts
----------------------------------------------------------------------

module Text.TeX.Context.Walk
  ( -- * Types
    Parser
  , ParserS
  , runParser
  , runParserWithState
    -- * Parser State
  , getMeta
  , putMeta
  , modifyMeta
    -- * Basic combinators
  , choice
  , count
  , sepBy
  , sepBy1
  , sepEndBy
  , sepEndBy1
  , list
    -- * Command parsers
    -- ** Specific command
  , cmd
  , inCmd
  , inCmd2
  , inCmd3
  , inCmdOpt2
  , inCmdCheckStar
  , inCmdWithOpts
  , cmdDown
    -- * Group parsers
    -- ** Specific group
  , grp
  , inGrp
  , inGrpChoice
  , inMathGrp
  , inSubScript
  , inSupScript
  , grpDown
  , grpUnwrap
    -- ** Any group
  , optNested
  , goDown
  , goUp
  , safeUp
    -- * Lift TeX Context traversals
  , step
  , stepRes
    -- * Low-level parsers
  , satisfy
  , peek
  , item
  , eof
  , eog
  , dropParents
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans.Class (lift)
import qualified Control.Monad.Trans.Except as E
import qualified Control.Monad.Trans.State as S

import Text.TeX.Parser.Types
import Text.TeX.Context.Types
import Text.Doc.Types (Meta(..), defaultMeta)

---------- Types

-- Note: All of the functions defined below could be generalized from
-- @Parser@ to @ParserS s@. However, since we currently only use the
-- @Parser@ type directly, we keep the simpler type declarations.

-- | A parser for walking a TeX AST,
-- parameterized by user state.
newtype ParserS s a = Parser
    { parser :: S.StateT TeXContext (S.StateT s (E.Except [TeXDocError])) a }
  deriving (Functor, Applicative, Monad, Alternative, MonadPlus)

-- | A parser for walking a TeX AST,
-- with a 'Meta' user state.
type Parser = ParserS Meta

-- | Run a parser on a TeX AST.
--
-- Include final 'Meta' state in the result.
runParserWithState :: Parser a -> TeX -> ThrowsError (a, Meta)
runParserWithState p xs =
  E.runExcept (S.runStateT (S.evalStateT
    (parser p) (pureTeXContext xs)) defaultMeta)

-- | Run a parser on a TeX AST.
runParser :: Parser a -> TeX -> ThrowsError a
runParser p xs = fst <$> runParserWithState p xs

state :: (TeXContext -> (a, TeXContext)) -> Parser a
state = Parser . S.state

put :: TeXContext -> Parser ()
put = Parser . S.put

get :: Parser TeXContext
get = Parser S.get

-- | Set the value of the 'Meta' state.
putMeta :: Meta -> Parser ()
putMeta = Parser . lift . S.put

-- | Fetch the current value of the 'Meta' state.
getMeta :: Parser Meta
getMeta = Parser (lift S.get)

-- | Modify the value of the 'Meta' state.
modifyMeta :: (Meta -> Meta) -> Parser ()
modifyMeta = Parser . lift . S.modify

throwE :: TeXDocError -> Parser a
throwE e = Parser (lift (lift (E.throwE [e])))

---------- Low-level parsers

-- | Return the next 'TeXAtom' if it satisfies the provided predicate.
satisfy :: (TeXAtom -> Bool) -> Parser TeXAtom
satisfy p = peek p *> item

-- | Peek at head of focus.
--
-- Like 'satisfy' but does not consume the matched 'TeXAtom'.
peek :: (TeXAtom -> Bool) -> Parser ()
peek = step . testHeadErr

-- | Return the next 'TeXAtom'.
item :: Parser TeXAtom
item = stepRes unconsFocus

-- | Succeed if context is empty.
eof :: Parser ()
eof = step testEof

-- | Succeed if focus is empty (i.e. if we hit an end of group).
eog :: Parser ()
eog = step testEog

-- | Restrict context to focus.
dropParents :: Parser ()
dropParents = step resetParents


---------- Basic combinators

-- | Try parsers from a list until one succeeds.
choice :: [Parser a] -> Parser a
choice = msum

-- | Run parser @n@ times.
count :: Int -> Parser a -> Parser [a]
count n p
  | n <= 0 = return []
  | otherwise = (:) <$> p <*> count (n-1) p

-- | @sepBy p sep@ parses zero or more occurrences of @p@,
-- separated by @sep@. Returns a list of values returned by @p@.
sepBy :: Parser a -> Parser b -> Parser [a]
sepBy p sep = sepBy1 p sep <|> pure []

-- | @sepBy p sep@ parses one or more occurrences of @p@,
-- separated by @sep@. Returns a list of values returned by @p@.
sepBy1 :: Parser a -> Parser b -> Parser [a]
sepBy1 p sep = (:) <$> p <*> list sep p

-- | @sepEndBy p sep@ parses zero or more occurrences of @p@,
-- separated and optionally ended by @sep@.
-- Returns a list of values returned by @p@.
sepEndBy :: Parser a -> Parser b -> Parser [a]
sepEndBy p sep = sepEndBy1 p sep <|> pure []

-- | @sepEndBy1 p sep@ parses one or more occurrences of @p@,
-- separated and optionally ended by @sep@.
-- Returns a list of values returned by @p@.
sepEndBy1 :: Parser a -> Parser b -> Parser [a]
sepEndBy1 p sep = (:) <$> p <*> ((sep *> sepEndBy p sep) <|> pure [])

-- | @list bullet p@ parses zero or more occurrences of @p@, each prefixed by @bullet@.
-- Returns a list of values returned by @p@.
--
-- Note: @p@ must not overlap with @bullet@.
list :: Parser a -> Parser b -> Parser [b]
list bullet p = many (bullet *> p)

---------- Command parsers

-- | Parse a specific command.
cmd :: String -> Parser TeXAtom
cmd = satisfy . isCmd

-- | Apply parser to the first mandatory argument of a specific command
-- (all other arguments are dropped).
inCmd :: String -> Parser a -> Parser a
inCmd n p = cmdDown n *> p <* safeUp

-- | Apply parser to the first mandatory argument of a specific command
-- (all other arguments are dropped). Return a boolean flag that indicates
-- whether the command had a 'StarArg', i.e. whether it was starred.
inCmdCheckStar :: String -> Parser a -> Parser (Bool, a)
inCmdCheckStar n p =
  (,) True <$> (cmdDownWithStar n *> p <* safeUp) <|>
  (,) False <$> (cmdDown n *> p <* safeUp)

-- | Descend into the first mandatory argument of a specific command
-- (all other arguments are dropped).
cmdDown :: String -> Parser ()
cmdDown n = peek (isCmd n) *> step intoCmdArg

-- | Descend into the first mandatory argument of a specific command
-- (all other arguments are dropped), but only if it is starred.
cmdDownWithStar :: String -> Parser ()
cmdDownWithStar n = peek (isCmdWithStar n) *> step intoCmdArg

-- Note: We are not creating an isolated context for the argument.
-- Parsers are expected to operate on the focus value only (no 'up').
--
-- | Apply parser to the n-th mandatory argument of a command,
-- without consuming the command.
cmdPeekOblArg :: Int -> Parser a -> Parser a
cmdPeekOblArg n p = step (peekOblArg n) *> p <* safeUp

-- Note: We are not creating an isolated context for the argument.
-- Parsers are expected to operate on the focus value only (no 'up').
--
-- | Apply parser to the n-th optional argument of a command,
-- without consuming the command.
cmdPeekOptArg :: Int -> Parser a -> Parser a
cmdPeekOptArg n p = step (peekOptArg n) *> p <* safeUp

-- | Parse a specific command and apply two parsers
-- to its first two mandatory arguments.
inCmd2 :: String -> Parser a -> Parser b -> Parser (a,b)
inCmd2 n p0 p1 = (,) <$> (peek (isCmd n) *>
  cmdPeekOblArg 0 p0) <*>
  cmdPeekOblArg 1 p1 <* cmd n

-- | Parse a specific command and apply three parsers
-- to its first three mandatory arguments.
inCmd3 :: String -> Parser a -> Parser b -> Parser c -> Parser (a,b,c)
inCmd3 n p0 p1 p2 = (,,) <$> (peek (isCmd n) *>
  cmdPeekOblArg 0 p0) <*>
  cmdPeekOblArg 1 p1 <*>
  cmdPeekOblArg 2 p2 <* cmd n

-- | @inCmdOpt2 name opt0 opt1 p@ parses the command @name@ and
-- applies the parsers @opt0@ and @opt1@ to its first two optional
-- arguments, respectively, and applies the parser @p@ to its
-- first mandatory argument.
inCmdOpt2 :: String -> Parser oa -> Parser ob -> Parser a -> Parser (oa,ob,a)
inCmdOpt2 n opt0 opt1 obl = (,,) <$> (peek (isCmd n) *>
  cmdPeekOptArg 0 opt0) <*>
  cmdPeekOptArg 1 opt1 <*>
  inCmd n obl

-- | @inCmdWithOpts name opts p@ parses the command @name@ and
-- applies the parsers @opts@ to its optional arguments and
-- the parser @p@ to its first mandatory argument.
inCmdWithOpts :: String -> [Parser a] -> Parser b -> Parser ([a],b)
inCmdWithOpts n opts obl = (,) <$> (peek (isCmd n) *>
  zipWithM cmdPeekOptArg [0..] opts) <*>
  inCmd n obl


---------- Group parsers

-- | Parse a specific group.
grp :: String -> Parser TeXAtom
grp = satisfy . isGrp

-- | Apply parser to specific group body.
inGrp :: String -> Parser a -> Parser a
inGrp n p = grpDown n *> p <* safeUp

-- | Apply parser to the body of one of the specified groups.
inGrpChoice :: [String] -> Parser a -> Parser a
inGrpChoice ns p = choice (map grpDown ns) *> p <* safeUp

-- | Descend into a specific group (ignoring all group arguments).
grpDown :: String -> Parser ()
grpDown n = peek (isGrp n) *> goDown

-- | Unwrap the content of a specific group.
--
-- Warning: This may extend the scope of contained commands.
grpUnwrap :: String -> Parser ()
grpUnwrap n = peek (isGrp n) *> step unwrap

-- | Apply parser inside a math group,
-- and also return its 'MathType'.
inMathGrp :: Parser a -> Parser (MathType, a)
inMathGrp p = (,) <$> stepRes downMath <*> p <* safeUp

-- | Apply parser to a subscript group.
inSubScript :: Parser a -> Parser a
inSubScript p = peek isSubScript *> inAnyGroup p

-- | Apply parser to a superscript group.
inSupScript :: Parser a -> Parser a
inSupScript p = peek isSupScript *> inAnyGroup p

-- Apply parser inside a group (any group).
-- The parser must exhaust the group content.
inAnyGroup :: Parser a -> Parser a
inAnyGroup p = goDown *> p <* safeUp

-- | Allow parser to walk into groups (if it fails at the top level).
-- If the parser opens a group, it must exhaust its content.
optNested :: Parser a -> Parser a
optNested p = p <|> inAnyGroup (optNested p)

-- | Descend into a group. See 'down'.
goDown :: Parser ()
goDown = step down

-- | Drop focus and climb up one level. See 'up'.
goUp :: Parser ()
goUp = step up

-- | If focus is empty, climb up one level.
safeUp :: Parser ()
safeUp = eog *> goUp


---------- Lift TeX Context traversals

-- | Execute a 'TeXStep' (no result).
step :: TeXStep -> Parser ()
step dir = get >>= either throwE put . dir

-- | Execute a 'TeXStepRes' (with result).
stepRes :: TeXStepRes a -> Parser a
stepRes dir = get >>= either throwE (state . const) . dir
