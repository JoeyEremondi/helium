-- do not edit; automatically generated by UU.AG
module TS_Apply where

import UHA_Syntax
import TypeConstraints
import ConstraintInfo
import Top.Types
import List
import UHA_Range (noRange)
import Utils (internalError, fst3)
import OneLiner
import Messages
import TypeErrors
import ImportEnvironment
import OperatorTable (OperatorTable)
import Parser (exp_)
import Lexer (strategiesLexer)
import ParseLibrary (runHParser)
import qualified ResolveOperators
import TS_Attributes
import TS_CoreSyntax
import Top.ComposedSolvers.Tree
import UHA_Source
import Data.FiniteMap
import DoublyLinkedTree (root)

type MetaVariableTable info = [(String, (ConstraintSet, info))]
type MetaVariableInfo = (Tp, UHA_Source, Range)

applyTypingStrategy :: Core_TypingStrategy -> (ConstraintSet, MetaVariableInfo) -> MetaVariableTable MetaVariableInfo -> Int -> (ConstraintSet, IO (), Int)
applyTypingStrategy = sem_Core_TypingStrategy

matchInformation :: ImportEnvironment -> Core_TypingStrategy -> [(Expression, [String])]
matchInformation importEnvironment typingStrategy = 
   case typingStrategy of 
      TypingStrategy (TypeRule premises conclusion) _ -> 
         let Judgement exprstring _ = conclusion
             expression = expressionParser (operatorTable importEnvironment) exprstring
             metas      = [ s | Judgement s t <- premises ]
         in [(expression, metas)]
      _ -> []
      
expressionParser :: OperatorTable -> String -> Expression
expressionParser operatorTable string = 
    case strategiesLexer "TS_Apply" string of 
        Left lexErr -> intErr
        Right (tokens, _) ->
            case runHParser exp_ "TS_Apply" tokens True {- wait for EOF -} of
                Left parseError  -> intErr
                Right expression -> 
                    ResolveOperators.expression operatorTable expression
  where
    intErr = internalError "TS_Apply.ag" "n/a" ("unparsable expression: "++show string)

standardConstraintInfo :: (Int, Int) -> (Tp, Tp) -> ConstraintInfo
standardConstraintInfo pos tppair =
   CInfo { location   = "Typing Strategy"
         , sources    = (UHA_Decls [], Nothing)
         , typepair   = tppair
         , localInfo  = root (LocalInfo (UHA_Decls []) Nothing emptyFM) []
         , properties = [ ]
         }

typeRuleCInfo :: String -> Maybe (String, UHA_Source) -> MetaVariableInfo -> (Tp, Tp) -> ConstraintInfo
typeRuleCInfo loc mTuple (tp1,tree,range) tppair =
   CInfo { location   = loc
         , sources    = (UHA_Decls [], Nothing)
         , typepair   = tppair
         , properties = []
         }
-- where (infoString, srcs, props) = case mTuple of 
--          Just (s,t) -> ("meta variable "++s, [sourceExpression t, sourceTerm tree], [])
--          Nothing    -> ("conclusion", [sourceExpression tree], [FolkloreConstraint])

-- see TypeInferenceInfo.ag
sourceTerm, sourceExpression :: OneLineTree -> (String, OneLineTree)
sourceTerm        = (,) "term"
sourceExpression  = (,) "expression"

exactlyOnce :: Eq a => [a] -> [a]
exactlyOnce []     = []
exactlyOnce (x:xs) | x `elem` xs = exactlyOnce . filter (/= x) $ xs
                   | otherwise   = x : exactlyOnce xs

setCustomTypeError :: MetaVariableInfo -> ConstraintInfo -> ConstraintInfo
setCustomTypeError (tp, source, range) cinfo =
   addProperty (WithTypeError customTypeError) cinfo        

     where customTypeError = TypeError [range] message [] []
           message = [ MessageOneLiner (MessageString ("Type error in "++"Typing Strategy"))
                     , MessageTable
                       [ (MessageString "Expression", MessageOneLineTree (oneLinerSource source)) ]                     
                     , MessageOneLiner (MessageString "   implies that the following types are equal:")
                     , MessageTable 
                       [ (MessageString "Type 1", MessageType (toTpScheme (fst (typepair cinfo))))
                       , (MessageString "Type 2", MessageType (toTpScheme (snd (typepair cinfo))))
                       ]                     
                     ]  

makeMessageAlgebra :: AttributeTable MessageBlock -> AttributeAlgebra MessageBlock
makeMessageAlgebra table = ( MessageString
                           , table
                           , \attribute -> internalError 
                                              "TS_Apply" "makeMessageAlgebra"
                                              ("unknown attribute " ++ showAttribute attribute ++
                                               "; known attributes are " ++ show (map (showAttribute . fst) table))
                           )

makeAttributeTable :: MetaVariableInfo -> MetaVariableTable MetaVariableInfo -> FiniteMapSubstitution -> [((String, Maybe String), MessageBlock)]
makeAttributeTable local table substitution = 
   let f :: String -> MetaVariableInfo -> [((String, Maybe String), MessageBlock)]
       f string (tp, source, range) = [ ((string, Just "type" ), MessageType (toTpScheme tp))
                                      , ((string, Just "pp"   ), MessageOneLineTree (oneLinerSource source))
                                      , ((string, Just "range"), MessageRange range)
                                      ]
   in f "expr" local 
   ++ concatMap (\(s,(_,info)) -> f s info) table 
   ++ [ ((show i, Nothing), MessageType (toTpScheme (substitution |-> TVar i))) | i <- dom substitution ]  
-- Core_Judgement ----------------------------------------------
-- semantic domain
type T_Core_Judgement = ((ConstraintSet, MetaVariableInfo)) ->
                        (MetaVariableTable MetaVariableInfo) ->
                        (FiniteMapSubstitution) ->
                        ( ([Int]),([(String, Tp)]))
-- cata
sem_Core_Judgement :: (Core_Judgement) ->
                      (T_Core_Judgement)
sem_Core_Judgement ((Judgement (_expression) (_type))) =
    (sem_Core_Judgement_Judgement (_expression) (_type))
sem_Core_Judgement_Judgement :: (String) ->
                                (Tp) ->
                                (T_Core_Judgement)
sem_Core_Judgement_Judgement (expression_) (type_) =
    \ _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsIsubstitution ->
        let _lhsOftv :: ([Int])
            _lhsOjudgements :: ([(String, Tp)])
            (_lhsOftv@_) =
                ftv type_
            (_lhsOjudgements@_) =
                [(expression_, type_)]
        in  ( _lhsOftv,_lhsOjudgements)
-- Core_Judgements ---------------------------------------------
-- semantic domain
type T_Core_Judgements = ((ConstraintSet, MetaVariableInfo)) ->
                         (MetaVariableTable MetaVariableInfo) ->
                         (FiniteMapSubstitution) ->
                         ( ([Int]),([(String, Tp)]))
-- cata
sem_Core_Judgements :: (Core_Judgements) ->
                       (T_Core_Judgements)
sem_Core_Judgements (list) =
    (foldr (sem_Core_Judgements_Cons) (sem_Core_Judgements_Nil) ((map sem_Core_Judgement list)))
sem_Core_Judgements_Cons :: (T_Core_Judgement) ->
                            (T_Core_Judgements) ->
                            (T_Core_Judgements)
sem_Core_Judgements_Cons (hd_) (tl_) =
    \ _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsIsubstitution ->
        let _lhsOftv :: ([Int])
            _lhsOjudgements :: ([(String, Tp)])
            _hdIftv :: ([Int])
            _hdIjudgements :: ([(String, Tp)])
            _hdOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _hdOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _hdOsubstitution :: (FiniteMapSubstitution)
            _tlIftv :: ([Int])
            _tlIjudgements :: ([(String, Tp)])
            _tlOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _tlOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _tlOsubstitution :: (FiniteMapSubstitution)
            ( _hdIftv,_hdIjudgements) =
                (hd_ (_hdOinfoTuple) (_hdOmetaVariableTable) (_hdOsubstitution))
            ( _tlIftv,_tlIjudgements) =
                (tl_ (_tlOinfoTuple) (_tlOmetaVariableTable) (_tlOsubstitution))
            (_lhsOftv@_) =
                _hdIftv ++ _tlIftv
            (_lhsOjudgements@_) =
                _hdIjudgements ++ _tlIjudgements
            (_hdOinfoTuple@_) =
                _lhsIinfoTuple
            (_hdOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_hdOsubstitution@_) =
                _lhsIsubstitution
            (_tlOinfoTuple@_) =
                _lhsIinfoTuple
            (_tlOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_tlOsubstitution@_) =
                _lhsIsubstitution
        in  ( _lhsOftv,_lhsOjudgements)
sem_Core_Judgements_Nil :: (T_Core_Judgements)
sem_Core_Judgements_Nil  =
    \ _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsIsubstitution ->
        let _lhsOftv :: ([Int])
            _lhsOjudgements :: ([(String, Tp)])
            (_lhsOftv@_) =
                []
            (_lhsOjudgements@_) =
                []
        in  ( _lhsOftv,_lhsOjudgements)
-- Core_TypeRule -----------------------------------------------
-- semantic domain
type T_Core_TypeRule = ((ConstraintSet, MetaVariableInfo)) ->
                       (MetaVariableTable MetaVariableInfo) ->
                       (FiniteMapSubstitution) ->
                       ( (TypeConstraints ConstraintInfo),([Int]),([(String, Tp)]))
-- cata
sem_Core_TypeRule :: (Core_TypeRule) ->
                     (T_Core_TypeRule)
sem_Core_TypeRule ((TypeRule (_premises) (_conclusion))) =
    (sem_Core_TypeRule_TypeRule ((sem_Core_Judgements (_premises))) ((sem_Core_Judgement (_conclusion))))
sem_Core_TypeRule_TypeRule :: (T_Core_Judgements) ->
                              (T_Core_Judgement) ->
                              (T_Core_TypeRule)
sem_Core_TypeRule_TypeRule (premises_) (conclusion_) =
    \ _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsIsubstitution ->
        let _lhsOconstraints :: (TypeConstraints ConstraintInfo)
            _lhsOftv :: ([Int])
            _lhsOjudgements :: ([(String, Tp)])
            _premisesIftv :: ([Int])
            _premisesIjudgements :: ([(String, Tp)])
            _premisesOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _premisesOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _premisesOsubstitution :: (FiniteMapSubstitution)
            _conclusionIftv :: ([Int])
            _conclusionIjudgements :: ([(String, Tp)])
            _conclusionOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _conclusionOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _conclusionOsubstitution :: (FiniteMapSubstitution)
            ( _premisesIftv,_premisesIjudgements) =
                (premises_ (_premisesOinfoTuple) (_premisesOmetaVariableTable) (_premisesOsubstitution))
            ( _conclusionIftv,_conclusionIjudgements) =
                (conclusion_ (_conclusionOinfoTuple) (_conclusionOmetaVariableTable) (_conclusionOsubstitution))
            (_lhsOconstraints@_) =
                let infoTuple@(localType, localTree, _) = snd _lhsIinfoTuple
                    localLocation = "expression"
                in [ (_lhsIsubstitution |-> tp1 .==. localType)
                        (typeRuleCInfo localLocation Nothing infoTuple)
                   | (s1, tp1) <- _conclusionIjudgements
                   ]
                   ++
                   [ (tp2 .==. _lhsIsubstitution |-> tp1)
                        (typeRuleCInfo localLocation (Just (s1, localTree)) mvinfo)
                   | (s1, tp1)                   <- _premisesIjudgements
                   , (s2, (_, mvinfo@(tp2,_,_))) <- _lhsImetaVariableTable
                   , s1 == s2
                   ]
            (_lhsOftv@_) =
                _premisesIftv ++ _conclusionIftv
            (_lhsOjudgements@_) =
                _premisesIjudgements ++ _conclusionIjudgements
            (_premisesOinfoTuple@_) =
                _lhsIinfoTuple
            (_premisesOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_premisesOsubstitution@_) =
                _lhsIsubstitution
            (_conclusionOinfoTuple@_) =
                _lhsIinfoTuple
            (_conclusionOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_conclusionOsubstitution@_) =
                _lhsIsubstitution
        in  ( _lhsOconstraints,_lhsOftv,_lhsOjudgements)
-- Core_TypingStrategy -----------------------------------------
-- semantic domain
type T_Core_TypingStrategy = ((ConstraintSet, MetaVariableInfo)) ->
                             (MetaVariableTable MetaVariableInfo) ->
                             (Int) ->
                             ( (ConstraintSet),(IO ()),(Int))
-- cata
sem_Core_TypingStrategy :: (Core_TypingStrategy) ->
                           (T_Core_TypingStrategy)
sem_Core_TypingStrategy ((Siblings (_functions))) =
    (sem_Core_TypingStrategy_Siblings (_functions))
sem_Core_TypingStrategy ((TypingStrategy (_typerule) (_statements))) =
    (sem_Core_TypingStrategy_TypingStrategy ((sem_Core_TypeRule (_typerule))) ((sem_Core_UserStatements (_statements))))
sem_Core_TypingStrategy_Siblings :: ([String]) ->
                                    (T_Core_TypingStrategy)
sem_Core_TypingStrategy_Siblings (functions_) =
    \ _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsIunique ->
        let _lhsOconstraintSet :: (ConstraintSet)
            _lhsOdebugIO :: (IO ())
            _lhsOunique :: (Int)
            (_lhsOdebugIO@_) =
                return ()
            (_lhsOconstraintSet@_) =
                emptyTree
            (_lhsOunique@_) =
                _lhsIunique
        in  ( _lhsOconstraintSet,_lhsOdebugIO,_lhsOunique)
sem_Core_TypingStrategy_TypingStrategy :: (T_Core_TypeRule) ->
                                          (T_Core_UserStatements) ->
                                          (T_Core_TypingStrategy)
sem_Core_TypingStrategy_TypingStrategy (typerule_) (statements_) =
    \ _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsIunique ->
        let _lhsOconstraintSet :: (ConstraintSet)
            _lhsOdebugIO :: (IO ())
            _lhsOunique :: (Int)
            _typeruleIconstraints :: (TypeConstraints ConstraintInfo)
            _typeruleIftv :: ([Int])
            _typeruleIjudgements :: ([(String, Tp)])
            _typeruleOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _typeruleOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _typeruleOsubstitution :: (FiniteMapSubstitution)
            _statementsIcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _statementsIcurrentPhase :: (Maybe Int)
            _statementsIcurrentPosition :: ((Int, Int))
            _statementsIftv :: ([Int])
            _statementsImetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _statementsOattributeTable :: ([((String, Maybe String), MessageBlock)])
            _statementsOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _statementsOcurrentPhase :: (Maybe Int)
            _statementsOcurrentPosition :: ((Int, Int))
            _statementsOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _statementsOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _statementsOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _statementsOsubstitution :: (FiniteMapSubstitution)
            ( _typeruleIconstraints,_typeruleIftv,_typeruleIjudgements) =
                (typerule_ (_typeruleOinfoTuple) (_typeruleOmetaVariableTable) (_typeruleOsubstitution))
            ( _statementsIcollectConstraints,_statementsIcurrentPhase,_statementsIcurrentPosition,_statementsIftv,_statementsImetavarConstraints) =
                (statements_ (_statementsOattributeTable) (_statementsOcollectConstraints) (_statementsOcurrentPhase) (_statementsOcurrentPosition) (_statementsOinfoTuple) (_statementsOmetaVariableTable) (_statementsOmetavarConstraints) (_statementsOsubstitution))
            (_specialSubst@_) =
                let conclusionVar = case snd (last _typeruleIjudgements) of
                                       TVar i -> Just i
                                       _      -> Nothing
                    find i | Just i == conclusionVar = [(i, fst3 (snd _lhsIinfoTuple))]
                           | otherwise               = [ (i,tp)
                                                       | (s1, TVar j)       <- _typeruleIjudgements
                                                       , i == j
                                                       , (s2, (_,(tp,_,_))) <- _lhsImetaVariableTable
                                                       , s1 == s2
                                                       ]
                in concatMap find _specialTV
            (_standardSubst@_) =
                zip _normalTV (map TVar [_lhsIunique..])
            (_normalTV@_) =
                _allTV \\ _specialTV
            (_specialTV@_) =
                concat . exactlyOnce . map ftv . filter isTVar . map snd $ _typeruleIjudgements
            (_allTV@_) =
                _typeruleIftv `union` _statementsIftv
            (_substitution@_) =
                listToSubstitution (_standardSubst ++ _specialSubst)
            (_lhsOdebugIO@_) =
                putStrLn "applying typing strategy"
            (_lhsOunique@_) =
                length _normalTV + _lhsIunique
            (_lhsOconstraintSet@_) =
                Node _allConstraintTrees
            (_statementsOattributeTable@_) =
                makeAttributeTable (snd _lhsIinfoTuple) _lhsImetaVariableTable _substitution
            (_statementsOmetavarConstraints@_) =
                [ (s,cs) | (s,(cs,_)) <- _lhsImetaVariableTable ]
            (_statementsOcurrentPosition@_) =
                (_lhsIunique, 0)
            (_statementsOcurrentPhase@_) =
                Nothing
            (_statementsOcollectConstraints@_) =
                []
            (_allConstraintTrees@_) =
                listTree (reverse _typeruleIconstraints) :
                (map snd _statementsImetavarConstraints) ++
                (reverse _statementsIcollectConstraints)
            (_typeruleOinfoTuple@_) =
                _lhsIinfoTuple
            (_typeruleOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_typeruleOsubstitution@_) =
                _substitution
            (_statementsOinfoTuple@_) =
                _lhsIinfoTuple
            (_statementsOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_statementsOsubstitution@_) =
                _substitution
        in  ( _lhsOconstraintSet,_lhsOdebugIO,_lhsOunique)
-- Core_UserStatement ------------------------------------------
-- semantic domain
type T_Core_UserStatement = ([((String, Maybe String), MessageBlock)]) ->
                            (Trees (TypeConstraint ConstraintInfo)) ->
                            (Maybe Int) ->
                            ((Int, Int)) ->
                            ((ConstraintSet, MetaVariableInfo)) ->
                            (MetaVariableTable MetaVariableInfo) ->
                            ([(String,Tree (TypeConstraint ConstraintInfo))]) ->
                            (FiniteMapSubstitution) ->
                            ( (Trees (TypeConstraint ConstraintInfo)),(Maybe Int),((Int, Int)),([Int]),([(String,Tree (TypeConstraint ConstraintInfo))]))
-- cata
sem_Core_UserStatement :: (Core_UserStatement) ->
                          (T_Core_UserStatement)
sem_Core_UserStatement ((Constraint (_leftType) (_rightType) (_message))) =
    (sem_Core_UserStatement_Constraint (_leftType) (_rightType) (_message))
sem_Core_UserStatement ((CorePhase (_phase))) =
    (sem_Core_UserStatement_CorePhase (_phase))
sem_Core_UserStatement ((MetaVariableConstraints (_name))) =
    (sem_Core_UserStatement_MetaVariableConstraints (_name))
sem_Core_UserStatement_Constraint :: (Tp) ->
                                     (Tp) ->
                                     (String) ->
                                     (T_Core_UserStatement)
sem_Core_UserStatement_Constraint (leftType_) (rightType_) (message_) =
    \ _lhsIattributeTable
      _lhsIcollectConstraints
      _lhsIcurrentPhase
      _lhsIcurrentPosition
      _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsImetavarConstraints
      _lhsIsubstitution ->
        let _lhsOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _lhsOcurrentPhase :: (Maybe Int)
            _lhsOcurrentPosition :: ((Int, Int))
            _lhsOftv :: ([Int])
            _lhsOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            (_lhsOftv@_) =
                ftv [leftType_, rightType_]
            (_lhsOcollectConstraints@_) =
                case _lhsIcurrentPhase of
                   Just phase | phase /= 5
                              -> Phase phase [ _newConstraint ] : _lhsIcollectConstraints
                   _          -> unitTree _newConstraint : _lhsIcollectConstraints
            (_lhsOcurrentPosition@_) =
                (\(x, y) -> (x, y+1)) _lhsIcurrentPosition
            (_newConstraint@_) =
                let cinfo   = addProperty (WithTypeError (TypeError [] message [] [])) .
                              addProperty (uncurry IsUserConstraint _lhsIcurrentPosition) .
                              standardConstraintInfo _lhsIcurrentPosition
                    message = [MessageOneLiner (MessageCompose (substituteAttributes (makeMessageAlgebra _lhsIattributeTable) message_))]
                in (_lhsIsubstitution |-> leftType_ .==. _lhsIsubstitution |-> rightType_) cinfo
            (_lhsOcurrentPhase@_) =
                _lhsIcurrentPhase
            (_lhsOmetavarConstraints@_) =
                _lhsImetavarConstraints
        in  ( _lhsOcollectConstraints,_lhsOcurrentPhase,_lhsOcurrentPosition,_lhsOftv,_lhsOmetavarConstraints)
sem_Core_UserStatement_CorePhase :: (Int) ->
                                    (T_Core_UserStatement)
sem_Core_UserStatement_CorePhase (phase_) =
    \ _lhsIattributeTable
      _lhsIcollectConstraints
      _lhsIcurrentPhase
      _lhsIcurrentPosition
      _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsImetavarConstraints
      _lhsIsubstitution ->
        let _lhsOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _lhsOcurrentPhase :: (Maybe Int)
            _lhsOcurrentPosition :: ((Int, Int))
            _lhsOftv :: ([Int])
            _lhsOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            (_lhsOcurrentPhase@_) =
                Just phase_
            (_lhsOftv@_) =
                []
            (_lhsOcollectConstraints@_) =
                _lhsIcollectConstraints
            (_lhsOcurrentPosition@_) =
                _lhsIcurrentPosition
            (_lhsOmetavarConstraints@_) =
                _lhsImetavarConstraints
        in  ( _lhsOcollectConstraints,_lhsOcurrentPhase,_lhsOcurrentPosition,_lhsOftv,_lhsOmetavarConstraints)
sem_Core_UserStatement_MetaVariableConstraints :: (String) ->
                                                  (T_Core_UserStatement)
sem_Core_UserStatement_MetaVariableConstraints (name_) =
    \ _lhsIattributeTable
      _lhsIcollectConstraints
      _lhsIcurrentPhase
      _lhsIcurrentPosition
      _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsImetavarConstraints
      _lhsIsubstitution ->
        let _lhsOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _lhsOcurrentPhase :: (Maybe Int)
            _lhsOcurrentPosition :: ((Int, Int))
            _lhsOftv :: ([Int])
            _lhsOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            (_lhsOcollectConstraints@_) =
                case lookup name_ _lhsImetavarConstraints of
                    Just tree -> tree : _lhsIcollectConstraints
                    Nothing   -> internalError "TS_Apply.ag" "n/a" "unknown constraint set"
            (_lhsOmetavarConstraints@_) =
                filter ((name_ /=) . fst) _lhsImetavarConstraints
            (_lhsOftv@_) =
                []
            (_lhsOcurrentPhase@_) =
                _lhsIcurrentPhase
            (_lhsOcurrentPosition@_) =
                _lhsIcurrentPosition
        in  ( _lhsOcollectConstraints,_lhsOcurrentPhase,_lhsOcurrentPosition,_lhsOftv,_lhsOmetavarConstraints)
-- Core_UserStatements -----------------------------------------
-- semantic domain
type T_Core_UserStatements = ([((String, Maybe String), MessageBlock)]) ->
                             (Trees (TypeConstraint ConstraintInfo)) ->
                             (Maybe Int) ->
                             ((Int, Int)) ->
                             ((ConstraintSet, MetaVariableInfo)) ->
                             (MetaVariableTable MetaVariableInfo) ->
                             ([(String,Tree (TypeConstraint ConstraintInfo))]) ->
                             (FiniteMapSubstitution) ->
                             ( (Trees (TypeConstraint ConstraintInfo)),(Maybe Int),((Int, Int)),([Int]),([(String,Tree (TypeConstraint ConstraintInfo))]))
-- cata
sem_Core_UserStatements :: (Core_UserStatements) ->
                           (T_Core_UserStatements)
sem_Core_UserStatements (list) =
    (foldr (sem_Core_UserStatements_Cons) (sem_Core_UserStatements_Nil) ((map sem_Core_UserStatement list)))
sem_Core_UserStatements_Cons :: (T_Core_UserStatement) ->
                                (T_Core_UserStatements) ->
                                (T_Core_UserStatements)
sem_Core_UserStatements_Cons (hd_) (tl_) =
    \ _lhsIattributeTable
      _lhsIcollectConstraints
      _lhsIcurrentPhase
      _lhsIcurrentPosition
      _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsImetavarConstraints
      _lhsIsubstitution ->
        let _lhsOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _lhsOcurrentPhase :: (Maybe Int)
            _lhsOcurrentPosition :: ((Int, Int))
            _lhsOftv :: ([Int])
            _lhsOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _hdIcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _hdIcurrentPhase :: (Maybe Int)
            _hdIcurrentPosition :: ((Int, Int))
            _hdIftv :: ([Int])
            _hdImetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _hdOattributeTable :: ([((String, Maybe String), MessageBlock)])
            _hdOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _hdOcurrentPhase :: (Maybe Int)
            _hdOcurrentPosition :: ((Int, Int))
            _hdOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _hdOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _hdOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _hdOsubstitution :: (FiniteMapSubstitution)
            _tlIcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _tlIcurrentPhase :: (Maybe Int)
            _tlIcurrentPosition :: ((Int, Int))
            _tlIftv :: ([Int])
            _tlImetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _tlOattributeTable :: ([((String, Maybe String), MessageBlock)])
            _tlOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _tlOcurrentPhase :: (Maybe Int)
            _tlOcurrentPosition :: ((Int, Int))
            _tlOinfoTuple :: ((ConstraintSet, MetaVariableInfo))
            _tlOmetaVariableTable :: (MetaVariableTable MetaVariableInfo)
            _tlOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            _tlOsubstitution :: (FiniteMapSubstitution)
            ( _hdIcollectConstraints,_hdIcurrentPhase,_hdIcurrentPosition,_hdIftv,_hdImetavarConstraints) =
                (hd_ (_hdOattributeTable) (_hdOcollectConstraints) (_hdOcurrentPhase) (_hdOcurrentPosition) (_hdOinfoTuple) (_hdOmetaVariableTable) (_hdOmetavarConstraints) (_hdOsubstitution))
            ( _tlIcollectConstraints,_tlIcurrentPhase,_tlIcurrentPosition,_tlIftv,_tlImetavarConstraints) =
                (tl_ (_tlOattributeTable) (_tlOcollectConstraints) (_tlOcurrentPhase) (_tlOcurrentPosition) (_tlOinfoTuple) (_tlOmetaVariableTable) (_tlOmetavarConstraints) (_tlOsubstitution))
            (_lhsOftv@_) =
                _hdIftv ++ _tlIftv
            (_lhsOcollectConstraints@_) =
                _tlIcollectConstraints
            (_lhsOcurrentPhase@_) =
                _tlIcurrentPhase
            (_lhsOcurrentPosition@_) =
                _tlIcurrentPosition
            (_lhsOmetavarConstraints@_) =
                _tlImetavarConstraints
            (_hdOattributeTable@_) =
                _lhsIattributeTable
            (_hdOcollectConstraints@_) =
                _lhsIcollectConstraints
            (_hdOcurrentPhase@_) =
                _lhsIcurrentPhase
            (_hdOcurrentPosition@_) =
                _lhsIcurrentPosition
            (_hdOinfoTuple@_) =
                _lhsIinfoTuple
            (_hdOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_hdOmetavarConstraints@_) =
                _lhsImetavarConstraints
            (_hdOsubstitution@_) =
                _lhsIsubstitution
            (_tlOattributeTable@_) =
                _lhsIattributeTable
            (_tlOcollectConstraints@_) =
                _hdIcollectConstraints
            (_tlOcurrentPhase@_) =
                _hdIcurrentPhase
            (_tlOcurrentPosition@_) =
                _hdIcurrentPosition
            (_tlOinfoTuple@_) =
                _lhsIinfoTuple
            (_tlOmetaVariableTable@_) =
                _lhsImetaVariableTable
            (_tlOmetavarConstraints@_) =
                _hdImetavarConstraints
            (_tlOsubstitution@_) =
                _lhsIsubstitution
        in  ( _lhsOcollectConstraints,_lhsOcurrentPhase,_lhsOcurrentPosition,_lhsOftv,_lhsOmetavarConstraints)
sem_Core_UserStatements_Nil :: (T_Core_UserStatements)
sem_Core_UserStatements_Nil  =
    \ _lhsIattributeTable
      _lhsIcollectConstraints
      _lhsIcurrentPhase
      _lhsIcurrentPosition
      _lhsIinfoTuple
      _lhsImetaVariableTable
      _lhsImetavarConstraints
      _lhsIsubstitution ->
        let _lhsOcollectConstraints :: (Trees (TypeConstraint ConstraintInfo))
            _lhsOcurrentPhase :: (Maybe Int)
            _lhsOcurrentPosition :: ((Int, Int))
            _lhsOftv :: ([Int])
            _lhsOmetavarConstraints :: ([(String,Tree (TypeConstraint ConstraintInfo))])
            (_lhsOftv@_) =
                []
            (_lhsOcollectConstraints@_) =
                _lhsIcollectConstraints
            (_lhsOcurrentPhase@_) =
                _lhsIcurrentPhase
            (_lhsOcurrentPosition@_) =
                _lhsIcurrentPosition
            (_lhsOmetavarConstraints@_) =
                _lhsImetavarConstraints
        in  ( _lhsOcollectConstraints,_lhsOcurrentPhase,_lhsOcurrentPosition,_lhsOftv,_lhsOmetavarConstraints)

