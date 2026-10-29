use kas::Widget;
use kas::window::Window;
use kas_widgets::{AdaptWidget, AdaptWidgetAny, Flow, Label, List, ScrollRegion, Text};

use crate::controller::BenchData;

pub const MAIN_TITLE: &str = "UI Framework Bench - Main";
pub const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";
pub const MAIN_OUTER_SIZE: (i32, i32) = (715, 514);
pub const AUXILIARY_OUTER_SIZE: (i32, i32) = (1215, 794);

pub fn main_selection(data: &BenchData) -> usize {
    data.selected
}

pub fn auxiliary_selection(data: &BenchData) -> usize {
    data.selected
}

fn static_label(text: impl ToString) -> impl Widget<Data = BenchData> {
    Label::new(text.to_string()).map_any()
}

fn entry(index: usize) -> impl Widget<Data = BenchData> {
    Text::new_gen(move |_, data: &BenchData| {
        let marker = if main_selection(data) == index {
            "▶"
        } else {
            " "
        };
        let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
        format!(
            "{marker}  u{}+{}    Representative shortcut action {:02}    {}",
            index % 3,
            (b'a' + (index % 26) as u8) as char,
            index + 1,
            sections[index % sections.len()]
        )
    })
    .with_min_size_px(660, 44)
}

fn key(index: usize) -> impl Widget<Data = BenchData> {
    Text::new_gen(move |_, data: &BenchData| {
        let marker = if auxiliary_selection(data) % 66 == index {
            "●"
        } else {
            " "
        };
        let label = if index < 26 {
            ((b'A' + index as u8) as char).to_string()
        } else {
            format!("K{:02}", index + 1)
        };
        format!("{marker} {label}")
    })
    .with_min_size_px(64, 42)
}

pub fn main_window() -> Window<BenchData> {
    let entries = (0..72).map(entry).collect::<Vec<_>>();
    let list = ScrollRegion::new_clip(List::down(entries)).with_fixed_bars(false, true);
    let content = kas_widgets::column![
        static_label("Shortcut Palette                                      72 ENTRIES"),
        static_label("Search shortcuts, commands, facets, and object memory"),
        static_label("Static benchmark corpus · selection drives the auxiliary canvas"),
        list,
    ]
    .with_min_size_px(700, 480);
    Window::new(content, MAIN_TITLE)
}

pub fn auxiliary_window() -> Window<BenchData> {
    let keys = (0..66).map(key).collect::<Vec<_>>();
    let atlas = kas_widgets::column![
        static_label("Binding Atlas · modifier plane and related bindings"),
        Flow::right(keys).with_num_columns(11, 11),
    ];
    let preview = Text::new_gen(|_, data: &BenchData| {
        format!(
            "Object Memory Preview\nSelected action {}: move, focus, or transform the active object\nRepresentative defining expression, scenario annotation, availability note, source path, and extended explanation.",
            auxiliary_selection(data) + 1
        )
    });
    let side = Text::new_gen(|_, data: &BenchData| {
        format!(
            "Navigation\nH  J  K  L\nword · line · page · history\nselected relation {}\n\nNumpad / Operations\n7   8   9   +\n4   5   6   -\n1   2   3   Enter\n\nDossier\nProvider       kanata\nFamily         komorebi\nTarget         window\nApplicability  available\nGeneration     {}",
            auxiliary_selection(data) % 12,
            auxiliary_selection(data)
        )
    })
    .with_min_size_px(266, 520);
    let content =
        kas_widgets::column![preview, kas_widgets::row![atlas, side]].with_min_size_px(1200, 760);
    Window::new(content, AUXILIARY_TITLE)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_views_read_the_same_top_level_selection() {
        let data = BenchData { selected: 57 };
        assert_eq!(main_selection(&data), 57);
        assert_eq!(auxiliary_selection(&data), 57);
    }

    #[test]
    fn scene_contract_has_exact_counts_titles_and_outer_sizes() {
        assert_eq!((0..72).count(), 72);
        assert_eq!((0..66).count(), 66);
        assert_eq!(MAIN_TITLE, "UI Framework Bench - Main");
        assert_eq!(AUXILIARY_TITLE, "UI Framework Bench - Auxiliary Canvas");
        assert_eq!(MAIN_OUTER_SIZE, (715, 514));
        assert_eq!(AUXILIARY_OUTER_SIZE, (1215, 794));
    }
}
