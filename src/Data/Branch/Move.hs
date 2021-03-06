{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}
module Data.Branch.Move
  ( moveIds
  , moveMaps
  , properties
  , spaces
  , theorems
  ) where

import Core hiding (notFound)

import           Data.Git    as Git
import qualified Data.Id     as Id
import qualified Data.Map    as M
import           Data.Parse  (spaceIds, spaceTraitIds, theoremIds)
import qualified Data.Text   as T
import           Git

import qualified Page
import qualified Page.Property
import qualified Page.Space
import qualified Page.Theorem
import qualified Page.Trait

default (T.Text)

moveIds :: (MonadLogger m, Git m) => BranchName -> CommitMeta -> Map Uid Uid -> m ()
moveIds branch meta mapping = do
  $(logDebug) $ T.intercalate ""
    [ "Moving files on "
    , branch
    , ": "
    , T.intercalate ", "
      ( map (\(k,v) -> k <> " => " <> v) $ M.toList mapping
      )
    ]

  (_, sha) <- Git.updateBranch branch meta $ \_ ->
    moveMaps (extract mapping) (extract mapping) (extract mapping)

  $(logInfo) $ "Updated " <> branch <> " to " <> show sha

moveMaps :: (Git m, MonadLogger m)
         => Map SpaceId    SpaceId
         -> Map PropertyId PropertyId
         -> Map TheoremId  TheoremId
         -> TreeT LgRepo m ()
moveMaps ss ps ts = do
  debug "Spaces" ss
  debug "Properties" ps
  debug "Theorems" ts

  $(logInfo) "Moving traits"
  traits ss ps

  $(logInfo) "Moving spaces"
  spaces ss

  $(logInfo) "Moving properties"
  properties ps

  $(logInfo) "Moving theorems"
  theorems ts ps

  where
    debug :: (MonadLogger m, Show k, Show v) => Text -> Map k v -> m ()
    debug label m = unless (M.null m) $
      $(logDebug) $ label <> ": " <>
        T.intercalate "\n" (map (\(k,v) -> show k <> " => " <> show v) $ M.toList m)

properties :: (Git m, MonadLogger m)
           => Map PropertyId PropertyId
           -> TreeT LgRepo m ()
properties mapping = forM_ (M.toList mapping) $ \(from, to) -> do
  transform ("properties/" <> unId from <> ".md") Page.Property.page $ \p ->
    p { propertyId = to }

spaces :: (Git m, MonadLogger m)
       => Map SpaceId SpaceId
       -> TreeT LgRepo m ()
spaces mapping = forM_ (M.toList mapping) $ \(from, to) -> do
  transform ("spaces/" <> unId from <> "/README.md") Page.Space.page $ \s ->
    s { spaceId = to }

theorems :: (Git m, MonadLogger m)
         => Map TheoremId TheoremId
         -> Map PropertyId PropertyId
         -> TreeT LgRepo m ()
theorems ts ps = do
  tree <- currentTree
  tids <- lift $ sourceToList $ theoremIds tree
  unless (M.null ps) $ forM_ tids $ \tid -> do
    transform ("theorems/" <> unId tid <> ".md") Page.Theorem.page $ \t -> do
      t { -- Update id of theorem itself
          theoremId = case M.lookup tid ts of
            Just updated -> updated
            Nothing      -> tid
          -- Replace occurences of property ids
        , theoremImplication = fmap (\p -> M.findWithDefault p p ps) $ theoremImplication t
        }

traits :: (Git m, MonadLogger m)
       => Map SpaceId SpaceId
       -> Map PropertyId PropertyId
       -> TreeT LgRepo m ()
traits ss ps = do
  tree <- currentTree
  sids <- lift $ sourceToList $ spaceIds tree
  forM_ sids $ \sid -> do
    pids <- if M.member sid ss
              -- Update all properties for the space
              then lift $ sourceToList $ spaceTraitIds sid tree
              -- Update only the properties that have changed
              else return $ M.keys ps
    forM_ pids $ \pid -> do
      transform ("spaces/" <> unId sid <> "/properties/" <> unId pid <> ".md") Page.Trait.page $ \t ->
        t { _traitSpace = sid, _traitProperty = pid }

extract :: Id.Identifiable a => Map Uid Uid -> Map (Id a) (Id a)
extract = foldr add M.empty . M.toList
  where
    add :: forall a. Id.Identifiable a
        => (Uid, Uid) -> Map (Id a) (Id a) -> Map (Id a) (Id a)
    add (k,v) = if (T.singleton $ Id.prefix @a) `T.isPrefixOf` v
      then M.insert (Id k) (Id v)
      else identity

transform :: (Git m, MonadLogger m, Eq a)
          => Text -> Page a -> (a -> a) -> TreeT LgRepo m ()
transform path' page f = do
  let path = encodeUtf8 path'
  entry <- getEntry path
  case entry of
    Just (BlobEntry oid _) -> do
      blob   <- lift $ catBlobUtf8 oid
      parsed <- either throwIO return $ Page.parse page (path, blob)
      let transformed = f parsed
      unless (transformed == parsed) $ do
        $(logDebug) $ "Updating refs " <> show path
        dropEntry path
        writePages [Page.write page transformed]
    -- TODO:
    -- we probably want to raise if we fail to find a path in general,
    --   but some of the trait lookups are likely to fail, so we can't
    _ -> $(logDebug) $ "Failed to find " <> show path