{-| Module      :  DerivingEq
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
-}

module Helium.CodeGeneration.DerivingEq(dataDictionary) where

import qualified Helium.Syntax.UHA_Syntax as UHA
import Helium.Syntax.UHA_Utils
import Helium.CodeGeneration.CoreUtils
import Lvm.Core.Expr
import Lvm.Core.Utils
import Lvm.Common.Id
import Helium.Utils.Utils

-- Eq Dictionary for a data type declaration
dataDictionary :: UHA.Declaration -> CoreDecl
dataDictionary  (UHA.Declaration_Data _ _ (UHA.SimpleType_SimpleType _ name names) constructors _) =
    DeclValue 
    { declName    = idFromString ("$dictEq" ++ getNameName name)
    , declAccess  = public
    , valueEnc    = Nothing
    , valueValue  = eqFunction names constructors
    , declCustoms = [ custom "type" ("DictEq" ++ getNameName name) ] 
    }
  where  
dataDictionary _ = error "pattern match failure in CodeGeneration.Deriving.dataDictionary"

-- Example: data X a b = C a b Int | D Char b
eqFunction :: [UHA.Name] -> [UHA.Constructor] -> Expr
eqFunction names constructors = 
    let 
        body = 
            Let (Strict (Bind fstArg (Var fstArg))) -- evaluate both
                (Let (Strict (Bind sndArg (Var sndArg)))
                    (Match fstArg  -- case $fstArg of ...
                        (map makeAlt constructors))) 
    in
        foldr Lam body (map idFromName names ++ [fstArg, sndArg]) -- \a b $fstArg $sndArg ->

fstArg, sndArg :: Id        
[fstArg, sndArg] = map idFromString ["$fstArg", "$sndArg"] 

makeAlt :: UHA.Constructor -> Alt
makeAlt constructor =
        -- C $v0 $v1 $v2 -> ...
        Alt (PatCon (ConId ident) vs)
            --             case $sndArg of
            --                  C $w0 $w1 $w2 -> ...
            --                      ?? $v0 $w0 &&
            --                      ?? $v1 $w1 &&
            --                      ?? $v2 $w2
            --                  _ -> False
            (Match sndArg 
                [ Alt (PatCon (ConId ident) ws)
                      ( if null types then Con (ConId (idFromString "True"))
                        else
                            foldr1 andCore [ Ap (Ap (eqFunForType tp) (Var v)) (Var w)
                                           | (v, w, tp) <- zip3 vs ws types
                                           ]
                      )
                , Alt PatDefault (Con (ConId (idFromString "False")))
                ])
  where
    (ident, types) = nameAndTypes constructor
    vs = [ idFromString ("$v"++show i) | i <- [0..length types-1] ]
    ws = [ idFromString ("$w"++show i) | i <- [0..length types-1] ]
{-  constructorToPat :: Id -> [UHA.Type] -> Pat
    constructorToPat id ts =
        PatCon (ConId ident) [ idFromNumber i | i <- [1..length ts] ] -}
    andCore x y = Ap (Ap (Var (idFromString "&&")) x) y
    
nameAndTypes :: UHA.Constructor -> (Id, [UHA.Type])
nameAndTypes c =
    case c of
        UHA.Constructor_Constructor _    n ts -> (idFromName n, map annotatedTypeToType ts      )
        UHA.Constructor_Infix       _ t1 n t2 -> (idFromName n, map annotatedTypeToType [t1, t2])
        UHA.Constructor_Record          _ _ _ -> error "pattern match failure in CodeGeneration.DerivingEq.nameAndTypes"
  where
    annotatedTypeToType :: UHA.AnnotatedType -> UHA.Type
    annotatedTypeToType (UHA.AnnotatedType_AnnotatedType _ _ t) = t

--idFromNumber :: Int -> Id
--idFromNumber i = idFromString ("v$" ++ show i)

eqFunForType :: UHA.Type -> Expr
eqFunForType t = 
    case t of
        UHA.Type_Variable _ n             -> Var (idFromName n) 
        UHA.Type_Constructor _ n          -> var ("$dictEq" ++ show n)
        UHA.Type_Application _ _ f xs     -> foldl Ap (eqFunForType f) (map eqFunForType xs)
        UHA.Type_Parenthesized _ ty       -> eqFunForType  ty
        _ -> internalError "DerivingEq" "eqFunForType" "unsupported type"
