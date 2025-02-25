{-# OPTIONS_GHC -O0 #-}

module UserSettings (
    userFlavours, userPackages, userDefaultFlavour,
    verboseCommand, buildProgressColour, successColour, finalStage
    ) where

import qualified Data.Set as Set

import Oracles.Flag
import Flavour.Type
import Expression
import {-# SOURCE #-} Settings.Default

userDefaultFlavour :: String
userDefaultFlavour = "default"

userFlavours :: [Flavour]
userFlavours = [userFlavour]

-- Define a custom flavour which disables problamatic dynamic ways of rts.
-- This is a very minimal flavour, only building 'vanilla'.
userFlavour :: Flavour
userFlavour = defaultFlavour {
  name = "custom-i686",
  extraArgs = performanceArgs,
  libraryWays = pure (Set.fromList [vanilla]),
  dynamicGhcPrograms = return False,
  rtsWays = Set.fromList <$>
  mconcat [
    pure [vanilla],
    notStage0 ? targetSupportsThreadedRts ? pure [threaded]
  ]
}

-- This is from `Settings/Flavours/Performance.hs`
performanceArgs :: Args
performanceArgs = sourceArgs SourceArgs
    { hsDefault  = pure ["-O", "-H64m"]
    , hsLibrary  = orM [notStage0, cross] ? arg "-O2"
    , hsCompiler = pure ["-O2"]
    , hsGhc      = mconcat
                    [ andM [stage0, notCross] ? arg "-O"
                    , orM  [notStage0, cross] ? arg "-O2"
                    ]
    }

userPackages :: [Package]
userPackages = []

verboseCommand :: Predicate
verboseCommand = do
    verbosity <- expr getVerbosity
    return $ verbosity >= Verbose

buildProgressColour :: BuildProgressColour
buildProgressColour = mkBuildProgressColour (Dull Magenta)

successColour :: SuccessColour
successColour = mkSuccessColour (Dull Green)

finalStage :: Stage
finalStage = Stage2
