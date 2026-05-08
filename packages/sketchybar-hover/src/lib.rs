//! Wire protocol shared between the `sketchybar-hover` client and the
//! `sketchybar-hoverd` daemon.

pub const SOCKET_PATH: &str = "/tmp/sketchybar-hover.sock";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HoverEvent {
    Enter(String),
    Exit(String),
    ExitAll,
}

impl HoverEvent {
    pub fn parse(line: &str) -> Option<Self> {
        let line = line.trim();
        if line == "EXIT_ALL" {
            return Some(Self::ExitAll);
        }
        let (cmd, name) = line.split_once(' ')?;
        let name = name.trim();
        if name.is_empty() {
            return None;
        }
        match cmd {
            "ENTER" => Some(Self::Enter(name.to_string())),
            "EXIT" => Some(Self::Exit(name.to_string())),
            _ => None,
        }
    }

    pub fn serialize(&self) -> String {
        match self {
            Self::Enter(name) => format!("ENTER {name}\n"),
            Self::Exit(name) => format!("EXIT {name}\n"),
            Self::ExitAll => "EXIT_ALL\n".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        for ev in [
            HoverEvent::Enter("clock".into()),
            HoverEvent::Exit("Control Center,WiFi".into()),
            HoverEvent::ExitAll,
        ] {
            let line = ev.serialize();
            assert_eq!(HoverEvent::parse(&line), Some(ev));
        }
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(HoverEvent::parse(""), None);
        assert_eq!(HoverEvent::parse("ENTER"), None);
        assert_eq!(HoverEvent::parse("ENTER  "), None);
        assert_eq!(HoverEvent::parse("WAT clock"), None);
    }

    /// Names with internal whitespace ("Control Center,WiFi") must round-
    /// trip — `split_once(' ')` only consumes the first space, so the rest
    /// of the name is kept intact.
    #[test]
    fn parses_name_with_spaces() {
        assert_eq!(
            HoverEvent::parse("ENTER Control Center,WiFi\n"),
            Some(HoverEvent::Enter("Control Center,WiFi".into()))
        );
        assert_eq!(
            HoverEvent::parse("EXIT Control Center,Battery"),
            Some(HoverEvent::Exit("Control Center,Battery".into()))
        );
    }
}
