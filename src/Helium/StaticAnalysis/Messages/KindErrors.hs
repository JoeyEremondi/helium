{-| Module      :  KindErrors
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
    
    Error messages repoted by kind inference.
-}

module Helium.StaticAnalysis.Messages.KindErrors where

import Top.Types
import Top.Constraint.Information(TypeConstraintInfo(..),PolyTypeConstraintInfo(..))

import Helium.Syntax.UHA_Syntax (Range, Type)
import Text.PrettyPrint.Leijen (Doc)
import Helium.StaticAnalysis.Messages.Messages
import Data.List (union)
import qualified Helium.Syntax.UHA_Pretty as PP
-- import qualified Text.PrettyPrint.Leijen as PPrint

type KindErrors = [KindError]
data KindError  = MustBeStar Range String Doc Kind
                | KindApplication Range Doc Doc Kind Kind

instance TypeConstraintInfo KindError
instance PolyTypeConstraintInfo KindError

-- two "smart" constructors
mustBeStar :: Range -> String -> Type -> (Kind, Kind) -> KindError
mustBeStar range location uhaType (kind, _) = 
   MustBeStar range location (PP.text_Syn_Type $ PP.wrap_Type (PP.sem_Type uhaType) PP.Inh_Type) kind

kindApplication :: Range -> Type -> Type -> (Kind, Kind) -> KindError
kindApplication range uhaType1 uhaType2 (kind1, kind2) = 
   KindApplication range (PP.text_Syn_Type $ PP.wrap_Type (PP.sem_Type uhaType1) PP.Inh_Type) (PP.text_Syn_Type $ PP.wrap_Type (PP.sem_Type uhaType2) PP.Inh_Type) kind1 kind2

instance Show KindError where 
   show _ = "<kindError>"

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
                 [ "type"          <:> MessageString (show d)
                 , "kind"          >:> MessageType (toTpScheme k)
                 , "expected kind" >:> MessageType (toTpScheme star)
                 ]
            ] 
            
         KindApplication _ d1 d2 k1 k2 -> 
            [ MessageOneLiner (MessageString "Illegal type in type application")
            , MessageTable
                 [ "type"             <:> MessageString (show d1)
                 , "type constructor" <:> MessageString (show d2)
                 , "kind"             >:> MessageType (toTpScheme k1)
                 , "does not match"   >:> MessageType (toTpScheme k2)
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

