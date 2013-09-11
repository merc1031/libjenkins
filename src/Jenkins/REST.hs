{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
module Jenkins.REST where

import           Control.Concurrent.Async (mapConcurrently)
import           Control.Exception (try, toException)
import           Control.Lens
import           Control.Applicative (Applicative(..))
import           Control.Monad.Free.Church (F, iterM, liftF)
import           Control.Monad.Trans.Control (liftWith, restoreT)
import           Control.Monad.IO.Class (MonadIO(..))
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import           Data.Conduit (ResourceT)
import           Network.HTTP.Conduit
  ( Manager, Request, RequestBody(..), HttpException
  , withManager, applyBasicAuth, httpLbs, parseUrl, responseBody
  , HttpException(..)
  )
import           Network.HTTP.Types
  (Status(..))
import qualified Network.HTTP.Conduit.Lens as L

import           Jenkins.REST.Method

{-# ANN module ("HLint: Use const" :: String) #-}


newtype Jenkins a = Jenkins { unJenkins :: F JenkinsF a }

instance Functor Jenkins where
  fmap f = Jenkins . fmap f . unJenkins
  {-# INLINE fmap #-}

instance Applicative Jenkins where
  pure = Jenkins . pure
  {-# INLINE pure #-}
  Jenkins f <*> Jenkins x = Jenkins (f <*> x)
  {-# INLINE (<*>) #-}

instance Monad Jenkins where
  return = pure
  {-# INLINE return #-}
  Jenkins x >>= k = Jenkins (x >>= unJenkins . k)
  {-# INLINE (>>=) #-}

instance MonadIO Jenkins where
  liftIO = liftJ . IO
  {-# INLINE liftIO #-}

-- | 'JenkinsF' terms
data JenkinsF a where
  Get  :: Method Complete f -> (BL.ByteString -> a) -> JenkinsF a
  Post :: (forall f. Method Complete f) -> BL.ByteString -> (BL.ByteString -> a) -> JenkinsF a
  Conc :: [Jenkins b] -> ([b] -> a) -> JenkinsF a
  IO   :: IO a -> JenkinsF a

instance Functor JenkinsF where
  fmap f (Get  m g)      = Get  m      (f . g)
  fmap f (Post m body g) = Post m body (f . g)
  fmap f (Conc ms g)     = Conc ms     (f . g)
  fmap f (IO a)          = IO (fmap f a)
  {-# INLINE fmap #-}


-- | List 'JenkinsF' term to the 'Jenkins' language
liftJ :: JenkinsF a -> Jenkins a
liftJ = Jenkins . liftF
{-# INLINE liftJ #-}


-- | @GET@ query
get :: Method Complete f -> Jenkins BL.ByteString
get m = liftJ $ Get m id
{-# INLINE get #-}

-- | @POST@ query (and payload)
post :: (forall f. Method Complete f) -> BL.ByteString -> Jenkins ()
post m body = liftJ $ Post m body (\_ -> ())
{-# INLINE post #-}

-- | Do a list of queries 'concurrently'
concurrently :: [Jenkins a] -> Jenkins [a]
concurrently js = liftJ $ Conc js id
{-# INLINE concurrently #-}

-- | Lift arbitrary 'IO' action
io :: IO a -> Jenkins a
io = liftIO
{-# INLINE io #-}


type Host     = String
type Port     = Int
type User     = B.ByteString
type Password = B.ByteString
type APIToken = B.ByteString


-- | Communicate with Jenkins REST API. Only catches exceptions from @http-conduit@ package;
-- does not catch exceptions from lifted arbitrary 'IO' actions
jenkins :: Host -> Port -> User -> Password -> Jenkins a -> IO (Either HttpException a)
jenkins h p user password jenk = try . withManager $ \manager -> do
  request <- liftIO $ parseUrl h
  let request' = request
        & L.port            .~ p
        & L.responseTimeout .~ Just (20 * 1000000)
  runIO manager (applyBasicAuth user password request') jenk

runIO :: Manager -> Request (ResourceT IO) -> Jenkins a -> ResourceT IO a
runIO manager request = iterM go . unJenkins where
  go (Get m next) = do
    let request' = request
          & L.path   %~ (`slash` render m)
          & L.method .~ "GET"
    bs <- httpLbs request' manager
    next (responseBody bs)
  go (Post m body next) = do
    let request' = request
          & L.path          %~ (`slash` render m)
          & L.method        .~ "POST"
          & L.requestBody   .~ RequestBodyLBS body
          & L.redirectCount .~ 0
          & L.checkStatus   .~ \s@(Status st _) hs cookie_jar ->
            if 200 <= st && st < 400
                then Nothing
                else Just . toException $ StatusCodeException s hs cookie_jar
    bs <- httpLbs request' manager
    next (responseBody bs)
  go (Conc js next) = do
    xs <- liftWith (\run ->
           mapConcurrently (run . runIO manager request) js)
    ys <- mapM (restoreT . return) xs
    next ys
  go (IO action) = do
    next <- liftIO action
    next