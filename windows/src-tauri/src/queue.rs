//! Cola mínima W13. Modelo puro del adaptador Windows hasta la extracción M7.
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_ENTRY_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueEntryDto {
    pub entry_id: String,
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub thumbnail: Option<String>,
    pub duration: Option<f64>,
}

impl QueueEntryDto {
    pub fn new(video_id: String, title: String, artists: String, thumbnail: Option<String>, duration: Option<f64>) -> Self {
        Self { entry_id: format!("queue-{}", NEXT_ENTRY_ID.fetch_add(1, Ordering::Relaxed)), video_id, title, artists, thumbnail, duration }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueSourceDto { pub kind: String, pub id: Option<String>, pub title: Option<String> }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueStateDto {
    pub items: Vec<QueueEntryDto>,
    pub current_index: Option<usize>,
    pub source: Option<QueueSourceDto>,
    pub revision: u64,
}

impl Default for QueueStateDto {
    fn default() -> Self { Self { items: vec![], current_index: None, source: None, revision: 0 } }
}

impl QueueStateDto {
    pub fn replace(&mut self, items: Vec<QueueEntryDto>, current_index: usize, source: QueueSourceDto) -> Option<QueueEntryDto> {
        if items.is_empty() || current_index >= items.len() { return None; }
        self.items = items;
        self.current_index = Some(current_index);
        self.source = Some(source);
        self.revision += 1;
        self.current()
    }
    pub fn current(&self) -> Option<QueueEntryDto> { self.current_index.and_then(|i| self.items.get(i)).cloned() }
    pub fn select(&mut self, index: usize) -> Option<QueueEntryDto> {
        if index >= self.items.len() { return None; }
        self.current_index = Some(index); self.revision += 1; self.current()
    }
    pub fn next(&mut self) -> Option<QueueEntryDto> {
        let next = self.current_index? + 1;
        self.select(next)
    }
    pub fn previous(&mut self, position: f64) -> Option<QueueEntryDto> {
        if position > 3.0 { return self.current(); }
        let index = self.current_index?;
        match index.checked_sub(1) { Some(previous) => self.select(previous), None => self.current() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn item(id: &str) -> QueueEntryDto { QueueEntryDto::new(id.into(), id.into(), String::new(), None, None) }
    fn queue() -> QueueStateDto {
        let mut q = QueueStateDto::default();
        q.replace(vec![item("same"), item("same"), item("last")], 1, QueueSourceDto { kind: "album".into(), id: Some("album".into()), title: Some("Album".into()) }); q
    }
    #[test] fn duplicates_keep_occurrence_identity_and_album_order() {
        let mut q = queue(); assert_eq!(q.items[0].video_id, q.items[1].video_id); assert_ne!(q.items[0].entry_id, q.items[1].entry_id); assert_eq!(q.current_index, Some(1)); assert_eq!(q.next().unwrap().video_id, "last");
    }
    #[test] fn previous_restarts_after_three_seconds_and_steps_at_or_below() {
        let mut q = queue(); let current = q.current().unwrap().entry_id; assert_eq!(q.previous(3.01).unwrap().entry_id, current); assert_eq!(q.current_index, Some(1)); assert_eq!(q.previous(3.0).unwrap().video_id, "same"); assert_eq!(q.current_index, Some(0));
        let first = q.current().unwrap().entry_id; let revision = q.revision;
        assert_eq!(q.previous(0.0).unwrap().entry_id, first);
        assert_eq!(q.current_index, Some(0)); assert_eq!(q.revision, revision);
    }
    #[test] fn eof_and_invalid_selection_do_not_wrap_or_mutate() {
        let mut q = queue(); q.select(2); let revision = q.revision; assert!(q.next().is_none()); assert_eq!(q.current_index, Some(2)); assert_eq!(q.revision, revision); assert!(q.select(99).is_none());
    }
}
