-----------------------------------------------------------------------------
-- |The Helium Compiler : Static Analysis
-- 
-- Maintainer  :  bastiaan@cs.uu.nl
-- Stability   :  experimental
-- Portability :  unknown
--
-- Error messages repoted by kind inference.
--
-----------------------------------------------------------------------------

module KindErrors where

import Top.Types
import UHA_Syntax (Range, Type)
import PPrint (Doc)
import Messages
import List (union)
import qualified UHA_Pretty as PP
import qualified PPrint

type KindErrors = [KindError]
data KindError  = MustBeStar Range String Doc Kind
                | KindApplication Range Doc Doc Kind Kind

-- two "smart" constructors
mustBeStar :: Range -> String -> Type -> (Kind, Kind) -> KindError
mustBeStar range location uhaType (kind, _) = 
   MustBeStar range location (PP.sem_Type uhaType) kind

kindApplication :: Range -> Type -> Type -> (Kind, Kind) -> KindError
kindApplication range uhaType1 uhaType2 (kind1, kind2) = 
   KindApplication range (PP.sem_Type uhaType1) (PP.sem_Type uhaType2) kind1 kind2

instance Show KindError where 
   show kindError = "<kindError>"

instance HasMessage KindError where

   getRanges kindError = 
      case kindError of
         MustBeStar      r _ _ _   -> [r]
         KindApplication r _ _ _ _ -> [r]

   getMessage kindError = 
      case kindError of
         MustBeStar _ s d k ->
            [ MessageOneLiner (MessageString $ "Illegal type in "++s)
            , MessageTable
                 [ (MessageString "type"         , MessageString (show d)) 
                 , (MessageString "kind"         , MessageType (toTpScheme k))
                 , (MessageString "expected kind", MessageType (toTpScheme star))
                 ]
            ] 
            
         KindApplication r d1 d2 k1 k2 -> 
            [ MessageOneLiner (MessageString $ "Illegal type in type application")
            , MessageTable
                 [ (MessageString "type"            , MessageString (show d1)) 
                 , (MessageString "type constructor", MessageString (show d2)) 
                 , (MessageString "kind"            , MessageType (toTpScheme k1))
                 , (MessageString "does not match"  , MessageType (toTpScheme k2))
                 ]
            ]          
         
instance Substitutable KindError where 

   sub |-> kindError = 
      case kindError of
         MustBeStar r s d k            -> MustBeStar r s d (sub |-> k)
         KindApplication r d1 d2 k1 k2 -> KindApplication r d1 d2 (sub |-> k1) (sub |-> k2)
         
   ftv kindError =
      case kindError of
         MustBeStar      _ _ _ k     -> ftv k
         KindApplication _ _ _ k1 k2 -> ftv k1 `union` ftv k2
