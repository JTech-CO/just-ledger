// Unix 소켓 + JSON 명령 수신 (백서 §3.3: web ↔ worker 통신 프로토콜).
// 명령은 '힌트'다 — 진실원천은 DB 상태 기계이므로 소켓이 죽어도 스캔이 일을 끝낸다.
//
// 프로토콜 (한 연결 = 한 요청/응답, 개행 종료 JSON):
//
//	{"op":"ping"}                                        → {"ok":true}
//	{"op":"enqueue_ingest","owner_id":u,"batch_id":b}    → {"ok":true}
//	{"op":"poll_fx"}                                     → {"ok":true} (소스 미설정이면 ok:false)
package queue

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"os"
	"time"
)

type Command struct {
	Op      string `json:"op"`
	OwnerID string `json:"owner_id,omitempty"`
	BatchID string `json:"batch_id,omitempty"`
}

type Reply struct {
	Ok    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

type SocketServer struct {
	Path    string
	Log     *slog.Logger
	Scanner *Scanner
	// PollFx 는 스케줄러 훅 (미설정이면 poll_fx 는 ok:false)
	PollFx func(context.Context) error
}

func (s *SocketServer) Run(ctx context.Context) error {
	_ = os.Remove(s.Path) // 이전 비정상 종료 잔재
	ln, err := net.Listen("unix", s.Path)
	if err != nil {
		return err
	}
	go func() {
		<-ctx.Done()
		ln.Close()
		_ = os.Remove(s.Path)
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return nil
			}
			s.Log.Error("소켓 accept 실패", "err", err)
			continue
		}
		go s.handle(ctx, conn)
	}
}

func (s *SocketServer) handle(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))

	var cmd Command
	if err := json.NewDecoder(conn).Decode(&cmd); err != nil {
		writeReply(conn, Reply{Ok: false, Error: "잘못된 JSON"})
		return
	}

	switch cmd.Op {
	case "ping":
		writeReply(conn, Reply{Ok: true})
	case "enqueue_ingest":
		if cmd.OwnerID == "" || cmd.BatchID == "" {
			writeReply(conn, Reply{Ok: false, Error: "owner_id/batch_id 필수"})
			return
		}
		select {
		case s.Scanner.Nudge <- Job{OwnerID: cmd.OwnerID, BatchID: cmd.BatchID}:
			writeReply(conn, Reply{Ok: true})
		default:
			// 큐가 가득 — 스캔이 어차피 집는다 (진실원천은 DB)
			writeReply(conn, Reply{Ok: true})
		}
	case "poll_fx":
		if s.PollFx == nil {
			writeReply(conn, Reply{Ok: false, Error: "환율 소스 미설정"})
			return
		}
		if err := s.PollFx(ctx); err != nil {
			writeReply(conn, Reply{Ok: false, Error: "환율 폴링 실패"})
			return
		}
		writeReply(conn, Reply{Ok: true})
	default:
		writeReply(conn, Reply{Ok: false, Error: "알 수 없는 op"})
	}
}

func writeReply(conn net.Conn, r Reply) {
	b, _ := json.Marshal(r)
	b = append(b, '\n')
	_, _ = conn.Write(b)
}
