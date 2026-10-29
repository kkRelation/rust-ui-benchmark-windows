use makepad_widgets::*;

pub const ENTRY_COUNT: usize = 72;
pub const KEY_COUNT: usize = 66;

live_design! {
    use link::theme::*;
    use link::shaders::*;
    use link::widgets::*;

    pub BenchmarkCellBase = {{BenchmarkCell}} {
        draw_normal: {
            fn pixel(self) -> vec4 {
                return #141a23;
            }
        }
        draw_selected: {
            fn pixel(self) -> vec4 {
                return #254b72;
            }
        }
        text_normal: {
            color: #b8c5d6,
            text_style: <THEME_FONT_REGULAR> { font_size: 11.0 }
        }
        text_selected: {
            color: #ffffff,
            text_style: <THEME_FONT_REGULAR> { font_size: 11.0 }
        }
    }

    pub MainRow = <BenchmarkCellBase> {
        width: Fill,
        height: 44,
        kind: 0
    }

    pub AtlasKey = <BenchmarkCellBase> {
        width: 64,
        height: 42,
        kind: 1
    }

    pub MainScene = <View> {
        width: Fill,
        height: Fill,
        flow: Down,
        spacing: 10,
        padding: 18,
        show_bg: true,
        draw_bg: { color: #0d1117 }

        <View> {
            width: Fill,
            height: 32,
            flow: Right,
            <Label> {
                width: Fill,
                text: "Shortcut Palette",
                draw_text: { color: #f0f5fb, text_style: { font_size: 21.0 } }
            }
            <Label> {
                width: 92,
                text: "72 ENTRIES",
                draw_text: { color: #7fb7ef, text_style: { font_size: 10.0 } }
            }
        }
        <View> {
            width: Fill,
            height: 54,
            flow: Down,
            spacing: 3,
            padding: 10,
            show_bg: true,
            draw_bg: { color: #111923 }
            <Label> {
                text: "Search shortcuts, commands, facets, and object memory",
                draw_text: { color: #d8e2ee, text_style: { font_size: 13.0 } }
            }
            <Label> {
                text: "Static benchmark corpus · selection drives the auxiliary canvas",
                draw_text: { color: #7f91a7, text_style: { font_size: 10.0 } }
            }
        }
        entries = <ScrollYView> {
            width: Fill,
            height: Fill,
            flow: Down,
            spacing: 2,
            row_00 = <MainRow> { index: 0 }
            row_01 = <MainRow> { index: 1 }
            row_02 = <MainRow> { index: 2 }
            row_03 = <MainRow> { index: 3 }
            row_04 = <MainRow> { index: 4 }
            row_05 = <MainRow> { index: 5 }
            row_06 = <MainRow> { index: 6 }
            row_07 = <MainRow> { index: 7 }
            row_08 = <MainRow> { index: 8 }
            row_09 = <MainRow> { index: 9 }
            row_10 = <MainRow> { index: 10 }
            row_11 = <MainRow> { index: 11 }
            row_12 = <MainRow> { index: 12 }
            row_13 = <MainRow> { index: 13 }
            row_14 = <MainRow> { index: 14 }
            row_15 = <MainRow> { index: 15 }
            row_16 = <MainRow> { index: 16 }
            row_17 = <MainRow> { index: 17 }
            row_18 = <MainRow> { index: 18 }
            row_19 = <MainRow> { index: 19 }
            row_20 = <MainRow> { index: 20 }
            row_21 = <MainRow> { index: 21 }
            row_22 = <MainRow> { index: 22 }
            row_23 = <MainRow> { index: 23 }
            row_24 = <MainRow> { index: 24 }
            row_25 = <MainRow> { index: 25 }
            row_26 = <MainRow> { index: 26 }
            row_27 = <MainRow> { index: 27 }
            row_28 = <MainRow> { index: 28 }
            row_29 = <MainRow> { index: 29 }
            row_30 = <MainRow> { index: 30 }
            row_31 = <MainRow> { index: 31 }
            row_32 = <MainRow> { index: 32 }
            row_33 = <MainRow> { index: 33 }
            row_34 = <MainRow> { index: 34 }
            row_35 = <MainRow> { index: 35 }
            row_36 = <MainRow> { index: 36 }
            row_37 = <MainRow> { index: 37 }
            row_38 = <MainRow> { index: 38 }
            row_39 = <MainRow> { index: 39 }
            row_40 = <MainRow> { index: 40 }
            row_41 = <MainRow> { index: 41 }
            row_42 = <MainRow> { index: 42 }
            row_43 = <MainRow> { index: 43 }
            row_44 = <MainRow> { index: 44 }
            row_45 = <MainRow> { index: 45 }
            row_46 = <MainRow> { index: 46 }
            row_47 = <MainRow> { index: 47 }
            row_48 = <MainRow> { index: 48 }
            row_49 = <MainRow> { index: 49 }
            row_50 = <MainRow> { index: 50 }
            row_51 = <MainRow> { index: 51 }
            row_52 = <MainRow> { index: 52 }
            row_53 = <MainRow> { index: 53 }
            row_54 = <MainRow> { index: 54 }
            row_55 = <MainRow> { index: 55 }
            row_56 = <MainRow> { index: 56 }
            row_57 = <MainRow> { index: 57 }
            row_58 = <MainRow> { index: 58 }
            row_59 = <MainRow> { index: 59 }
            row_60 = <MainRow> { index: 60 }
            row_61 = <MainRow> { index: 61 }
            row_62 = <MainRow> { index: 62 }
            row_63 = <MainRow> { index: 63 }
            row_64 = <MainRow> { index: 64 }
            row_65 = <MainRow> { index: 65 }
            row_66 = <MainRow> { index: 66 }
            row_67 = <MainRow> { index: 67 }
            row_68 = <MainRow> { index: 68 }
            row_69 = <MainRow> { index: 69 }
            row_70 = <MainRow> { index: 70 }
            row_71 = <MainRow> { index: 71 }
        }
    }

    pub AuxiliaryScene = <View> {
        width: Fill,
        height: Fill,
        flow: Down,
        spacing: 18,
        padding: 22,
        show_bg: true,
        draw_bg: { color: #080b10 }

        <View> {
            width: Fill,
            height: 114,
            flow: Down,
            spacing: 7,
            padding: 15,
            show_bg: true,
            draw_bg: { color: #111923 }
            <Label> {
                text: "Object Memory Preview",
                draw_text: { color: #7fb7ef, text_style: { font_size: 12.0 } }
            }
            <Label> {
                text: "Selected action is shared with the shortcut palette",
                draw_text: { color: #f0f5fb, text_style: { font_size: 16.0 } }
            }
            <Label> {
                text: "Representative defining expression, scenario annotation, availability note, source path, and extended explanation.",
                draw_text: { color: #96a8bd, text_style: { font_size: 10.0 } }
            }
        }

        <View> {
            width: Fill,
            height: Fill,
            flow: Right,
            spacing: 18,

            <View> {
                width: 854,
                height: Fill,
                flow: Down,
                spacing: 16,
                padding: 17,
                show_bg: true,
                draw_bg: { color: #0f151e }
                <Label> {
                    height: 28,
                    text: "Binding Atlas · modifier plane and related bindings",
                    draw_text: { color: #e5edf6, text_style: { font_size: 14.0 } }
                }
                key_grid = <View> {
                    width: Fill,
                    height: 292,
                    flow: RightWrap,
                    spacing: 8,
                    key_00 = <AtlasKey> { index: 0 }
                    key_01 = <AtlasKey> { index: 1 }
                    key_02 = <AtlasKey> { index: 2 }
                    key_03 = <AtlasKey> { index: 3 }
                    key_04 = <AtlasKey> { index: 4 }
                    key_05 = <AtlasKey> { index: 5 }
                    key_06 = <AtlasKey> { index: 6 }
                    key_07 = <AtlasKey> { index: 7 }
                    key_08 = <AtlasKey> { index: 8 }
                    key_09 = <AtlasKey> { index: 9 }
                    key_10 = <AtlasKey> { index: 10 }
                    key_11 = <AtlasKey> { index: 11 }
                    key_12 = <AtlasKey> { index: 12 }
                    key_13 = <AtlasKey> { index: 13 }
                    key_14 = <AtlasKey> { index: 14 }
                    key_15 = <AtlasKey> { index: 15 }
                    key_16 = <AtlasKey> { index: 16 }
                    key_17 = <AtlasKey> { index: 17 }
                    key_18 = <AtlasKey> { index: 18 }
                    key_19 = <AtlasKey> { index: 19 }
                    key_20 = <AtlasKey> { index: 20 }
                    key_21 = <AtlasKey> { index: 21 }
                    key_22 = <AtlasKey> { index: 22 }
                    key_23 = <AtlasKey> { index: 23 }
                    key_24 = <AtlasKey> { index: 24 }
                    key_25 = <AtlasKey> { index: 25 }
                    key_26 = <AtlasKey> { index: 26 }
                    key_27 = <AtlasKey> { index: 27 }
                    key_28 = <AtlasKey> { index: 28 }
                    key_29 = <AtlasKey> { index: 29 }
                    key_30 = <AtlasKey> { index: 30 }
                    key_31 = <AtlasKey> { index: 31 }
                    key_32 = <AtlasKey> { index: 32 }
                    key_33 = <AtlasKey> { index: 33 }
                    key_34 = <AtlasKey> { index: 34 }
                    key_35 = <AtlasKey> { index: 35 }
                    key_36 = <AtlasKey> { index: 36 }
                    key_37 = <AtlasKey> { index: 37 }
                    key_38 = <AtlasKey> { index: 38 }
                    key_39 = <AtlasKey> { index: 39 }
                    key_40 = <AtlasKey> { index: 40 }
                    key_41 = <AtlasKey> { index: 41 }
                    key_42 = <AtlasKey> { index: 42 }
                    key_43 = <AtlasKey> { index: 43 }
                    key_44 = <AtlasKey> { index: 44 }
                    key_45 = <AtlasKey> { index: 45 }
                    key_46 = <AtlasKey> { index: 46 }
                    key_47 = <AtlasKey> { index: 47 }
                    key_48 = <AtlasKey> { index: 48 }
                    key_49 = <AtlasKey> { index: 49 }
                    key_50 = <AtlasKey> { index: 50 }
                    key_51 = <AtlasKey> { index: 51 }
                    key_52 = <AtlasKey> { index: 52 }
                    key_53 = <AtlasKey> { index: 53 }
                    key_54 = <AtlasKey> { index: 54 }
                    key_55 = <AtlasKey> { index: 55 }
                    key_56 = <AtlasKey> { index: 56 }
                    key_57 = <AtlasKey> { index: 57 }
                    key_58 = <AtlasKey> { index: 58 }
                    key_59 = <AtlasKey> { index: 59 }
                    key_60 = <AtlasKey> { index: 60 }
                    key_61 = <AtlasKey> { index: 61 }
                    key_62 = <AtlasKey> { index: 62 }
                    key_63 = <AtlasKey> { index: 63 }
                    key_64 = <AtlasKey> { index: 64 }
                    key_65 = <AtlasKey> { index: 65 }
                }
            }

            <View> {
                width: Fill,
                height: Fill,
                flow: Down,
                spacing: 18,
                <View> {
                    width: Fill,
                    height: 172,
                    flow: Down,
                    spacing: 8,
                    padding: 14,
                    show_bg: true,
                    draw_bg: { color: #111923 }
                    <Label> { text: "Navigation", draw_text: { color: #7fb7ef, text_style: { font_size: 13.0 } } }
                    <Label> { text: "H  J  K  L", draw_text: { color: #f0f5fb, text_style: { font_size: 18.0 } } }
                    <Label> { text: "word · line · page · history", draw_text: { color: #96a8bd, text_style: { font_size: 10.0 } } }
                    <Label> { text: "selected relation shared", draw_text: { color: #96a8bd, text_style: { font_size: 10.0 } } }
                }
                <View> {
                    width: Fill,
                    height: 172,
                    flow: Down,
                    spacing: 8,
                    padding: 14,
                    show_bg: true,
                    draw_bg: { color: #111923 }
                    <Label> { text: "Numpad / Operations", draw_text: { color: #7fb7ef, text_style: { font_size: 13.0 } } }
                    <Label> { text: "7   8   9   +", draw_text: { color: #f0f5fb, text_style: { font_size: 16.0 } } }
                    <Label> { text: "4   5   6   -", draw_text: { color: #f0f5fb, text_style: { font_size: 16.0 } } }
                    <Label> { text: "1   2   3   Enter", draw_text: { color: #f0f5fb, text_style: { font_size: 16.0 } } }
                }
                <View> {
                    width: Fill,
                    height: 172,
                    flow: Down,
                    spacing: 7,
                    padding: 14,
                    show_bg: true,
                    draw_bg: { color: #111923 }
                    <Label> { text: "Dossier", draw_text: { color: #7fb7ef, text_style: { font_size: 13.0 } } }
                    <Label> { text: "Provider       kanata", draw_text: { color: #c1cedd, text_style: { font_size: 10.0 } } }
                    <Label> { text: "Family         komorebi", draw_text: { color: #c1cedd, text_style: { font_size: 10.0 } } }
                    <Label> { text: "Target         window", draw_text: { color: #c1cedd, text_style: { font_size: 10.0 } } }
                    <Label> { text: "Applicability  available", draw_text: { color: #c1cedd, text_style: { font_size: 10.0 } } }
                }
            }
        }
    }
}

#[derive(Live, LiveHook, Widget)]
pub struct BenchmarkCell {
    #[redraw]
    #[live]
    draw_normal: DrawQuad,
    #[redraw]
    #[live]
    draw_selected: DrawQuad,
    #[live]
    text_normal: DrawText,
    #[live]
    text_selected: DrawText,
    #[walk]
    walk: Walk,
    #[live]
    index: f64,
    #[live]
    kind: f64,
}

fn is_selected(kind: usize, index: usize, selected: usize) -> bool {
    match kind {
        0 => selected == index,
        1 => selected % KEY_COUNT == index,
        _ => false,
    }
}

fn cell_text(kind: usize, index: usize, selected: usize) -> String {
    if kind == 0 {
        let marker = if is_selected(kind, index, selected) {
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
    } else {
        let marker = if is_selected(kind, index, selected) {
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
    }
}

impl Widget for BenchmarkCell {
    fn draw_walk(&mut self, cx: &mut Cx2d, scope: &mut Scope, walk: Walk) -> DrawStep {
        let selected = scope.props.get::<usize>().copied().unwrap_or_default();
        let index = self.index as usize;
        let kind = self.kind as usize;
        let selected_now = is_selected(kind, index, selected);
        let rect = if selected_now {
            self.draw_selected.draw_walk(cx, walk)
        } else {
            self.draw_normal.draw_walk(cx, walk)
        };
        let position = if kind == 0 {
            rect.pos + dvec2(12.0, 27.0)
        } else {
            rect.pos + dvec2(10.0, 26.0)
        };
        let text = cell_text(kind, index, selected);
        if selected_now {
            self.text_selected.draw_abs(cx, position, &text);
        } else {
            self.text_normal.draw_abs(cx, position, &text);
        }
        DrawStep::done()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scene_contract_has_exact_counts_and_content() {
        assert_eq!((0..ENTRY_COUNT).count(), 72);
        assert_eq!((0..KEY_COUNT).count(), 66);
        assert!(cell_text(0, 0, 0).contains("Representative shortcut action 01"));
        assert_eq!(cell_text(1, 0, 0), "● A");
        assert_eq!(cell_text(1, 65, 65), "● K66");
    }

    #[test]
    fn both_scenes_project_the_same_selection() {
        let selected = 57;
        assert!(is_selected(0, 57, selected));
        assert!(is_selected(1, 57, selected));
        assert!(!is_selected(0, 56, selected));
        assert!(!is_selected(1, 56, selected));
    }
}
