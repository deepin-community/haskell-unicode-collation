{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

-- | We define our own normalization function instead of depending on
-- unicode-transforms, because we need a lazy (streaming) normalization
-- function for maximum efficiency.  No point normalizing two whole 'Text's
-- if we can see from the first few characters how they should be ordered.
-- See <https://unicode.org/reports/tr15/> for a description of the algorithm
-- implemented here.
module Text.Collate.Normalize
  ( toNFD
  )
where
import qualified Data.IntMap as M
import Text.Collate.UnicodeData (genCanonicalDecompositionMap)
import Text.Collate.CanonicalCombiningClass (canonicalCombiningClass)
import Data.List (sortOn)

canonicalDecompositionMap :: M.IntMap [Int]
canonicalDecompositionMap = $(genCanonicalDecompositionMap)

-- | Lazily normalize a list of code points to its canonical decomposition (NFD).
toNFD :: [Int] -> [Int]
toNFD = rearrangeCombiningMarks . recursivelyDecompose

rearrangeCombiningMarks :: [Int] -> [Int]
rearrangeCombiningMarks = go
 where
  go [] = []
  go (c:cs) =
    if canonicalCombiningClass c == 0
       then c : reorderMarks cs
       else reorderMarks (c:cs)
  reorderMarks zs =
    case break (\z -> canonicalCombiningClass z == 0) zs of
      ([], ys)  -> go ys
      ([x], ys) -> x : go ys
      ([x1,x2], ys)
        | canonicalCombiningClass x1 <= canonicalCombiningClass x2
                    -> x1 : x2 : go ys
        | otherwise -> x2 : x1 : go ys
      (xs, ys)  -> sortOn canonicalCombiningClass xs ++ go ys

recursivelyDecompose :: [Int] -> [Int]
recursivelyDecompose = foldr go mempty
  where go c
          | c < 0xc0 = (c :)
          | isHangulSyllable c = decomposeHangulSyllable c
          | otherwise =
              case M.lookup c canonicalDecompositionMap of
                Nothing -> (c :)
                Just ds -> (\xs -> foldr go xs ds)

-- | Hangul syllable range is AC00 - D7A3.
isHangulSyllable :: Int -> Bool
isHangulSyllable cp = cp >= 0xAC00 && cp <= 0xD7A3

-- Hangul decomposition is algorithmic; see "Hangul Syllable Decomposition" in
-- the Unicode spec, which gives this algorithm:
--
-- SBase = AC0016
-- LBase = 110016
-- VBase = 116116
-- TBase = 11A716
-- LCount = 19
-- VCount = 21
-- TCount = 28
-- NCount = 588 (VCount * TCount) SCount = 11172 (LCount * NCount)
-- SIndex = s - SBase
-- LIndex = SIndex div NCount
-- VIndex = (SIndex mod NCount) div TCount TIndex = SIndex mod TCount
-- LPart = LBase + LIndex
-- VPart = VBase + VIndex
-- TPart = TBase + TIndex if TIndex > 0
-- If TIndex = 0, then there is no trailing consonant, so map the precomposed
-- Hangul syllable s to its full decomposition d = <LPart, VPart>. Otherwise,
-- there is a trailing consonant, so map s to its full decomposition d = <LPart,
-- VPart, TPart>.

decomposeHangulSyllable :: Int -> ([Int] -> [Int])
decomposeHangulSyllable !c =
  if sindex < 0 || sindex >= scount
     then (c:)
     else
       let l = lbase + (sindex `div` ncount)
           v = vbase + ((sindex `mod` ncount) `div` tcount)
           t = tbase + (sindex `mod` tcount)
        in if t /= tbase
              then (l:) . (v:) . (t:)
              else (l:) . (v:)
 where
  !sindex = c - sbase
  !sbase = 0xAC00
  !lbase = 0x1100
  !vbase = 0x1161
  !tbase = 0x11A7
  !tcount = 28
  !ncount = 588 -- vcount * tcount
  !scount = 11172 -- lcount * ncount
  -- !lcount = 19
  -- !vcount = 21

