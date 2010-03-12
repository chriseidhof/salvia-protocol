{-# LANGUAGE TypeOperators, FlexibleContexts #-}
module Network.Protocol.Http.Parser
(

-- * Top level message parsers.

  parseRequest
, parseResponse
, parseHeaders

-- * Exposure of internal parsec parsers.

, pRequest
, pResponse
, pHeaders
, pVersion
, pMethod

-- * Helper methods.

, versionFromString
, methodFromString

)
where

import Control.Applicative hiding (empty)
import Data.Char
import Data.List hiding (insert)
import Network.Protocol.Http.Data
import Network.Protocol.Http.Status
import Text.ParserCombinators.Parsec hiding (many, (<|>))

-- | Parse a string as an HTTP request message. This parser is very forgiving.

parseRequest :: String -> Either String (Http Request)
parseRequest = either (Left . show) (Right . id) . parse pRequest ""

-- | Parse a string as an HTTP request message. This parser is very forgiving.

parseResponse :: String -> Either String (Http Response)
parseResponse = either (Left . show) (Right . id) . parse pResponse ""

-- | Parse a string as a list of HTTP headers.

parseHeaders :: String -> Either String Headers
parseHeaders = either (Left . show) (Right . id) . parse pHeaders ""

-- | Parsec parser to parse the header part of an HTTP request.

pRequest :: GenParser Char st (Http Request)
pRequest =
      (\m u v h -> Http (Request m u) v h)
  <$> (pMethod <* many1 (oneOf ls))
  <*> (many1 (noneOf ws) <* many1 (oneOf ls))
  <*> (pVersion <* eol)
  <*> (pHeaders <* eol)

-- | Parsec parser to parse the header part of an HTTP response.

pResponse :: GenParser Char st (Http Response)
pResponse =
      (\v s h -> Http (Response (statusFromCode $ read s)) v h)
  <$> (pVersion <* many1 (oneOf ls))
  <*> (many1 digit <* many1 (oneOf ls) <* many1 (noneOf lf) <* eol)
  <*> (pHeaders <* eol)

-- | Parsec parser to parse one or more, possibly multiline, HTTP header lines.

pHeaders :: GenParser Char st Headers
pHeaders = Headers <$> p
  where
    p = (\k v -> ((k, v):))
        <$> many1 (noneOf (':':ws)) <* string ":"
        <*> (intercalate ws <$> (many $ many1 (oneOf ls) *> many1 (noneOf lf) <* eol))
        <*> option [] p

-- | Parsec parser to parse HTTP versions. Recognizes X.X versions only.

pVersion :: GenParser Char st Version
pVersion = 
      (\h l -> Version (ord h - ord '0') (ord l  - ord '0'))
  <$> (istring "HTTP/" *> digit)
  <*> (char '.'       *> digit)

-- | Parsec parser to parse an HTTP method. Parses arbitrary method but
-- actually recognizes the ones listed as a constructor for `Method'.

pMethod :: GenParser Char st Method
pMethod =
     choice
   $ map (\a -> a <$ (try . istring . show $ a)) methods
  ++ [OTHER <$> many (noneOf ws)]

-- | Recognizes HTTP protocol version 1.0 and 1.1, all other string will
-- produce version 1.1.

versionFromString :: String -> Version
versionFromString "HTTP/1.1" = http11
versionFromString "HTTP/1.0" = http10
versionFromString _          = http11

-- | Helper to turn fully capitalized string into request method.

methodFromString :: String -> Method
methodFromString "OPTIONS" = OPTIONS
methodFromString "GET"     = GET 
methodFromString "HEAD"    = HEAD
methodFromString "POST"    = POST
methodFromString "PUT"     = PUT 
methodFromString "DELETE"  = DELETE
methodFromString "TRACE"   = TRACE
methodFromString "CONNECT" = CONNECT
methodFromString xs        = OTHER xs

-- Helpers.

lf, ws, ls :: String
lf = "\r\n"
ws = " \t\r\n"
ls = " \t"

-- Optional parser with maybe result.

pMaybe :: GenParser tok st a -> GenParser tok st (Maybe a)
pMaybe a = option Nothing (Just <$> a)

-- Parse end of line, \r, \n or \r\n.

eol :: GenParser Char st ()
eol = () <$ ((char '\r' <* pMaybe (char '\n')) <|> char '\n')

-- Case insensitive string parser.

istring :: String -> GenParser Char st String
istring s = sequence (map (\c -> satisfy (\d -> toUpper c == toUpper d)) s)

