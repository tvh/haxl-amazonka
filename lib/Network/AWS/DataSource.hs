{-# LANGUAGE GADTs, FlexibleInstances, MultiParamTypeClasses, OverloadedStrings, TypeFamilies, FlexibleContexts #-}
module Network.AWS.DataSource where

import Data.Hashable
import Data.Maybe
import Control.Monad.IO.Class
import Control.Monad
import Data.Monoid
import Data.Typeable
import Network.AWS as AWS
import Haxl.Core as Haxl
import Control.Concurrent.Async
import GHC.Generics

data AWSReq res where
    AWSReq
        :: ( AWSRequest req
           , Show req
           , Typeable req
           , Eq req
           )
        => req -> AWSReq (Rs req)
  deriving (Typeable)

instance Eq (AWSReq res) where
    AWSReq req1 == AWSReq req2 =
        let m_eq = do
                req2' <- cast req2
                return $ req1 == req2'
        in fromMaybe False m_eq

instance Show (AWSReq res) where
    show (AWSReq req) = "(AWSReq " <> show req <> ")"

instance Hashable (AWSReq res) where
    hashWithSalt salt (AWSReq req) = hashWithSalt salt (show req, typeOf req)

instance DataSourceName AWSReq where
    dataSourceName _ = "AWS"

instance Show1 AWSReq where
    show1 = show

instance StateKey AWSReq where
    data State AWSReq = AWSState AWS.Env

instance DataSource u AWSReq where
    fetch (AWSState env) _ _ blocked_fetches = SyncFetch $ do
        runResourceT . runAWS env . forM_ blocked_fetches $ \blocked_fetch -> do
            () <- case blocked_fetch of
                BlockedFetch (AWSReq request) result ->
                    liftIO . putSuccess result =<< send request
            return ()

sendHaxl
    :: ( AWSRequest a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq (Rs a)
       )
    => a -> GenHaxl u (Rs a)
sendHaxl req = dataFetch (AWSReq req)
