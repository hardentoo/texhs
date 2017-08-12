{-# LANGUAGE CPP #-}
----------------------------------------------------------------------
-- |
-- Module      :  Text.TeX.Lexer.TokenParser.Expansion
-- Copyright   :  2015-2017 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mschenner.dev@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- Expansion of user-defined macros and environments.
----------------------------------------------------------------------

module Text.TeX.Lexer.TokenParser.Expansion
  ( -- * Macro expansion
    expand
    -- * Environment expansion
  , expandEnvironment
  ) where

#if MIN_VERSION_base(4,8,0)
-- Prelude exports all required operators from Control.Applicative
#else
import Control.Applicative ((<$), (<$>), (*>))
#endif
import Control.Monad ((>=>), guard)
import Data.Maybe (fromMaybe)

import Text.TeX.Lexer.Macro
import Text.TeX.Lexer.Token
import Text.TeX.Lexer.TokenParser.Basic
import Text.TeX.Lexer.TokenParser.Core


-------------------- Macro expansion

-- | Expand a call of a user-defined macro
-- and push the expansion back into the input stream.
expand :: Monad m => MacroCmd -> LexerT m ()
expand = expansion >=> prependTokens

-- | Expand a call of a user-defined macro
-- and return the expansion.
expansion :: Monad m => MacroCmd -> LexerT m [Token]
expansion m = do
  guard $ isMacroCmdUser m
  args <- parseArgspec (macroCmdContext m)
  return $ applyMacro (macroCmdBody m) args

-------------------- Environment expansion

-- | Expand a user-defined environment
-- and return the expansion as a pair of
-- @start code@ and @end code@.
expandEnvironment :: Monad m => MacroEnv -> LexerT m ([Token], [Token])
expandEnvironment (MacroEnv _ context startCode endCode) = do
  args <- parseArgspec context
  return (applyMacro startCode args, applyMacro endCode args)

-------------------- Helper functions

-- Parse the arguments in a macro call.
parseArgspec :: Monad m => ArgSpec -> LexerT m [[Token]]
parseArgspec = mapM parseArgtype

-- Parse a single argument in a macro call.
parseArgtype :: Monad m => ArgType -> LexerT m [Token]
parseArgtype Mandatory = stripBraces <$>
  (skipSpaceExceptPar *> nextTokenNoExpand)
parseArgtype (Until [t]) = untilTok t
parseArgtype (Until ts) = untilToks ts
parseArgtype (UntilCC cc) = many (charccno cc)
parseArgtype (Delimited open close defval) =
  option (fromMaybe [noValueTok] defval) (balanced open close)
parseArgtype (OptionalGroup open close defval) =
  option (fromMaybe [noValueTok] defval) (balanced open close)
parseArgtype (OptionalGroupCC open close defval) =
  option (fromMaybe [noValueTok] defval) (balancedCC open close)
parseArgtype (OptionalToken t) =
  option [falseTok] ([trueTok] <$ tok t)
parseArgtype (LiteralToken t) = count 1 (tok t)
