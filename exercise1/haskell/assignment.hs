{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

import Prelude ()
import Prelude.Compat

import Data.Aeson
import Control.Monad.Except
import GHC.Generics
import Network.Wai
import Network.Wai.Handler.Warp
import Servant
import System.Directory
import qualified System.IO.Strict as Strict
import qualified Data.ByteString.Lazy.Char8 as BS

-- | 1. Hello world!

type HelloAPI = Get '[PlainText] String
hello :: String
hello = "hello world!"

-- | 2-3. Static file

type FileAPI = Get '[JSON] FileContent

newtype FileContent = FileContent String deriving Generic
instance ToJSON FileContent

-- | Update count in serialized 'FileData' instance.
-- Returns 'Nothing' if parsing of 'content' to 'FileData' instance fails.
incCount :: String -> Maybe String
incCount content = (BS.unpack . encode . inc) <$> mfd
  where mfd :: Maybe FileData
        mfd = decode $ BS.pack content
        inc :: FileData -> FileData
        inc fd = fd { count = (count fd) + 1 }

-- | Serve and update contents of file in 'path'.
-- Only updates the contents if it forms a valid JSON serialization of
-- a 'FileData' object. If it is, it increments the count field in
-- the file by 1.
fileServer :: FilePath -> Server FileAPI
fileServer path = do
  exists <- liftIO (doesFileExist path)
  if exists
     then do
          -- read contents from file (strictly, we are writing to the same file soon)
          content <- liftIO (Strict.readFile path)
          case incCount content of
            -- write if succesfully parsed and updated, do nothing otherwise
            Just content' -> liftIO (writeFile path content')
            Nothing -> return ()
          -- have webserver serve the file's contents
          return (FileContent content)
     else throwError custom404Err
  where custom404Err = err404 { errBody = "could not find file." }

data FileData = FileData {
  count :: Int,
  -- underscore to suppress 'defined but not used' warning
  _name :: String
}

-- | Boilerplate to allow deserialization of JSON-ized 'FileData' objects.
-- Boilerplate is avoidable, but requires another language extension.
instance FromJSON FileData where
    parseJSON (Object v) = FileData <$>
                           v .: "count" <*>
                           v .: "name"
    -- Any non Object value is of the wrong type, so fail.
    parseJSON _          = mzero


-- | Boilerplate to allow serialization of JSON-ized 'FileData' objects.
instance ToJSON FileData where
    toJSON (FileData c n) = object ["name" .= n, "count" .= c]

-- | Combining both into a single API

type API = HelloAPI :<|> ("count" :> FileAPI)

api :: Proxy API
api = Proxy

server :: FilePath -> Server API
server path = return hello :<|> fileServer path

app :: FilePath -> Application
app path = serve api (server path)

main :: IO ()
main = run 8081 (app "count.json")
