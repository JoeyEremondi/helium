{-| Module      :  PhaseLexer
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
-}

module PhaseLexer(phaseLexer) where

import CompileUtils
import LexerToken(Token)
import Lexer
import LayoutRule(layout)

phaseLexer :: String -> [String] -> String -> [Option] -> 
                IO ([LexerWarning], [Token])
phaseLexer fullName doneModules contents options = do
    enterNewPhase "Lexing" options

    case lexer fullName contents of 
        Left lexError -> do
            unless (NoLogging `elem` options) $ 
                sendLog "L" fullName doneModules options
            showErrorsAndExit [lexError] 1 options
        Right (tokens, lexerWarnings) -> do
            let tokensWithLayout = layout tokens
            when (DumpTokens `elem` options) $ do
                putStrLn (show tokensWithLayout)
            let warnings = filterLooksLikeFloatWarnings lexerWarnings tokensWithLayout
            return (warnings, tokensWithLayout)

-- Throw away the looks like float warnings between the keywords "module"
-- and "where".
filterLooksLikeFloatWarnings :: [LexerWarning] -> [Token] -> [LexerWarning]
filterLooksLikeFloatWarnings warnings tokens = 
   case tokens of
      (_, LexKeyword "module"):_ ->
         case dropWhile test tokens of
            (sp, _):_ -> filter (pred sp) warnings
            _         -> warnings
      _               -> warnings
 where
   test (_, t) = t /= LexKeyword "where"
   pred sp1 (LexerWarning sp2 w) = 
      not (sp2 <= sp1 && isLooksLikeFloatWarningInfo w)