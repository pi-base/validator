{-# LANGUAGE TemplateHaskell #-}
module Data.Theorem
  ( fetch
  , pending
  , put
  ) where

import Protolude hiding (find, put)

import           Core
import           Data (findParsed, makeId, required, updateBranch)
import           Data.Git (writePages)
import qualified Data.Parse as Parse
import qualified Data.Property
import qualified Page
import           Page.Theorem (page)

find :: MonadStore m => Branch -> TheoremId -> m (Maybe (Theorem Property))
find branch _id = findParsed Parse.theorem branch _id >>= \case
  Nothing -> return Nothing
  Just theorem ->
    mapM (Data.Property.find branch) theorem >>= return . sequence

fetch :: MonadStore m => Branch -> TheoremId -> m (Theorem Property)
fetch branch _id = find branch _id >>= Data.required "Theorem" (unId _id)

pending :: TheoremId
pending = Id ""

put :: (MonadStore m, MonadLogger m) 
    => Branch 
    -> CommitMeta 
    -> Theorem PropertyId 
    -> m (Theorem Property, Sha)
put branch meta theorem' = do
  theorem <- assignId theorem'
  -- TODO: verify deductions here?
  (_, sha) <- updateBranch branch meta $ \_ ->
    writePages [Page.write page theorem]
  -- TODO: don't go back to store?
  loaded <- fetch branch $ theoremId theorem
  return (loaded, sha)

assignId :: MonadIO m => Theorem p -> m (Theorem p)
assignId t = if theoremId t == pending
  then do
    _id <- makeId "t"
    return $ t { theoremId = _id }
  else return t
