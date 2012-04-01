{-# LANGUAGE TemplateHaskell #-}

module Tfoo.Handlers.Root where

import Tfoo.Foundation
import Tfoo.Matrix
import Tfoo.Board
import Tfoo.Game

import Application
import Tfoo.Helpers.Application
import Tfoo.Helpers.Game

import Data.Text as T
import Data.List as L
import Data.Maybe as M
import Control.Monad

import Control.Concurrent.MVar

import Yesod
import Yesod.Default.Util

import Control.Concurrent.Chan
import Network.Wai.EventSource (ServerEvent (..), eventSourceApp)


getHomeR :: Handler RepHtml
getHomeR = do
  tfoo <- getYesod
  defaultLayout $(widgetFileNoReload "index")

postGamesR :: Handler RepHtml
postGamesR = do
    tfoo <- getYesod
    id   <- liftIO $ newGame tfoo
    redirect $ GameR id

getGameR :: Int -> Handler RepHtml
getGameR id = let
    columns = [0..19]
    rows    = [0..19]
  in do
    game <- getGame id
    maybePlayers <- lookupSession $ T.pack "players"
    tfoo <- getYesod
    defaultLayout $(widgetFileNoReload "game")

postMarkR :: Int -> Int -> Int -> Handler ()
postMarkR id x y = do
    game               <- getGame id
    whoseTurn'         <- return $ whoseTurn game
    board'             <- return $ board game
    userAuthorizations <- do
      authorizations <- lookupSession $ T.pack "players"
      return $ fmap (L.words . T.unpack) authorizations

    -- The target cell has to be empty.
    require $ (getCell (board game) x y) == Nothing
    -- User has to be authorized to make this move
    require $ fromMaybe False (liftM2 elem whoseTurn' userAuthorizations)
    -- The game has to be still in progress
    require $ (winner board') == Nothing

    updateGame id $ game {board = replace' x y (Just $ nextMark board') board'}
    game' <- getGame id

    broadcast id "mark-new" [
        ("x", show x), ("y", show y), ("mark", show (nextMark board'))
      ]

    broadcast id "alert" [("content", gameState game')]

  where require result = if result == False
          then permissionDenied $ T.pack "Permission Denied"
          else return ()
        elem' x y = (elem . L.words . T.unpack)

postPlayerOR :: Int -> Handler RepHtml
postPlayerOR id = do
  game <- getGame id
  if (playerO game) == Nothing
    then do
      joinGame id O
      broadcast id "player-new" [("side", "O")]
      broadcast id "alert" [("content", "Player joined: Circle")]
      return ()
    else return ()
  redirect $ GameR id

postPlayerXR :: Int -> Handler RepHtml
postPlayerXR id = do
  game <- getGame id
  if (playerX game) == Nothing
    then do
      joinGame id X
      broadcast id "player-new" [("side", "X")]
      broadcast id "alert" [("content", "Player joined: Cross")]
      return ()
    else return ()
  redirect $ GameR id

getChannelR :: Int -> Handler ()
getChannelR id = do
  game <- getGame id
  channel <- liftIO $ dupChan $ channel game
  request  <- waiRequest
  response  <- lift $ eventSourceApp channel request
  updateGame id game
  sendWaiResponse response
