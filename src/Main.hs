{-# LANGUAGE OverloadedStrings, RankNTypes #-}

module Main where

import           Control.Applicative ((<$>))
import           Control.Monad.IO.Class (liftIO)
import           Data.ByteString (append)
import           Data.ByteString.UTF8 (toString)
import qualified Data.HashMap.Strict as HM (map)
import           Data.IORef
import qualified Data.IntMap as IM
import qualified Data.Text as T
import           Snap.Core
import           Snap.Extras.JSON
import           Snap.Http.Server.Config (defaultConfig)
import           Snap.Snaplet
import           Snap.Snaplet.Session
import           Snap.Snaplet.Session.Backends.CookieSession (initCookieSessionManager)
import           Snap.Snaplet.Session.SessionManager ()
import           Snap.Util.FileServe
import           System.IO
import           System.Process (runInteractiveCommand)
import           System.Random

import           CoqTypes
import           Coqtop
import           Rooster

type RoosterHandler = Handler Rooster Rooster ()
type RoosterHandlerWithHandles = Handle -> Handle -> RoosterHandler

main :: IO ()
main = do
  serveSnaplet defaultConfig roosterSnaplet

startCoqtop :: IO (Handle, Handle)
startCoqtop = do
  (hi, ho, _, _) <- runInteractiveCommand "coqtop -ideslave"
  hSetBinaryMode hi False
  hSetBuffering stdin LineBuffering
  hSetBuffering hi NoBuffering
  hInterp hi "Require Import Unicode.Utf8."
  hForceValueResponse ho
  return (hi, ho)

sessionKey :: T.Text
sessionKey = "key"

withSessionHandles ::
  IORef RoosterState
  -> RoosterHandlerWithHandles
  -> RoosterHandler
withSessionHandles r h = do
  -- retrieve or create a key for this session
  mapKey <- with lSession $ do
    mkey <- getFromSession sessionKey
    case mkey of
      Nothing -> do
        key <- liftIO randomIO
        setInSession sessionKey (T.pack . show $ key)
        commitSession
        return key
      Just key -> do
        return . read . T.unpack $ key
  -- retrieve or create two handles for this session
  (hi, ho) <- liftIO $ do
    m <- readIORef r
    case IM.lookup mapKey m of
      Nothing -> do
        (hi, ho) <- startCoqtop
        atomicModifyIORef' r $ \ _m -> (IM.insert mapKey (hi, ho) _m, ())
        return (hi, ho)
      Just hiho -> do
        return hiho
  -- run the handler
  h hi ho

roosterSnaplet :: SnapletInit Rooster Rooster
roosterSnaplet = makeSnaplet "rooster" "rooster" Nothing $ do
  ref <- liftIO $ newIORef IM.empty
  s <- nestSnaplet "session" lSession cookieSessionManager
  addRoutes $
    map (\(r, handler) -> (r, withSessionHandles ref handler))
    [ ("query",            queryHandler)
    , ("queryundo",        queryUndoHandler)
    , ("undo",             undoHandler)
    , ("status",           statusHandler)
    , ("rewind",           rewindHandler)
    , ("qed",              qedHandler)
    , ("setprintingall",   togglePrintingAll True)
    , ("unsetprintingall", togglePrintingAll False)
    ] ++
    [ ("/",                serveDirectoryWith myDirConfig "web/")
    ]
  return $ Rooster s
  where
    cookieSessionManager = initCookieSessionManager "encription_key" "rooster_session" Nothing
    myDirConfig =
      defaultDirectoryConfig {
        mimeTypes = HM.map (\m -> append m "; charset=utf-8") defaultMimeTypes
        }

respond :: CoqtopResponse [String] -> RoosterHandlerWithHandles
respond response hi ho = do
  goals <- liftIO $ hQueryGoal hi ho
  writeJSON $ MkRoosterResponse goals response

queryHandler :: RoosterHandlerWithHandles
queryHandler hi ho = do
  param <- getParam "query"
  case param of
    Nothing -> return ()
    Just queryBS -> do
      response <- liftIO $ do
        -- might want to sanitize? :3
        let query = toString queryBS
        putStrLn $ query
        hInterp hi query
        hForceValueResponse ho
      respond response hi ho

queryUndoHandler :: RoosterHandlerWithHandles
queryUndoHandler hi ho = do
  param <- getParam "query"
  case param of
    Nothing -> return ()
    Just queryBS -> do
      response <- liftIO $ do
        -- might want to sanitize? :3
        let query = toString queryBS
        hInterp hi query
        hForceValueResponse ho
      respond response hi ho
      case response of
        Fail _ ->
          return ()
        Good _ ->
          do
            liftIO $ hCall hi [("val", "rewind"), ("steps", "1")] ""
            liftIO $ hForceValueResponse ho
            return ()

undoHandler :: RoosterHandlerWithHandles
undoHandler hi ho = do
  liftIO $ hCall hi [("val", "rewind"), ("steps", "1")] ""
  r <- liftIO $ hForceValueResponse ho
  respond r hi ho

statusHandler :: RoosterHandlerWithHandles
statusHandler hi ho = do
  liftIO $ hCall hi [("val", "status")] ""
  r <- liftIO $ hForceStatusResponse ho
  respond (return . show <$> r) hi ho

rewindHandler :: RoosterHandlerWithHandles
rewindHandler hi ho = do
  param <- getParam "query"
  case param of
    Nothing -> return ()
    Just stepsBS -> do
      liftIO $ hCall hi [("val", "rewind"), ("steps", toString stepsBS)] ""
      r <- liftIO $ hForceValueResponse ho
      respond (return . show <$> r) hi ho

qedHandler :: RoosterHandlerWithHandles
qedHandler hi ho = do
  liftIO $ hInterp hi "Qed."
  r <- liftIO $ hForceValueResponse ho
  respond r hi ho

togglePrintingAll :: Bool -> RoosterHandlerWithHandles
togglePrintingAll b hi ho = do
  let query =
        "<call id=\"0\" val=\"setoptions\">"
        ++ "<pair><list><string>Printing</string><string>All</string></list>"
        ++ "<option_value val=\"boolvalue\"><bool val=\""
        ++ (if b then "true" else "false")
        ++ "\"></bool></option_value>"
        ++ "</pair></call>"
  liftIO $ hPutStrLn hi query
  r <- liftIO $ hForceValueResponse ho
  respond r hi ho
