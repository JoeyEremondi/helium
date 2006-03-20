{-| Module      :  PhaseStaticChecks
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
-}

module PhaseStaticChecks(phaseStaticChecks) where

import CompileUtils
import Warnings(Warning)
import StaticErrors(errorsLogCode)
import qualified StaticChecks(sem_Module)
import UHA_Syntax (Name)
import Top.Types (TpScheme)

phaseStaticChecks :: String -> [String] -> Module -> [ImportEnvironment] -> 
                        [Option] -> IO (ImportEnvironment, [(Name,TpScheme)], [Warning])
phaseStaticChecks fullName doneModules module_ importEnvs options = do
    enterNewPhase "Static checking" options

    let (_, baseName, _) = splitFilePath fullName

        (localEnv, errors, _, typeSignatures, warnings) =
            StaticChecks.sem_Module module_ baseName importEnvs options

    when (not (null errors)) $ do
        when (DumpInformationForAllModules `elem` options) $
            putStrLn (show (foldr combineImportEnvironments 
                emptyEnvironment importEnvs))
        unless (NoLogging `elem` options) $ 
            sendLog ("S"++errorsLogCode errors) fullName doneModules options
        showErrorsAndExit errors 20 options
    
    return (localEnv, typeSignatures, warnings)
