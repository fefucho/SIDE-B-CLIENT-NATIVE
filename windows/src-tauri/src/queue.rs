use serde::{Deserialize, Serialize};
use std::collections::HashSet;
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
    #[serde(default)]
    pub artist_id: Option<String>,
    #[serde(default)]
    pub album_id: Option<String>,
    #[serde(default)]
    pub album: Option<String>,
}

impl QueueEntryDto {
    pub fn new(
        video_id: String,
        title: String,
        artists: String,
        thumbnail: Option<String>,
        duration: Option<f64>,
    ) -> Self {
        Self::with_metadata(
            video_id, title, artists, thumbnail, duration, None, None, None,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_metadata(
        video_id: String,
        title: String,
        artists: String,
        thumbnail: Option<String>,
        duration: Option<f64>,
        artist_id: Option<String>,
        album_id: Option<String>,
        album: Option<String>,
    ) -> Self {
        Self {
            entry_id: format!("queue-{}", NEXT_ENTRY_ID.fetch_add(1, Ordering::Relaxed)),
            video_id,
            title,
            artists,
            thumbnail,
            duration,
            artist_id,
            album_id,
            album,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueSourceDto {
    pub kind: String,
    pub id: Option<String>,
    pub title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueRadioDto {
    pub loading: bool,
    pub error: Option<String>,
    pub can_retry: bool,
}

impl Default for QueueRadioDto {
    fn default() -> Self {
        Self {
            loading: false,
            error: None,
            can_retry: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueStateDto {
    pub items: Vec<QueueEntryDto>,
    pub current_index: Option<usize>,
    pub source: Option<QueueSourceDto>,
    pub revision: u64,
    #[serde(default)]
    pub radio: Option<QueueRadioDto>,
}

impl Default for QueueStateDto {
    fn default() -> Self {
        Self {
            items: vec![],
            current_index: None,
            source: None,
            revision: 0,
            radio: None,
        }
    }
}

impl QueueStateDto {
    pub fn replace(
        &mut self,
        items: Vec<QueueEntryDto>,
        current_index: usize,
        source: QueueSourceDto,
    ) -> Option<QueueEntryDto> {
        if items.is_empty() || current_index >= items.len() {
            return None;
        }
        // A replacement starts a new queue owner. Never trust occurrence IDs supplied
        // by the previous owner/client; stale asynchronous work must not match this queue.
        self.items = items
            .into_iter()
            .map(|mut item| {
                item.entry_id = new_entry_id();
                item
            })
            .collect();
        self.current_index = Some(current_index);
        self.source = Some(source);
        self.radio = None;
        self.revision += 1;
        self.current()
    }

    pub fn current(&self) -> Option<QueueEntryDto> {
        self.current_index
            .and_then(|index| self.items.get(index))
            .cloned()
    }

    pub fn select(&mut self, index: usize) -> Option<QueueEntryDto> {
        if index >= self.items.len() {
            return None;
        }
        self.current_index = Some(index);
        self.revision += 1;
        self.current()
    }

    pub fn select_entry(&mut self, entry_id: &str) -> Option<QueueEntryDto> {
        let index = self
            .items
            .iter()
            .position(|entry| entry.entry_id == entry_id)?;
        self.select(index)
    }

    pub fn next(&mut self) -> Option<QueueEntryDto> {
        let next = self.current_index?.checked_add(1)?;
        self.select(next)
    }

    pub fn previous(&mut self, position: f64) -> Option<QueueEntryDto> {
        if position > 3.0 {
            return self.current();
        }
        let index = self.current_index?;
        match index.checked_sub(1) {
            Some(previous) => self.select(previous),
            None => self.current(),
        }
    }

    pub fn enqueue(&mut self, items: Vec<QueueEntryDto>, at_next: bool) {
        if items.is_empty() {
            return;
        }
        let mut entries = items;
        let mut known_ids = self
            .items
            .iter()
            .map(|entry| entry.entry_id.clone())
            .collect::<HashSet<_>>();
        for entry in &mut entries {
            entry.entry_id = new_unique_entry_id(&mut known_ids);
        }
        let insert_at = if at_next {
            self.current_index
                .map_or(self.items.len(), |index| index + 1)
        } else {
            self.items.len()
        };
        self.items.splice(insert_at..insert_at, entries);
        if self.source.is_none() {
            self.source = Some(QueueSourceDto {
                kind: "manual".into(),
                id: None,
                title: None,
            });
        }
        self.revision += 1;
    }

    /// Removes a queue occurrence. The current item is protected so it cannot desync audio.
    pub fn remove_entry(&mut self, entry_id: &str) -> Result<bool, QueueRemoveError> {
        let Some(index) = self
            .items
            .iter()
            .position(|entry| entry.entry_id == entry_id)
        else {
            return Ok(false);
        };
        if self.current_index == Some(index) {
            return Err(QueueRemoveError::CurrentEntry);
        }
        self.items.remove(index);
        if let Some(current) = self.current_index {
            if index < current {
                self.current_index = Some(current - 1);
            }
        }
        self.revision += 1;
        Ok(true)
    }

    pub fn begin_radio(&mut self) {
        self.radio = Some(QueueRadioDto {
            loading: true,
            error: None,
            can_retry: false,
        });
        self.revision += 1;
    }

    pub fn end_radio(&mut self, error: Option<String>, can_retry: bool) {
        self.radio = Some(QueueRadioDto {
            loading: false,
            error,
            can_retry,
        });
        self.revision += 1;
    }

    /// Appends unique radio recommendations, leaving explicit queue duplicates intact.
    pub fn merge_radio(&mut self, recommendations: Vec<QueueEntryDto>) -> Option<String> {
        let mut known = self
            .items
            .iter()
            .map(|entry| entry.video_id.clone())
            .collect::<HashSet<_>>();
        let mut added = Vec::new();
        for entry in recommendations {
            if entry.video_id.trim().is_empty() || !known.insert(entry.video_id.clone()) {
                continue;
            }
            added.push(entry);
        }
        let cursor = added.last().map(|entry| entry.video_id.clone());
        if !added.is_empty() {
            let mut entry_ids = self
                .items
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<HashSet<_>>();
            for entry in &mut added {
                if entry.entry_id.trim().is_empty() || !entry_ids.insert(entry.entry_id.clone()) {
                    entry.entry_id = new_unique_entry_id(&mut entry_ids);
                }
            }
            self.items.extend(added);
            self.revision += 1;
        }
        cursor
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QueueRemoveError {
    CurrentEntry,
}

fn new_entry_id() -> String {
    format!("queue-{}", NEXT_ENTRY_ID.fetch_add(1, Ordering::Relaxed))
}

fn new_unique_entry_id(seen: &mut HashSet<String>) -> String {
    loop {
        let id = new_entry_id();
        if seen.insert(id.clone()) {
            return id;
        }
    }
}

pub(crate) fn next_owner_epoch(epoch: u64) -> u64 {
    epoch.wrapping_add(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str) -> QueueEntryDto {
        QueueEntryDto::new(id.into(), id.into(), String::new(), None, None)
    }

    fn source() -> QueueSourceDto {
        QueueSourceDto {
            kind: "playlist".into(),
            id: Some("PL1".into()),
            title: Some("Playlist".into()),
        }
    }

    fn queue() -> QueueStateDto {
        let mut queue = QueueStateDto::default();
        queue.replace(vec![item("same"), item("same"), item("last")], 1, source());
        queue
    }

    #[test]
    fn duplicates_keep_occurrence_identity_and_playlist_order() {
        let mut queue = queue();
        assert_eq!(queue.items[0].video_id, queue.items[1].video_id);
        assert_ne!(queue.items[0].entry_id, queue.items[1].entry_id);
        assert_eq!(queue.current_index, Some(1));
        assert_eq!(queue.next().unwrap().video_id, "last");
    }

    #[test]
    fn previous_restarts_after_three_seconds_and_steps_at_or_below() {
        let mut queue = queue();
        let current = queue.current().unwrap().entry_id;
        assert_eq!(queue.previous(3.01).unwrap().entry_id, current);
        assert_eq!(queue.current_index, Some(1));
        assert_eq!(queue.previous(3.0).unwrap().video_id, "same");
        assert_eq!(queue.current_index, Some(0));
        let first = queue.current().unwrap().entry_id;
        let revision = queue.revision;
        assert_eq!(queue.previous(0.0).unwrap().entry_id, first);
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.revision, revision);
    }

    #[test]
    fn eof_and_invalid_selection_do_not_wrap_or_mutate() {
        let mut queue = queue();
        queue.select(2);
        let revision = queue.revision;
        assert!(queue.next().is_none());
        assert_eq!(queue.current_index, Some(2));
        assert_eq!(queue.revision, revision);
        assert!(queue.select(99).is_none());
    }

    #[test]
    fn enqueue_next_and_end_preserve_current_and_reassign_client_ids() {
        let mut queue = queue();
        let current = queue.current().unwrap().entry_id;
        let mut client_item = item("same");
        client_item.entry_id = queue.items[0].entry_id.clone();
        queue.enqueue(vec![client_item.clone()], true);
        assert_eq!(queue.current().unwrap().entry_id, current);
        assert_eq!(queue.items[2].video_id, "same");
        assert_ne!(queue.items[2].entry_id, queue.items[0].entry_id);
        queue.enqueue(vec![client_item], false);
        assert_eq!(queue.items.last().unwrap().video_id, "same");
        assert_eq!(queue.items[0].video_id, "same");
        assert_eq!(queue.current_index, Some(1));
    }

    #[test]
    fn removing_by_occurrence_preserves_current_and_rejects_itself() {
        let mut queue = queue();
        let current = queue.current().unwrap().entry_id;
        assert_eq!(
            queue.remove_entry(&current),
            Err(QueueRemoveError::CurrentEntry)
        );
        let before_current = queue.items[0].entry_id.clone();
        assert_eq!(queue.remove_entry(&before_current), Ok(true));
        assert_eq!(queue.current_index, Some(0));
        assert_eq!(queue.current().unwrap().entry_id, current);
        assert_eq!(queue.remove_entry("missing"), Ok(false));
    }

    #[test]
    fn selecting_by_entry_id_survives_removing_an_earlier_occurrence() {
        let mut queue = queue();
        let intended = queue.items[2].entry_id.clone();
        let before_current = queue.items[0].entry_id.clone();
        queue.remove_entry(&before_current).unwrap();
        let selected = queue.select_entry(&intended).unwrap();
        assert_eq!(selected.entry_id, intended);
        assert_eq!(queue.current_index, Some(1));
    }

    #[test]
    fn queue_replacement_invalidates_old_occurrence_ids_even_if_the_client_reuses_them() {
        let mut queue = queue();
        let stale_id = queue.items[0].entry_id.clone();
        queue.replace(vec![item("replacement")], 0, source());
        assert_ne!(queue.items[0].entry_id, stale_id);
        assert!(queue.select_entry(&stale_id).is_none());
    }

    #[test]
    fn radio_merge_deduplicates_recommendations_but_not_manual_occurrences() {
        let mut queue = queue();
        queue.enqueue(vec![item("same"), item("manual")], false);
        let cursor = queue.merge_radio(vec![item("last"), item("radio"), item("radio")]);
        assert_eq!(cursor.as_deref(), Some("radio"));
        assert_eq!(
            queue
                .items
                .iter()
                .filter(|entry| entry.video_id == "same")
                .count(),
            3
        );
        assert_eq!(
            queue
                .items
                .iter()
                .filter(|entry| entry.video_id == "radio")
                .count(),
            1
        );
    }

    #[test]
    fn replaced_queue_resets_optional_radio_state() {
        let mut queue = queue();
        queue.begin_radio();
        assert!(queue.radio.as_ref().unwrap().loading);
        queue.replace(vec![item("new")], 0, source());
        assert!(queue.radio.is_none());
    }

    #[test]
    fn queue_owner_epoch_invalidates_stale_radio_results() {
        let old_epoch = 41;
        let new_epoch = next_owner_epoch(old_epoch);
        assert_ne!(old_epoch, new_epoch);
        assert_eq!(next_owner_epoch(u64::MAX), 0);
    }

    #[test]
    fn older_queue_snapshots_deserialize_without_radio_or_metadata() {
        let queue: QueueStateDto = serde_json::from_str(
            r#"{"items":[{"entryId":"entry-1","videoId":"v1","title":"Track","artists":"Artist","thumbnail":null,"duration":null}],"currentIndex":0,"source":null,"revision":4}"#,
        ).unwrap();
        assert!(queue.radio.is_none());
        assert!(queue.items[0].artist_id.is_none());
        assert!(queue.items[0].album_id.is_none());
        assert!(queue.items[0].album.is_none());
    }
}
