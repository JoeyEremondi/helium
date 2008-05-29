{-| Module      :  Args
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable

    
-}

module Args
    ( Option(..)
    , processHeliumArgs
    , processTexthintArgs
    , lvmPathFromOptions
    , loggerDEFAULTHOST
    , loggerDEFAULTPORT
    , hostNameFromOptions
    , portNrFromOptions
    ) where

import System
import Version
import Data.Char
import Monad(when)
import System.Console.GetOpt

loggerDEFAULTHOST :: String
loggerDEFAULTHOST = "localhost"

loggerDEFAULTPORT :: Int
loggerDEFAULTPORT = 5010

unwordsBy :: String -> [String] -> String
unwordsBy sep [] = ""
unwordsBy sep [w] = w
unwordsBy sep (w:ws) = w ++ sep ++ unwordsBy sep ws

-- Keep only the last of the overloading flags and the last of the logging enable flags.
-- The alert flag overrides logging turned off.
-- This function also collects all -P flags together and merges them into one. The order of the
-- directories is the order in which they were specified.
-- Adds Overloading flag to make sure that this is the default.
simplifyOptions :: [Option] -> [Option]
simplifyOptions ops = 
    let
      revdefops = reverse (DisableLogging : (Overloading : ops)) -- Add defaults that will be ignored if explicit flags are present
      modops    = if (AlertLogging `elem` revdefops) 
                  then EnableLogging : revdefops -- Explicitly enable logging as well, just to be safe
                  else revdefops
    in
      collectPaths (keepFirst [Overloading, NoOverloading] (keepFirst [EnableLogging, DisableLogging] modops)) [] []
          where
            -- Assumes the options are in reverse order, and also reverses them.
            -- Collects several LvmPath options into one
            collectPaths [] paths newops       = LvmPath (unwordsBy ":" paths) : newops              
            collectPaths (LvmPath path : rest) paths newops
                                               = collectPaths rest (path : paths) newops
            collectPaths (opt : rest) paths newops
                                               = collectPaths rest paths (opt : newops)                                   
            keepFirst fromList []              = []
            keepFirst fromList (opt : rest)    = if (opt `elem` fromList) then
                                                   opt : optionFilter fromList rest
                                                 else
                                                   opt : keepFirst fromList rest
            optionFilter fromList []           = []
            optionFilter fromList (opt : rest) = if (opt `elem` fromList) then
                                                   optionFilter fromList rest
                                                 else
                                                   opt : optionFilter fromList rest

terminateWithMessage :: [Option] -> String -> [String] -> IO ([Option], Maybe String)
terminateWithMessage options message errors = do
    let experimentalOptions = ExperimentalOptions `elem` options
    let moreOptions         = MoreOptions `elem` options || experimentalOptions
    putStrLn message
    putStrLn (unlines errors)
    putStrLn $ "Helium compiler " ++ version
    putStrLn (usageInfo "Usage: helium [options] file [options]" (optionDescription moreOptions experimentalOptions))
    exitWith (ExitFailure 1)

processTexthintArgs :: [String] -> IO ([Option], Maybe String)
processTexthintArgs = basicProcessArgs 

processHeliumArgs :: [String] -> IO ([Option], Maybe String)
processHeliumArgs args = do
    (options, maybeFiles) <- basicProcessArgs args
    case maybeFiles of
        Nothing ->
          terminateWithMessage options "Error in invocation: the name of the module to be compiled seems to be missing." []
        Just x ->
          return (options, maybeFiles)

-- The Maybe String indicates that a file may be missing                                           
basicProcessArgs :: [String] -> IO ([Option], Maybe String)
basicProcessArgs args =
    let (options, arguments, errors) = getOpt Permute (optionDescription True True) args
    in if not (null errors) then do
          terminateWithMessage options "Error in invocation: list of parameters is erroneous.\nProblem(s):" 
                               (map ("  " ++) errors)
    else
        if (length arguments > 1) then
            terminateWithMessage options ("Error in invocation: only one non-option parameter expected, but found instead:\n" ++ (unlines (map ("  "++) arguments))) []
        else 
            do 
              let simpleOptions = simplifyOptions options
              when (Verbose `elem` simpleOptions) $
                putStrLn ("Options after simplification: " ++ (show simpleOptions)++"\n")
              let argument = if null arguments then Nothing else Just (head arguments)
              return (simpleOptions, argument)

optionDescription moreOptions experimentalOptions =
      -- Main options
      [ Option "b" [flag BuildOne]                      (NoArg BuildOne) "recompile module even if up to date"
      , Option "B" [flag BuildAll]                      (NoArg BuildAll) "recompile all modules even if up to date"
      , Option "i" [flag DumpInformationForThisModule]  (NoArg DumpInformationForThisModule) "show information about this module"
      , Option "I" [flag DumpInformationForAllModules]  (NoArg DumpInformationForAllModules) "show information about all imported modules"
      , Option ""  [flag EnableLogging]                 (NoArg EnableLogging) "enable logging, overrides previous disable-logging"
      , Option ""  [flag DisableLogging]                (NoArg DisableLogging) "disable logging (default), overrides previous enable-logging flags"
      , Option "a" [flag AlertLogging]                  (NoArg AlertLogging) "compiles with alert flag in logging, overrides all disable-logging flags"
      , Option ""  [flag Overloading]                   (NoArg Overloading) "turn overloading on (default), overrides all previous no-overloading flags"
      , Option ""  [flag NoOverloading]                 (NoArg NoOverloading) "turn overloading off, overrides all previous overloading flags"
      , Option "P" [flag (LvmPath "_")]                 (ReqArg LvmPath "PATH") "use PATH as search path"
      , Option "v" [flag Verbose]                       (NoArg Verbose) "show the phase the compiler is in"
      , Option "w" [flag NoWarnings]                    (NoArg NoWarnings) "do notflag warnings"
      , Option "X" [flag MoreOptions]                   (NoArg MoreOptions) "show more compiler options"
      , Option ""  [flag (Information "_")]             (ReqArg Information "NAME") "display information about NAME"
      
      ]
      ++
      -- More options
      if not moreOptions then [] else
      [ Option "1" [flag StopAfterParser]               (NoArg StopAfterParser) "stop after parsing"
      , Option "2" [flag StopAfterStaticAnalysis]       (NoArg StopAfterStaticAnalysis) "stop after static analysis"
      , Option "3" [flag StopAfterTypeInferencing]      (NoArg StopAfterTypeInferencing) "stop after type inferencing"
      , Option "4" [flag StopAfterDesugar]              (NoArg StopAfterDesugar) "stop after desugaring into Core"    
      , Option "t" [flag DumpTokens]                    (NoArg DumpTokens) "dump tokens to screen"
      , Option "u" [flag DumpUHA]                       (NoArg DumpUHA) "pretty print abstract syntax tree"
      , Option "c" [flag DumpCore]                      (NoArg DumpCore) "pretty print Core program"
      , Option "C" [flag DumpCoreToFile]                (NoArg DumpCoreToFile) "write Core program to file"
      , Option ""  [flag DebugLogger]                   (NoArg DebugLogger) "show logger debug information"
      , Option ""  [flag (HostName "_")]                (ReqArg HostName "HOST") ("specify which HOST to use for logging (default " ++ loggerDEFAULTHOST ++ ")")
      , Option ""  [flag (PortNr 0)]                    (ReqArg selectPortNr "PORT") ("select the PORT number for the logger (default: " ++ show loggerDEFAULTPORT ++ ")")
      , Option "d" [flag DumpTypeDebug]                 (NoArg DumpTypeDebug) "debug constraint-based type inference"         
      , Option "W" [flag AlgorithmW]                    (NoArg AlgorithmW) "use bottom-up type inference algorithm W"
      , Option "M" [flag AlgorithmM ]                   (NoArg AlgorithmM) "use folklore top-down type inference algorithm M"
      , Option ""  [flag DisableDirectives]             (NoArg DisableDirectives) "disable type inference directives"
      , Option ""  [flag NoRepairHeuristics]            (NoArg NoRepairHeuristics) "don't suggest program fixes"
      ]
      ++
      -- Experimental options
      if not experimentalOptions then [] else
      [ Option "" [flag ExperimentalOptions]            (NoArg ExperimentalOptions) "show experimental compiler options"
      , Option "" [flag KindInferencing]                (NoArg KindInferencing) "perform kind inference (experimental)"
      , Option "" [flag SignatureWarnings]              (NoArg SignatureWarnings) "warn for too specific signatures (experimental)" 
      , Option "" [flag RightToLeft]                    (NoArg RightToLeft) "right-to-left treewalk"
      , Option "" [flag NoSpreading]                    (NoArg NoSpreading) "do not spread type constraints (experimental)"
      , Option "" [flag TreeWalkTopDown]                (NoArg TreeWalkTopDown) "top-down treewalk"
      , Option "" [flag TreeWalkBottomUp]               (NoArg TreeWalkBottomUp) "bottom up-treewalk"
      , Option "" [flag TreeWalkInorderTopFirstPre]     (NoArg TreeWalkInorderTopFirstPre) "treewalk (top;upward;child)"
      , Option "" [flag TreeWalkInorderTopLastPre]      (NoArg TreeWalkInorderTopLastPre) "treewalk (upward;child;top)"
      , Option "" [flag TreeWalkInorderTopFirstPost]    (NoArg TreeWalkInorderTopFirstPost) "treewalk (top;child;upward)"
      , Option "" [flag TreeWalkInorderTopLastPost]     (NoArg TreeWalkInorderTopLastPost) "treewalk (child;upward;top)"
      , Option "" [flag SolverSimple]                   (NoArg SolverSimple) "a simple constraint solver"
      , Option "" [flag SolverGreedy]                   (NoArg SolverGreedy) "a fast constraint solver"
      , Option "" [flag SolverTypeGraph]                (NoArg SolverTypeGraph) "type graph constraint solver"
      , Option "" [flag SolverCombination]              (NoArg SolverCombination) "switches between \"greedy\" and \"type graph\""
      , Option "" [flag SolverChunks]                   (NoArg SolverChunks) "solves chunks of constraints (default)"
      , Option "" [flag UnifierHeuristics]              (NoArg UnifierHeuristics)  "use unifier heuristics (experimental)"
      , Option "" [flag (SelectConstraintNumber 0)]     (ReqArg selectCNR "CNR") "select constraint number to be reported"
      ]


data Option 
   -- Main options
   = BuildOne | BuildAll | DumpInformationForThisModule | DumpInformationForAllModules
   | DisableLogging | EnableLogging | AlertLogging | Overloading | NoOverloading | LvmPath String | Verbose | NoWarnings | MoreOptions
   | Information String
   -- More options
   | StopAfterParser | StopAfterStaticAnalysis | StopAfterTypeInferencing | StopAfterDesugar
   | DumpTokens | DumpUHA | DumpCore | DumpCoreToFile 
   | DebugLogger | HostName String | PortNr Int 
   | DumpTypeDebug | AlgorithmW | AlgorithmM | DisableDirectives | NoRepairHeuristics
   -- Experimental options
   | ExperimentalOptions | KindInferencing | SignatureWarnings | RightToLeft | NoSpreading
   | TreeWalkTopDown | TreeWalkBottomUp | TreeWalkInorderTopFirstPre | TreeWalkInorderTopLastPre
   | TreeWalkInorderTopFirstPost | TreeWalkInorderTopLastPost | SolverSimple | SolverGreedy
   | SolverTypeGraph | SolverCombination | SolverChunks | UnifierHeuristics
   | SelectConstraintNumber Int
 deriving (Eq)

stripShow :: String -> String
stripShow name = 
  let 
    parts = words name
  in 
    if null parts then 
      ""
    else
      let
        hd = head parts
      in 
        case hd of
          ('-':('-':rest)) -> rest
          _                -> error ("illegal parameter name " ++ hd)

flag = stripShow . show

instance Show Option where
 show BuildOne                           = "--build"
 show BuildAll                           = "--build-all"
 show DumpInformationForThisModule       = "--dump-information"
 show DumpInformationForAllModules       = "--dump-all-information"
 show EnableLogging                      = "--enable-logging"
 show DisableLogging                     = "--disable-logging"
 show AlertLogging                       = "--alert"
 show Overloading                        = "--overloading"
 show NoOverloading                      = "--no-overloading"
 show (LvmPath str)                      = "--lvmpath "++str
 show Verbose                            = "--verbose"
 show NoWarnings                         = "--no-warnings"
 show MoreOptions                        = "--moreoptions"
 show (Information str)                  = "--info "++str
 show StopAfterParser                    = "--stop-after-parsing"
 show StopAfterStaticAnalysis            = "--stop-after-static-analysis"
 show StopAfterTypeInferencing           = "--stop-after-type-inferencing"
 show StopAfterDesugar                   = "--stop-after-desugaring"
 show DumpTokens                         = "--dump-tokens"
 show DumpUHA                            = "--dump-uha"
 show DumpCore                           = "--dump-core"
 show DumpCoreToFile                     = "--save-core"
 show DebugLogger                        = "--debug-logger"
 show (HostName host)                    = "--hostshow " ++ host
 show (PortNr port)                      = "--portnumber" ++ (show port)
 show DumpTypeDebug                      = "--type-debug"
 show AlgorithmW                         = "--algorithm-w"
 show AlgorithmM                         = "--algorithm-m"
 show DisableDirectives                  = "--no-directives"
 show NoRepairHeuristics                 = "--no-repair-heuristics"
 show ExperimentalOptions                = "--experimental-options"
 show KindInferencing                    = "--kind-inferencing"
 show SignatureWarnings                  = "--signature-warnings"
 show RightToLeft                        = "--right-to-left"
 show NoSpreading                        = "--no-spreading"
 show TreeWalkTopDown                    = "--treewalk-topdown"
 show TreeWalkBottomUp                   = "--treewalk-bottomup"
 show TreeWalkInorderTopFirstPre         = "--treewalk-inorder1"
 show TreeWalkInorderTopLastPre          = "--treewalk-inorder2"
 show TreeWalkInorderTopFirstPost        = "--treewalk-inorder3"
 show TreeWalkInorderTopLastPost         = "--treewalk-inorder4"
 show SolverSimple                       = "--solver-simple"
 show SolverGreedy                       = "--solver-greedy"
 show SolverTypeGraph                    = "--solver-typegraph"
 show SolverCombination                  = "--solver-combination"
 show SolverChunks                       = "--solver-chunks"     
 show UnifierHeuristics                  = "--unifier-heuristics"
 show (SelectConstraintNumber cnr)       = "--select-cnr " ++ (show cnr)

lvmPathFromOptions :: [Option] -> Maybe String
lvmPathFromOptions [] = Nothing
lvmPathFromOptions (LvmPath s : _) = Just s
lvmPathFromOptions (_ : rest) = lvmPathFromOptions rest


-- Takes the first in the list. Better to remove duplicates!
hostNameFromOptions :: [Option] -> Maybe String
hostNameFromOptions [] = Nothing
hostNameFromOptions (HostName s : _) = Just s
hostNameFromOptions (_ : rest) = hostNameFromOptions rest

-- Takes the first in the list. Better to remove duplicates!
portNrFromOptions :: [Option] -> Maybe Int
portNrFromOptions [] = Nothing
portNrFromOptions (PortNr pn: _) = Just pn
portNrFromOptions (_ : rest) = portNrFromOptions rest

selectPortNr :: String -> Option
selectPortNr pn 
   | all isDigit pn = PortNr (read ('0':pn)) 
   | otherwise     = PortNr (-1) -- problem with argument
   
selectCNR :: String -> Option
selectCNR s
   | all isDigit s = SelectConstraintNumber (read ('0':s)) 
   | otherwise     = SelectConstraintNumber (-1) -- problem with argument
