{-| Module      :  Logger
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
-}

module Logger ( logger ) where

{-# NOTINLINE logger #-}

logger :: String -> Maybe ([String],String) -> Bool -> IO ()
logger _ _ _ = return ()
  
