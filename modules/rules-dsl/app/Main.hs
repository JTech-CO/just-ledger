-- | JSONL stdin → JSONL stdout 배치. 한 줄 = 한 요청.
-- make run-dsl < fixtures/dsl/requests.jsonl 로 단독 실행된다.
module Main (main) where

import Data.ByteString.Lazy.Char8 qualified as BL8
import System.IO (BufferMode (LineBuffering), hSetBuffering, stdout)

import Rules.Protocol (handleLine)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  input <- BL8.getContents
  mapM_ (BL8.putStrLn . handleLine) (filter (not . BL8.null) (BL8.lines input))
