{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
module Jenkins.RestSpec (spec) where

import           Control.Applicative
import           Control.Monad.Trans.State (State, evalState, get, put)
import qualified Data.ByteString as Strict
import qualified Data.ByteString.Lazy as Lazy
import           Data.Functor.Identity (Identity)
import           Data.Monoid (mempty)
import           Test.Hspec
import qualified Jenkins.Rest as Jenkins
import           Jenkins.Rest.Internal
import qualified Jenkins.Rest.Method.Internal as Method


spec :: Spec
spec = do
  context "POST requests" $ do
    it "post_ sends POST request with empty body" $ do
      interpret $ do
        Jenkins.post_ "foo"
        Jenkins.post_ "bar"
        Jenkins.post_ "baz"
     `shouldBe`
      [QPost 0 "" "foo", QPost 1 "" "bar", QPost 2 "" "baz"]

    it "post sends POST request with non-empty body" $ do
      interpret $ do
        Jenkins.post "foo" "qux"
        Jenkins.post "bar" "quux"
        Jenkins.post "baz" "xyzzy"
     `shouldBe`
      [QPost 0 "qux" "foo", QPost 1 "quux" "bar", QPost 2 "xyzzy" "baz"]

  context "GET requests" $
    it "get sends GET requests" $ do
      interpret $ do
        Jenkins.get Jenkins.plain "foo"
        Jenkins.get Jenkins.plain "bar"
        Jenkins.get Jenkins.plain "baz"
     `shouldBe`
      [QGet 0 "foo", QGet 1 "bar", QGet 2 "baz"]


  describe "reload" $
    it "calls $jenkins_url/reload with POST query and then disconnects" $ do
      interpret $ do
        Jenkins.reload
        Jenkins.post_ "foo"
     `shouldBe`
      [QPost 0 "" "reload", QDisconnect]

  describe "restart" $
    it "calls $jenkins_url/safeRestart with POST query and then disconnects" $ do
      interpret $ do
        Jenkins.restart
        Jenkins.post_ "bar"
     `shouldBe`
      [QPost 0 "" "safeRestart", QDisconnect]

  describe "forceRestart" $
    it "calls $jenkins_url/restart with POST query and then disconnects" $ do
      interpret $ do
        Jenkins.forceRestart
        Jenkins.post_ "baz"
     `shouldBe`
      [QPost 0 "" "restart", QDisconnect]


data Query =
    QGet Int Strict.ByteString
  | QPost Int Lazy.ByteString Strict.ByteString
  | QDisconnect
    deriving (Show, Eq)

newtype Requests a = Requests [a]
  deriving (Show, Eq)

interpret :: JenkinsT Identity a -> [Query]
interpret adt = evalState (iter go ([] <$ adt)) (Requests [0..]) where
  go :: JF Identity (State (Requests Int) [Query]) -> State (Requests Int) [Query]
  go (Get m n) = do
    r <- render QGet m
    fmap (r :) (n mempty)
  go (Post m body n) = do
    r <- render (\x y -> QPost x body y) m
    fmap (r :) (n mempty)
  go Dcon =
    return [QDisconnect]

render :: (a -> Strict.ByteString -> Query) -> Jenkins.Method Method.Complete f -> State (Requests a) Query
render f m = do
  n <- next
  return $ f n (Method.render m)

next :: State (Requests a) a
next = do
  Requests (x:xs) <- get
  put (Requests xs)
  return x