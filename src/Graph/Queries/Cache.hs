module Graph.Queries.Cache
  ( Cache
  , loadAll
  , mkCache
  , mutation
  , Graph.Queries.Cache.query
  ) where

import Protolude

import Graph.Schema hiding (Error)
import GraphQL

import           Data.Attoparsec.Text
import qualified Data.Map              as M
import qualified Data.Text             as T
import           Data.Text.IO          (readFile)
import           GraphQL.Internal.Name (Name(..), makeName)
import           UnliftIO

import Util (traverseDir)

data CacheError = InvalidPathName FilePath | CompilationError QueryError
  deriving (Eq, Show)

data Cache = Cache
  { root :: FilePath
  , schema :: Schema
  , queries :: IORef (Map Name Query)
  }

mkCache :: MonadIO m => Schema -> FilePath -> m Cache
mkCache schema root = Cache 
  <$> pure root
  <*> pure schema
  <*> newIORef mempty

loadAll :: MonadIO m => Cache -> m (Map FilePath CacheError)
loadAll cache = liftIO $ traverseDir f (root cache) mempty
  where
    f :: Map FilePath CacheError -> FilePath -> IO (Map FilePath CacheError)
    f acc path = case parseName (root cache) path of
      Nothing   -> return $ M.insert path (InvalidPathName path) acc
      Just name -> do
        result <- load cache name path
        case result of
          Left err -> return $ M.insert path (CompilationError err) acc
          Right  _ -> return $ acc

query :: MonadIO m => Cache -> Name -> m (Maybe Query)
query cache name = do
  qs <- readIORef (queries cache)
  case M.lookup name qs of
    Just q  -> return $ Just q
    Nothing ->
      let path = root cache ++ "/" ++ (T.unpack $ unName name) ++ ".gql"
      in rightToMaybe <$> load cache name path

mutation :: MonadIO m => Cache -> Name -> m (Maybe Query)
mutation = Graph.Queries.Cache.query -- for now at least

-- Helpers

load :: MonadIO m
     => Cache 
     -> Name
     -> FilePath 
     -> m (Either QueryError Query)
load Cache{..} name path = do
  contents <- liftIO . readFile $ path
  case compileQuery schema contents of
    Left err -> return $ Left err
    Right q  -> do
      modifyIORef' queries $ M.insert name q
      return $ Right q

parseName :: FilePath -> [Char] -> Maybe Name
parseName root str = do
  let parser = do
        _ <- string (T.pack root)
        _ <- "/"
        name <- takeTill (== '.')
        _ <- ".gql"
        return name
  parsed <- maybeResult . parse parser $ T.pack str
  rightToMaybe $ makeName parsed
