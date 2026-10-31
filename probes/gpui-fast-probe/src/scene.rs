use gpui::{
    App, Bounds, Context, Div, FontWeight, Render, TitlebarOptions, Window, WindowBounds,
    WindowOptions, div, prelude::*, px, rgb, size,
};

pub struct MainView {
    pub selected: usize,
}

impl MainView {
    pub fn new() -> Self {
        Self { selected: 0 }
    }
}

impl Render for MainView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
        div()
            .size_full()
            .flex()
            .flex_col()
            .gap_3()
            .p_4()
            .bg(rgb(0x0d1117))
            .text_color(rgb(0xc9d1d9))
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .text_size(px(25.0))
                            .font_weight(FontWeight::BOLD)
                            .text_color(rgb(0xf0f6fc))
                            .child("Shortcut Palette"),
                    )
                    .child(
                        div()
                            .px_4()
                            .py_2()
                            .rounded_full()
                            .bg(rgb(0x132a46))
                            .text_xs()
                            .text_color(rgb(0x79c0ff))
                            .child("72 ENTRIES"),
                    ),
            )
            .child(
                div()
                    .h(px(54.0))
                    .px_4()
                    .py_2()
                    .border_1()
                    .border_color(rgb(0x30363d))
                    .rounded_lg()
                    .bg(rgb(0x161b22))
                    .child("Search shortcuts, commands, facets, and object memory")
                    .child(
                        div().text_xs().text_color(rgb(0x8b949e)).child(
                            "Static benchmark corpus · selection drives the auxiliary canvas",
                        ),
                    ),
            )
            .child(
                div()
                    .id("shortcut-list")
                    .flex_1()
                    .overflow_y_scroll()
                    .border_1()
                    .border_color(rgb(0x30363d))
                    .rounded_lg()
                    .children((0..72_usize).map(|index| {
                        let selected = self.selected == index;
                        div()
                            .id(index)
                            .h(px(44.0))
                            .flex()
                            .items_center()
                            .gap_3()
                            .px_3()
                            .border_b_1()
                            .border_color(rgb(0x21262d))
                            .bg(rgb(if selected {
                                0x163459
                            } else if index % 2 == 0 {
                                0x0d1117
                            } else {
                                0x11161c
                            }))
                            .child(
                                div()
                                    .w(px(128.0))
                                    .font_weight(FontWeight::BOLD)
                                    .child(format!(
                                        "u{}+{}",
                                        index % 3,
                                        (b'a' + (index % 26) as u8) as char
                                    )),
                            )
                            .child(
                                div().w(px(360.0)).child(format!(
                                    "Representative shortcut action {:02}",
                                    index + 1
                                )),
                            )
                            .child(
                                div()
                                    .ml_auto()
                                    .text_color(rgb(0x8b949e))
                                    .child(sections[index % sections.len()]),
                            )
                    })),
            )
    }
}

pub struct AuxiliaryView {
    pub selected: usize,
}

impl AuxiliaryView {
    pub fn new() -> Self {
        Self { selected: 0 }
    }
}

fn panel() -> Div {
    div()
        .border_1()
        .border_color(rgb(0x30363d))
        .rounded_xl()
        .bg(rgb(0x161b22))
}

impl Render for AuxiliaryView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .size_full()
            .flex()
            .flex_col()
            .gap_4()
            .p_5()
            .bg(rgb(0x080b10))
            .text_color(rgb(0xc9d1d9))
            .child(
                panel()
                    .h(px(114.0))
                    .p_4()
                    .child(
                        div()
                            .text_color(rgb(0x79c0ff))
                            .font_weight(FontWeight::BOLD)
                            .child("Object Memory Preview"),
                    )
                    .child(
                        div()
                            .text_lg()
                            .font_weight(FontWeight::BOLD)
                            .text_color(rgb(0xf0f6fc))
                            .child(format!(
                                "Selected action {}: move, focus, or transform the active object",
                                self.selected + 1
                            )),
                    )
                    .child(div().text_xs().text_color(rgb(0x8b949e)).child(
                        "Representative defining expression, scenario annotation, availability note, source path, and extended explanation.",
                    )),
            )
            .child(
                div()
                    .flex_1()
                    .flex()
                    .gap_4()
                    .child(
                        panel()
                            .w(px(854.0))
                            .p_4()
                            .bg(rgb(0x0d1117))
                            .child(
                                div()
                                    .text_lg()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(rgb(0xf0f6fc))
                                    .child("Binding Atlas · modifier plane and related bindings"),
                            )
                            .child(
                                div()
                                    .grid()
                                    .grid_cols(11)
                                    .gap_2()
                                    .mt_4()
                                    .children((0..66_usize).map(|index| {
                                        let selected = self.selected % 66 == index;
                                        div()
                                            .h(px(42.0))
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .rounded_md()
                                            .border_1()
                                            .border_color(rgb(if selected {
                                                0x79c0ff
                                            } else {
                                                0x30363d
                                            }))
                                            .bg(rgb(if selected { 0x2f81f7 } else { 0x21262d }))
                                            .font_weight(FontWeight::BOLD)
                                            .child(if index < 26 {
                                                ((b'A' + index as u8) as char).to_string()
                                            } else {
                                                format!("K{:02}", index + 1)
                                            })
                                    })),
                            ),
                    )
                    .child(
                        div()
                            .w(px(266.0))
                            .flex()
                            .flex_col()
                            .gap_4()
                            .child(
                                panel()
                                    .flex_1()
                                    .p_4()
                                    .child(div().text_color(rgb(0x79c0ff)).child("Navigation"))
                                    .child(
                                        div()
                                            .text_xl()
                                            .font_weight(FontWeight::BOLD)
                                            .child("H  J  K  L"),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(rgb(0x8b949e))
                                            .child("word · line · page · history"),
                                    )
                                    .child(format!("selected relation {}", self.selected % 12)),
                            )
                            .child(
                                panel()
                                    .flex_1()
                                    .p_4()
                                    .child(
                                        div().text_color(rgb(0x79c0ff)).child("Numpad / Operations"),
                                    )
                                    .child(div().text_lg().child("7   8   9   +"))
                                    .child(div().text_lg().child("4   5   6   -"))
                                    .child(div().text_lg().child("1   2   3   Enter")),
                            )
                            .child(
                                panel()
                                    .flex_1()
                                    .p_4()
                                    .child(div().text_color(rgb(0x79c0ff)).child("Dossier"))
                                    .child("Provider       kanata")
                                    .child("Family         komorebi")
                                    .child("Target         window")
                                    .child("Applicability  available")
                                    .child(format!("Generation     {}", self.selected)),
                            ),
                    ),
            )
    }
}

pub fn window_options(title: &str, width: f32, height: f32, cx: &App) -> WindowOptions {
    let bounds = Bounds::centered(None, size(px(width), px(height)), cx);
    WindowOptions {
        show: false,
        focus: false,
        titlebar: Some(TitlebarOptions {
            title: Some(title.into()),
            ..Default::default()
        }),
        window_bounds: Some(WindowBounds::Windowed(bounds)),
        ..Default::default()
    }
}
