{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskellQuotes #-}
module Text.Collate.TH
  ( genCollation
  , genCJKOverrides
  )
where
import Language.Haskell.TH
import Language.Haskell.TH.Syntax (qAddDependentFile)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Binary as Binary ( encode )
import Text.Collate.Collation (parseCollation, parseCJKOverrides)
import Data.Text.Encoding (decodeUtf8)
-- import Debug.Trace

-- NOTE: The reason for the indirection through binary
-- is that including a string literal in the sources instead
-- of a large structured object (e.g. a Map) dramatically
-- reduces compile times.  This seems a flaw in GHC and when
-- it is addressed, we could switch to a more straightforward
-- method.

genCollation :: FilePath -> Q Exp
genCollation fp = do
  qAddDependentFile fp
  binaryRep <- Binary.encode . parseCollation . decodeUtf8
                  <$> runIO (B.readFile fp)
  return $ LitE $ StringL $ BL.unpack binaryRep

genCJKOverrides :: FilePath -> Q Exp
genCJKOverrides fp = do
  qAddDependentFile fp
  binaryRep <- Binary.encode . parseCJKOverrides . decodeUtf8
                  <$> runIO (B.readFile fp)
  return $ LitE $ StringL $ BL.unpack binaryRep

