{-# LANGUAGE GADTs, FlexibleInstances, MultiParamTypeClasses, OverloadedStrings, TypeFamilies #-}
module Network.AWS.DataSource where

import Control.Monad.IO.Class
import Control.Monad
import Data.Monoid
import Data.Typeable
import Network.AWS as AWS
import Haxl.Core
import Control.Concurrent.Async

data AWSReq res where
    AWSReq :: (AWSRequest req, Show req) => req -> AWSReq (Rs req)
  deriving Typeable

instance Show (AWSReq req) where
    show (AWSReq req) = "(AWSReq " <> show req <> ")"

instance DataSourceName AWSReq where
    dataSourceName _ = "AWS"

instance StateKey AWSReq where
    data State AWSReq = AWSKey

instance Show1 AWSReq where
    show1 = show

instance (HasEnv u) => DataSource u AWSReq where
    fetch _ _ env blocked_fetches = SyncFetch $ do
        runResourceT . runAWS env . forM_ blocked_fetches $ \blocked_fetch -> do
            () <- case blocked_fetch of
                BlockedFetch (AWSReq request) result ->
                    liftIO . putSuccess result =<< send request
            return ()
