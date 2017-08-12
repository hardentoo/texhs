----------------------------------------------------------------------
-- |
-- Module      :  Text.TeX.Lexer.Macro
-- Copyright   :  2015-2017 Mathias Schenner,
--                2015-2016 Language Science Press.
-- License     :  GPL-3
--
-- Maintainer  :  mschenner.dev@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- Types and utility functions for TeX macros and environments.
----------------------------------------------------------------------

module Text.TeX.Lexer.Macro
  ( -- * Macro commands
    MacroCmd(..)
  , MacroCmdKey
  , isMacroCmdUser
  , isMacroCmdPrim
  , isMacroCmdChar
    -- * Macro environments
  , MacroEnv(..)
  , MacroEnvKey
    -- * Macro arguments
  , ArgSpec
  , ArgType(..)
    -- * Macro definition modes
  , MacroDefinitionMode(..)
    -- * Macro expansion
  , applyMacro
    -- * Primitive commands
  , Primitive
  , defaultPrimitives
    -- * Meanings
  , Meaning(..)
  , showMeaning
  , isPrimitive
  ) where

import Text.TeX.Lexer.Token (Token(..), detokenize)
import Text.TeX.Lexer.Catcode (Catcode, showCatcodePP)

-------------------- Argument Specification

-- | A list of argument types that a macro consumes.
type ArgSpec = [ArgType]

-- | Possible argument types for macros.
--
-- This mainly corresponds to xparse (LaTeX3) argument types,
-- except for the addition of 'LiteralToken' which facilitates
-- the translation from original TeX macro definitions (\\def).
data ArgType
  -- | For 'm' args.
  = Mandatory
  -- | For 'u' args.
  | Until [Token]
  -- | For 'l' args.
  | UntilCC Catcode
  -- | For 'r' args: Opening delimiter, closing delimiter, default value.
  | Delimited Token Token (Maybe [Token])
  -- | For 'o' and 'd' args: Opening delimiter, closing delimiter, default value.
  | OptionalGroup Token Token (Maybe [Token])
  -- | For 'g' args: Opening delimiter, closing delimiter, default value.
  | OptionalGroupCC Catcode Catcode (Maybe [Token])
  -- | For 's' and 't' args.
  | OptionalToken Token
  -- | Literal token.
  | LiteralToken Token
  deriving (Eq, Show)

-------------------- Primitive Commands

-- | Primitives are internal names of executable commands
-- and possible meanings of control sequences.
type Primitive = String

-- | Default mapping of tokens (control sequences) to primitives.
defaultPrimitives :: [(MacroCmdKey, MacroCmd)]
defaultPrimitives = map wrapPrim
  [ "begingroup"
  , "endgroup"
  , "bgroup"
  , "egroup"
  , "("
  , ")"
  , "["
  , "]"
  , "begin"
  , "end"
  , "catcode"
  , "def"
  , "let"
  , "iftrue"
  , "iffalse"
  , "char"
  , "number"
  , "NewDocumentCommand"
  , "RenewDocumentCommand"
  , "ProvideDocumentCommand"
  , "DeclareDocumentCommand"
  , "NewDocumentEnvironment"
  , "RenewDocumentEnvironment"
  , "ProvideDocumentEnvironment"
  , "DeclareDocumentEnvironment"
  , "IfBooleanTF"
  , "IfNoValueTF"
  , "newcommand"
  , "renewcommand"
  , "providecommand"
  , "DeclareRobustCommand"
  , "newenvironment"
  , "renewenvironment"
  , "input"
  , "include"
  , "year"
  , "month"
  , "day"
  , "time"
  , "meaning"
  , "undefined"
    -- primitive constants
  , "else"
  , "fi"
  ]
  where wrapPrim t = ((t, False), MacroCmdPrim t)

-------------------- Macro Commands

-- | Key for macro command lookup: name and active flag.
type MacroCmdKey = (String, Bool)

-- | Definition of a macro command.
data MacroCmd
  = MacroCmdUser
    { macroCmdName :: MacroCmdKey
    , macroCmdContext :: ArgSpec
    , macroCmdBody :: [Token]
    }
  | MacroCmdPrim
    { macroCmdPrim :: Primitive
    }
  | MacroCmdChar
    { macroCmdChar :: Char
    , macroCmdCatcode :: Catcode
    }
  deriving (Eq, Show)

-- | Test whether a 'MacroCmd' is a user-defined command.
isMacroCmdUser :: MacroCmd -> Bool
isMacroCmdUser MacroCmdUser{} = True
isMacroCmdUser _ = False

-- | Test whether a 'MacroCmd' is a primitive command.
isMacroCmdPrim :: MacroCmd -> Bool
isMacroCmdPrim MacroCmdPrim{} = True
isMacroCmdPrim _ = False

-- | Test whether a 'MacroCmd' is an implicit character.
isMacroCmdChar :: MacroCmd -> Bool
isMacroCmdChar MacroCmdChar{} = True
isMacroCmdChar _ = False

-------------------- Macro Environments

-- | Key for macro environment lookup.
type MacroEnvKey = [Token]

-- | Definition of a macro environment.
data MacroEnv = MacroEnv
  { macroEnvName :: MacroEnvKey
  , macroEnvContext :: ArgSpec
  , macroEnvStart :: [Token]
  , macroEnvEnd :: [Token]
  } deriving (Eq, Show)

-------------------- Macro expansion

-- | Substitute variables in macro body.
--
-- Given a macro definition body and a list of actual arguments,
-- substitute the parameter tokens in the macro body by the actual arguments.
applyMacro :: [Token] -> [[Token]] -> [Token]
applyMacro (Param i n : ts) args = if n == 1
                                   then (args !! (i-1)) ++ applyMacro ts args
                                   else Param i (n-1) : applyMacro ts args
applyMacro (tok@(TeXChar _ _):ts) args = tok : applyMacro ts args
applyMacro (tok@(CtrlSeq _ _):ts) args = tok : applyMacro ts args
applyMacro [] _ = []

-------------------- Macro definition modes

-- | Requests for registering a macro can specify whether the macro is
-- allowed or required to overwrite an existing macro with the same
-- name.
data MacroDefinitionMode
  = MacroNew
  | MacroRenew
  | MacroProvide
  | MacroDeclare

-------------------- Meanings

-- | The meaning of a control sequence or a character.
data Meaning
  = MeaningChar Char Catcode
  | MeaningMacro MacroCmd
  | MeaningUndef
  deriving (Eq, Show)

-- | Describe the meaning of a token.
showMeaning :: Meaning -> String
showMeaning (MeaningChar ch cc)
  = showCatcodePP cc ++ " " ++ [ch]
showMeaning (MeaningMacro (MacroCmdUser _ ctx body))
  = "macro:" ++ show ctx ++ "->" ++ concatMap detokenize body
showMeaning (MeaningMacro (MacroCmdPrim p))
  = "primitive:" ++ p
showMeaning (MeaningMacro (MacroCmdChar ch cc))
  = showMeaning (MeaningChar ch cc)
showMeaning MeaningUndef
  = "undefined"

-- | Test whether a meaning equals the provided primitive command.
isPrimitive :: Primitive -> Meaning -> Bool
isPrimitive n (MeaningMacro (MacroCmdPrim p)) = n == p
isPrimitive _ _ = False
