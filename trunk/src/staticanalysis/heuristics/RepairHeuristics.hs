{-| Module      :  RepairHeuristics
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
    
    Heuristics that supply additional hints with a type error how a program
	can be corrected.
-}

module RepairHeuristics where

import Top.TypeGraph.Heuristics
import Top.TypeGraph.Basics
import Top.States.TIState
import Top.States.SubstState
import Top.TypeGraph.TypeGraphState
import Top.Types
import OnlyResultHeuristics
import Data.List
import Data.Maybe
import TypeErrors
import ConstraintInfo
import Messages (showNumber, ordinal, prettyAndList)
import OneLiner (OneLineTree)
import UHA_Source
import UHA_Syntax (Range)

-----------------------------------------------------------------------------

type Siblings = [[(String, TpScheme)]]

class MaybeImported a where
   maybeImportedName :: a -> Maybe String

siblingFunctions :: (MaybeImported info, HasTwoTypes info, WithHints info, HasTypeGraph m info) 
                       => Siblings -> Selector m info
siblingFunctions siblings = 
   Selector ("Sibling functions", f) where
  
 f (edge, cnr, info) =
   case maybeImportedName info of 
      Nothing   -> return Nothing
      Just name -> 
      
         do let functions = filter ( (name /=) . fst)
                          . concat
                          . filter ( (name `elem`) .  map fst)
                          $ siblings
                          
            if null functions 
              then return Nothing
              else doWithoutEdge (edge,info) $ 

                   do synonyms <- getTypeSynonyms
                      (_, mtp) <- getSubstitutedTypes info
                                        
                      case mtp of 
                      
                         Nothing -> 
                            return Nothing
      
                         Just tp ->                             
                            case filter (unifiable synonyms tp . unqualify . snd . instantiate 123456789 . snd) functions of
			      
                               (s, scheme):_ -> let hint = fixHint ("use "++s++" instead")
                                                in return $ Just
                                                      (10,"Sibling "++show s++" instead of "++show name, [edge], [hint info])
                               _             -> return Nothing
			       
-----------------------------------------------------------------------------

class MaybeLiteral a where
   maybeLiteral :: a -> Maybe String  

similarLiterals :: (HasTypeGraph m info, MaybeLiteral info, HasTwoTypes info, WithHints info) => Selector m info
similarLiterals = 
   Selector ("Similar literal", f) where

 f (edge, cnr, info) =
   case maybeLiteral info of 
      Nothing      -> return Nothing
      Just literal ->

         doWithoutEdge (edge,info) $

            do synonyms <- getTypeSynonyms
               (_, mtp) <- getSubstitutedTypes info

               case (literal,mtp) of

                  ("Int", Just (TCon "Float"))
                       -> let hint = fixHint "use a float literal instead"
                          in return $ Just
                                (5, "Int literal should be a Float", [edge], [hint info])

                  ("Float", Just (TCon "Int" ))
                       -> let hint = fixHint "use an int literal instead"
                          in return $ Just
                                (5, "Float literal should be an Int", [edge], [hint info])

                  ("Char", Just (TApp (TCon "[]") (TCon "Char"))) 
                       -> let hint = fixHint "use a string literal instead"
                          in return $ Just
                                (5, "Char literal should be a String", [edge], [hint info])

                  ("String", Just (TCon "Char"))   
                       -> let hint = fixHint "use a char literal instead"
                          in return $ Just
                                (5, "String literal should be a Char", [edge], [hint info])

                  _ -> return Nothing 

-----------------------------------------------------------------------------

similarNegation :: (HasTypeGraph m info, MaybeNegation info, HasTwoTypes info, WithHints info) => Selector m info
similarNegation  =
   Selector ("Similar negation", f) where

 f (edge, cnr, info) =   
   case maybeNegation info of
      Nothing            -> return Nothing
      Just isIntNegation ->

         doWithoutEdge (edge,info) $

            do synonyms <- getTypeSynonyms
               (_, mtp) <- getSubstitutedTypes info
               
               case mtp of
                  Just tp
                     | floatNegationEdge && intNegation && not floatNegation
                        -> let hint = fixHint "use int negation (-) instead"
                           in return $ Just
                                 (6, "Int negation instead of float negation", [edge], [hint info])

                     | intNegationEdge && not intNegation && floatNegation 
                        -> let hint = fixHint "use float negation (-.) instead"
                           in return $ Just
                                 (6, "Float negation instead of int negation", [edge], [hint info])
                       
                    where intNegation       = unifiable synonyms tp (intType .->. intType)
                          floatNegation     = unifiable synonyms tp (floatType .->. floatType)
                          intNegationEdge   = isIntNegation
                          floatNegationEdge = not isIntNegation                                         

                  _ -> return Nothing

-----------------------------------------------------------------------------

applicationEdge :: (HasTypeGraph m info, MaybeApplication info, IsPattern info, HasTwoTypes info, WithHints info) => Selector m info
applicationEdge =
   Selector ("Application heuristics", f) where

 f (edge, cnr, info) =
   case maybeApplicationEdge info of
      Nothing -> return Nothing
      Just (isBinary,tuplesForArguments) ->

       doWithoutEdge (edge,info) $

          do synonyms <- getTypeSynonyms                 
             (maybeFunctionType, maybeExpectedType) <- getSubstitutedTypes info
             
             case (maybeFunctionType,maybeExpectedType) of

               (Just functionType,Just expectedType) 

                  -- the expression to which arguments are given does not have a function type
                  | maybe False (<= 0) maximumForFunction && not isBinary && not isPatternApplication ->                       
                       let hint = becauseHint "it is not a function"
                       in return $ Just
                             (6, "not a function", [edge], [hint info])
                 
                  -- function used as infix that expects < 2 arguments
                  | maybe False (<= 1) maximumForFunction && isBinary && not isPatternApplication ->
                       let hint = becauseHint "it is not a binary function"
                       in return $ Just
                             (6, "no binary function", [edge], [hint info])
 
                  -- can a permutation of the arguments resolve the type inconsistency
                  | length argumentPermutations == 1 -> 
                       let p = head argumentPermutations
                       in 
                         if p==[1,0] && isBinary
                            then 
                                 let hint = fixHint "swap the two arguments"
                                 in return $ Just
                                       (3, "swap the two arguments", [edge], [hint info])
                            else                                       
                                  let hint = fixHint "re-order arguments"
                                  in return $ Just
                                        (1, "application: permute with "++show p, [edge], [hint info])
                           
                  -- is there one particular argument that is inconsistent
                  | length incorrectArguments == 1  ->
                      do let (t1, t2) = getTwoTypes info
                         fullTp <- applySubst t1 -- ???
                         let i = head incorrectArguments
                             {- bug fix 25 september 2003: don't forget to expand the type synonyms -}
                             expandedTp  = expandType (snd synonyms) fullTp
                             (source,tp) = tuplesForArguments !! i
			     range       = rangeOfSource source
			     oneLiner    = oneLinerSource source
                             infoFun     = typeErrorForTerm (isBinary,isPatternApplication) i oneLiner (tp,expargtp) range
                             expargtp    = fst (functionSpine expandedTp) !! i
                         return $ Just 
                            (3, "incorrect argument of application="++show i, [edge], [infoFun info])
                   
                  -- too many arguments are given
                  | maybe False (< numberOfArguments) maximumForFunction && not isPatternApplication ->
                       case typesZippedWithHoles of

                          -- there is only one possible set to remove arguments 
                          [is] | not isBinary
                              -> let hint = fixHint ("remove "++prettyAndList (map (ordinal True . (+1)) is)++" argument")
                                 in return $ Just
                                       (4, "too many arguments are given: "++show is, [edge], [hint info])

                          -- more than one or no possible set of arguments to be removed
                          _   -> let hint = becauseHint "too many arguments are given"
                                 in return $ Just
                                       (2, "too many arguments are given", [edge], [hint info])
                                         
                  -- not enough arguments are given
                  | minimumForContext > numberOfArguments && not isPatternApplication && contextIsUnifiable ->
                       case typesZippedWithHoles of

                          [is] | not isBinary 
                              -> let hint = fixHint ("insert a "++prettyAndList (map (ordinal True . (+1)) is)++" argument")
                                 in return $ Just
                                       (4, "not enough arguments are given"++show is, [edge], [hint info])

                          _   -> let hint = becauseHint "not enough arguments are given"
                                 in return $ Just
                                       (2, "not enough arguments are given", [edge], [hint info])

                where unifiableTypeLists :: Tps -> Tps -> Bool
                      unifiableTypeLists xs ys = unifiable synonyms (tupleType xs) (tupleType ys)   

                      -- number of arguments for this function application
                      numberOfArguments = length tuplesForArguments         
                                
                      -- (->) spines for function type and expected type for the given number of arguments
                      (functionArguments, functionResult) = functionSpineOfLength numberOfArguments functionType
                      (expectedArguments, expectedResult) = functionSpineOfLength numberOfArguments expectedType

                      -- (->) spines for function type and expected type ignoring the given number of arguments                      
                      (allFunctionArgs, allFunctionRes) = functionSpine functionType
                      (allExpectedArgs, allExpectedRes) = functionSpine expectedType
                      
                      -- maximum number of arguments for the function type (result type should not be polymorphic!)
                      --   e.g.: (a -> b) -> [a] -> [b]             yields (Just 2)
                      --         (a -> b -> b) -> b -> [a] -> b     yields Nothing
                      maximumForFunction = case functionSpine functionType of
                                              (_, TVar _) -> Nothing
                                              (tps, _   ) -> Just (length tps)
                      
                      -- minimum number of arguments that should be applied to the function to meet the expected context type
                      minimumForContext = length allFunctionArgs + numberOfArguments - length allExpectedArgs
                      
                      -- is the context unifiable?
                      contextIsUnifiable    = unifiable synonyms expectedResult (snd (functionSpineOfLength minimumForContext functionType))

                      -- is there one argument in particular that is incorrect?                                  
                      incorrectArguments = [ i 
                                           | length functionArguments == length expectedArguments 
                                           , i <- [0..numberOfArguments-1]
                                           , not (unifiable synonyms (functionArguments !! i) (expectedArguments !! i))
                                           , unifiableTypeLists (functionResult : deleteIndex i functionArguments) 
                                                                (expectedResult : deleteIndex i expectedArguments)
                                           ]

                      -- is there a permutation of the arguments that resolves the type inconsistency?
                      argumentPermutations = [ p 
                                             | length functionArguments == length expectedArguments 
                                             , p <- take heuristics_MAX (permutationsForLength numberOfArguments)
                                             , unifiableTypeLists (functionResult : functionArguments) 
                                                                  (expectedResult : permute p expectedArguments) 
                                             ]         ;                                                                

                      -- at which locations should an extra argument be inserted?
                      typesZippedWithHoles  = [ is 
                                              | (is,zl) <- take heuristics_MAX (zipWithHoles allFunctionArgs allExpectedArgs)
                                              , let (as,bs) = unzip zl
                                              , unifiableTypeLists (allFunctionRes : as) 
                                                                   (allExpectedRes : bs)
                                              ]                     
                      
                      isPatternApplication = isPattern info
                      
               _ -> return Nothing

-----------------------------------------------------------------------------

class IsTupleEdge a where
   isTupleEdge :: a -> Bool
   
tupleEdge :: (HasTypeGraph m info, IsTupleEdge info, HasTwoTypes info, WithHints info) => Selector m info
tupleEdge =
   Selector ("Tuple heuristics", f) where

 f (edge, cnr, info)    
   | not (isTupleEdge info) = return Nothing
   | otherwise              =
   
   doWithoutEdge (edge,info) $ 
   
      do synonyms <- getTypeSynonyms                         
         (mTupleTp, mExpectedTp) <- getSubstitutedTypes info
         
         case (fmap leftSpine mTupleTp,fmap leftSpine mExpectedTp) of 

          (Just (TCon s,tupleTps),Just (TCon t,expectedTps)) | isTupleConstructor s && isTupleConstructor t ->
            case compare (length tupleTps) (length expectedTps) of
            
               EQ -> -- try if a permutation can make the tuple types equivalent
                     case [ p 
                          | p <- take heuristics_MAX (permutationsForLength (length tupleTps))
                          , unifiable synonyms (tupleType tupleTps) (tupleType (permute p expectedTps))
                          ] of
                       p:_  ->  -- a permutation possible!
                               let hint = fixHint "re-order elements of tuple"
                               in return $ Just 
                                     (4, "tuple: permute with "++show p, [edge], [hint info])
                       _    -> return Nothing                       
            
               compare -> case [ is 
                               | (is,zl) <- take heuristics_MAX (zipWithHoles tupleTps expectedTps)
                               , let (xs, ys) = unzip zl in unifiable synonyms (tupleType xs) (tupleType ys)
                               ] of
                       [is] -> case compare of
                                 LT -> let hint = fixHint ("insert a "++prettyAndList (map (ordinal True. (+1)) is)++" element to the tuple")
                                       in return $ Just 
                                             (4, "tuple:insert "++show is, [edge], [hint info])
                                 GT -> let hint = fixHint ("remove "++prettyAndList (map (ordinal True . (+1)) is)++" element of tuple")
                                       in return $ Just 
                                             (4, "tuple:remove "++show is, [edge], [hint info])
                       _    -> let hint = becauseHint ("a "++show (length tupleTps)++"-tuple does not match a "++show (length expectedTps)++"-tuple")
                               in return $ Just 
                                     (2, "different sizes of tuple", [edge], [hint info])
          _ -> return Nothing  

-----------------------------------------------------------------------------

class IsFunctionBinding a where
   isExplicitlyTyped    :: a -> Bool
   maybeFunctionBinding :: a -> Maybe Int

fbHasTooManyArguments :: (HasTypeGraph m info, IsFunctionBinding info, HasTwoTypes info, WithHints info) => Selector m info
fbHasTooManyArguments =
   Selector ("Function Binding heuristics", f) where

 f (edge, cnr, info)   
   | not (isExplicitlyTyped info) = return Nothing
   | otherwise                    =

      do synonyms <- getTypeSynonyms
         let (t1,t2)         = getTwoTypes info
             maximumExplicit = arityOfTp (expandType (snd synonyms) t1)
             tvar            = head (ftv t2)
   
         edgeList <- edgesFrom tvar       
         let maybeNumberOfPatterns = 
                case [ i | Just i <- map (\(_,_,info) -> maybeFunctionBinding info) edgeList ] of 
                   [i] -> Just i
                   _   -> Nothing
                                      
         case maybeNumberOfPatterns of
            Just n | n > maximumExplicit -> 
               let msg = "the function binding has "++prettyPat n++", but its type signature "++prettyArg maximumExplicit
                   prettyPat i = if i == 1 then "1 pattern" else show i++" patterns"
                   prettyArg 0 = "does not allow patterns"
                   prettyArg n = "allows at most "++show n
                   hint = becauseHint msg
               in return $ Just 
                     (8, "function binding has too many arguments", [edge], [hint info])
            _ -> return Nothing

-----------------------------------------------------------------------------

class IsExprVariable a where
   isExprVariable          :: a -> Bool
   isEmptyInfixApplication :: a -> Bool
   
variableFunction :: (HasTypeGraph m info, IsExprVariable info, MaybeApplication info, HasTwoTypes info, WithHints info) => Selector m info
variableFunction =
   Selector ("Variable function", f) where

 f (edge, cnr, info)      
   | not (isExprVariable info)
        = return Nothing
   | otherwise 
        = doWithoutEdge (edge,info) $ 
            
           do synonyms   <- getTypeSynonyms
              (mt1, mt2) <- getSubstitutedTypes info
              
              -- is this variable involved in an application?
              let EdgeID v1 v2 = edge
              edges1 <- edgesFrom v1
              edges2 <- edgesFrom v2
              let f ((EdgeID v1 v2),_,_) = [v1,v2]
              let special = concatMap f (filter (isEmptyInfixApplication . (\(_,_,info) -> info)) (edges1 ++ edges2)) \\ [v1,v2]
              edges3 <- mapM edgesFrom special
              let isApplicationEdge = isJust . maybeApplicationEdge
                  application = any (\(_,_,info) -> isApplicationEdge info) (edges1 ++ edges2 ++ concat edges3)                                                               
             
              case (mt1, mt2) of
                 (Just functionType, Just expectedType) | not application -> 
                    let maxArgumentsForFunction = length (fst (functionSpine functionType))
                        minArgumentsForContext  = maxArgumentsForFunction - length (fst (functionSpine expectedType)) 
                        contextIsUnifiable      = unifiable synonyms 
                                                     (snd $ functionSpineOfLength minArgumentsForContext functionType)
                                                     expectedType
                    in if minArgumentsForContext <= 0 || not contextIsUnifiable
                         then return Nothing
                         else let hint = fixHint ("insert "++showNumber minArgumentsForContext++" argument"++
                                              if minArgumentsForContext <= 1 then "" else "s")
                              in return $ Just 
                                    (4, "insert arguments to function variable", [edge], [hint info])
                 _ -> return Nothing

-----------------------------------------------------------------------------

class MaybeUnaryMinus a where
   maybeUnaryMinus :: a -> Maybe (Either Int Float)

unaryMinus :: (HasTypeGraph m info, MaybeApplication info, MaybeUnaryMinus info, HasTwoTypes info, WithHints info) => Selector m info
unaryMinus = 
   Selector ("Unary minus", f) where

 f (edge, cnr, info) =
   case maybeApplicationEdge info of
      Just (isInfix, tuplesForArguments) | isInfix && length tuplesForArguments == 2 -> 
         case maybeUnaryMinus info of
	    Just someLiteral ->
	       doWithoutEdge (edge,info) $ 
	          do synonyms <- getTypeSynonyms 
		     let leftBeta = snd (head tuplesForArguments)
		     leftType <- safeApplySubst leftBeta
		     (_, mt2) <- getSubstitutedTypes info
		     let contextType = fmap (snd . functionSpineOfLength 2 . expandType (snd synonyms)) mt2
		     case (someLiteral, leftType, contextType) of
		        (Left int, Just leftTp, Just contextTp) 
			   | unifiable synonyms leftTp (intType .->. contextTp) -> 
			        let hint = possibleHint ("Insert parentheses to negate the int literal: (-"++show int++")")
                                in return $ Just 
                                     (5, "Unary minus for int", [edge], [hint info])
	                (Right float, Just leftTp, Just contextTp) 
			   | unifiable synonyms leftTp (floatType .->. contextTp) -> 
			        let hint = possibleHint ("Insert parentheses to negate the float literal: (-."++show float++")")
                                in return $ Just 
                                     (5, "Unary minus for float", [edge], [hint info])
			_ -> return Nothing
	    _ -> return Nothing
      
      {- waarom staat dit nog in commentaar, vraagt Arjan; haddock zeurde er over vanwege
         commentaar en dan een verticale streep
         | isBinary && isInfixMinus info ->
        $
       
          do undefined-}
	  
      _ -> return Nothing
                       
-----------------------------------------------------------------------------
-- REST 

heuristics_MAX = 120 :: Int

zipWithHoles :: [a] -> [b] -> [ ( [Int] , [(a,b)] ) ] 
zipWithHoles = rec 0 where

   rec i [] bs = [ (take (length bs) [i..] , []) ]
   rec i as [] = [ (take (length as) [i..] , []) ]
   rec i (a:as) (b:bs) = case compare (length as) (length bs) of
         LT -> [ (  is,(a,b):zl) | (is,zl) <- rec (i+1) as     bs ]
            ++ [ (i:is,      zl) | (is,zl) <- rec (i+1) (a:as) bs ]
         EQ -> [ ([],zip (a:as) (b:bs)) ] 
         GT -> [ (  is,(a,b):zl) | (is,zl) <- rec (i+1) as bs     ]
            ++ [ (i:is,      zl) | (is,zl) <- rec (i+1) as (b:bs) ]

type Permutation = [Int]

permutationsForLength :: Int -> [Permutation]
permutationsForLength 0 = [ [] ]
permutationsForLength i = [ ys | xs <- permutationsForLength (i-1), ys <- insertSomewhere (i-1) xs ]
  where
	insertSomewhere i []     = [ [i] ]
	insertSomewhere i (x:xs) = (i:x:xs) : map (x:) (insertSomewhere i xs)
         
deleteIndex :: Int -> [a] -> [a]
deleteIndex _ []     = []
deleteIndex 0 (a:as) = as
deleteIndex i (a:as) = a : deleteIndex (i-1) as

permute :: Permutation -> [a] -> [a]
permute is as = map (as !!) is

class WithHints a where
   addHint          :: String -> String -> a -> a
   typeErrorForTerm :: (Bool,Bool) -> Int -> OneLineTree -> (Tp,Tp) -> Range -> a -> a
   
fixHint, becauseHint, possibleHint :: WithHints a => String -> a -> a
fixHint      = addHint "probable fix"
becauseHint  = addHint "because"
possibleHint = addHint "possible fix"
