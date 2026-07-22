-- | JSONL stdin → JSONL stdout 배치. 한 줄 = 한 요청.
-- make run-dsl < fixtures/dsl/requests.jsonl 로 단독 실행된다.
-- CRLF 입력은 후행 \r 을 벗겨 처리하고, \r 만 남는 빈 줄은 스킵한다.
module Main (main) where

import Data.ByteString.Lazy.Char8 qualified as BL8
import System.IO (BufferMode (LineBuffering), hSetBuffering, stdout)

import Rules.Protocol (handleLine, requestLines)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  input <- BL8.getContents
  mapM_ (BL8.putStrLn . handleLine) (requestLines input)
