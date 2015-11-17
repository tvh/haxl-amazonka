{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TypeFamilies          #-}
{-# OPTIONS_GHC -Wall #-}
module Network.AWS.DataSource (
    AWSReq(..),
    initGlobalState,
    fetchAWS,
    uncachedFetchAWS,
    fetchAllAWS,
    uncachedFetchAllAWS,
) where

import           Control.Concurrent.Async
import           Control.Exception        as E
import           Control.Monad
import           Control.Monad.IO.Class
import           Data.Conduit
import           Data.Conduit.List
import           Data.Hashable
import           Data.Maybe
import           Data.Typeable
import           Haxl.Core                as Haxl
import           Network.AWS              as AWS

data AWSReq res where
    AWSReq
        :: ( AWSRequest req
           , Show req
           , Typeable req
           , Eq req
           )
        => req -> AWSReq (Rs req)
    AWSReqAll
        :: ( AWSPager req
           , Show req
           , Typeable req
           , Eq req
           )
        => req -> AWSReq [(Rs req)]

deriving instance Show (AWSReq res)

instance Eq (AWSReq res) where
    r1 == r2 = case (r1, r2) of
        (AWSReq r1', AWSReq r2') -> typedEQ r1' r2'
        (AWSReqAll r1', AWSReqAll r2') -> typedEQ r1' r2'
        _ -> False
      where
        typedEQ r1' r2' =
            let m_eq = do
                    r2'' <- cast r2'
                    Just $ r1' == r2''
            in fromMaybe False m_eq

instance Hashable (AWSReq res) where
    hashWithSalt salt (AWSReq req)    = hashWithSalt salt (0::Int, show req, typeOf req)
    hashWithSalt salt (AWSReqAll req) = hashWithSalt salt (1::Int, show req, typeOf req)

instance DataSourceName AWSReq where
    dataSourceName _ = "AWS"

instance Show1 AWSReq where
    show1 = show

instance StateKey AWSReq where
    data State AWSReq = AWSState AWS.Env

instance DataSource u AWSReq where
    fetch (AWSState aws_env) _ _ blocked_fetches = AsyncFetch $ \inner -> do
        reqs <- forM blocked_fetches $ \(BlockedFetch aws_req result) ->
            async $ do
                res <- E.try $ runResourceT $ runAWS aws_env $ case aws_req of
                    AWSReq req -> send req
                    AWSReqAll req -> paginate req $$ consume
                liftIO $ putResult result res
        forM_ (reqs :: [Async ()]) link
        inner
        forM_ reqs wait

-- | Construct a global state to use in Haxl.
initGlobalState :: AWS.Env -> State AWSReq
initGlobalState aws_env = AWSState aws_env

-- | Sends an 'AWSRequest'.
--
-- The result will be cached. This should only be used for read-only access.
fetchAWS
    :: ( AWSRequest a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq (Rs a)
       )
    => a -> GenHaxl u (Rs a)
fetchAWS req = dataFetch (AWSReq req)

-- | Uncached version of 'fetchAWS'
uncachedFetchAWS
    :: ( AWSRequest a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq (Rs a)
       )
    => a -> GenHaxl u (Rs a)
uncachedFetchAWS req = uncachedRequest (AWSReq req)

-- | Sends requests necessary to fetch all result pages of a 'AWSRequest'
--
-- The result will be cached. This should only be used for read-only access.
fetchAllAWS
    :: ( AWSPager a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq [(Rs a)]
       )
    => a -> GenHaxl u [(Rs a)]
fetchAllAWS req = dataFetch (AWSReqAll req)

-- | Uncached version of 'fetchAllAWS'
uncachedFetchAllAWS
    :: ( AWSPager a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq [(Rs a)]
       )
    => a -> GenHaxl u [(Rs a)]
uncachedFetchAllAWS req = uncachedRequest (AWSReqAll req)
