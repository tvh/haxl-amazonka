module Main where

import Network.AWS
import Network.AWS.S3
import Network.AWS.DataSource
import Haxl.Core
import Control.Lens
import Data.Traversable

main :: IO ()
main = do
    aws_env <- newEnv Sydney Discover
    env <- initEnv (stateSet (initGlobalState aws_env) stateEmpty) ()
    res <- runHaxl env{flags = Flags 3 1} $ do
        buckets_response <- fetchAWS listBuckets
        let buckets = buckets_response ^. lbrsBuckets
        flip traverse buckets $ \bucket -> do
            let name = bucket ^. bName
            location_response <- fetchAWS $ getBucketLocation name
            return (name, location_response ^. grsLocationConstraint)
    print res
