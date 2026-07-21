//! 최소 RFC4180 CSV 분해. 따옴표 필드("4,500")·이스케이프("") 를 처리한다.
//! 은행 명세서 CSV 는 필드 내 줄바꿈을 쓰지 않으므로 행 단위 분해로 충분하다.
//!
//! 성능(DoD 3): 따옴표 없는 행은 제로카피 슬라이스로 빌리고(50MB에서 수백만 할당 절약),
//! 따옴표 행만 문자 단위로 조립한다.

use std::borrow::Cow;

pub fn split_lines(text: &str) -> Vec<&str> {
    text.split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .filter(|l| !l.trim().is_empty())
        .collect()
}

pub fn split_fields(line: &str) -> Vec<Cow<'_, str>> {
    // 빠른 경로: 따옴표가 없으면 콤마 분할 = 그대로 빌림
    if !line.contains('"') {
        return line.split(',').map(Cow::Borrowed).collect();
    }

    // 바이트 스캐너: 구분자(" , )는 ASCII 이고 UTF-8 멀티바이트 문자 안에는 ASCII
    // 바이트가 나타나지 않으므로 바이트 단위 스캔이 안전하다. 문자 단위 push 대신
    // 구간 슬라이스를 통째로 복사하고, 따옴표 없는 필드는 빌린다 (DoD 3).
    let b = line.as_bytes();
    let mut out: Vec<Cow<'_, str>> = Vec::with_capacity(8);
    let mut i = 0usize;

    loop {
        // 필드 하나 파싱
        let field_start = i;
        let mut cur: Option<String> = None; // 따옴표를 만난 필드만 소유 버퍼 사용
        let mut seg_start = i;
        let mut in_quotes = false;

        while i < b.len() {
            let c = b[i];
            if in_quotes {
                if c == b'"' {
                    // 지금까지의 따옴표 내부 구간을 반영
                    cur.as_mut().unwrap().push_str(&line[seg_start..i]);
                    if b.get(i + 1) == Some(&b'"') {
                        cur.as_mut().unwrap().push('"');
                        i += 2;
                    } else {
                        in_quotes = false;
                        i += 1;
                    }
                    seg_start = i;
                } else {
                    i += 1;
                }
            } else if c == b'"' {
                let s = cur.get_or_insert_with(String::new);
                s.push_str(&line[seg_start..i]);
                in_quotes = true;
                i += 1;
                seg_start = i;
            } else if c == b',' {
                break;
            } else {
                i += 1;
            }
        }

        match cur {
            None => out.push(Cow::Borrowed(&line[field_start..i])),
            Some(mut s) => {
                s.push_str(&line[seg_start..i]);
                out.push(Cow::Owned(s));
            }
        }

        if i >= b.len() {
            break;
        }
        i += 1; // ',' 건너뜀
        if i == b.len() {
            // 행이 콤마로 끝나면 마지막 빈 필드
            out.push(Cow::Borrowed(""));
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(fields: Vec<Cow<'_, str>>) -> Vec<String> {
        fields.into_iter().map(|c| c.into_owned()).collect()
    }

    #[test]
    fn quoted_thousands() {
        assert_eq!(
            v(split_fields(r#"1,2026.06.02,"4,500","1,234,500",강남"#)),
            vec!["1", "2026.06.02", "4,500", "1,234,500", "강남"]
        );
    }

    #[test]
    fn escaped_quote() {
        assert_eq!(v(split_fields(r#""a""b",c"#)), vec![r#"a"b"#, "c"]);
    }

    #[test]
    fn crlf_and_blank_lines() {
        assert_eq!(split_lines("a\r\n\r\nb\n"), vec!["a", "b"]);
    }

    #[test]
    fn empty_trailing_field() {
        assert_eq!(v(split_fields("a,b,")), vec!["a", "b", ""]);
    }

    #[test]
    fn no_quote_fast_path_borrows() {
        let fields = split_fields("a,b,c");
        assert!(matches!(fields[0], Cow::Borrowed(_)));
    }
}
