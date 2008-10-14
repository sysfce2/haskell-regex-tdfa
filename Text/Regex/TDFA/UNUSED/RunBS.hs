-- | This is a version of Run that caters to Data.ByteString.Char8
module Text.Regex.TDFA.RunBS(findMatch,findMatchAll,countMatchAll) where

import Control.Monad(MonadPlus(..))
import Data.Array.IArray((!),array)
import qualified Data.ByteString.Char8 as B
import qualified Data.IntMap as IMap
import Data.List(maximumBy)
import qualified Data.Map as Map(lookup)
import Data.Maybe(isJust)

import Text.Regex.Base(MatchArray)
import Text.Regex.TDFA.Common
import Text.Regex.TDFA.RunState(makeTagComparer,tagsToGroups,update,newScratchMap)
-- import Debug.Trace

{- By Chris Kuklewicz, 2007. BSD License, see the LICENSE file. -}

-- err :: String -> a
-- err = common_error "Text.Regex.TDFA.RunBS"

{-# INLINE findMatch #-}
findMatch :: Regex -> B.ByteString -> Maybe MatchArray
findMatch regexIn input = loop 0 where
  final = B.length input
  loop offset =
    let result = matchHere regexIn offset input
    in if isJust result then result
         else if offset == final then Nothing
                else let offset' = succ offset
                     in seq offset' $ loop offset'

{-# INLINE findMatchAll #-}
findMatchAll :: Regex -> B.ByteString -> [MatchArray]
findMatchAll regexIn input = loop 0 where
  final = B.length input
  loop offset =
    case matchHere regexIn offset input of
      Nothing -> if offset == final then []
                   else let offset' = succ offset
                        in seq offset' $ loop offset'
      Just ma -> ma : let (start,len) = ma!0
                      in if offset==final || len==0 then []
                           else let offset' = start + len
                                in seq offset' $ loop offset'

{-# INLINE countMatchAll #-}
countMatchAll :: Regex -> B.ByteString -> Int
countMatchAll regexIn input = loop 0 $! 0 where
  final = B.length input
  loop offset count =
    case matchHere regexIn offset input of
      Nothing -> if offset == final then count
                   else let offset' = succ offset
                        in seq offset' $ loop offset' $! count
      Just ma -> let (start,len) = ma!0
                 in if offset==final || len==0 then count
                      else let offset' = start + len
                           in seq offset' $ loop offset' $! succ count

{-# INLINE matchHere #-}
matchHere :: Regex -> Position -> B.ByteString -> Maybe MatchArray
matchHere regexIn offsetIn input = ans where
  ans = if captureGroups (regex_execOptions regexIn)
          then fmap (tagsToGroups (regex_groups regexIn)) $
                 runHere Nothing (d_dt (regex_dfa regexIn)) initialScratchMap offsetIn
          else let winOff = runHereNoCap Nothing (d_dt (regex_dfa regexIn)) offsetIn
               in case winOff of
                    Nothing -> Nothing
                    Just offsetEnd -> Just (array (0,0) [(0,(offsetIn,offsetEnd-offsetIn))])

  initialScratchMap = newScratchMap regexIn offsetIn
  comp = makeTagComparer (regex_tags regexIn)

  final = B.length input
  test = if multiline (regex_compOptions regexIn)
           then test_multiline
           else test_singleline
  test_multiline wt off =
    case wt of Test_BOL -> off == 0 || '\n' == B.index input (pred off)
               Test_EOL -> off == final || '\n' == B.index input off
  test_singleline wt off =
    case wt of Test_BOL -> off == 0
               Test_EOL -> off == final
  
  runHere winning dt tags off =
    let best (destIndex,mSourceDelta) = (destIndex
                                        ,maximumBy comp 
                                         . map (\(sourceIndex,(_,rs)) ->
                                                update rs off (look sourceIndex tags))
                                         . IMap.toList $ mSourceDelta)
    in case dt of
         Simple' {dt_win=w, dt_trans=t, dt_other=o} ->
           let winning' = if IMap.null w then winning
                            else Just . maximumBy comp
                                      . map (\(sourceIndex,rs) ->
                                               update rs off (look sourceIndex tags))
                                      . IMap.toList $ w
        
           in seq winning' $
              if off==final then winning' else
                let c = B.index input off
                in case Map.lookup c t `mplus` o of
                     Nothing -> winning'
                     Just (dfa,trans) -> let dt' = d_dt dfa
                                             tags' = IMap.fromAscList
                                                     . map best
                                                     . IMap.toAscList $ trans
                                             off' = succ off
                                         in seq off' $ runHere winning' dt' tags' off'
         Testing' {dt_test=wt,dt_a=a,dt_b=b} ->
           if test wt off
             then runHere winning a tags off
             else runHere winning b tags off

  runHereNoCap winning dt off =
    case dt of
      Simple' {dt_win=w, dt_trans=t, dt_other=o} ->
        let winning' = if IMap.null w then winning else Just off
        in seq winning' $
           if off==final then winning' else
             let c = B.index input off
             in case Map.lookup c t `mplus` o of
                  Nothing -> winning'
                  Just (dfa,_) -> let dt' = d_dt dfa
                                      off' = succ off
                                  in seq off' $ runHereNoCap winning' dt' off'
      Testing' {dt_test=wt,dt_a=a,dt_b=b} ->
        if test wt off
          then runHereNoCap winning a off
          else runHereNoCap winning b off