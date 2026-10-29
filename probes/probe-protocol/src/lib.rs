use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufWriter, Write};
use std::path::Path;
use std::str::FromStr;
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime};

use serde::Serialize;
use serde_json::Value;

pub const WORKLOAD_STEPS: usize = 400;
pub const WORKLOAD_STEP_MILLIS: u64 = 20;
pub const WORKLOAD_DURATION_MILLIS: u64 = WORKLOAD_STEPS as u64 * WORKLOAD_STEP_MILLIS;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Show,
    Workload,
    Hide,
    Cycle { count: u16 },
    Quit,
}

impl FromStr for Command {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        let parts = value.split_whitespace().collect::<Vec<_>>();
        match parts.as_slice() {
            ["show"] => Ok(Self::Show),
            ["workload"] => Ok(Self::Workload),
            ["hide"] => Ok(Self::Hide),
            ["cycle", count] => {
                let count = count
                    .parse::<u16>()
                    .map_err(|_| format!("invalid cycle count: {count}"))?;
                if (1..=1_000).contains(&count) {
                    Ok(Self::Cycle { count })
                } else {
                    Err(format!("cycle count out of range: {count}"))
                }
            }
            ["quit"] => Ok(Self::Quit),
            _ => Err(format!("unknown benchmark command: {value}")),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum EventKind {
    ReadyHidden,
    ShowStart,
    ShowEnd,
    WorkloadStart,
    WorkloadEnd,
    HideStart,
    HideEnd,
    CycleStart,
    CycleEnd,
    Quit,
    Error,
}

pub const REQUIRED_EVENT_ORDER: [EventKind; 10] = [
    EventKind::ReadyHidden,
    EventKind::ShowStart,
    EventKind::ShowEnd,
    EventKind::WorkloadStart,
    EventKind::WorkloadEnd,
    EventKind::HideStart,
    EventKind::HideEnd,
    EventKind::CycleStart,
    EventKind::CycleEnd,
    EventKind::Quit,
];

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub framework: String,
    pub event: EventKind,
    pub timestamp: String,
    pub elapsed_ms: u128,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<Value>,
}

impl Event {
    pub fn new(
        framework: impl Into<String>,
        event: EventKind,
        elapsed_ms: u128,
        detail: Option<Value>,
    ) -> Self {
        let timestamp = time::OffsetDateTime::from(SystemTime::now())
            .format(&time::format_description::well_known::Rfc3339)
            .expect("RFC 3339 timestamps are always representable");
        Self {
            framework: framework.into(),
            event,
            timestamp,
            elapsed_ms,
            detail,
        }
    }
}

#[derive(Clone)]
pub struct EventLog {
    framework: Arc<str>,
    started: Instant,
    writer: Arc<Mutex<BufWriter<File>>>,
}

impl EventLog {
    pub fn create(framework: impl Into<Arc<str>>, path: impl AsRef<Path>) -> std::io::Result<Self> {
        let file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(path)?;
        Ok(Self {
            framework: framework.into(),
            started: Instant::now(),
            writer: Arc::new(Mutex::new(BufWriter::new(file))),
        })
    }

    pub fn emit(&self, event: EventKind, detail: Option<Value>) -> std::io::Result<()> {
        let event = Event::new(
            self.framework.as_ref(),
            event,
            self.started.elapsed().as_millis(),
            detail,
        );
        let mut writer = self.writer.lock().expect("event log mutex poisoned");
        serde_json::to_writer(&mut *writer, &event)?;
        writer.write_all(b"\n")?;
        writer.flush()
    }
}

pub fn read_commands(
    reader: impl BufRead,
    mut handler: impl FnMut(Command) -> Result<bool, String>,
) -> Result<(), String> {
    for line in reader.lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        if !handler(line.parse()?)? {
            break;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_complete_command_language() {
        assert_eq!("show".parse(), Ok(Command::Show));
        assert_eq!("workload".parse(), Ok(Command::Workload));
        assert_eq!("hide".parse(), Ok(Command::Hide));
        assert_eq!("cycle 30".parse(), Ok(Command::Cycle { count: 30 }));
        assert_eq!("quit".parse(), Ok(Command::Quit));
    }

    #[test]
    fn rejects_commands_that_would_change_the_protocol() {
        assert!("cycle 0".parse::<Command>().is_err());
        assert!("cycle 1001".parse::<Command>().is_err());
        assert!("workload 200".parse::<Command>().is_err());
        assert!("unknown".parse::<Command>().is_err());
    }

    #[test]
    fn workload_has_exactly_400_twenty_millisecond_steps() {
        assert_eq!(WORKLOAD_STEPS, 400);
        assert_eq!(WORKLOAD_STEP_MILLIS, 20);
        assert_eq!(WORKLOAD_DURATION_MILLIS, 8_000);
    }

    #[test]
    fn event_is_one_json_object_with_stable_fields() {
        let event = Event::new("tauri", EventKind::ReadyHidden, 17, None);
        let encoded = serde_json::to_string(&event).unwrap();
        let value: serde_json::Value = serde_json::from_str(&encoded).unwrap();

        assert_eq!(value["framework"], "tauri");
        assert_eq!(value["event"], "ready-hidden");
        assert_eq!(value["elapsedMs"], 17);
        assert!(value["timestamp"].as_str().unwrap().contains('T'));
        assert!(value.get("detail").is_none());
        assert!(!encoded.contains('\n'));
    }

    #[test]
    fn required_event_sequence_is_stable() {
        assert_eq!(
            REQUIRED_EVENT_ORDER,
            [
                EventKind::ReadyHidden,
                EventKind::ShowStart,
                EventKind::ShowEnd,
                EventKind::WorkloadStart,
                EventKind::WorkloadEnd,
                EventKind::HideStart,
                EventKind::HideEnd,
                EventKind::CycleStart,
                EventKind::CycleEnd,
                EventKind::Quit,
            ]
        );
    }
}
