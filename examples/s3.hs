module Main where

import Network.AWS
import Network.AWS.S3
import Network.AWS.Data.Text
import Network.AWS.DataSource
import Haxl.Core
import Control.Lens
import Data.Traversable
import Data.Foldable

main :: IO ()
main = do
    aws_env <- newEnv Sydney Discover
    env <- initEnv (stateSet (initGlobalState aws_env) stateEmpty) ()
    res <- runHaxl env{flags = Flags 2 1} $ do
        buckets_response <- fetchAWS listBuckets
        let buckets = buckets_response ^. lbrsBuckets
        for buckets $ \bucket -> do
            let name = bucket ^. bName
            location_response <- fetchAWS $ getBucketLocation name
            let region = location_response ^. grsLocationConstraint . _LocationConstraint
            objects <- fetchAllAWSIn region $ listObjects name
            let num_objs = length $ objects ^.. traversed . lorsContents . traversed
            return ( toText name
                   , num_objs
                   , region
                   )
    for_ res print
