module Network.Protocol.Uri.Encode where

import Data.Bits
import Data.Char
import Data.Maybe
import Data.Record.Label
import Network.Protocol.Uri.Chars
import Prelude hiding ((.), id)

-- | URI encode a string.

encode :: String -> String
encode = concatMap encodeChr
  where
    encodeChr c
      | unreserved c || genDelims c || subDelims c = [c]
      | otherwise = '%' :
          intToDigit (shiftR (ord c) 4) :
          intToDigit ((ord c) .&. 0x0F) : []

-- | URI decode a string.

decode :: String -> String
decode [] = []
decode ('%':d:e:ds) | isHexDigit d && isHexDigit e = (chr $ digs d * 16 + digs e) : decode ds 
  where digs a = fromJust $ lookup (toLower a) $ zip "0123456789abcdef" [0..]
decode (d:ds) = d : decode ds

-- | Decoding and encoding as a label.

encoded :: String :<->: String
encoded = decode <-> encode

