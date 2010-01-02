{-# LANGUAGE StandaloneDeriving, TypeOperators, FlexibleContexts #-}
module Network.Protocol.Uri.Parser where

import Control.Applicative hiding (empty)
import Control.Category
import Data.Char
import Data.List 
import Data.Maybe
import Data.Record.Label
import Network.Protocol.Uri.Data
import Network.Protocol.Uri.Encode
import Network.Protocol.Uri.Printer ()
import Network.Protocol.Uri.Query
import Prelude hiding ((.), id, mod)
import Safe
import Text.Parsec hiding (many, (<|>))

-- | Access the host part of the URI.

host :: Uri :-> String
host = (show <-> either (const mkHost) id . parseHost) `iso` (_host . authority)

-- | Access the path part of the URI. The query will be properly decoded when
-- reading and encoded when writing.

path :: Uri :-> FilePath
path = (decode . show <-> either (const mkPath) id . parsePath . encode) `iso` _path

-- | Access the path and query parts of the URI as a single string. The string
-- will will be properly decoded when reading and encoded when writing.

pathAndQuery :: Uri :-> String
pathAndQuery = values "?" `osi` Label ((\p q -> [p, q]) <$> idx 0 `for` path <*> idx 1 `for` query)
  where idx = flip (atDef "")

-- | Parse string into a URI and ignore all failures by returning an empty URI
-- when parsing fails. Can be quite useful in situations that parse errors are
-- unlikely.

toUri :: String -> Uri
toUri = either (const mkUri) id . parseUri

-- | Parse string into a URI.

parseUri :: String -> Either ParseError Uri
parseUri = parse pUriReference ""

-- | Parse string into a URI and only accept absolute URIs.

parseAbsoluteUri :: String -> Either ParseError Uri
parseAbsoluteUri = parse pAbsoluteUri ""

-- | Parse string into an authority.

parseAuthority :: String -> Either ParseError Authority
parseAuthority = parse pAuthority ""

-- | Parse string into a path.

parsePath :: String -> Either ParseError Path
parsePath = parse pPath ""

-- | Parse string into a host.

parseHost :: String -> Either ParseError Host
parseHost = parse pHost ""

-- D.2.  Modifications

pAlpha, pDigit, pAlphanum :: Stream s m Char => ParsecT s u m Char
pAlpha    = letter
pDigit    = digit
pAlphanum = alphaNum

-- 2.3.  Unreserved Characters

pUnreserved :: Stream s m Char => ParsecT s u m Char
pUnreserved  = pAlphanum <|> oneOf "-._~"

{-
pReserved :: Stream s m Char => ParsecT s u m Char
pReserved  = pGenDelims <|> pSubDelims
pGenDelims :: Stream s m Char => ParsecT s u m Char
pGenDelims = oneOf ":/?#[]@"
-}

pSubDelims :: Stream s m Char => ParsecT s u m Char
pSubDelims = oneOf "!$&'()*+,;="

-- 2.1.  Percent-Encoding

pPctEncoded :: Stream s m Char => ParsecT s u m String
pPctEncoded = (:) <$> char '%' <*> pHex

pHex :: Stream s m Char => ParsecT s u m String
pHex = (\a b -> a:b:[])
    <$> hexDigit
    <*> hexDigit

-- 3.  Syntax Components

-- With the hier-part integrated.

pUri :: Stream s m Char => ParsecT s u m Uri
pUri = (\a (b,c) d e -> Uri False a b c d e)
  <$> (pScheme <* string ":")
  <*> (ap <|> p)
  <*> option "" (string "?" *> pQuery)
  <*> option "" (string "#" *> pFragment)
  where
    ap = (,) <$> (string "//" *> pAuthority) <*> pPathAbempty
    p  = ((,) mkAuthority) <$> (pPathAbsolute <|> pPathRootless {-<|> pPathEmpty-})

-- 3.1.  Scheme

pScheme :: Stream s m Char => ParsecT s u m Scheme
pScheme = (:) <$> pAlpha <*> many (pAlphanum <|> oneOf "+_.")

-- 3.2.  Authority

pAuthority :: Stream s m Char => ParsecT s u m Authority
pAuthority = Authority
  <$> option mkUserinfo (try (pUserinfo <* string "@"))
  <*> pHost
  <*> option Nothing (string ":" *> pPort)

-- 3.2.1.  User Information

pUserinfo :: Stream s m Char => ParsecT s u m String
pUserinfo = concat <$> many (
      (pure <$> pUnreserved)
  <|> (         pPctEncoded)
  <|> (pure <$> pSubDelims)
  <|> (pure <$> oneOf ":")
  )

-- 3.2.2.  Host

pHost :: Stream s m Char => ParsecT s u m Host
pHost = diff <$> pRegName -- <|> RegName <$> pRegName
  where
    diff  a = either (const (RegName a)) sep (parse pHostname "" a)
    sep   a = if hst a then Hostname (Domain a) else ipreg a
    ipreg a = if ip a then IP (toIP a) else RegName (intercalate "." a)
    hst     = not . all isDigit . headDef "" . dropWhile null . reverse
    ip    a = length a == 4 && length (mapMaybe (either (const Nothing) Just . parse pDecOctet "") a) == 4
    toIP [a, b, c, d] = IPv4 (read a) (read b) (read c) (read d)
    toIP _            = IPv4 0 0 0 0

{-
pfff, ipv6 is sooo not gonna make it..

pIPLiteral = "[" ( IPv6address <|> IPvFuture  ) "]"

pIPvFuture = "v" 1*HEXDIG "." 1*( unreserved <|> subDelims <|> ":" )

pIPv6address =
                                 6( h16 ":" ) ls32
  <|>                       "::" 5( h16 ":" ) ls32
  <|> [               h16 ] "::" 4( h16 ":" ) ls32
  <|> [ *1( h16 ":" ) h16 ] "::" 3( h16 ":" ) ls32
  <|> [ *2( h16 ":" ) h16 ] "::" 2( h16 ":" ) ls32
  <|> [ *3( h16 ":" ) h16 ] "::"    h16 ":"   ls32
  <|> [ *4( h16 ":" ) h16 ] "::"              ls32
  <|> [ *5( h16 ":" ) h16 ] "::"              h16
  <|> [ *6( h16 ":" ) h16 ] "::"

pH16           = 1*4HEXDIG
pLs32          = ( h16 ":" h16 ) <|> IPv4address
-}

{-
pIPv4address :: Stream s m Char => ParsecT s u m [Int]
pIPv4address = (:) <$> pDecOctet <*> (count 3 $ char '.' *> pDecOctet)
-}

pDecOctet :: Stream s m Char => ParsecT s u m Int
pDecOctet = read <$> choice [
    try ((\a b c -> [a,b,c]) <$> char '2' <*> char '5'      <*> oneOf "012345")
  , try ((\a b c -> [a,b,c]) <$> char '2' <*> oneOf "01234" <*> digit)
  , try ((\a b c -> [a,b,c]) <$> char '1' <*> digit         <*> digit)
  , try ((\a b   -> [a,b])   <$>              digit         <*> digit)
  ,     (pure                <$>                                digit)
  ]

pRegName :: Stream s m Char => ParsecT s u m String
pRegName = concat <$> many1 (
      (pure <$> pUnreserved)
  <|>           pPctEncoded
  <|> (pure <$> pSubDelims))

-- Not actually part of the rfc3986, but comptability with the rfc2396.
-- This information can be useful, so why throw away.

pHostname :: Stream s m Char => ParsecT s u m [String]
pHostname = sepBy (option "" pDomainlabel) (string ".")

pDomainlabel :: Stream s m Char => ParsecT s u m String
pDomainlabel = intercalate "-" <$> sepBy1 (some pAlphanum) (string "-")

-- 3.2.3.  Port

pPort :: Stream s m Char => ParsecT s u m (Maybe Port)
pPort = readMay <$> some pDigit

-- 3.4.  Query

pQuery :: Stream s m Char => ParsecT s u m String
pQuery = concat <$> many (pPchar <|> pure <$> oneOf "/?")

-- 3.5.  Fragment

pFragment :: Stream s m Char => ParsecT s u m String
pFragment = concat <$> many (pPchar <|> pure <$> oneOf "/?" )

-- 3.3.  Path

pPath, pPathAbempty, pPathAbsolute, pPathNoscheme, pPathRootless, pPathEmpty
  :: Stream s m Char => ParsecT s u m Path

pPath =
      try pPathAbsolute -- begins with "/" but not "//"
  <|> try pPathNoscheme -- begins with a nonColon segment
  <|> try pPathRootless -- begins with a segment
  <|> pPathEmpty        -- zero characters

pPathAbempty  = Path . ("":) <$> _pSlashSegments
pPathAbsolute = (char '/' *>) $ Path . ("":) <$> (option [] $ (:) <$> pSegmentNz <*> _pSlashSegments)
pPathNoscheme = Path <$> ((:) <$> pSegmentNzNc <*> _pSlashSegments)
pPathRootless = Path <$> ((:) <$> pSegmentNz    <*> _pSlashSegments)
pPathEmpty    = Path [] <$ string ""

pSegment, pSegmentNz, pSegmentNzNc :: Stream s m Char => ParsecT s u m String
pSegment     = concat <$> many pPchar
pSegmentNz   = concat <$> some pPchar
pSegmentNzNc = concat <$> some (
      (pure <$> pUnreserved)
  <|>           pPctEncoded
  <|> (pure <$> pSubDelims)
  <|> (pure <$> oneOf "@" ))

_pSlashSegments :: Stream s m Char => ParsecT s u m [PathSegment]
_pSlashSegments = (many $ (:) <$> char '/' *> pSegment)

pPchar :: Stream s m Char => ParsecT s u m String
pPchar = choice [
    pure <$> pUnreserved
  , pPctEncoded
  , pure <$> pSubDelims
  , pure <$> oneOf ":@"
  ]

-- 4.1.  URI Reference

pUriReference :: Stream s m Char => ParsecT s u m Uri
pUriReference = try pAbsoluteUri <|> pRelativeRef

-- 4.2.  Relative Reference

-- With the relative-part integrated.

pRelativeRef :: Stream s m Char => ParsecT s u m Uri
pRelativeRef = ($)
  <$> (try pRelativePart
  <|> ((Uri True mkScheme mkAuthority)
  <$> (pPathAbsolute <|> pPathRootless <|> pPathEmpty)))
  <*> option "" (string "?" *> pQuery)
  <*> option "" (string "#" *> pFragment)

pRelativePart :: Stream s m Char => ParsecT s u m (Query -> Fragment -> Uri)
pRelativePart = (Uri True mkScheme) <$> (string "//" *> pAuthority) <*> pPathAbempty

-- 4.3.  Absolute URI

pAbsoluteUri :: Stream s m Char => ParsecT s u m Uri
pAbsoluteUri = pUri

