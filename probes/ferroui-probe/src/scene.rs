use std::rc::Rc;

use ferroui::base::media::{IBrush, SolidColorBrush};
use ferroui::controls::primitives::ScrollBarVisibility;
use ferroui::controls::{ScrollViewer, WrapPanel};
use ferroui::prelude::*;

pub const ENTRY_COUNT: usize = 72;
pub const KEY_COUNT: usize = 66;

const BACKGROUND: u32 = 0xff0d1117;
const PANEL: u32 = 0xff111923;
const CELL: u32 = 0xff141a23;
const SELECTED: u32 = 0xff254b72;
const TEXT: u32 = 0xffb8c5d6;
const BRIGHT_TEXT: u32 = 0xfff0f5fb;
const ACCENT: u32 = 0xff7fb7ef;
const MUTED: u32 = 0xff96a8bd;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg(test)]
pub struct SceneProjection {
    pub main_row: usize,
    pub auxiliary_key: usize,
}

#[cfg(test)]
pub fn project_selection(selected: usize) -> SceneProjection {
    SceneProjection {
        main_row: selected % ENTRY_COUNT,
        auxiliary_key: selected % KEY_COUNT,
    }
}

fn brush(color: u32) -> Rc<dyn IBrush> {
    SolidColorBrush::from_uint32(color).into()
}

fn text(value: &str, size: f64, color: u32) -> Ref<TextBlock> {
    let result = TextBlock::new();
    result.set_text(Some(value));
    result.set_font_size(size);
    result.set_foreground(Some(brush(color)));
    result
}

fn card(lines: &[(&str, f64, u32)], height: f64) -> Ref<Border> {
    let panel = StackPanel::new();
    panel.set_spacing(5.0);
    for (value, size, color) in lines {
        panel.children().add(text(value, *size, *color));
    }

    let card = Border::new();
    card.set_height(height);
    card.set_background(Some(brush(PANEL)));
    card.set_padding(Thickness::uniform(12.0));
    card.set_child(panel);
    card
}

fn main_row_text(index: usize, selected: bool) -> String {
    let marker = if selected { "▶" } else { " " };
    let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
    format!(
        "{marker}  u{}+{}    Representative shortcut action {:02}    {}",
        index % 3,
        (b'a' + (index % 26) as u8) as char,
        index + 1,
        sections[index % sections.len()]
    )
}

fn key_text(index: usize, selected: bool) -> String {
    let marker = if selected { "●" } else { " " };
    let label = if index < 26 {
        ((b'A' + index as u8) as char).to_string()
    } else {
        format!("K{:02}", index + 1)
    };
    format!("{marker} {label}")
}

pub struct MainScene {
    root: Ref<Border>,
    rows: Vec<Ref<Border>>,
    labels: Vec<Ref<TextBlock>>,
}

impl MainScene {
    pub fn new() -> Self {
        let layout = StackPanel::new();
        layout.set_spacing(10.0);
        layout.children().add(text(
            "Shortcut Palette                                      72 ENTRIES",
            21.0,
            BRIGHT_TEXT,
        ));
        layout.children().add(card(
            &[
                (
                    "Search shortcuts, commands, facets, and object memory",
                    13.0,
                    BRIGHT_TEXT,
                ),
                (
                    "Static benchmark corpus · selection drives the auxiliary canvas",
                    10.0,
                    MUTED,
                ),
            ],
            58.0,
        ));

        let entries = StackPanel::new();
        entries.set_spacing(2.0);
        let mut rows = Vec::with_capacity(ENTRY_COUNT);
        let mut labels = Vec::with_capacity(ENTRY_COUNT);
        for index in 0..ENTRY_COUNT {
            let label = text(
                &main_row_text(index, index == 0),
                11.0,
                if index == 0 { BRIGHT_TEXT } else { TEXT },
            );
            label.set_padding(Thickness::new(12.0, 8.0, 8.0, 8.0));
            let row = Border::new();
            row.set_height(34.0);
            row.set_background(Some(brush(if index == 0 { SELECTED } else { CELL })));
            row.set_child(label.clone());
            entries.children().add(row.clone());
            rows.push(row);
            labels.push(label);
        }

        let scroll = ScrollViewer::new();
        scroll.set_height(352.0);
        scroll.set_horizontal_scroll_bar_visibility(ScrollBarVisibility::Disabled);
        scroll.set_vertical_scroll_bar_visibility(ScrollBarVisibility::Auto);
        scroll.set_content(Some(Control::boxed(entries)));
        layout.children().add(scroll);

        let root = Border::new();
        root.set_background(Some(brush(BACKGROUND)));
        root.set_padding(Thickness::uniform(18.0));
        root.set_child(layout);
        Self { root, rows, labels }
    }

    pub fn root(&self) -> Ref<Border> {
        self.root.clone()
    }

    pub fn set_selected(&self, previous: usize, selected: usize) {
        let previous = previous % ENTRY_COUNT;
        let selected = selected % ENTRY_COUNT;
        self.rows[previous].set_background(Some(brush(CELL)));
        self.labels[previous].set_foreground(Some(brush(TEXT)));
        self.labels[previous].set_text(Some(&main_row_text(previous, false)));
        self.rows[selected].set_background(Some(brush(SELECTED)));
        self.labels[selected].set_foreground(Some(brush(BRIGHT_TEXT)));
        self.labels[selected].set_text(Some(&main_row_text(selected, true)));
    }
}

pub struct AuxiliaryScene {
    root: Ref<Border>,
    keys: Vec<Ref<Border>>,
    labels: Vec<Ref<TextBlock>>,
}

impl AuxiliaryScene {
    pub fn new() -> Self {
        let layout = StackPanel::new();
        layout.set_spacing(16.0);
        layout.children().add(card(
            &[
                ("Object Memory Preview", 12.0, ACCENT),
                (
                    "Selected action is shared with the shortcut palette",
                    16.0,
                    BRIGHT_TEXT,
                ),
                (
                    "Representative expression, scenario annotation, availability note, source path, and extended explanation.",
                    10.0,
                    MUTED,
                ),
            ],
            108.0,
        ));
        layout.children().add(text(
            "Binding Atlas · modifier plane and related bindings",
            14.0,
            BRIGHT_TEXT,
        ));

        let atlas = WrapPanel::new();
        atlas.set_item_width(64.0);
        atlas.set_item_height(42.0);
        atlas.set_item_spacing(8.0);
        atlas.set_line_spacing(8.0);
        let mut keys = Vec::with_capacity(KEY_COUNT);
        let mut labels = Vec::with_capacity(KEY_COUNT);
        for index in 0..KEY_COUNT {
            let label = text(
                &key_text(index, index == 0),
                11.0,
                if index == 0 { BRIGHT_TEXT } else { TEXT },
            );
            label.set_padding(Thickness::new(10.0, 11.0, 4.0, 4.0));
            let key = Border::new();
            key.set_background(Some(brush(if index == 0 { SELECTED } else { CELL })));
            key.set_child(label.clone());
            atlas.children().add(key.clone());
            keys.push(key);
            labels.push(label);
        }
        layout.children().add(atlas);

        let details = StackPanel::new();
        details.set_orientation(Orientation::Horizontal);
        details.set_spacing(18.0);
        details.children().add(card(
            &[
                ("Navigation", 13.0, ACCENT),
                ("H  J  K  L", 18.0, BRIGHT_TEXT),
                ("word · line · page · history", 10.0, MUTED),
            ],
            150.0,
        ));
        details.children().add(card(
            &[
                ("Numpad / Operations", 13.0, ACCENT),
                ("7   8   9   +", 16.0, BRIGHT_TEXT),
                ("4   5   6   -", 16.0, BRIGHT_TEXT),
                ("1   2   3   Enter", 16.0, BRIGHT_TEXT),
            ],
            150.0,
        ));
        details.children().add(card(
            &[
                ("Dossier", 13.0, ACCENT),
                ("Provider       kanata", 10.0, TEXT),
                ("Family         komorebi", 10.0, TEXT),
                ("Target         window", 10.0, TEXT),
            ],
            150.0,
        ));
        layout.children().add(details);

        let root = Border::new();
        root.set_background(Some(brush(0xff080b10)));
        root.set_padding(Thickness::uniform(22.0));
        root.set_child(layout);
        Self { root, keys, labels }
    }

    pub fn root(&self) -> Ref<Border> {
        self.root.clone()
    }

    pub fn set_selected(&self, previous: usize, selected: usize) {
        let previous = previous % KEY_COUNT;
        let selected = selected % KEY_COUNT;
        self.keys[previous].set_background(Some(brush(CELL)));
        self.labels[previous].set_foreground(Some(brush(TEXT)));
        self.labels[previous].set_text(Some(&key_text(previous, false)));
        self.keys[selected].set_background(Some(brush(SELECTED)));
        self.labels[selected].set_foreground(Some(brush(BRIGHT_TEXT)));
        self.labels[selected].set_text(Some(&key_text(selected, true)));
    }
}
