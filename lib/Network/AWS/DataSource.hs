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
    fetchAWSIn,
    uncachedFetchAWSIn,
    fetchAllAWSIn,
    uncachedFetchAllAWSIn,
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
        => Maybe Region -> req -> AWSReq (Rs req)
    AWSReqAll
        :: ( AWSPager req
           , Show req
           , Typeable req
           , Eq req
           )
        => Maybe Region -> req -> AWSReq [Rs req]

deriving instance Show (AWSReq res)

instance Eq (AWSReq res) where
    r1 == r2 = case (r1, r2) of
        (AWSReq reg1 r1', AWSReq reg2 r2') -> (reg1==reg2) && typedEQ r1' r2'
        (AWSReqAll reg1 r1', AWSReqAll reg2 r2') -> (reg1==reg2) && typedEQ r1' r2'
        _ -> False
      where
        typedEQ r1' r2' =
            let m_eq = do
                    r2'' <- cast r2'
                    Just $ r1' == r2''
            in fromMaybe False m_eq

instance Hashable (AWSReq res) where
    hashWithSalt salt (AWSReq reg req)    = hashWithSalt salt (0::Int, reg, show req, typeOf req)
    hashWithSalt salt (AWSReqAll reg req) = hashWithSalt salt (1::Int, reg, show req, typeOf req)

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
                    AWSReq Nothing req -> send req
                    AWSReq (Just reg) req -> within reg $ send req
                    AWSReqAll Nothing req -> paginate req $$ consume
                    AWSReqAll (Just reg) req -> within reg $ paginate req $$ consume
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
fetchAWS req = dataFetch (AWSReq Nothing req)

-- | Sends an 'AWSRequest' in a specific region.
--
-- The result will be cached. This should only be used for read-only access.
fetchAWSIn
    :: ( AWSRequest a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq (Rs a)
       )
    => Region -> a -> GenHaxl u (Rs a)
fetchAWSIn region req = dataFetch (AWSReq (Just region) req)

-- | Uncached version of 'fetchAWS'
uncachedFetchAWS
    :: ( AWSRequest a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq (Rs a)
       )
    => a -> GenHaxl u (Rs a)
uncachedFetchAWS req = uncachedRequest (AWSReq Nothing req)

-- | Uncached version of 'fetchAWSIn'
uncachedFetchAWSIn
    :: ( AWSRequest a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq (Rs a)
       )
    => Region -> a -> GenHaxl u (Rs a)
uncachedFetchAWSIn region req = uncachedRequest (AWSReq (Just region) req)

-- | Sends requests necessary to fetch all result pages of a 'AWSRequest'
--
-- The result will be cached. This should only be used for read-only access.
fetchAllAWS
    :: ( AWSPager a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq [Rs a]
       )
    => a -> GenHaxl u [Rs a]
fetchAllAWS req = dataFetch (AWSReqAll Nothing req)

-- | Sends requests necessary to fetch all result pages of a 'AWSRequest'
-- in a specific region.
--
-- The result will be cached. This should only be used for read-only access.
fetchAllAWSIn
    :: ( AWSPager a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq [Rs a]
       )
    => Region -> a -> GenHaxl u [Rs a]
fetchAllAWSIn region req = dataFetch (AWSReqAll (Just region) req)

-- | Uncached version of 'fetchAllAWS'
uncachedFetchAllAWS
    :: ( AWSPager a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq [Rs a]
       )
    => a -> GenHaxl u [Rs a]
uncachedFetchAllAWS req = uncachedRequest (AWSReqAll Nothing req)

-- | Uncached version of 'fetchAllAWSIn'
uncachedFetchAllAWSIn
    :: ( AWSPager a
       , Show a
       , Typeable a
       , Eq a
       , Haxl.Request AWSReq [Rs a]
       )
    => Region -> a -> GenHaxl u [Rs a]
uncachedFetchAllAWSIn region req = uncachedRequest (AWSReqAll (Just region) req)
