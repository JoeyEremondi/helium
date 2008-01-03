{-| Module      :  Main
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
    
    The textual Helium interpreter

-}

module Main where

import Char
import List(isPrefixOf, isSuffixOf)
import Monad(when)
import IO(stdout, hFlush)
import System(system, getEnv, getArgs, exitWith, ExitCode(..))
import OSSpecific(slash)
import Directory
import ConfigFile(Config, readConfig)

-- Constants for configuration files
configFilename = ".hint.conf" 
basepathKey    = "basepath"
temppathKey    = "temppath"
unknown        = "<unknown>"
passToHelium   = ["overloading", "loggingon", "lvmpaths", "additionalHeliumParameters"]

data State = 
    State
    { maybeModName :: Maybe String
    , maybeFileName :: Maybe String
    , tempDir :: String
    , binDir :: String
    , compOptions :: [String] -- Contains both options for helium as well as lvmrun. 
            -- For lvmrun only the -P options are selected to be passed on 
    }

unwordsBy :: String -> [String] -> String
unwordsBy sep [] = ""
unwordsBy sep [w] = w
unwordsBy sep (w:ws) = w ++ sep ++ unwordsBy sep ws

header :: String
header = unlines
    [ " _          _ _                 "
    , "| |        | (_)                   "
    , "| |__   ___| |_ _   _ _ __ ___     -- Welcome to the Helium interpreter --"
    , "| '_ \\ / _ \\ | | | | | '_ ` _ \\    ---------------------------------------"
    , "| | | |  __/ | | |_| | | | | | |   -- Type an expression to evaluate    --"
    , "|_| |_|\\___|_|_|\\__,_|_| |_| |_|   --    or a command (:? for a list)   --"
    ]

extractOptions :: Config -> [String]
extractOptions []         = []
extractOptions ((k,v):xs) = 
  if k `elem` passToHelium then
      tfm k : rest
  else
      rest
   where
     rest = extractOptions xs
     tfm k = case k of 
               "overloading" -> if v == "false" then
                                   "--no-overloading"
                                else
                                   "--overloading"
               "loggingon"   -> if v == "false" then
                                  "--disable-logging"
                                else
                                   "--enable-logging"
               "lvmpaths"    -> if v == "" then "" else "-P"++v
               "additionalHeliumParameters" -> v


slashify :: String -> String
slashify xs = if last xs == slash then xs else xs ++ [slash]

-- Determines whether the overloading flag is really on (i.e., there is no 
-- such flag, or it is the final one.
addStandardLVMPath :: String -> [String] -> [String]
addStandardLVMPath basepath config = 
  addPreludePath basepath ("-P." : config)
  where
    addPreludePath bp conf 
      | bp == unknown = conf
      | otherwise     = ("-P" ++ bp ++ (slash:"lib") ++ [slash] ++  
                        (if reallyOverloading config then "" else "simple"++[slash])) : config
    reallyOverloading xs =
      let 
        onlyOverloadingFlags = reverse (filter (\x -> x == "--overloading" || x == "--no-overloading") xs)
      in 
        case onlyOverloadingFlags of
           []                   -> True
           ("--overloading":_)  -> True
           _                    -> False

main :: IO ()
main = do
    home <- getEnv "HOME" 
    configInfo <-
        readConfig (home ++ (slash : configFilename))
    let tempDirFromEnv = case lookup temppathKey configInfo of
                           Nothing -> "."
                           Just xs -> xs
    let basepath       = case lookup basepathKey configInfo of
                           Nothing -> unknown
                           Just xs -> xs
    let configOptions  = extractOptions configInfo
    putStrLn (show configOptions) 
    let initialState = 
         State { tempDir = slashify tempDirFromEnv
               , maybeModName = Nothing
               , maybeFileName = Nothing
               , binDir = if basepath == unknown then "" else basepath ++ (slash:"bin") ++ [slash] -- Hope for $PATH
               , compOptions = []
               }
 
    -- Logo
    putStrLn header
    
    -- Load command-line parameter module
    -- If the final parameter happens to refer to a source name, then that file is loaded.
    args <- getArgs
    stateAfterLoad <-
        if length args >= 1 then do
            let filename = last args
                rest = init args
            exists <- doesFileExist filename
            existsWithHs <- doesFileExist (filename ++ ".hs")
            if exists || existsWithHs then
                cmdLoadModule filename (initialState{ compOptions = addStandardLVMPath basepath (configOptions ++ rest) })
              else
                return initialState{ compOptions = addStandardLVMPath basepath (configOptions ++ args) }
        else
            return initialState{ compOptions = addStandardLVMPath basepath configOptions }
    
    -- Enter read-eval-print loop
    loop stateAfterLoad

    return ()

addSlashIfNeeded :: String -> String
addSlashIfNeeded dir = 
    case reverse dir of
        '/' : _ -> dir
        '\\' : _ -> dir
        _ -> dir ++ [slash] -- "\\" for Windows, "/" for UNIX

loop :: State -> IO State
loop state = do
    putStr (prompt state)
    hFlush stdout
    command' <- getLine
    let command = trim command'
    newState <- case command of
        (':':cmd:rest) -> 
            processCommand (toLower cmd) (trim rest) state
        (':':_) -> do
            putStrLn "Expecting command after colon. Type :? for help"
            return state
        expression -> do
            if null expression 
              then return ()
              else processExpression expression state
            return state
    loop newState
  where
    prompt :: State -> String
    prompt State{ maybeModName = Nothing} = "Prelude> "
    prompt State{ maybeModName = Just modName} = modName ++ "> "
  
processCommand :: Char -> String -> State -> IO State
processCommand cmd rest state = 
    case cmd of
        '!' -> cmdSystem       rest state
        't' -> cmdShowType     rest state
        'l' -> cmdLoadModule   rest state
        'r' -> cmdReloadModule      state
        'b' -> cmdBrowse            state
        '?' -> cmdHelp              state
        'q' -> do   putStrLn "[Leaving texthint]"
                    exitWith ExitSuccess
        _   -> do   putStrLn "Command not recognised.  Type :? for help"
                    return state

------------------------
-- Command :!
------------------------
        
cmdSystem :: String -> State -> IO State
cmdSystem command state = do       
    system command
    return state

------------------------
-- Command :t
------------------------

cmdShowType :: String -> State -> IO State
cmdShowType [] state = do
    putStrLn "ERROR: Expecting expression after :t"
    return state
cmdShowType expression state = do
    let moduleContents = expressionModule expression state
    writeInternalModule moduleContents state
    (success, output) <- compileInternalModule "-i" state
    if success then do
        let typeLine = filter (interpreterMain `isPrefixOf`) (map trim (lines output))
        if null typeLine then
            return ()
          else 
            let typeString = 
                      trim
                    . dropWhile (== ':')
                    . dropWhile isSpace
                    . drop (length interpreterMain) 
                    . head
                    $ typeLine
            in do 
                  putStrLn (expression ++ " :: " ++ typeString)
      else
        putStr (removeEvidence output)
    return state

------------------------
-- Command :l 
------------------------

cmdLoadModule :: String -> State -> IO State
cmdLoadModule [] state = -- unload
    return state{maybeModName = Nothing, maybeFileName = Nothing }
cmdLoadModule fileName state = do
    fileExists <- doesFileExist fileName
    if fileExists 
      then loadExistingModule fileName state
      else do
        let fileNameWithHS = fileName ++ ".hs"
        fileExistsWithHS <- doesFileExist fileNameWithHS
        if fileExistsWithHS
          then loadExistingModule fileNameWithHS state
          else do
            putStr $ "ERROR - Unable to open file \"" ++ fileName ++ "\"\n"
            return state

loadExistingModule :: String -> State -> IO State
loadExistingModule fileName state = do
    let (path, baseName, _) = splitFilePath fileName
    when (not (null path)) $
        setCurrentDirectory path
    let newState = state{ maybeModName = Just baseName, maybeFileName = Just fileName }
        moduleContents = expressionModule "()" newState
    writeInternalModule moduleContents newState
    (success, output) <- compileInternalModule "" newState
    putStr (removeEvidence output)
    return newState    

------------------------
-- Command :r
------------------------

cmdReloadModule :: State -> IO State
cmdReloadModule state = 
    case maybeModName state of
        Nothing -> return state
        Just name -> cmdLoadModule name state

------------------------
-- Command :b
------------------------

cmdBrowse :: State -> IO State
cmdBrowse state = 
    case maybeModName state of
        Nothing -> do
            let moduleContents = "import Prelude\n"
            writeInternalModule moduleContents state
            (succes, output) <- compileInternalModule "-I3b" state
            putStr (unlines (safeTail (lines output)))
            return state
        Just modName -> do
            (succes, output) <- compileModule modName "-i3b" state
            putStr (unlines (safeTail (lines output)))
            return state

------------------------
-- Command :?
------------------------

cmdHelp :: State -> IO State
cmdHelp state = do
    putStrLn ":l <filename>    load module"
    putStrLn ":l               unload module"
    putStrLn ":r               reload module"
    putStrLn ":t <expression>  show type of expression"
    putStrLn ":b               browse definitions in current module"
    putStrLn ":! <command>     shell command"
    putStrLn ":q               quit"
    return state

------------------------
-- Expression 
------------------------

processExpression :: String -> State -> IO ()
processExpression expression state = do
    removeLVM state
    let moduleContents = expressionModule expression state
    writeInternalModule moduleContents state
    (success, output) <- compileInternalModule "" state
    putStr (removeEvidence output)
    when success $ 
        executeInternalModule state

------------------------
-- Interpreter module 
------------------------

outputFileName, internalModule, interpreterMain :: String
outputFileName = "___InterpreterOutput.txt"        
internalModule = "___Interpreter"
interpreterMain = "interpreter_main"

internalModulePath :: State -> String
internalModulePath state = tempDir state ++ internalModule

writeInternalModule :: String -> State -> IO ()
writeInternalModule contents state =
    writeModule (internalModulePath state) contents

writeModule :: String -> String -> IO ()
writeModule modulePath contents = do
    let hsFile = modulePath ++ ".hs"
    writeFile hsFile contents
        `catch` (\_ -> fatal ("Unable to write to file \"" ++ hsFile ++ "\""))

compileInternalModule :: String -> State -> IO (Bool, String)
compileInternalModule options state =
    compileModule (internalModulePath state) options state

compileModule :: String -> String -> State -> IO (Bool, String)
compileModule fileName options state = do
    let outputFilePath = tempDir state ++ outputFileName
    exitCode <- sys ("\"" ++ binDir state ++ "helium\" " ++ " " ++ unwords (compOptions state) 
                          ++ " " ++ options ++ " " ++ fileName ++ "> " ++ outputFilePath)
    contents <- readFile outputFilePath
                `catch` (\_ -> fatal ("Unable to read from file \"" ++ outputFilePath ++ "\""))
    return (exitCode == ExitSuccess, contents)

executeInternalModule :: State -> IO ()
executeInternalModule state =
    executeModule (internalModulePath state) state

-- We do compensate for the fact that helium allows -P... and -P ... and that lvmrun only allows the former. 
lvmOptionsFilter :: [String] -> [String]
lvmOptionsFilter []          = []
lvmOptionsFilter ["-P"]      = []
lvmOptionsFilter ("-P" : xs) = (head xs) : lvmOptionsFilter (tail xs)
lvmOptionsFilter (('-' : 'P' : ys) : xs) = ys : lvmOptionsFilter xs
lvmOptionsFilter (x:xs)      = lvmOptionsFilter xs

executeModule :: String -> State -> IO ()
executeModule fileName state = do
    sys ("\"" ++ binDir state ++ "lvmrun\" -P" ++ unwordsBy ":" (lvmOptionsFilter (compOptions state)) ++ " "++ fileName)
    return ()

removeLVM :: State -> IO ()
removeLVM state = do
    let lvmFile = tempDir state ++ internalModule ++ ".lvm"
    lvmExist <- doesFileExist lvmFile
    when lvmExist $ removeFile lvmFile

expressionModule :: String -> State -> String
expressionModule expression state =
    unlines
    (  case maybeModName state of 
        Nothing -> []
        Just name -> [ "import " ++ name ]
    ++ [ interpreterMain ++ " = " ++ expression ]
    )

sys s = do
    -- putStrLn ("System:" ++ s)
    system s

------------------------
-- Remove evidence 
------------------------

-- remove evidence that there is an Interpreter module 
-- that is compiled each time you type an expression
-- or ask for a type

removeEvidence :: String -> String
removeEvidence = 
    unlines . firstState . lines
  where
    firstState :: [String] -> [String]
    firstState [] = []
    firstState (line:lines)
        | "Compiling" `isPrefixOf` line && 
                (internalModule ++ ".hs") `isSuffixOf` line =
            interpreterState [] lines
        | "Compiling" `isPrefixOf` line =
            line : otherModuleState lines
        | "is up to date" `isSuffixOf` line =
            firstState lines
        | otherwise =
            line : firstState lines
    
    interpreterState soFar [] = soFar
    interpreterState soFar (line:lines) 
        | "Compilation successful" `isPrefixOf` line =
            firstState lines
        | "Compilation" `isPrefixOf` line = 
            map removePositions soFar ++ firstState lines
        | otherwise =
            interpreterState (soFar ++ [line]) lines

    otherModuleState [] = []
    otherModuleState (line:lines)  
        | "Compilation" `isPrefixOf` line = 
            line : firstState lines
        | otherwise = 
            line : otherModuleState lines
    
    removePositions line = 
        let (upToColon, rest) = span (/= ':') line
        in if not (all isSpace upToColon) &&
                all (\c -> isDigit c || c `elem` "(), ") upToColon then
            safeTail rest
           else 
            line

------------------------
-- Utility functions 
------------------------

fatal :: String -> IO a
fatal msg = do    
    putStrLn msg
    putStrLn "Make sure that the environment variable TEMP points to a valid directory"
    exitWith (ExitFailure 1)

contains :: Eq a => [a] -> [a] -> Bool
_  `contains` [] = True
[] `contains` _  = False
(large@(_:rest)) `contains` small = 
    small `isPrefixOf` large || rest `contains` small 

safeTail :: [a] -> [a]
safeTail (x:xs) = xs
safeTail [] = []

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

-- Split file name
-- e.g. /docs/haskell/Hello.hs =>
--   filePath = /docs/haskell  baseName = Hello  ext = hs
splitFilePath :: String -> (String, String, String)
splitFilePath filePath = 
    let slashes = "\\/"
        (revFileName, revPath) = span (`notElem` slashes) (reverse filePath)
        (baseName, ext)  = span (/= '.') (reverse revFileName)
    in (reverse revPath, baseName, dropWhile (== '.') ext)

