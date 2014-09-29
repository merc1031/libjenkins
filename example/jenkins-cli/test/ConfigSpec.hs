{-# LANGUAGE OverloadedStrings #-}
module ConfigSpec (spec) where

import           Control.Lens
import           Data.Aeson
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           Jenkins.Rest as Jenkins
import           Test.Hspec.Lens

import           Config


spec :: Spec
spec = do
  it "parses default configuration" $ do
    let configJson = Text.unlines
          [ "{ \"url\": \"http://example.com/jenkins\""
          , ", \"port\": 80"
          , ", \"user\": \"jenkins\""
          , ", \"api-token\": \"12345678\""
          , "}"
          ]
        config = Config
          { _unConfig = Jenkins.ConnectInfo
            { _jenkinsUrl = "http://example.com/jenkins"
            , _jenkinsPort = 80
            , _jenkinsUser = "jenkins"
            , _jenkinsApiToken = "12345678"
            }
          }
    decodeStrict (Text.encodeUtf8 configJson) `shouldHave` _Just.only config

  it "parses custom configuration" $ do
    let customConfigText = Text.unlines
          [ "{ \"url\": \"https://google.com/hudson\""
          , ", \"port\": 443"
          , ", \"user\": \"google\""
          , ", \"api-token\": \"87654321\""
          , "}"
          ]
        customConfig = Config
          { _unConfig = Jenkins.ConnectInfo
            { _jenkinsUrl = "https://google.com/hudson"
            , _jenkinsPort = 443
            , _jenkinsUser = "google"
            , _jenkinsApiToken = "87654321"
            }
          }
    decodeStrict (Text.encodeUtf8 customConfigText) `shouldHave` _Just.only customConfig